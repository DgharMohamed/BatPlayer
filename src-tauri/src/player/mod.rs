//! mpv playback engine.
//!
//! All libmpv access lives behind [`Player`]: the Tauri command layer talks
//! only to this struct, and the UI only sees the emitted
//! [`PlayerEvent`]s. libmpv's client API is thread-safe, so commands call
//! into the shared [`Mpv`] handle directly while a dedicated thread pumps
//! `mpv_wait_event` and forwards property changes to the webview.

use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::time::{Duration, Instant};

use libmpv2::events::{Event, PropertyData};
use libmpv2::{Format, Mpv, MpvInitializer, mpv_end_file_reason};
use serde::Serialize;
use tauri::{AppHandle, Emitter};

use crate::settings::AudioState;

/// Maximum rate for `time-pos` updates pushed to the frontend (30 fps).
const TIME_POS_MIN_INTERVAL: Duration = Duration::from_millis(33);

#[derive(Debug, thiserror::Error)]
pub enum PlayerError {
    #[error("mpv error: {0}")]
    Mpv(#[from] libmpv2::Error),

    #[error("failed to start the mpv event loop: {0}")]
    EventLoop(String),

    #[error("no suitable screenshot folder was found")]
    NoScreenshotDir,
}

/// Event pushed to the frontend on the `player-event` channel.
#[derive(Clone, Debug, Serialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum PlayerEvent {
    /// An observed property changed. `value` is a number, boolean or string.
    Property {
        name: String,
        value: serde_json::Value,
    },
    /// A new file started loading.
    StartFile,
    /// The file finished loading and playback is starting.
    FileLoaded,
    /// Playback of the current file ended; `error` is set when it failed.
    EndFile { error: Option<String> },
}

/// Where a track cycle landed: the 1-based position of the now-current track
/// among the tracks of that type, and how many of that type the file has.
/// `current` is 0 when the type is switched off (or the file has none).
#[derive(Clone, Copy, Debug, Serialize)]
pub struct TrackInfo {
    pub current: u32,
    pub total: u32,
}

pub struct Player {
    mpv: Arc<Mpv>,
    shutdown: Arc<AtomicBool>,
    event_thread: Option<std::thread::JoinHandle<()>>,
}

impl Player {
    /// Creates the mpv instance rendering into the native `wid` surface and
    /// starts the event-loop thread. `audio` applies the persisted volume
    /// and mute before the first event reaches the frontend.
    pub fn new(wid: i64, app: AppHandle, audio: AudioState) -> Result<Self, PlayerError> {
        let mpv = Mpv::with_initializer(|init: MpvInitializer| {
            configure(init, wid)?;
            Ok(())
        })?;

        let mpv = Arc::new(mpv);

        // Only set what differs from mpv's defaults; a no-op set fires a
        // property event for nothing, which would wake the frontend during
        // startup for no visible change.
        let default_audio = AudioState::default();
        if audio.volume != default_audio.volume
            && let Err(err) = mpv.set_property("volume", audio.volume)
        {
            eprintln!("failed to restore the saved volume: {err}");
        }
        if audio.mute
            && let Err(err) = mpv.set_property("mute", audio.mute)
        {
            eprintln!("failed to restore the saved mute state: {err}");
        }

        // Observed properties → frontend. ids are stable per property.
        for (id, (name, format)) in (1u64..).zip([
            ("time-pos", Format::Double),
            ("duration", Format::Double),
            ("pause", Format::Flag),
            ("volume", Format::Double),
            ("mute", Format::Flag),
            ("speed", Format::Double),
            ("eof-reached", Format::Flag),
            ("seekable", Format::Flag),
            ("idle-active", Format::Flag),
            ("media-title", Format::String),
        ]) {
            mpv.observe_property(name, format, id)?;
        }

        let shutdown = Arc::new(AtomicBool::new(false));
        let thread_shutdown = Arc::clone(&shutdown);
        let thread_mpv = Arc::clone(&mpv);
        let event_thread = std::thread::Builder::new()
            .name("mpv-events".into())
            .spawn(move || event_loop(thread_mpv, thread_shutdown, app))
            .map_err(|err| PlayerError::EventLoop(err.to_string()))?;

        Ok(Self {
            mpv,
            shutdown,
            event_thread: Some(event_thread),
        })
    }

