/**
 * Frontend playback state, mirrored from the Rust `Player` through the
 * `player-event` channel.
 *
 * Property changes that turn *unavailable* (e.g. `duration` after a `stop`)
 * never reach the frontend — the Rust side drops them — so this store resets
 * aggregate state itself on `startFile` / idle transitions.
 */
import { writable } from "svelte/store";

import { onPlayerEvent, type PlayerEvent } from "../api/player";

/** Nothing is loaded; the idle mark shows and media controls lock. */
export const idle = writable(true);
/** A file is loaded (not necessarily decoding yet). */
export const mediaLoaded = writable(false);
/** mpv's `pause` property: true when playback is momentarily stopped. */
export const paused = writable(true);
export const currentTime = writable(0);
export const duration = writable(0);
/** mpv's `volume` property: percent of its maximum (100 by default). */
export const volume = writable(100);
export const muted = writable(false);
export const speed = writable(1);
export const seekable = writable(false);
export const displayTitle = writable("");
/** Playback is parked at the end of the file (`keep-open`). */
export const eofReached = writable(false);
/** True between `start-file` and `file-loaded`. */
export const loading = writable(false);
/** Basename of the file being opened, shown on the loading plate. */
export const loadingName = writable("");

/** Popup notice pinned to the bottom of the stage, or `null` when hidden. */
export const notice = writable<{ kind: "error" | "info"; text: string } | null>(null);

/** Applies a single `player-event` payload to the stores. */
export function handlePlayerEvent(event: PlayerEvent): void {
  if (event.type === "property") {
    const value = event.value;
    switch (event.name) {
      case "time-pos":
        currentTime.set(Number(value));
        break;
      case "duration":
        duration.set(Number(value));
        break;
      case "pause":
        paused.set(Boolean(value));
        break;
      case "volume":
        volume.set(Number(value));
        break;
      case "mute":
        muted.set(Boolean(value));
        break;
      case "speed":
        speed.set(Number(value));
        break;
      case "eof-reached":
        eofReached.set(Boolean(value));
        break;
      case "seekable":
        seekable.set(Boolean(value));
        break;
      case "idle-active":
        // mpv parked without a file: back to the idle mark.
        if (Boolean(value)) {
          idle.set(true);
          mediaLoaded.set(false);
          loading.set(false);
          paused.set(true);
          eofReached.set(false);
          currentTime.set(0);
          duration.set(0);
          seekable.set(false);
          displayTitle.set("");
        } else {
          idle.set(false);
        }
        break;
      case "media-title":
        displayTitle.set(String(value));
        break;
    }
    return;
  }

  if (event.type === "startFile") {
    loading.set(true);
    mediaLoaded.set(false);
    currentTime.set(0);
    duration.set(0);
    eofReached.set(false);
    return;
  }

  if (event.type === "fileLoaded") {
    loading.set(false);
    mediaLoaded.set(true);
    idle.set(false);
    notice.set(null);
    return;
  }

  // endFile: with `keep-open`, a clean end of file only surfaces here.
  loading.set(false);
  if (event.error) {
    showNotice(event.error, "error");
  }
}

/** Subscribes the stores to the `player-event` channel. Returns unlisten. */
export function bindPlayerEvents(): Promise<() => void> {
  return onPlayerEvent(handlePlayerEvent);
}

const NOTICE_ERROR_MS = 6000;
const NOTICE_INFO_MS = 3500;

let noticeTimer: ReturnType<typeof setTimeout> | undefined;

/** Shows a transient notice; errors stay a little longer so they read well. */
export function showNotice(text: string, kind: "error" | "info" = "info"): void {
  notice.set({ kind, text });
  if (noticeTimer) {
    clearTimeout(noticeTimer);
  }
  noticeTimer = setTimeout(
    () => notice.set(null),
    kind === "error" ? NOTICE_ERROR_MS : NOTICE_INFO_MS,
  );
}
