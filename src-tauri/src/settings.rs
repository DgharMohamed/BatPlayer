//! Persisted audio settings (volume, mute), so a session restarts with the
//! levels the user left behind (VLC parity: `volume-save`).
//!
//! One small JSON document in the app-data directory, flushed a short
//! debounce after the last change so dragging a slider never hits the disk
//! hundreds of times through the update thread. Same graceful degradation
//! and temp-swap write as [`crate::history`]: a missing or corrupt document
//! falls back to defaults and IO failures are logged, never fatal.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use crate::storage::write_and_swap;

/// How long after the last change the document is rewritten.
const WRITE_DELAY: Duration = Duration::from_millis(400);

/// Volume/mute snapshot applied to every fresh mpv instance.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct AudioState {
    pub volume: f64,
    pub mute: bool,
}

impl Default for AudioState {
    fn default() -> Self {
        Self {
            volume: 100.0,
            mute: false,
        }
    }
}

pub struct Settings {
    inner: Arc<Inner>,
    thread: Option<std::thread::JoinHandle<()>>,
}

struct Inner {
    file: PathBuf,
    audio: Mutex<AudioState>,
    /// Flush deadline of a pending change; `None` when there is none. A
    /// separate mutex keeps `set_audio` free of the write-side Condvar.
    schedule: Mutex<Schedule>,
    changed: Condvar,
}

#[derive(Default)]
struct Schedule {
    due: Option<Instant>,
    shutdown: bool,
}

impl Settings {
    /// Loads the settings document under `data_dir`, creating the directory
    /// if needed, and starts the debounced writer thread. A missing or
    /// corrupt document starts from the defaults.
    pub fn open(data_dir: &Path) -> Self {
        if let Err(err) = fs::create_dir_all(data_dir) {
            eprintln!("failed to create the app-data directory: {err}");
        }
        let inner = Arc::new(Inner {
            file: data_dir.join("settings.json"),
            audio: Mutex::new(Self::read(&data_dir.join("settings.json"))),
            schedule: Mutex::new(Schedule::default()),
            changed: Condvar::new(),
        });
        // The thread only ever calls `flush(&inner)`; its handle keeps
        // shutdown orderly. A failed spawn is a non-fatal edge case — writes
        // fall back to inline flushes without the debounce.
        let writer_inner = Arc::clone(&inner);
        let thread = match std::thread::Builder::new()
            .name("settings-writer".into())
            .spawn(move || writer(writer_inner))
        {
            Ok(thread) => Some(thread),
            Err(err) => {
                eprintln!("failed to start the settings writer: {err}");
                None
            }
        };
        Self { inner, thread }
    }

    fn read(file: &Path) -> AudioState {
        let audio = fs::read_to_string(file)
            .ok()
            .and_then(|body| serde_json::from_str::<AudioState>(&body).ok());
        audio.unwrap_or_default()
    }

    /// The applied-on-startup audio state for a fresh mpv instance.
    pub fn audio(&self) -> AudioState {
        *self.lock_audio()
    }

    /// Updates either half of the audio state and schedules a flush. `None`
    /// leaves a value untouched, so each command sends only what it knows.
    pub fn set_audio(&self, volume: Option<f64>, mute: Option<bool>) {
        let mut audio = self.lock_audio();
        let changed =
            volume.is_some_and(|v| v != audio.volume) || mute.is_some_and(|m| m != audio.mute);
        if let Some(volume) = volume {
            audio.volume = volume;
        }
        if let Some(mute) = mute {
            audio.mute = mute;
        }
        drop(audio);
        if !changed {
            return;
        }
        if self.thread.is_none() {
            // No writer thread (failed spawn): keep saving, just every time.
            flush(&self.inner);
            return;
        }
        let mut schedule = self.lock_schedule();
        schedule.due = Some(Instant::now() + WRITE_DELAY);
        self.inner.changed.notify_all();
    }

    fn lock_audio(&self) -> MutexGuard<'_, AudioState> {
        self.inner
            .audio
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn lock_schedule(&self) -> MutexGuard<'_, Schedule> {
        self.inner
            .schedule
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Rewrites the document now (used on drop): last changes are not lost
    /// to a pending debounce at exit.
    fn flush_now(&self) {
        // Mirrors the writer's shutdown path, for the inline fallback.
        flush(&self.inner);
    }
}

