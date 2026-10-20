/**
 * Recent files state, mirrored from the Rust history state: fetched once
 * on startup and refreshed whenever the Rust side pushes `history-changed`
 * (after a successful load or a history clear).
 */
import { writable } from "svelte/store";

import { onHistoryChanged, recentFiles, type RecentEntry } from "../api/history";

/** Recently opened paths, newest first. */
export const recent = writable<RecentEntry[]>([]);

/**
 * Starts following the history state and re-fetches on every push. The
 * listener attaches *before* the first fetch so pushes never race the
 * initial load.
 */
export async function bindHistory(): Promise<() => void> {
  const unlisten = await onHistoryChanged(() => void refresh());
  await refresh();
  return unlisten;
}

/** Current refresh "generation"; only the freshest response may land. */
let refreshId = 0;

async function refresh(): Promise<void> {
  const id = ++refreshId;
  try {
    const entries = await recentFiles();
    // A push-triggered refresh may have overtaken this one; never let a
    // stale response overwrite fresher data.
    if (id === refreshId) {
      recent.set(entries);
    }
  } catch (error) {
    // The store stays as-is; the notice system is for player failures.
    console.error("failed to read the recent files:", error);
  }
}
