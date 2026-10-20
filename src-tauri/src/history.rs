//! Persisted file history: recently opened media paths for the File menu's
//! "Open Recent" section (resume positions follow later milestones).
//!
//! One small JSON document in the app-data directory, rewritten on every
//! change through a temp file so a crash mid-write cannot truncate it.
//! Failures degrade gracefully on purpose: a missing or corrupt document,
//! an unwritable directory or a full disk never take the app down — the
//! list simply stays whatever it last had and saves are retried on the
//! next change.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

/// Entries beyond this count fall off the list entirely; the File menu
/// displays at most the newest few.
const KEEP: usize = 20;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecentEntry {
    /// Absolute path of the media file.
    pub path: String,
    /// Unix milliseconds of the most recent open.
    pub opened_at: u64,
}

/// Shared, mutex-guarded history managed by Tauri and touched by the
/// `load_file` command on every successful open.
pub struct History {
    /// Destination document for [`History::save`].
    file: PathBuf,
    entries: Mutex<Vec<RecentEntry>>,
}

impl History {
    /// Loads the history document under `data_dir`, creating the directory
    /// if needed. A missing or corrupt document starts an empty list.
    pub fn open(data_dir: &Path) -> Self {
        if let Err(err) = fs::create_dir_all(data_dir) {
            eprintln!("failed to create the app-data directory: {err}");
        }
        let file = data_dir.join("history.json");
        // Missing or corrupt documents (old versions, manual edits, a past
        // crash) both mean the same thing: start over.
        let entries = fs::read_to_string(&file)
            .ok()
            .and_then(|body| serde_json::from_str::<Vec<RecentEntry>>(&body).ok())
            .unwrap_or_default();
        Self {
            file,
            entries: Mutex::new(entries),
        }
    }

    /// Records an open of `path`: deduplicates, moves the file to the front
    /// and caps the list at [`KEEP`]. Persisted immediately; IO problems
    /// still keep the change in memory.
    pub fn record(&self, path: &str) {
        let mut entries = self.lock();
        entries.retain(|entry| entry.path != path);
        entries.insert(
            0,
            RecentEntry {
                path: path.to_string(),
                opened_at: now_ms(),
            },
        );
        entries.truncate(KEEP);
        self.save(&entries);
    }

    /// The recent list, newest first, pruned of files that no longer exist
    /// on disk. The prune is persisted so dead entries do not linger.
    pub fn recent(&self) -> Vec<RecentEntry> {
        let mut entries = self.lock();
        let before = entries.len();
        entries.retain(|entry| Path::new(&entry.path).exists());
        if entries.len() != before {
            self.save(&entries);
        }
        entries.clone()
    }

    /// Wipes the whole list (File ▸ "Clear Recent Files").
    pub fn clear(&self) {
        let mut entries = self.lock();
        entries.clear();
        self.save(&entries);
    }

    /// Recovers a poisoned mutex instead of panicking commands: the list
    /// may briefly lag, but the player keeps running.
    fn lock(&self) -> MutexGuard<'_, Vec<RecentEntry>> {
        self.entries.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Rewrites the document through a temp file, replacing old data.
    fn save(&self, entries: &[RecentEntry]) {
        let body = match serde_json::to_string_pretty(entries) {
            Ok(body) => body,
            Err(err) => {
                // Vec<RecentEntry> serialization cannot actually fail, but
                // the Result response is part of the API contract.
                eprintln!("failed to serialize the file history: {err}");
                return;
            }
        };
        let temp = self.file.with_extension("json.tmp");
        write_and_swap(&temp, &self.file, body);
    }
}

/// Writes `body` to `temp`, then swaps it over `target`. The remove-first
/// dance exists because `fs::rename` refuses to replace a file on Windows.
fn write_and_swap(temp: &Path, target: &Path, body: String) {
    if let Err(err) = fs::write(temp, body) {
        eprintln!("failed to save the file history: {err}");
        return;
    }
    let _ = fs::remove_file(target);
    if let Err(err) = fs::rename(temp, target) {
        eprintln!("failed to save the file history: {err}");
    }
}

/// Unix milliseconds of "now", 0 if the clock is before the epoch.
fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |dur| duration_to_ms_offset(&dur))
}

fn duration_to_ms_offset(dur: &std::time::Duration) -> u64 {
    u64::try_from(dur.as_millis()).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Each test gets a fresh, uniquely named scratch directory.
    fn scratch(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "batplayer-history-test-{}-{}-{tag}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0, |dur| duration_to_ms_offset(&dur))
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn touch(path: &Path) {
        fs::write(path, b"x").unwrap();
    }

    #[test]
    fn record_deduplicates_and_orders_newest_first() {
        let dir = scratch("dedup");
        // Entries must exist on disk or the read-time prune drops them.
        let a = dir.join("a.mkv");
        let b = dir.join("b.mkv");
        touch(&a);
        touch(&b);

        let history = History::open(&dir);
        history.record(a.to_str().unwrap());
        history.record(b.to_str().unwrap());
        history.record(a.to_str().unwrap());

        let recent = history.recent();
        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].path, a.to_str().unwrap());
        assert_eq!(recent[1].path, b.to_str().unwrap());
    }

    #[test]
    fn record_caps_the_list_size() {
        let dir = scratch("cap");
        let files: Vec<_> = (0..(KEEP * 2))
            .map(|i| {
                let path = dir.join(format!("f{i}.mkv"));
                touch(&path);
                path
            })
            .collect();

        let history = History::open(&dir);
        for file in &files {
            history.record(file.to_str().unwrap());
        }
        let recent = history.recent();
        assert_eq!(recent.len(), KEEP);
        assert_eq!(recent[0].path, files[files.len() - 1].to_str().unwrap());
    }

    #[test]
    fn recent_prunes_files_that_vanished() {
        let dir = scratch("prune");
        let gone = dir.join("gone.mkv");
        touch(&gone);
        let history = History::open(&dir);
        history.record(gone.to_str().unwrap());
        history.record("Z:\\never-existed.mkv");

        let recent = history.recent();
        assert_eq!(recent.len(), 1);
        assert_eq!(recent[0].path, gone.to_str().unwrap());

        fs::remove_file(&gone).unwrap();
        assert!(history.recent().is_empty());
    }

    #[test]
    fn a_corrupt_document_starts_over() {
        let dir = scratch("corrupt");
        fs::write(dir.join("history.json"), "{ not json").unwrap();
        let history = History::open(&dir);
        assert!(history.recent().is_empty());

        let a = dir.join("a.mkv");
        touch(&a);
        history.record(a.to_str().unwrap());
        assert_eq!(history.recent().len(), 1);
    }

    #[test]
    fn the_list_survives_a_reload() {
        let dir = scratch("reload");
        let a = dir.join("a.mkv");
        let b = dir.join("b.mkv");
        touch(&a);
        touch(&b);
        {
            let history = History::open(&dir);
            history.record(a.to_str().unwrap());
            history.record(b.to_str().unwrap());
        }
        let reopened = History::open(&dir);
        let recent = reopened.recent();
        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].path, b.to_str().unwrap());
    }

    #[test]
    fn clear_wipes_the_list_and_the_document() {
        let dir = scratch("clear");
        let history = History::open(&dir);
        history.record("C:\\a.mkv");
        history.clear();
        assert!(history.recent().is_empty());
        assert!(History::open(&dir).recent().is_empty());
    }
}
