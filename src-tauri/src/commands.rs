//! Tauri commands: the frontend's only entry point into the player.

use tauri::{Manager, State};

use crate::player::{Player, PlayerError};

type PlayerResult = Result<(), String>;
type ScreenshotResult = Result<String, String>;

fn map(err: PlayerError) -> String {
    err.to_string()
}

#[tauri::command]
pub fn load_file(path: String, player: State<'_, Player>) -> PlayerResult {
    player.load_file(&path).map_err(map)
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
pub fn set_volume(volume: f64, player: State<'_, Player>) -> PlayerResult {
    player.set_volume(volume).map_err(map)
}

#[tauri::command]
pub fn set_mute(mute: bool, player: State<'_, Player>) -> PlayerResult {
    player.set_mute(mute).map_err(map)
}

#[tauri::command]
pub fn set_speed(speed: f64, player: State<'_, Player>) -> PlayerResult {
    player.set_speed(speed).map_err(map)
}

#[tauri::command]
pub fn cycle_audio(player: State<'_, Player>) -> PlayerResult {
    player.cycle_audio().map_err(map)
}

#[tauri::command]
pub fn cycle_subtitle(player: State<'_, Player>) -> PlayerResult {
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