    pub fn load_file(&self, path: &str) -> Result<(), PlayerError> {
        self.mpv.command("loadfile", &[path])?;
        // A freshly opened file always auto-plays. `pause` is sticky in mpv
        // (keep-open leaves it set at end of file), so clear it explicitly;
        // when it was already false no change event fires, hence the matching
        // `paused` sync on `fileLoaded` in the frontend.
        self.mpv.set_property("pause", false)?;
        Ok(())
    }

    pub fn stop(&self) -> Result<(), PlayerError> {
        self.mpv.command("stop", &[])?;
        Ok(())
    }

    pub fn play_pause(&self) -> Result<(), PlayerError> {
        let paused: bool = self.mpv.get_property("pause")?;
        self.mpv.set_property("pause", !paused)?;
        Ok(())
    }

    pub fn seek_to(&self, seconds: f64) -> Result<(), PlayerError> {
        self.mpv
            .command("seek", &[&seconds.to_string(), "absolute"])?;
        Ok(())
    }

    pub fn seek_by(&self, seconds: f64) -> Result<(), PlayerError> {
        self.mpv.command("seek", &[&seconds.to_string()])?;
        Ok(())
    }

    pub fn set_volume(&self, volume: f64) -> Result<(), PlayerError> {
        self.mpv.set_property("volume", volume)?;
        Ok(())
    }

    pub fn set_mute(&self, mute: bool) -> Result<(), PlayerError> {
        self.mpv.set_property("mute", mute)?;
        Ok(())
    }

    pub fn set_speed(&self, speed: f64) -> Result<(), PlayerError> {
        self.mpv.set_property("speed", speed)?;
        Ok(())
    }

    /// Cycles the audio track; the result says where it landed.
    pub fn cycle_audio(&self) -> Result<TrackInfo, PlayerError> {
        self.mpv.command("cycle", &["audio"])?;
        Ok(track_info(&self.mpv, "aid", "audio"))
    }

    /// Cycles the subtitle track; the result says where it landed.
    pub fn cycle_subtitle(&self) -> Result<TrackInfo, PlayerError> {
        self.mpv.command("cycle", &["sub"])?;
        Ok(track_info(&self.mpv, "sid", "sub"))
    }

    pub fn add_subtitle_file(&self, path: &str) -> Result<(), PlayerError> {
        self.mpv.command("sub-add", &[path, "select"])?;
        Ok(())
    }

    /// `direction` is +1 for forward, -1 for backward.
    pub fn frame_step(&self, direction: i32) -> Result<(), PlayerError> {
        let cmd = if direction >= 0 {
            "frame-step"
        } else {
            "frame-back-step"
        };
        self.mpv.command(cmd, &[])?;
        Ok(())
    }

    pub fn screenshot(&self, folder: &std::path::Path) -> Result<std::path::PathBuf, PlayerError> {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or_default();
        let path = folder.join(format!("batplayer-{stamp}.png"));
        self.dump_screenshot(&path)?;
        Ok(path)
    }

    /// Saves a snapshot of the currently decoded frame to an exact path.
    ///
    /// `screenshot-to-file` writes the *video frame*, not the window
    /// composite, so it also serves the end-to-end checks in
    /// `scripts/autotest.ps1` and the `autotest` module.
    pub(crate) fn dump_screenshot(&self, path: &std::path::Path) -> Result<(), PlayerError> {
        let path_str = path.to_string_lossy().into_owned();
        self.mpv.command("screenshot-to-file", &[&path_str])?;
        Ok(())
    }
}

impl Drop for Player {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Some(thread) = self.event_thread.take() {
            let _ = thread.join();
        }
    }
}

