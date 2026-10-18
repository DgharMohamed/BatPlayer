//! BatPlayer — a modern cross-platform media player.
//!
//! Milestone 1 skeleton: an opaque Tauri window hosting a transparent webview
//! layered over a native child window that will carry mpv video output
//! (Milestone 2).

pub mod platform;

use tauri::{LogicalPosition, LogicalSize, WebviewUrl, WindowEvent, webview::WebviewBuilder};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            // The window itself must stay OPAQUE: on Windows, Tauri's
            // window-level transparency (DWM blur-behind) prevents native
            // child windows from compositing, which would hide the video
            // surface entirely. Transparency lives on the webview only, so
            // the HTML controls overlay the native video surface below them.
            let window = tauri::Window::builder(app, "main")
                .title("BatPlayer")
                .inner_size(1280.0, 720.0)
                .min_inner_size(640.0, 360.0)
                .center()
                .build()?;

            let webview = WebviewBuilder::new("main", WebviewUrl::App(Default::default()))
                .transparent(true)
                .auto_resize();
            window.add_child(
                webview,
                LogicalPosition::new(0.0, 0.0),
                LogicalSize::new(1280.0, 720.0),
            )?;

            // Native surface that mpv will render into (Milestone 2). It is
            // kept below the transparent webview so HTML controls overlay
            // the video.
            let surface = platform::VideoSurface::attach(&window)?;
            surface.resize_to_fit()?;

            window.on_window_event(move |event| {
                if let WindowEvent::Resized(_) = event
                    && let Err(err) = surface.resize_to_fit()
                {
                    eprintln!("failed to resize the video surface: {err}");
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running BatPlayer");
}
