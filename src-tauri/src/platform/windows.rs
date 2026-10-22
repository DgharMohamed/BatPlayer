//! Windows video surface: an empty native child window that mpv will render
//! into via the `wid` option (Milestone 2). It fills the whole parent client
//! area — the translucent HTML bars simply overlay the picture — is created
//! with a near-black background, and is kept at the bottom of the window's
//! z-order so the transparent webview above it lets the video show through.

use std::ffi::c_void;

use windows::Win32::Foundation::{
    COLORREF, ERROR_CLASS_ALREADY_EXISTS, GetLastError, HINSTANCE, HWND, LPARAM, LRESULT, POINTS,
    RECT, WPARAM,
};
use windows::Win32::Graphics::Gdi::{
    CombineRgn, CreateRectRgn, CreateSolidBrush, HBRUSH, RGN_DIFF, SetWindowRgn,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::{GetDpiForWindow, GetSystemMetricsForDpi};
use windows::Win32::UI::Shell::{DefSubclassProc, SetWindowSubclass};
use windows::Win32::UI::WindowsAndMessaging::{
    CS_HREDRAW, CS_VREDRAW, CreateWindowExW, DefWindowProcW, FindWindowExW, GWL_STYLE,
    GetClientRect, GetParent, GetWindowLongPtrW, GetWindowRect, HCURSOR, HICON, HTBOTTOM,
    HTBOTTOMLEFT, HTBOTTOMRIGHT, HTLEFT, HTRIGHT, HTTOP, HTTOPLEFT, HTTOPRIGHT, HTTRANSPARENT,
    HWND_BOTTOM, HWND_TOP, IsZoomed, PostMessageW, RegisterClassW, SM_CXFRAME, SM_CYFRAME,
    SWP_ASYNCWINDOWPOS, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOOWNERZORDER, SWP_NOSIZE, SetWindowPos,
    WINDOW_EX_STYLE, WM_NCDESTROY, WM_NCHITTEST, WM_NCLBUTTONDOWN, WM_SIZE, WM_USER,
    WNDCLASS_STYLES, WNDCLASSW, WS_CHILD, WS_CLIPSIBLINGS, WS_SIZEBOX, WS_VISIBLE,
};
use windows::core::{Free, Owned, PCWSTR, w};

use super::Error;

const CLASS_NAME: PCWSTR = w!("BatPlayerVideoSurface");

/// Surface background until mpv takes over painting: 0x00BBGGRR of the UI's
/// near-black background rgb(10, 10, 12).
const SURFACE_COLOR: COLORREF = COLORREF(0x000C_0A0A);

pub struct VideoSurface {
    /// Win32 HWNDs stored as `isize` so the struct stays `Send`.
    parent: isize,
    child: isize,
}

impl VideoSurface {
    /// Creates the child surface for `window` and puts it below the webview.
    pub fn attach(window: &tauri::Window) -> Result<Self, Error> {
        let parent = window
            .hwnd()
            .map_err(|err| Error::Platform(format!("failed to get the window HWND: {err}")))?
            .0 as isize;

        // Safety: runs on the Tauri main thread (setup hook); all handles
        // belong to this process.
        let child = unsafe { create_child(parent)? };
        Ok(Self { parent, child })
    }

    /// Fits the surface to the parent's full client area. The HTML bars are
    /// translucent overlays above it, so chrome-free playback (bars slid
    /// away, e.g. fullscreen) shows the picture edge to edge. Also
    /// re-asserts that the surface stays below the webview.
    pub fn resize_to_fit(&self) -> Result<(), Error> {
        let parent = HWND(self.parent as *mut c_void);
        let child = HWND(self.child as *mut c_void);

        // Safety: window events run on the Tauri main thread; handles belong
        // to this process.
        unsafe {
            let mut rect = RECT::default();
            GetClientRect(parent, &mut rect)
                .map_err(|err| Error::Platform(format!("GetClientRect failed: {err}")))?;

            SetWindowPos(
                child,
                Some(HWND_BOTTOM),
                0,
                0,
                rect.right,
                rect.bottom,
                SWP_NOACTIVATE,
            )
            .map_err(|err| Error::Platform(format!("SetWindowPos failed: {err}")))?;
        }
        Ok(())
    }

    /// Window id for mpv's `wid` option: the raw child `HWND`, as an integer
    /// because mpv takes a stringified pointer.
    pub fn wid(&self) -> Result<i64, Error> {
        Ok(self.child as i64)
    }
}

unsafe fn create_child(parent: isize) -> Result<isize, Error> {
    unsafe {
        let instance = GetModuleHandleW(None)
            .map_err(|err| Error::Platform(format!("GetModuleHandleW failed: {err}")))?;

        let class = WNDCLASSW {
            style: CS_HREDRAW | CS_VREDRAW,
            lpfnWndProc: Some(video_wnd_proc),
            cbClsExtra: 0,
            cbWndExtra: 0,
            hInstance: HINSTANCE(instance.0),
            hIcon: HICON::default(),
            hCursor: HCURSOR::default(),
            hbrBackground: CreateSolidBrush(SURFACE_COLOR),
            lpszMenuName: PCWSTR::null(),
            lpszClassName: CLASS_NAME,
        };
        // RegisterClassW returns 0 both on real failures and when the class
        // already exists (e.g. after a dev-mode reload); the latter is fine
        // because the registration is identical.
        if RegisterClassW(&class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
            let err = GetLastError();
            return Err(Error::Platform(format!("RegisterClassW failed: {err:?}")));
        }

        let child = CreateWindowExW(
            WINDOW_EX_STYLE(0),
            CLASS_NAME,
            w!("BatPlayer video surface"),
            WS_CHILD | WS_VISIBLE,
            0,
            0,
            0,
            0, // sized to the client area right after creation
            Some(HWND(parent as *mut c_void)),
            None,
            Some(HINSTANCE(instance.0)),
            None,
        )
        .map_err(|err| Error::Platform(format!("CreateWindowExW failed: {err}")))?;

        // Keep the surface below the transparent webview so HTML controls
        // overlay the video.
        SetWindowPos(
            child,
            Some(HWND_BOTTOM),
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
        )
        .map_err(|err| Error::Platform(format!("SetWindowPos failed: {err}")))?;

        Ok(child.0 as isize)
    }
}

unsafe extern "system" fn video_wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) }
}

