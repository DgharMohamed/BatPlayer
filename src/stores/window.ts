/**
 * Window state mirrored from Tauri: maximized/fullscreen flags drive the
 * window-control icons and the fullscreen shortcut, and re-sync on every
 * native resize (progressbar-free: the flag is only reread on idle).
 */
import { get, writable } from "svelte/store";
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { UnlistenFn } from "@tauri-apps/api/event";

export const fullscreen = writable(false);
export const maximized = writable(false);

const RESIZE_SYNC_DEBOUNCE_MS = 120;

let resyncTimer: ReturnType<typeof setTimeout> | undefined;

async function resyncFlags(): Promise<void> {
  const win = getCurrentWindow();
  // Concurrent reads are fine, but a resize burst should coalesce into one.
  if (resyncTimer) {
    clearTimeout(resyncTimer);
  }
  resyncTimer = setTimeout(async () => {
    const [fs, max] = await Promise.all([win.isFullscreen(), win.isMaximized()]);
    fullscreen.set(fs);
    maximized.set(max);
  }, RESIZE_SYNC_DEBOUNCE_MS);
}

/** Mirrors the current flags and keeps them fresh on native resizes. */
export async function bindWindowState(): Promise<UnlistenFn> {
  const win = getCurrentWindow();
  await resyncFlags();
  return win.onResized(() => void resyncFlags());
}

/** Toggles the OS fullscreen state of the main window. */
export async function toggleFullscreen(): Promise<void> {
  await setFullscreen(!get(fullscreen));
}

/** Fullscreen switch used by the Esc shortcut. */
export async function exitFullscreen(): Promise<void> {
  if (get(fullscreen)) {
    await setFullscreen(false);
  }
}

/** Sets the OS fullscreen state of the main window (optimistic flag). */
export async function setFullscreen(value: boolean): Promise<void> {
  fullscreen.set(value);
  const win = getCurrentWindow();
  try {
    await win.setFullscreen(value);
  } catch {
    // The native switch failed (or raced): trust the real state.
    fullscreen.set(await win.isFullscreen());
  }
}

/** Minimises, maximises/restores or closes the (frameless) main window. */
export function minimizeWindow(): void {
  void getCurrentWindow().minimize();
}

export function toggleMaximize(): void {
  void getCurrentWindow().toggleMaximize();
}

export function closeWindow(): void {
  void getCurrentWindow().close();
}
