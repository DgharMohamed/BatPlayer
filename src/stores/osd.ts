/**
 * Transient on-stage feedback ("OSD") for actions whose result would be
 * invisible otherwise: volume steps, mute, speed, seek jumps, track
 * cycling and play/pause flips (which count when the chrome is hidden in
 * fullscreen). The plate itself lives in `components/Osd.svelte`.
 */
import { writable } from "svelte/store";

export type OsdContent =
  | { kind: "volume"; value: number }
  | { kind: "muted" }
  | { kind: "paused" }
  | { kind: "playing" }
  | { kind: "speed"; speed: number }
  | { kind: "seek"; delta: number; target: number }
  | { kind: "audio"; current: number; total: number }
  | { kind: "subtitle"; current: number; total: number };

/** Current OSD message, or `null` while nothing is showing. */
export const osd = writable<OsdContent | null>(null);

/** Default dwell time; seek feedback carries a time to read, so it lingers. */
const OSD_MS = 900;
const OSD_SEEK_MS = 1200;

let timer: ReturnType<typeof setTimeout> | undefined;

/**
 * Shows `content`. While the plate is visible another call only replaces the
 * message and restarts the clock, so held keys keep one OSD alive instead of
 * flickering a new one per repeat.
 */
export function showOsd(content: OsdContent): void {
  osd.set(content);
  if (timer) {
    clearTimeout(timer);
  }
  timer = setTimeout(
    () => osd.set(null),
    content.kind === "seek" ? OSD_SEEK_MS : OSD_MS,
  );
}