// ---------------------------------------------------------------------------
// Frameless drag-resize ring
// ---------------------------------------------------------------------------
// Tauri's runtime attaches its frameless resize ring (tauri-runtime-wry's
// `undecorated_resizing`) only when a webview is built as the window's own
// content (`WebviewKind::WindowContent`). BatPlayer adds its webview manually
// with `Window::add_child`, which yields `WebviewKind::WindowChild`, so no
// ring is attached: the transparent webview then swallows every
// `WM_NCHITTEST` near the window edges and frameless edge-drag resizing
// (including dragging the window onto Snap zones) never engages.
//
// This module replicates the runtime's ring — same class/window names,
// hit-test math and cutout region — for our manually added webview. Keeping
// the names identical also makes Tauri's own `attach_resize_handler`
// early-return instead of adding a second ring if a future version starts
// attaching one for child webviews.

const RING_CLASS: PCWSTR = w!("TAURI_DRAG_RESIZE_BORDERS");
const RING_WINDOW: PCWSTR = w!("TAURI_DRAG_RESIZE_WINDOW");

/// Edge flags for the `WM_NCHITTEST` mask (left/right/top/bottom bits).
const RING_LEFT: i32 = 0b0001;
const RING_RIGHT: i32 = 0b0010;
const RING_TOP: i32 = 0b0100;
const RING_BOTTOM: i32 = 0b1000;
// Combined corners, evaluated as single values for the match below.
const RING_TOPLEFT: i32 = RING_TOP | RING_LEFT;
const RING_TOPRIGHT: i32 = RING_TOP | RING_RIGHT;
const RING_BOTTOMLEFT: i32 = RING_BOTTOM | RING_LEFT;
const RING_BOTTOMRIGHT: i32 = RING_BOTTOM | RING_RIGHT;

struct RingParentData {
    child: isize,
}