/// Reads the position of the current audio/subtitle track. `selector` is
/// mpv's `aid`/`sid`; anything that is not a positive number ("no", "auto")
/// counts as switched off.
fn track_info(mpv: &Mpv, selector: &str, kind: &str) -> TrackInfo {
    let current = match mpv.get_property::<String>(selector) {
        Ok(text) => text.parse::<i64>().unwrap_or(0),
        Err(_) => mpv.get_property::<i64>(selector).unwrap_or(0),
    };
    let count = mpv.get_property::<i64>("track-list/count").unwrap_or(0);
    let mut total = 0u32;
    let mut position = 0u32;
    for index in 0..count {
        let entry = format!("track-list/{index}");
        let matches_kind = mpv
            .get_property::<String>(&format!("{entry}/type"))
            .is_ok_and(|value| value == kind);
        if !matches_kind {
            continue;
        }
        total += 1;
        if current > 0
            && mpv
                .get_property::<i64>(&format!("{entry}/id"))
                .is_ok_and(|id| id == current)
        {
            position = total;
        }
    }
    TrackInfo {
        current: position,
        total,
    }
}

fn configure(init: MpvInitializer, wid: i64) -> Result<(), libmpv2::Error> {
    // Render into the native video surface; the transparent webview above it
    // carries the HTML controls.
    init.set_option("wid", wid)?;
    // Stay alive without a file; pause at end-of-file instead of unloading.
    init.set_option("idle", true)?;
    init.set_option("keep-open", true)?;
    // BatPlayer ships its own UI: no mpv OSD/controller or default keys.
    init.set_option("osc", false)?;
    init.set_option("input-default-bindings", false)?;
    init.set_option("input-vo-keyboard", false)?;
    // Hardware decoding with the safest API selection.
    init.set_option("hwdec", "auto-safe")?;
    // Optional end-to-end diagnostics hook (scripts/autotest.ps1).
    if let Ok(log_file) = std::env::var("BATPLAYER_MPV_LOG")
        && !log_file.is_empty()
    {
        init.set_option("msg-level", "all=v".to_string())?;
        init.set_option("log-file", log_file)?;
    }
    Ok(())
}

fn event_loop(mpv: Arc<Mpv>, shutdown: Arc<AtomicBool>, app: AppHandle) {
    let mut last_time_pos = Instant::now()
        .checked_sub(TIME_POS_MIN_INTERVAL)
        .unwrap_or_else(Instant::now);

    while !shutdown.load(Ordering::Relaxed) {
        // The timeout doubles as the shutdown check interval.
        let Some(event) = mpv.wait_event(0.5) else {
            continue;
        };
        let payload = match event {
            Ok(Event::PropertyChange { name, change, .. }) => {
                let value = match change {
                    PropertyData::Double(v) => serde_json::Value::from(v),
                    PropertyData::Int64(v) => serde_json::Value::from(v),
                    PropertyData::Flag(v) => serde_json::Value::from(v),
                    PropertyData::Str(v) | PropertyData::OsdStr(v) => serde_json::Value::from(v),
                };
                // time-pos arrives at up to frame rate; throttle the event
                // traffic to the frontend instead.
                if name == "time-pos" {
                    let now = Instant::now();
                    if now.duration_since(last_time_pos) < TIME_POS_MIN_INTERVAL {
                        continue;
                    }
                    last_time_pos = now;
                }
                PlayerEvent::Property {
                    name: name.to_string(),
                    value,
                }
            }
            Ok(Event::StartFile) => PlayerEvent::StartFile,
            Ok(Event::FileLoaded) => PlayerEvent::FileLoaded,
            Ok(Event::EndFile(reason)) => {
                let error = if reason == mpv_end_file_reason::Error {
                    Some("the file could not be played".to_string())
                } else {
                    None
                };
                PlayerEvent::EndFile { error }
            }
            Ok(_) => continue,
            Err(_) => continue,
        };
        if let Err(err) = app.emit("player-event", &payload) {
            eprintln!("failed to emit a player event: {err}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn player_events_serialize_with_camel_case_tags() {
        let json = serde_json::to_string(&PlayerEvent::Property {
            name: "pause".into(),
            value: serde_json::Value::from(true),
        })
        .expect("serialization is plain JSON");
        assert_eq!(json, r#"{"type":"property","name":"pause","value":true}"#);
    }

    #[test]
    fn track_info_serializes_plain_fields() {
        let json = serde_json::to_string(&TrackInfo {
            current: 2,
            total: 3,
        })
        .expect("serialization is plain JSON");
        assert_eq!(json, r#"{"current":2,"total":3}"#);
    }
}
