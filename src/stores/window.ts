/**
 * Window state mirrored from Tauri: maximized/fullscreen flags drive the
 * window-control icons and the fullscreen shortcut, and re-sync on every
 * native resize (progressbar-free: the flag is only reread on idle).
 */
import { get, writable } from "svelte/store";
import { getCurrentWindow, LogicalSize, PhysicalSize } from "@tauri-apps/api/window";
import type { UnlistenFn } from "@tauri-apps/api/event";

export const fullscreen = writable(false);
export const maximized = writable(false);
/** Small always-on-top player mode. */
export const miniPlayer = writable(false);

let regularSize: PhysicalSize | null = null;
let restoreMaximizedAfterFullscreen = false;

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
  const win = getCurrentWindow();
  try {
    if (value) {
      // Windows can retain the maximized work-area placement when a
      // borderless window enters fullscreen. Normalize first, then let the
      // fullscreen transition capture the ordinary window placement.
      restoreMaximizedAfterFullscreen = await win.isMaximized();
      if (restoreMaximizedAfterFullscreen) {
        await win.toggleMaximize();
        maximized.set(false);
      }
      await win.setFullscreen(true);
      fullscreen.set(true);
    } else {
      await win.setFullscreen(false);
      fullscreen.set(false);
      if (restoreMaximizedAfterFullscreen) {
        await win.toggleMaximize();
        maximized.set(true);
      }
      restoreMaximizedAfterFullscreen = false;
    }
  } catch (error) {
    // The native switch failed (or raced): trust the real state.
    console.error("Could not change fullscreen mode", error);
    const [isFullscreen, isMaximized] = await Promise.all([
      win.isFullscreen(),
      win.isMaximized(),
    ]);
    fullscreen.set(isFullscreen);
    maximized.set(isMaximized);
    if (!isFullscreen) restoreMaximizedAfterFullscreen = false;
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

/** Resizes the current window into an always-on-top mini player. */
export async function enterMiniPlayer(): Promise<void> {
  const win = getCurrentWindow();
  if (get(miniPlayer)) return;
  try {
    if (await win.isFullscreen()) await win.setFullscreen(false);
    if (await win.isMaximized()) await win.unmaximize();
    fullscreen.set(false);
    maximized.set(false);
    regularSize = await win.innerSize();
    await win.setMinSize(new LogicalSize(320, 180));
    await win.setSize(new LogicalSize(480, 270));
    await win.setAlwaysOnTop(true);
    miniPlayer.set(true);
  } catch (error) {
    regularSize = null;
    console.error("Could not enter mini-player mode", error);
  }
}

/** Restores the main player window from mini-player mode. */
export async function exitMiniPlayer(): Promise<void> {
  const win = getCurrentWindow();
  try {
    await win.setAlwaysOnTop(false);
    await win.setMinSize(new LogicalSize(640, 360));
    if (regularSize) await win.setSize(regularSize);
    miniPlayer.set(false);
    regularSize = null;
  } catch (error) {
    console.error("Could not exit mini-player mode", error);
  }
}