/// Attaches the invisible edge ring that makes `decorations(false)` windows
/// edge-drag resizable although the webview covers the whole client area.
pub fn attach_resize_ring(window: &tauri::Window) -> Result<(), Error> {
    let parent = window
        .hwnd()
        .map_err(|err| Error::Platform(format!("failed to get the window HWND: {err}")))?
        .0 as isize;

    // Safety: runs on the Tauri main thread (setup hook); all handles belong
    // to this process and the ring is created at most once per window.
    unsafe { create_ring(parent) }
}

unsafe fn create_ring(parent_id: isize) -> Result<(), Error> {
    unsafe {
        let parent = HWND(parent_id as *mut c_void);

        // Idempotent guard; also covers Tauri's own ring, which shares these
        // class and window names.
        if FindWindowExW(Some(parent), None, RING_CLASS, RING_WINDOW).is_ok() {
            return Ok(());
        }

        let instance = GetModuleHandleW(None)
            .map_err(|err| Error::Platform(format!("GetModuleHandleW failed: {err}")))?;

        let class = WNDCLASSW {
            style: WNDCLASS_STYLES::default(),
            lpfnWndProc: Some(ring_wnd_proc),
            cbClsExtra: 0,
            cbWndExtra: 0,
            hInstance: HINSTANCE(instance.0),
            hIcon: HICON::default(),
            hCursor: HCURSOR::default(),
            hbrBackground: HBRUSH::default(),
            lpszMenuName: PCWSTR::null(),
            lpszClassName: RING_CLASS,
        };
        if RegisterClassW(&class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
            let err = GetLastError();
            return Err(Error::Platform(format!("RegisterClassW failed: {err:?}")));
        }

        let mut rect = RECT::default();
        GetClientRect(parent, &mut rect)
            .map_err(|err| Error::Platform(format!("GetClientRect failed: {err}")))?;
        let width = rect.right - rect.left;
        let height = rect.bottom - rect.top;

        let child = CreateWindowExW(
            WINDOW_EX_STYLE(0),
            RING_CLASS,
            RING_WINDOW,
            WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
            0,
            0,
            width,
            height,
            Some(parent),
            None,
            Some(HINSTANCE(instance.0)),
            None,
        )
        .map_err(|err| Error::Platform(format!("CreateWindowExW failed: {err}")))?;

        set_ring_region(child, width, height);

        // Raise the ring above the webview: only its outer edge band
        // intercepts the mouse, the cutout region passes everything else on.
        let _ = SetWindowPos(
            child,
            Some(HWND_TOP),
            0,
            0,
            0,
            0,
            SWP_ASYNCWINDOWPOS | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_NOSIZE,
        );

        // The parent subclass keeps the ring fitted to the client area across
        // resizes (and strips it while maximized) without app involvement.
        let data = Box::into_raw(Box::new(RingParentData {
            child: child.0 as isize,
        }));
        let _ = SetWindowSubclass(
            parent,
            Some(parent_wnd_proc),
            (WM_USER + 1) as usize,
            data as usize,
        );

        Ok(())
    }
}

unsafe extern "system" fn parent_wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
    _id: usize,
    data: usize,
) -> LRESULT {
    unsafe {
        match msg {
            WM_SIZE => {
                let state = &*(data as *const RingParentData);
                let child = HWND(state.child as *mut c_void);
                if IsZoomed(hwnd).as_bool() {
                    // Strip the ring while maximized so the edges stay inert.
                    let _ = SetWindowPos(
                        child,
                        Some(HWND_TOP),
                        0,
                        0,
                        0,
                        0,
                        SWP_ASYNCWINDOWPOS | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOMOVE,
                    );
                } else {
                    let mut rect = RECT::default();
                    if GetClientRect(hwnd, &mut rect).is_ok() {
                        let width = rect.right - rect.left;
                        let height = rect.bottom - rect.top;
                        let _ = SetWindowPos(
                            child,
                            Some(HWND_TOP),
                            0,
                            0,
                            width,
                            height,
                            SWP_ASYNCWINDOWPOS | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOMOVE,
                        );
                        set_ring_region(child, width, height);
                    }
                }
            }
            WM_NCDESTROY => drop(Box::from_raw(data as *mut RingParentData)),
            _ => {}
        }

        DefSubclassProc(hwnd, msg, wparam, lparam)
    }
}