impl Drop for Settings {
    fn drop(&mut self) {
        {
            let mut schedule = self.lock_schedule();
            schedule.shutdown = true;
            self.inner.changed.notify_all();
        }
        if self.thread.is_none() {
            self.flush_now();
        }
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

/// Wakes when a change is scheduled, waits out the debounce (fresh changes
/// push the deadline) and rewrites the document. One pending flush at a
/// time; failures collapse to logging, the next change retries.
fn writer(inner: Arc<Inner>) {
    let mut schedule = lock(&inner.schedule);
    loop {
        if schedule.shutdown {
            // Save a change queued within the last debounce window.
            if schedule.due.take().is_some() {
                flush(&inner);
            }
            return;
        }
        match schedule.due {
            None => {
                schedule = wait_inner(&inner, schedule);
            }
            Some(due) => {
                let now = Instant::now();
                if now >= due {
                    schedule.due = None;
                    drop(schedule);
                    flush(&inner);
                    schedule = lock(&inner.schedule);
                } else {
                    schedule = wait_deadline(&inner, schedule, due - now);
                }
            }
        }
    }
}

fn flush(inner: &Inner) {
    let audio = inner
        .audio
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let body = match serde_json::to_string_pretty(&*audio) {
        Ok(body) => body,
        Err(err) => {
            // AudioState serialization cannot actually fail, but the Result
            // return keeps the writing path honest.
            eprintln!("failed to serialize the audio settings: {err}");
            return;
        }
    };
    drop(audio);
    let temp = inner.file.with_extension("json.tmp");
    write_and_swap("the audio settings", &temp, &inner.file, body);
}

/// Recovers from a poisoned lock like history does: the settings may
/// briefly lag, but the player stays up.
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Waits for the next change; recovers from a poisoned lock like history.
fn wait_inner<'a>(
    inner: &'a Inner,
    schedule: MutexGuard<'a, Schedule>,
) -> MutexGuard<'a, Schedule> {
    inner
        .changed
        .wait(schedule)
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn wait_deadline<'a>(
    inner: &'a Inner,
    schedule: MutexGuard<'a, Schedule>,
    timeout: Duration,
) -> MutexGuard<'a, Schedule> {
    match inner.changed.wait_timeout(schedule, timeout) {
        Ok((guard, _)) => guard,
        Err(poisoned) => poisoned.into_inner().0,
    }
}

/// Test-side file read: `Some(volume)` when the document exists and parses.
#[cfg(test)]
impl AudioState {
    fn read_from(dir: &Path) -> Option<f64> {
        let body = fs::read_to_string(dir.join("settings.json")).ok()?;
        let parsed: AudioState = serde_json::from_str(&body).ok()?;
        Some(parsed.volume)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "batplayer-settings-test-{}-{}-{tag}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |dur| u64::try_from(dur.as_millis()).unwrap_or(0))
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_missing_document_starts_from_defaults() {
        let dir = scratch("defaults");
        let settings = Settings::open(&dir);
        assert_eq!(settings.audio(), AudioState::default());
    }

    #[test]
    fn a_corrupt_document_starts_from_defaults() {
        let dir = scratch("corrupt");
        fs::write(dir.join("settings.json"), "{ not json").unwrap();
        let settings = Settings::open(&dir);
        assert_eq!(settings.audio(), AudioState::default());
    }

    #[test]
    fn flushes_changes_after_the_debounce() {
        let dir = scratch("debounce");
        {
            let settings = Settings::open(&dir);
            settings.set_audio(Some(72.0), None);
            // Not written yet: the debounce is pending.
            assert_eq!(AudioState::read_from(&dir), None);
        }
        // Drop flushed the pending change synchronously.
        assert_eq!(AudioState::read_from(&dir).as_ref(), Some(&72.0));

        let reopened = Settings::open(&dir);
        assert_eq!(reopened.audio().volume, 72.0);
    }

    #[test]
    fn dropping_without_changes_writes_no_document() {
        let dir = scratch("noop");
        {
            let settings = Settings::open(&dir);
            // Same values as the defaults: nothing to save.
            settings.set_audio(Some(100.0), None);
            settings.set_audio(None, Some(false));
        }
        assert!(!dir.join("settings.json").exists());
    }
}
