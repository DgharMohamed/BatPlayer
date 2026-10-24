//! BatPlayer — a modern cross-platform media player.
//!
//! Milestone 2: libmpv renders into the native child window created by
//! [`platform`], and the transparent webview layered above it carries the
//! HTML controls. The frontend never touches mpv: it calls the commands in
//! [`commands`] and listens for [`player::PlayerEvent`]s.

mod commands;
pub mod history;
pub(crate) mod media_scan;
pub mod open_with;
pub mod platform;
mod player;
pub(crate) mod settings;
pub mod storage;

use std::time::Duration;

use tauri::{
    LogicalPosition, LogicalSize, Manager, WebviewUrl, WindowEvent, webview::WebviewBuilder,
};

use player::Player;

#[cfg(debug_assertions)]
mod autotest;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // File arguments this process was launched with (Explorer ▸ "Open with",
    // file-association double-clicks). The single-instance plugin below only
    // reports SECOND launches, so this process's own argv is captured here;
    // consumed by the webview's boot pull in setup.
    let cwd = std::env::current_dir();
    let boot_files = open_with::open_file_candidates(
        &std::env::args().collect::<Vec<_>>(),
        cwd.as_deref().ok(),
    );

    tauri::Builder::default()
        // Registered first by plugin convention: a second launch (chosen
        // while BatPlayer already runs) forwards its "Open with" arguments
        // to this instance instead of opening a bare second player.
        .plugin(tauri_plugin_single_instance::init(|app, argv, cwd| {
            open_with::forward_launch(app, argv, std::path::Path::new(&cwd));
        }))
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            commands::load_file,
            commands::save_position,
            commands::resolve_media_paths,
            open_with::take_pending_open_files,
            commands::autotest_scene_names,
            commands::autotest_log,
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
            commands::set_playlist_dock,
            commands::open_external,
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
            app.manage(surface.clone());

            // The runtime's frameless drag-resize ring only attaches for
            // windows that own their webview content; ours is added with
            // add_child, so attach the equivalent ring ourselves. Without it
            // the transparent webview eats every WM_NCHITTEST at the window
            // edges: no edge-drag resizing, no Snap-by-drag. Degradable, so a
            // failure is logged instead of failing the boot.
            if let Err(err) = platform::attach_resize_ring(&window) {
                eprintln!("failed to attach the frameless resize ring: {err}");
            }

            // mpv owns the surface from here on; its event thread forwards
            // property changes to the webview as `player-event`s. The
            // persisted volume/mute is applied before any event can arrive.
            let data_dir = app.path().app_data_dir()?;
            let settings = settings::Settings::open(&data_dir);
            let audio = settings.audio();
            app.manage(Player::new(surface.wid()?, app.handle().clone(), audio)?);

            let app_handle = app.handle().clone();
            window.on_window_event(move |event| {
                if let WindowEvent::Resized(_) = event
                    && let Err(err) = surface.resize_to_fit()
                {
                    eprintln!("failed to resize the video surface: {err}");
                }
                // The fullscreen transition settles its client size over
                // several events, and mpv's `wid` renderer can latch onto a
                // transient one and keep presenting at that stale geometry
                // (picture top-left, rest of the screen black). Once the
                // resize burst is over, force two WM_SIZE steps so mpv
                // re-reads the settled size. Redundant nudges are harmless.
                let nudger = surface.clone();
                let handle = app_handle.clone();
                std::thread::spawn(move || {
                    std::thread::sleep(Duration::from_millis(250));
                    let _ = handle.run_on_main_thread(move || {
                        if let Err(err) = nudger.force_repaint() {
                            eprintln!("failed to nudge the video surface: {err}");
                        }
                    });
                });
            });

            // Persisted recent-files state for the File menu (Milestone 3),
            // plus the resume points and audio settings read above.
            app.manage(history::History::open(&data_dir));
            app.manage(settings);

            // Hand this launch's own command-line media paths to the open-with
            // queue (delivered on the webview's boot pull), then publish the
            // state so second-instance callbacks can push to it.
            let pending = open_with::PendingOpenFiles::default();
            pending.enqueue(app.handle(), boot_files);
            app.manage(pending);

            // Optional env-var driven self-test (scripts/autotest.ps1).
            #[cfg(debug_assertions)]
            autotest::kick(app.handle().clone());

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running BatPlayer");
}