unsafe extern "system" fn ring_wnd_proc(
    child: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    unsafe {
        match msg {
            WM_NCHITTEST => LRESULT(match edge_at(child, lparam) {
                Some(edge) => edge as isize,
                None => HTTRANSPARENT as isize,
            }),
            WM_NCLBUTTONDOWN => {
                if let Some(edge) = edge_at(child, lparam) {
                    // Forward like a native frame-border click so the OS runs
                    // its own modal sizing loop for the parent window.
                    let points = POINTS {
                        x: GET_X_LPARAM(lparam),
                        y: GET_Y_LPARAM(lparam),
                    };
                    if let Ok(parent) = GetParent(child) {
                        let _ = PostMessageW(
                            Some(parent),
                            WM_NCLBUTTONDOWN,
                            WPARAM(edge as _),
                            LPARAM(&points as *const _ as _),
                        );
                    }
                }
                LRESULT(0)
            }
            _ => DefWindowProcW(child, msg, wparam, lparam),
        }
    }
}

/// The edge/corner at the cursor (native `WM_NCHITTEST` screen coordinates),
/// or `None` when the parent is not drag-resizable or the point sits inside.
unsafe fn edge_at(child: HWND, lparam: LPARAM) -> Option<u32> {
    unsafe {
        // The parent must still be resizable (WS_SIZEBOX).
        let parent = GetParent(child).ok()?;
        if GetWindowLongPtrW(parent, GWL_STYLE) as u32 & WS_SIZEBOX.0 == 0 {
            return None;
        }

        let mut rect = RECT::default();
        GetWindowRect(child, &mut rect).ok()?;

        let dpi = GetDpiForWindow(child);
        let border_x = GetSystemMetricsForDpi(SM_CXFRAME, dpi);
        let border_y = GetSystemMetricsForDpi(SM_CYFRAME, dpi);

        let (cx, cy) = (GET_X_LPARAM(lparam) as i32, GET_Y_LPARAM(lparam) as i32);
        let mask = (RING_LEFT * (cx < rect.left + border_x) as i32)
            | (RING_RIGHT * (cx >= rect.right - border_x) as i32)
            | (RING_TOP * (cy < rect.top + border_y) as i32)
            | (RING_BOTTOM * (cy >= rect.bottom - border_y) as i32);

        let edge = match mask {
            RING_LEFT => HTLEFT,
            RING_RIGHT => HTRIGHT,
            RING_TOP => HTTOP,
            RING_BOTTOM => HTBOTTOM,
            RING_TOPLEFT => HTTOPLEFT,
            RING_TOPRIGHT => HTTOPRIGHT,
            RING_BOTTOMLEFT => HTBOTTOMLEFT,
            RING_BOTTOMRIGHT => HTBOTTOMRIGHT,
            _ => return None,
        };
        Some(edge)
    }
}

/// Cuts the middle out of the ring so only the outer edge band receives the
/// mouse; everything else passes through to the webview beneath it.
unsafe fn set_ring_region(child: HWND, width: i32, height: i32) {
    unsafe {
        let dpi = GetDpiForWindow(child);
        let border_x = GetSystemMetricsForDpi(SM_CXFRAME, dpi);
        let border_y = GetSystemMetricsForDpi(SM_CYFRAME, dpi);

        let mut region = CreateRectRgn(0, 0, width, height);
        let inner = Owned::new(CreateRectRgn(
            border_x,
            border_y,
            width - border_x,
            height - border_y,
        ));
        CombineRgn(Some(region), Some(region), Some(*inner), RGN_DIFF);

        // The system owns the region on success; free it ourselves on failure.
        if SetWindowRgn(child, Some(region), true) == 0 {
            region.free();
        }
    }
}

/// Implementations of the `GET_X_LPARAM`/`GET_Y_LPARAM` macros.
#[allow(non_snake_case)]
#[inline]
fn GET_X_LPARAM(lparam: LPARAM) -> i16 {
    ((lparam.0 as usize) & 0xFFFF) as u16 as i16
}

#[allow(non_snake_case)]
#[inline]
fn GET_Y_LPARAM(lparam: LPARAM) -> i16 {
    (((lparam.0 as usize) & 0xFFFF_0000) >> 16) as u16 as i16
}
