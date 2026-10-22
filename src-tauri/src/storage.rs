//! Small shared helper for writing app-state documents safely.

use std::fs;
use std::path::Path;

/// Writes `body` to `temp`, then swaps it over `target`. The remove-first
/// dance exists because `fs::rename` refuses to replace a file on Windows.
/// Failures are logged with `label` and swallowed on purpose: a save that
/// cannot land must never take the player down.
pub fn write_and_swap(label: &str, temp: &Path, target: &Path, body: String) {
    if let Err(err) = fs::write(temp, body) {
        eprintln!("failed to save {label}: {err}");
        return;
    }
    let _ = fs::remove_file(target);
    if let Err(err) = fs::rename(temp, target) {
        eprintln!("failed to save {label}: {err}");
    }
}
