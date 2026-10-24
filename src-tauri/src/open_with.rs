//! Windows "Open with" integration: media paths arriving via the command
//! line.
//!
//! BatPlayer receives files through the command line in two ways: its own
//! launch arguments (Explorer ▸ "Open with", file-association launches) and
//! the forwarded arguments of a second launch while the player already runs
//! (handled by `tauri-plugin-single-instance`). Both funnel through
//! [`PendingOpenFiles`]: the webview pulls whatever queued during boot via
//! [`take_pending_open_files`], and later arrivals are pushed as an
//! `open-files` event. Either way the paths play through the same frontend
//! pipeline as drag-and-drop — expansion, playlist replace and resume
//! behavior included.

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, MutexGuard, PoisonError};

use tauri::{AppHandle, Emitter, Manager, State};

/// Command-line media paths the webview has not received yet.
pub struct PendingOpenFiles {
    queue: Mutex<Vec<String>>,
    ready: AtomicBool,
}

impl Default for PendingOpenFiles {
    fn default() -> Self {
        Self {
            queue: Mutex::new(Vec::new()),
            ready: AtomicBool::new(false),
        }
    }
}

impl PendingOpenFiles {
    /// Adds an arrival batch. While the webview boots the paths are queued
    /// (its first pull drains them); after that they are pushed to the
    /// `open-files` listener instead. The handover happens in
    /// [`Self::drain`], which the webview calls once at boot after
    /// subscribing — so an arrival can never end up both queued and pushed.
    pub fn enqueue(&self, app: &AppHandle, paths: Vec<String>) {
        if paths.is_empty() {
            return;
        }
        if !self.ready.load(Ordering::SeqCst) {
            self.queue_lock().extend(paths);
            return;
        }
        if let Err(err) = app.emit("open-files", paths) {
            eprintln!("failed to push the opened files to the webview: {err}");
        }
    }

    /// Empties the queue and flips deliver from pull to push: later arrivals
    /// are emitted to the webview instead of queued. Exactly one caller —
    /// the webview's single boot pull.
    fn drain(&self) -> Vec<String> {
        self.ready.store(true, Ordering::SeqCst);
        std::mem::take(&mut *self.queue_lock())
    }

    fn queue_lock(&self) -> MutexGuard<'_, Vec<String>> {
        // A panic while the queue was locked must not brick the player; the
        // vec is always recoverable.
        self.queue.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// Converts one launch's command line into openable paths: drops the program
/// name (present or not, depending on how the line arrives), command-line
/// flags and self references; resolves relative inputs against the launching
/// working directory.
pub fn open_file_candidates(argv: &[String], cwd: Option<&Path>) -> Vec<String> {
    // The player binary: path equality is case-sensitive on Windows, so the
    // executable's own file name is the reliable self-reference test.
    let exe_name = std::env::current_exe().ok().and_then(|exe| {
        Some(exe.file_name()?.to_ascii_lowercase())
    });

    let mut out = Vec::new();
    for raw in argv {
        let arg = raw.trim();
        if arg.is_empty() || arg.starts_with('-') {
            continue;
        }
        let path = Path::new(arg);
        let is_self = path.file_name().map(|name| name.to_ascii_lowercase())
            == exe_name;
        if is_self {
            continue; // the program itself, not a media path
        }
        if path.is_absolute() {
            out.push(arg.to_owned());
        } else if let Some(cwd) = cwd {
            out.push(cwd.join(path).to_string_lossy().into_owned());
        } else {
            out.push(arg.to_owned());
        }
    }
    out
}

/// Runs on the first instance whenever a second one launches: hands its file
/// arguments to the webview and brings the player to front.
pub fn forward_launch(app: &AppHandle, argv: Vec<String>, cwd: &Path) {
    if let Some(pending) = app.try_state::<PendingOpenFiles>() {
        pending.enqueue(app, open_file_candidates(&argv, Some(cwd)));
    } else {
        eprintln!("a second launch arrived before the open-with state was ready; dropped");
    }
    if let Some(window) = app.get_window("main") {
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

/// The webview's one boot pull: every command-line path since the process
/// started (Explorer ▸ "Open with", association launches). Must be called
/// after subscribing to `open-files` — afterwards arrivals come as pushes.
#[tauri::command]
pub fn take_pending_open_files(pending: State<'_, PendingOpenFiles>) -> Vec<String> {
    pending.drain()
}
