/**
 * OS "Open with" bindings: media paths Windows handed the process on the
 * command line (Explorer ▸ "Open with", file-association launches).
 *
 * Boot pull and live pushes are the two delivery legs of
 * `src-tauri/src/open_with.rs`: whatever queued until the webview mounted is
 * drained once via `takePendingOpenFiles`, and later arrivals — a second
 * launch forwarded to the running instance — come in on `open-files`.
 * Everything plays through the same pipeline as drag-and-drop.
 */
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

/**
 * Drains the command-line paths queued since process start. Must be called
 * after subscribing to `open-files`: the drain flips later arrivals from
 * queued to pushed.
 */
export const takePendingOpenFiles = (): Promise<string[]> =>
  invoke("take_pending_open_files");

/** Subscribes to media paths pushed by a second launch's forwarding. */
export function onOpenFiles(
  handler: (paths: string[]) => void,
): Promise<UnlistenFn> {
  return listen<string[]>("open-files", (event) => handler(event.payload));
}
