//! Windows video surface: an empty native child window that mpv will render
//! into via the `wid` option (Milestone 2). It is created with a near-black
//! background and kept at the bottom of the window's z-order so the
//! transparent webview above it lets the video show through.

use std::ffi::c_void;

use windows::Win32::Foundation::{
    COLORREF, ERROR_CLASS_ALREADY_EXISTS, GetLastError, HINSTANCE, HWND, LPARAM, LRESULT, RECT,
    WPARAM,
};
use windows::Win32::Graphics::Gdi::CreateSolidBrush;
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CS_HREDRAW, CS_VREDRAW, CreateWindowExW, DefWindowProcW, GetClientRect, HCURSOR, HICON,
    HWND_BOTTOM, RegisterClassW, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SetWindowPos,
    WINDOW_EX_STYLE, WNDCLASSW, WS_CHILD, WS_VISIBLE,
};
use windows::core::{PCWSTR, w};

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

    /// Fits the surface to the parent's client area, re-asserting that it
    /// stays below the webview.
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
