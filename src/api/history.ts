/**
 * Thin, typed bindings to the Rust history commands and the
 * `history-changed` push channel. The recent-files list lives in Rust
 * state; the frontend only reads it and asks for actions.
 */
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

/** One "Open Recent" entry, newest first. */
export type RecentEntry = {
  path: string;
  /** Unix milliseconds of the most recent open. */
  openedAt: number;
};

export const recentFiles = (): Promise<RecentEntry[]> => invoke("recent_files");

/** Clears the whole list (File ▸ "Clear Recent Files"). */
export const clearHistory = (): Promise<void> => invoke("clear_history");

/**
 * Subscribes to changes pushed by the Rust side, triggered by every
 * successful file load and history clearing.
 */
export function onHistoryChanged(handler: () => void): Promise<UnlistenFn> {
  return listen("history-changed", () => handler());
}
