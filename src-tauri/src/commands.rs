//! Tauri commands: the frontend's only entry point into the player.

use serde::Serialize;
use tauri::{Emitter, Manager, State};

use crate::history::{History, RecentEntry};
use crate::media_scan::{MediaResolve, expand_inputs};
use crate::player::{Player, PlayerError, TrackInfo};
use crate::settings::Settings;

type PlayerResult = Result<(), String>;
type TrackResult = Result<TrackInfo, String>;
type ScreenshotResult = Result<String, String>;

fn map(err: PlayerError) -> String {
    err.to_string()
}

/// Notifies the webview that the history list changed, so the File menu
/// re-renders. Failures only leave a stale menu until the next change.
fn notify_history_changed(app: &tauri::AppHandle) {
    if let Err(err) = app.emit("history-changed", ()) {
        eprintln!("failed to notify the history change: {err}");
    }
}

/// The stored resume point of the file about to play, returned by
/// `load_file`. The frontend seeks here once the file finishes loading.
#[derive(Debug, Clone, Copy, Serialize)]
pub struct ResumeHint {
    pub position: f64,
    pub duration: f64,
}

/// Expands drag-dropped or dialog-picked inputs (files and folders) into a
/// flat, sorted media-file queue for the playlist. A pure scan: it touches
/// no player state and reports no errors — unreadable inputs are skipped
/// and truncation is flagged on [`MediaResolve::truncated`].
#[tauri::command]
pub fn resolve_media_paths(paths: Vec<String>) -> MediaResolve {
    expand_inputs(&paths)
}

#[tauri::command]
pub fn load_file(
    path: String,
    app: tauri::AppHandle,
    player: State<'_, Player>,
    history: State<'_, History>,
) -> Result<ResumeHint, String> {
    // Read before any state changes: this is the progress of *previous*
    // sessions of `path`, not of the one starting now.
    let (position, duration) = history.resume_point(&path);
    player.load_file(&path).map_err(map)?;
    // A successful load bumps the file to the top of "Open Recent" —
    // whoever triggered it (dialog, drag-and-drop, recent entry).
    history.record(&path);
    notify_history_changed(&app);
    Ok(ResumeHint { position, duration })
}

/// Periodic and per-navigation progress save for resume-on-reopen. Fire and
/// forget: a failed save costs at most a resume window, never an error.
#[tauri::command]
pub fn save_position(path: String, position: f64, duration: f64, history: State<'_, History>) {
    history.update_position(&path, position, duration);
}

/// The newest first list shown under File ▸ "Open Recent".
#[tauri::command]
pub fn recent_files(history: State<'_, History>) -> Vec<RecentEntry> {
    history.recent()
}

#[tauri::command]
pub fn clear_history(app: tauri::AppHandle, history: State<'_, History>) {
    history.clear();
    notify_history_changed(&app);
}

#[tauri::command]
pub fn play_pause(player: State<'_, Player>) -> PlayerResult {
    player.play_pause().map_err(map)
}

#[tauri::command]
pub fn stop(player: State<'_, Player>) -> PlayerResult {
    player.stop().map_err(map)
}

#[tauri::command]
pub fn seek_to(seconds: f64, player: State<'_, Player>) -> PlayerResult {
    player.seek_to(seconds).map_err(map)
}

#[tauri::command]
pub fn seek_by(seconds: f64, player: State<'_, Player>) -> PlayerResult {
    player.seek_by(seconds).map_err(map)
}

#[tauri::command]
pub fn set_volume(
    volume: f64,
    player: State<'_, Player>,
    settings: State<'_, Settings>,
) -> PlayerResult {
    player.set_volume(volume).map_err(map)?;
    settings.set_audio(Some(volume), None);
    Ok(())
}

#[tauri::command]
pub fn set_mute(
    mute: bool,
    player: State<'_, Player>,
    settings: State<'_, Settings>,
) -> PlayerResult {
    player.set_mute(mute).map_err(map)?;
    settings.set_audio(None, Some(mute));
    Ok(())
}

#[tauri::command]
pub fn set_speed(speed: f64, player: State<'_, Player>) -> PlayerResult {
    player.set_speed(speed).map_err(map)
}

#[tauri::command]
pub fn cycle_audio(player: State<'_, Player>) -> TrackResult {
    player.cycle_audio().map_err(map)
}

#[tauri::command]
pub fn cycle_subtitle(player: State<'_, Player>) -> TrackResult {
    player.cycle_subtitle().map_err(map)
}

#[tauri::command]
pub fn add_subtitle_file(path: String, player: State<'_, Player>) -> PlayerResult {
    player.add_subtitle_file(&path).map_err(map)
}

/// `direction`: +1 steps one frame forward, -1 one frame backward.
#[tauri::command]
pub fn frame_step(direction: i32, player: State<'_, Player>) -> PlayerResult {
    player.frame_step(direction).map_err(map)
}

/// Saves a screenshot to the user's Pictures folder (mpv's default naming
/// convention) and returns the written path.
#[tauri::command]
pub fn screenshot(app: tauri::AppHandle, player: State<'_, Player>) -> ScreenshotResult {
    let folder = app
        .path()
        .picture_dir()
        .or_else(|_| app.path().download_dir())
        .map_err(|_| map(PlayerError::NoScreenshotDir))?;
    player
        .screenshot(&folder)
        .map(|path| path.to_string_lossy().into_owned())
        .map_err(map)
}
