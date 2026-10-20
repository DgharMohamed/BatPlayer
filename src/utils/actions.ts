/**
 * Player actions shared by menus, control bar and keyboard shortcuts.
 *
 * Every action forwards mpv failures to the on-screen notice instead of
 * swallowing them, so bad commands never disappear silently.
 */
import {
  cycleAudio,
  cycleSubtitle,
  frameStep,
  playPause,
  screenshot,
  seekBy,
  seekTo,
  setMute,
  setSpeed,
  setVolume,
  stop,
} from "../api/player";
import { get } from "svelte/store";
import {
  currentTime,
  duration,
  eofReached,
  muted,
  paused,
  showNotice,
  speed,
  volume,
} from "../stores/player";
import { showOsd } from "../stores/osd";

const VOLUME_MAX = 130;
const SPEED_MIN = 0.25;
const SPEED_MAX = 4;

/* Clamps shared by all volume/speed entry points. */
export function clampVolume(value: number): number {
  return Math.min(VOLUME_MAX, Math.max(0, Math.round(value)));
}

export function clampSpeed(value: number): number {
  return Math.min(SPEED_MAX, Math.max(SPEED_MIN, Math.round(value * 100) / 100));
}

/** Runs a command, surfacing failures through the bottom-bar notice. */
export async function report(action: () => Promise<unknown>): Promise<void> {
  try {
    await action();
  } catch (error) {
    showNotice(String(error));
  }
}

/**
 * Restarts a file parked at the end (`keep-open` pauses at EOF, so a plain
 * unpause would not replay): seek home first, then resume.
 */
function replayFromStart(): Promise<void> {
  return report(async () => {
    await seekTo(0);
    if (get(paused)) {
      await playPause();
    }
  });
}

export function togglePlayPause(): Promise<void> {
  if (get(eofReached)) {
    return replayFromStart();
  }
  // Chrome-free fullscreen hides the paused state, so echo the intended one
  // on the OSD — optimistic, like the volume and mute shortcuts.
  const willPause = !get(paused);
  showOsd(willPause ? { kind: "paused" } : { kind: "playing" });
  return report(playPause);
}

export const stopPlayback = (): Promise<void> => report(stop);

/** Seeks by `seconds` and echoes the expected landing spot on the OSD. */
export function seekRelative(seconds: number): Promise<void> {
  const limit = get(duration) > 0 ? get(duration) : Number.POSITIVE_INFINITY;
  const target = Math.max(0, Math.min(get(currentTime) + seconds, limit));
  showOsd({ kind: "seek", delta: seconds, target });
  return report(() => seekBy(seconds));
}

export const seekAbsolute = (seconds: number): Promise<void> =>
  report(() => seekTo(seconds));

/** Cycles the audio track and reports the new position from the engine. */
export async function cycleAudioTrack(): Promise<void> {
  try {
    const info = await cycleAudio();
    showOsd({ kind: "audio", ...info });
  } catch (error) {
    showNotice(String(error));
  }
}

export async function cycleSubtitleTrack(): Promise<void> {
  try {
    const info = await cycleSubtitle();
    showOsd({ kind: "subtitle", ...info });
  } catch (error) {
    showNotice(String(error));
  }
}

export function toggleMute(): Promise<void> {
  const next = !get(muted);
  // Unmuting is the interesting half: show the level that comes back.
  showOsd(
    next ? { kind: "muted" } : { kind: "volume", value: get(volume) },
  );
  return report(() => setMute(next));
}

/** Bumps volume by `delta`, clamped to mpv's configured range. */
export function stepVolume(delta: number): Promise<void> {
  const target = clampVolume(get(volume) + delta);
  showOsd({ kind: "volume", value: target });
  return report(() => setVolume(target));
}

/** Scales playback speed by +/− `delta`, clamped and rounded to 0.01. */
export function stepSpeed(delta: number): Promise<void> {
  const target = clampSpeed(get(speed) + delta);
  showOsd({ kind: "speed", speed: target });
  return report(() => setSpeed(target));
}

export function resetSpeed(): Promise<void> {
  showOsd({ kind: "speed", speed: 1 });
  return report(() => setSpeed(1));
}

export const stepFrame = (direction: 1 | -1): Promise<void> =>
  report(() => frameStep(direction));

/** Saves a snapshot into the user's Pictures folder and says where it went. */
export async function takeSnapshot(): Promise<void> {
  try {
    showNotice(await screenshot(), "info");
  } catch (error) {
    showNotice(String(error));
  }
}
