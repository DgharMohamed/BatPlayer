/**
 * Chrome visibility state shared by the top bar and the control bar: both
 * bars fade away after a moment without interaction while a file is playing,
 * and stay pinned while a menu is open or the pointer rests on the controls.
 */
import { get, writable } from "svelte/store";

import { eofReached, idle, paused } from "./player";const AUTOHIDE_INACTIVITY_MS = 2400;

/** Identifier of the open menu flyout (e.g. "media"), or false if none. */
export const menuOpen = writable<string | false>(false);

/** True when the bars are slid out of view. */
export const chromeHidden = writable(false);

let hideTimer: ReturnType<typeof setTimeout> | undefined;
let pinned = false;

/** Auto-hide only makes sense while a file actively plays and no menu is up. */
function canHide(): boolean {
  return pinned || Boolean(get(menuOpen)) || get(paused) || get(idle) || get(eofReached);
}

/** Cancels the countdown and keeps the bars visible. */
export function pinChrome(value: boolean): void {
  pinned = value;
  if (pinned) {
    chromeHidden.set(false);
    disarmHide();
  } else {
    keepChromeVisible();
  }
}

/** Rearms the countdown (called on every pointer move or interaction). */
export function keepChromeVisible(): void {
  if (pinned) {
    return;
  }
  chromeHidden.set(false);
  disarmHide();
  if (!canHide()) {
    hideTimer = setTimeout(() => {
      if (!canHide()) {
        chromeHidden.set(true);
      }
    }, AUTOHIDE_INACTIVITY_MS);
  }
}

/** Immediately hides the bars (e.g. after pressing play and moving on). */
export function hideChrome(): void {
  if (!canHide()) {
    chromeHidden.set(true);
  }
}

function disarmHide(): void {
  if (hideTimer) {
    clearTimeout(hideTimer);
    hideTimer = undefined;
  }
}

// Whenever the player stops actively playing (pause flips, EOF parks the
// decoder with `keep-open`, or the file unloads), the bars come back instead
// of leaving the video fullscreen-hidden forever.
for (const store of [paused, idle, eofReached]) {
  store.subscribe(() => {
    disarmHide();
    if (!canHide()) {
      chromeHidden.set(false);
    } else {
      keepChromeVisible();
    }
  });
}
