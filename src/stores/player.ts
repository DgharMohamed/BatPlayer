/**
 * Frontend playback state.
 *
 * Milestone 1 placeholder: these values are static until Milestone 2 wires
 * the Rust player's mpv property events (`time-pos`, `duration`, `pause`,
 * `volume`, `mute`, ...) to them.
 */
import { writable } from "svelte/store";

/** A media file is loaded and the controls should be interactive. */
export const mediaLoaded = writable(false);
export const playing = writable(false);
export const currentTime = writable(0);
export const duration = writable(0);
export const volume = writable(100);
export const muted = writable(false);
