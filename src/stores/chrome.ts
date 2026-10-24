/**
 * Chrome visibility state shared by the top bar and the control bar: both
 * bars fade away after a moment without interaction while a file is playing
 * — in fullscreen also while it is paused, to keep the picture chrome-free —
 * and stay pinned while a menu is open or the pointer rests on the controls.
 */
import { get, writable } from "svelte/store";

import { eofReached, idle, paused } from "./player";
import { playlistOpen } from "./playlist";
import { fullscreen } from "./window";

const AUTOHIDE_INACTIVITY_MS = 2400;

/** Identifier of the open menu flyout (e.g. "media"), or false if none. */
export const menuOpen = writable<string | false>(false);

/** True when the bars are slid out of view. */
export const chromeHidden = writable(false);

let hideTimer: ReturnType<typeof setTimeout> | undefined;
let pinned = false;
let focusPinned = false;

/**
 * Holds that keep the bars up: direct interaction (pointer resting on a bar,
 * keyboard focus inside one), an open menu, or no running playback to watch.
 * Paused only holds in the windowed layout — a fullscreen pause echoes on
 * the OSD instead, so the chrome slides away like during playback.
 */
function hasHold(): boolean {
  if (pinned || focusPinned || Boolean(get(menuOpen)) || get(playlistOpen) || get(idle) || get(eofReached)) {
    return true;
  }
  return get(paused) && !get(fullscreen);
}

/** Cancels the countdown and keeps the bars visible. */
export function pinChrome(value: boolean): void {
  // In fullscreen, a stationary pointer over a control must not keep both
  // bars on screen indefinitely. Let the normal inactivity timer hide them.
  if (get(fullscreen)) {
    pinned = false;
    keepChromeVisible();
    return;
  }
  pinned = value;
  if (pinned) {
    chromeHidden.set(false);
    disarmHide();
  } else {
    keepChromeVisible();
  }
}

/**
 * Keyboard focus inside a bar holds it open too, so Tab never lands on a
 * control that the inactivity timer slid out of view.
 */
export function pinChromeFocus(value: boolean): void {
  if (get(fullscreen)) {
    focusPinned = false;
    keepChromeVisible();
    return;
  }
  if (focusPinned === value) {
    return;
  }
  focusPinned = value;
  if (value) {
    chromeHidden.set(false);
    disarmHide();
  } else {
    keepChromeVisible();
  }
}

/** Rearms the countdown (called on every pointer move or interaction). */
export function keepChromeVisible(): void {
  if (pinned || focusPinned) {
    return;
  }
  chromeHidden.set(false);
  disarmHide();
  if (!hasHold()) {
    hideTimer = setTimeout(() => {
      if (!hasHold()) {
        chromeHidden.set(true);
      }
    }, AUTOHIDE_INACTIVITY_MS);
  }
}

/** Immediately hides the bars (e.g. after pressing play and moving on). */
export function hideChrome(): void {
  if (!hasHold()) {
    chromeHidden.set(true);
  }
}

function disarmHide(): void {
  if (hideTimer) {
    clearTimeout(hideTimer);
    hideTimer = undefined;
  }
}

// Every playback/hold flip re-arms the countdown immediately, so state
// changes never wait for the next pointer move: a file loading or unloading,
// EOF parking the decoder with `keep-open`, a fullscreen flip (pressing `f`
// with the mouse parked must still slide the chrome away, and leaving
// fullscreen shows the bars again), a fullscreen pause — which releases
// its hold in `hasHold` and now auto-hides like playing does — and the
// playlist drawer, which holds the bars up for its duration.
fullscreen.subscribe(() => {
  // A pointer may already be resting on a bar when fullscreen is entered.
  // Clear the windowed pin so the fullscreen timer can run from that point.
  pinned = false;
  focusPinned = false;
  keepChromeVisible();
});

for (const store of [paused, idle, eofReached, playlistOpen]) {
  store.subscribe(() => keepChromeVisible());
}
