//! Media discovery for folder opens and drag-drops: turns a list of files
//! and folders into a flat media-file queue.
//!
//! Mirrors the extension allowlist in `src/api/player.ts`. Recursion is
//! depth-capped so junction/symlink cycles cannot spin the scan forever,
//! and result-capped so an accidental system-directory drop cannot freeze
//! the UI. Both caps degrade with a `truncated` flag the frontend shows,
//! never with an error.

use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;

/// Media extensions accepted into the queue (mirror of
/// `MEDIA_EXTENSIONS` in `src/api/player.ts`, lowercase).
const MEDIA_EXTS: &[&str] = &[
    "mkv", "mp4", "m4v", "avi", "mov", "webm", "wmv", "flv", "ts", "m2ts", "mts", "mpg", "mpeg",
    "vob", "ogv", "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma",
];

/// Deepest folder level followed during a scan; also the loop-catcher for
/// junctions and symlinks.
const MAX_SCAN_DEPTH: u32 = 32;

/// Files beyond this count stop the scan; the caller is told via
/// [`MediaResolve::truncated`].
const MAX_SCANNED_FILES: usize = 5000;

/// Result of queue-source expansion sent to the frontend.
#[derive(Debug, Clone, Serialize)]
pub struct MediaResolve {
    /// Absolute media-file paths in play order.
    pub files: Vec<String>,
    /// True when the scan stopped at [`MAX_SCANNED_FILES`] or deeper than
    /// [`MAX_SCAN_DEPTH`].
    pub truncated: bool,
}

/// Expands every input (file or folder) into media paths. Single files keep
/// the caller's order; folder contents are collected level by level, each
/// level sorted case-insensitively — a deterministic queue instead of a
/// filesystem-order surprise.
pub fn expand_inputs(inputs: &[String]) -> MediaResolve {
    let mut files: Vec<String> = Vec::new();
    let mut truncated = false;
    for input in inputs {
        let path = Path::new(input);
        if path.is_dir() {
            truncated |= walk_dir(path, 0, &mut files);
        } else if path.is_file() && is_media_path(path) {
            truncated |= push_file(path, &mut files);
        }
    }
    MediaResolve { files, truncated }
}

/// Depth-first collection of one directory. Returns true when the global
/// scan cap hit. Entries of each level are sorted before visiting, so the
/// queue order does not depend on NTFS internals.
fn walk_dir(dir: &Path, depth: u32, files: &mut Vec<String>) -> bool {
    if depth > MAX_SCAN_DEPTH {
        return true;
    }
    let mut entries: Vec<PathBuf> = match fs::read_dir(dir) {
        Ok(read) => read
            .filter_map(|entry| entry.ok().map(|entry| entry.path()))
            .collect(),
        Err(err) => {
            // Unreadable folder (permissions, disconnected drive): skip it,
            // the rest of the input still queues.
            eprintln!("failed to read folder {}: {err}", dir.display());
            return false;
        }
    };
    entries.sort_by_key(|path| path.as_os_str().to_string_lossy().to_lowercase());
    let mut truncated = false;
    for entry in entries {
        if truncated {
            break;
        }
        if entry.is_dir() {
            truncated |= walk_dir(&entry, depth + 1, files);
        } else if entry.is_file() && is_media_path(&entry) {
            truncated |= push_file(&entry, files);
        }
    }
    truncated
}

/// Appends one media path, honouring the global cap. Returns true on the
/// transition to "truncated" so higher frames see it once.
fn push_file(path: &Path, files: &mut Vec<String>) -> bool {
    if files.len() >= MAX_SCANNED_FILES {
        return true;
    }
    files.push(path.to_string_lossy().into_owned());
    files.len() >= MAX_SCANNED_FILES
}

