//! Optional end-to-end test hooks.
//!
//! Driven only through environment variables (see `scripts/autotest.ps1`):
//!
//! - `BATPLAYER_AUTOTEST_FILE` — media to auto-play right after startup
//! - `BATPLAYER_AUTOTEST_FOLDER` — folder to expand (Rust media scan) and
//!   play the first queued file of, proving the folder-open path
//! - `BATPLAYER_AUTOTEST_SHOT` — exact path for an mpv screenshot (`file`),
//!   taken a moment after playback starts, proving the command round-trip
//! - `BATPLAYER_MPV_LOG` — mpv log file for diagnosing a failing run
//!
//! Normal runs (no such variables) do nothing. Release builds omit the
//! module entirely.

use std::path::PathBuf;
use std::time::Duration;

use tauri::{AppHandle, Manager};

use crate::player::Player;

const FILE_VAR: &str = "BATPLAYER_AUTOTEST_FILE";
const FOLDER_VAR: &str = "BATPLAYER_AUTOTEST_FOLDER";
const SHOT_VAR: &str = "BATPLAYER_AUTOTEST_SHOT";

/// How long mpv gets before the harness screenshot (decode + first frames).
const SHOT_DELAY: Duration = Duration::from_secs(3);

/// Lets playback settle before the UI has to be up.
const START_DELAY: Duration = Duration::from_millis(800);

pub fn kick(app: AppHandle) {
    let media = std::env::var(FILE_VAR)
        .ok()
        .filter(|value| !value.is_empty());
    let folder = std::env::var(FOLDER_VAR)
        .ok()
        .filter(|value| !value.is_empty());
    if media.is_none() && folder.is_none() {
        return;
    }
    let shot = std::env::var(SHOT_VAR)
        .ok()
        .filter(|value| !value.is_empty())
        .map(PathBuf::from);

    // Give the webview a beat so the UI is up before playback begins.
    std::thread::Builder::new()
        .name("autotest".into())
        .spawn(move || {
            std::thread::sleep(START_DELAY);

            let player: tauri::State<Player> = app.state::<Player>();
            if let Some(folder) = folder {
                // Folder smoke test: expand Rust-side exactly as the
                // `resolve_media_paths` command does, log the queue, then
                // play the first file like the frontend's queue would.
                eprintln!("autotest: folder {folder}");
                let resolve = crate::media_scan::expand_inputs(&[folder]);
                eprintln!(
                    "autotest: {} file(s), truncated={}",
                    resolve.files.len(),
                    resolve.truncated
                );
                for file in &resolve.files {
                    eprintln!("autotest: queue {file}");
                }
                // First media file plays: folder expansion feeds `playPaths`.
                if resolve.files.is_empty() {
                    eprintln!("autotest: folder has no playable media");
                    return;
                }
                match player.load_file(&resolve.files[0]) {
                    Ok(hint) => {
                        eprintln!("autotest: loaded {} (resume {hint:?})", resolve.files[0])
                    }
                    Err(error) => {
                        eprintln!("autotest: failed to load {}: {error}", resolve.files[0])
                    }
                }
                return;
            }
            let Some(media) = media else {
                return;
            };
            if let Err(error) = player.load_file(&media) {
                eprintln!("autotest: failed to load {media}: {error}");
                return;
            }
            eprintln!("autotest: loaded {media}");

            let Some(shot) = shot else {
                return;
            };
            std::thread::sleep(SHOT_DELAY.saturating_sub(START_DELAY));
            match player.dump_screenshot(&shot) {
                Ok(()) => eprintln!("autotest: screenshot written to {}", shot.display()),
                Err(error) => eprintln!("autotest: screenshot failed: {error}"),
            }
        })
        .expect("autotest thread spawns alongside the player");
}
