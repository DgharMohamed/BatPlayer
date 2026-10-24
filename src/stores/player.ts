/**
 * Frontend playback state, mirrored from the Rust `Player` through the
 * `player-event` channel.
 *
 * Property changes that turn *unavailable* (e.g. `duration` after a `stop`)
 * never reach the frontend — the Rust side drops them — so this store resets
 * aggregate state itself on `startFile` / idle transitions.
 */
import { get, writable } from "svelte/store";

import { t } from "../i18n";
import { seekTo, onPlayerEvent, type PlayerEvent } from "../api/player";

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
/** Absolute path of the file the engine owns, null when nothing is loaded.
 * The resume saver writes back to this file (unknown after a `stop` otherwise). */
export const currentPath = writable<string | null>(null);
/** Playback is parked at the end of the file (`keep-open`). */
export const eofReached = writable(false);
/** True between `start-file` and `file-loaded`. */
export const loading = writable(false);
/** Basename of the file being opened, shown on the loading plate. */
export const loadingName = writable("");

/** Popup notice pinned to the bottom of the stage, or `null` when hidden. */
export const notice = writable<{ kind: "error" | "info"; text: string } | null>(null);

/**
 * Resume slot: exactly one playback position may be waiting for its file to
 * finish loading (opens are serialized through `openMediaPath`, so a FIFO
 * would only carry a stale entry after a failed load).
 */
let pendingResume: { path: string; position: number } | null = null;

/** Queues a resume position to seek to once the file has loaded. */
export function queueResume(path: string, position: number): void {
  pendingResume = { path, position };
}

/** Subscribers to end-of-file: the playlist advances from here. */
const endFileListeners = new Set<(error: string | null) => void>();

/** Registers a listener for the `end-file` boundary; returns the unlisten. */
export function onEndFile(listener: (error: string | null) => void): () => void {
  endFileListeners.add(listener);
  return () => endFileListeners.delete(listener);
}

/** Applies the queued resume position, waiting for seekability if needed. */
function applyResume(position: number): void {
  const perform = async (): Promise<void> => {
    try {
      await seekTo(position);
    } catch (error) {
      // The file plays unresumed rather than failing the open.
      showNotice(String(error), "error");
    }
  };
  if (get(seekable)) {
    void perform();
    return;
  }
  // Streams report `seekable` around file-loaded; try briefly, then start
  // from the beginning like an unresumable web stream would.
  let giveUp: ReturnType<typeof setTimeout> | undefined;
  const unsubscribe = seekable.subscribe((value) => {
    if (!value) return;
    if (giveUp !== undefined) {
      clearTimeout(giveUp);
    }
    unsubscribe();
    void perform();
  });
  giveUp = setTimeout(() => {
    unsubscribe();
  }, 3000);
}

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
          currentPath.set(null);
          pendingResume = null;
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
    // A freshly opened file always auto-plays; mpv emits no `pause` change
    // when it was already false, so sync the mirror here too.
    paused.set(false);
    // The event carries the engine's real audio state: a persisted mute or
    // volume is applied in Rust before the webview binds, so no property
    // event ever reaches these stores and the controls would disagree.
    muted.set(event.audioMuted);
    volume.set(event.audioVolume);
    notice.set(null);
    if (event.audioTracks.total === 0) {
      showNotice(t("notices.noAudioTrack"), "info");
    }
    // A queued resume position is consumed by exactly the file that queued
    // it: this event is that file (the slot clears on end-file/idle too).
    if (pendingResume !== null) {
      const resume = pendingResume;
      pendingResume = null;
      applyResume(resume.position);
    }
    return;
  }

  // endFile: with `keep-open`, a clean end of file only surfaces here.
  loading.set(false);
  pendingResume = null;
  const { error } = event;
  if (error) {
    showNotice(error, "error");
  }
  for (const listener of [...endFileListeners]) {
    listener(error);
  }
}

/** Subscribes the stores to the `player-event` channel. Returns unlisten. */
export function bindPlayerEvents(): Promise<() => void> {
  return onPlayerEvent(handlePlayerEvent);
}

// Give diagnostic messages enough time to read, especially when a file starts
// playing immediately after it loads.
const NOTICE_ERROR_MS = 15000;
const NOTICE_INFO_MS = 8000;

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
