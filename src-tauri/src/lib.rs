//! BatPlayer — a modern cross-platform media player.
//!
//! Milestone 2: libmpv renders into the native child window created by
//! [`platform`], and the transparent webview layered above it carries the
//! HTML controls. The frontend never touches mpv: it calls the commands in
//! [`commands`] and listens for [`player::PlayerEvent`]s.

mod commands;
pub mod history;
pub mod platform;
mod player;

use tauri::{
    LogicalPosition, LogicalSize, Manager, WebviewUrl, WindowEvent, webview::WebviewBuilder,
};

use player::Player;

#[cfg(debug_assertions)]
mod autotest;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            commands::load_file,
            commands::play_pause,
            commands::stop,
            commands::seek_to,
            commands::seek_by,
            commands::set_volume,
            commands::set_mute,
            commands::set_speed,
            commands::cycle_audio,
            commands::cycle_subtitle,
            commands::add_subtitle_file,
            commands::frame_step,
            commands::screenshot,
            commands::recent_files,
            commands::clear_history,
        ])
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
                .decorations(false)
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

            // Native surface that mpv renders into. It stays below the
            // transparent webview so the HTML controls overlay the video.
            let surface = platform::VideoSurface::attach(&window)?;
            surface.resize_to_fit()?;

            // mpv owns the surface from here on; its event thread forwards
            // property changes to the webview as `player-event`s.
            app.manage(Player::new(surface.wid()?, app.handle().clone())?);

            // Persisted recent-files state for the File menu (Milestone 3).
            let data_dir = app.path().app_data_dir()?;
            app.manage(history::History::open(&data_dir));

            // Optional env-var driven self-test (scripts/autotest.ps1).
            #[cfg(debug_assertions)]
            autotest::kick(app.handle().clone());

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
