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
import { muted, showNotice, speed, volume } from "../stores/player";

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

export const togglePlayPause = (): Promise<void> => report(playPause);

export const stopPlayback = (): Promise<void> => report(stop);

export const seekRelative = (seconds: number): Promise<void> =>
  report(() => seekBy(seconds));

export const seekAbsolute = (seconds: number): Promise<void> =>
  report(() => seekTo(seconds));

export const cycleAudioTrack = (): Promise<void> => report(cycleAudio);

export const cycleSubtitleTrack = (): Promise<void> => report(cycleSubtitle);

export const toggleMute = (): Promise<void> => report(() => setMute(!get(muted)));

/** Bumps volume by `delta`, clamped to mpv's configured range. */
export const stepVolume = (delta: number): Promise<void> =>
  report(() => setVolume(clampVolume(get(volume) + delta)));

/** Scales playback speed by +/− `delta`, clamped and rounded to 0.01. */
export const stepSpeed = (delta: number): Promise<void> =>
  report(() => setSpeed(clampSpeed(get(speed) + delta)));

export const resetSpeed = (): Promise<void> => report(() => setSpeed(1));

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