/// `true` when `path`'s extension names a playable media file. The same
/// allowlist as the frontend; extension matching is case-insensitive.
pub fn is_media_path(path: &Path) -> bool {
    match path.extension().and_then(|extension| extension.to_str()) {
        Some(extension) => MEDIA_EXTS.contains(&extension.to_ascii_lowercase().as_str()),
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    /// Each test gets a fresh, uniquely named scratch directory.
    fn scratch(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "batplayer-mediascan-test-{}-{}-{tag}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0, |dur| u64::try_from(dur.as_millis()).unwrap_or(0))
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn put(path: &Path) -> PathBuf {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(path, b"x").unwrap();
        path.to_path_buf()
    }

    fn expand(paths: &[&Path]) -> Vec<String> {
        let inputs: Vec<String> = paths
            .iter()
            .map(|path| path.to_string_lossy().into_owned())
            .collect();
        expand_inputs(&inputs).files
    }

    #[test]
    fn a_folder_expands_recursively_without_non_media() {
        let dir = scratch("expand");
        let nested = put(&dir.join("sub").join("b.wav"));
        let top = put(&dir.join("a.mp4"));
        put(&dir.join("notes.txt"));

        let expected = vec![
            top.to_string_lossy().into_owned(),
            nested.to_string_lossy().into_owned(),
        ];
        assert_eq!(expand(&[&dir]), expected);
    }

    #[test]
    fn file_and_folder_inputs_mix_in_caller_order() {
        let dir = scratch("mix");
        let solo = put(&dir.join("solo.mkv"));
        let folder = dir.join("album");
        put(&folder.join("01 one.mp3"));
        put(&folder.join("02 two.mp3"));

        let files = expand(&[&solo, &folder]);
        assert_eq!(files.len(), 3);
        assert_eq!(files[0], solo.to_string_lossy().into_owned());
        // Folder contents stay sorted case-insensitively.
        assert!(files[1].contains("01 one.mp3"));
        assert!(files[2].contains("02 two.mp3"));
    }

    #[test]
    fn mixed_case_extensions_count_as_media() {
        let dir = scratch("case");
        put(&dir.join("readme.Mp4"));
        let files = expand(&[&dir]);
        assert_eq!(files.len(), 1);
    }

    #[test]
    fn directories_deep_beyond_the_cap_are_pruned() {
        let dir = scratch("deep");
        // One link deeper than the cap, so the walk must stop before the
        // file buried at the bottom of the chain.
        let mut buried_under = dir.clone();
        for level in 0..(MAX_SCAN_DEPTH + 2) {
            buried_under = buried_under.join(format!("d{level}"));
        }
        let buried = put(&buried_under.join("deep.wav"));
        let resolve = expand_inputs(&[dir.to_string_lossy().into_owned()]);
        // The whole chain sits below the cap, so nothing was reachable and
        // the walk reports the pruning through `truncated`.
        assert!(
            !resolve
                .files
                .contains(&buried.to_string_lossy().into_owned())
        );
        assert!(resolve.truncated);
    }

    #[test]
    fn the_cap_truncates_and_reports() {
        let dir = scratch("cap");
        for i in 0..(MAX_SCANNED_FILES + 50) {
            put(&dir.join(format!("take{i:04}.wav")));
        }
        let resolve = expand_inputs(&[dir.to_string_lossy().into_owned()]);
        assert_eq!(resolve.files.len(), MAX_SCANNED_FILES);
        assert!(resolve.truncated);
    }

    #[test]
    fn unreadable_folders_are_skipped_not_fatal() {
        let dir = scratch("denied");
        put(&dir.join("outside.wav"));
        let missing = dir.join("not-a-real-folder");
        let expected = vec![dir.join("outside.wav").to_string_lossy().into_owned()];
        assert_eq!(expand(&[&missing, &dir]), expected);
    }

    #[test]
    fn direct_file_inputs_keep_working() {
        let dir = scratch("solo");
        let solo = put(&dir.join("clip.avi"));
        assert_eq!(expand(&[&solo]), vec![solo.to_string_lossy().into_owned()]);
    }
}
