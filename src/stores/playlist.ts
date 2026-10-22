/**
 * Queue state shared by the playlist panel, the transport controls and the
 * keyboard: an ordered list of files, the play position inside it, VLC-style
 * loop (off / all / one) and an optional shuffled play order.
 *
 * Auto-advance lives here, fed by the player store's end-of-file signal:
 * a natural end-of-file moves to the next item (loop and shuffle deciding
 * the target), a file that cannot play is skipped (VLC parity), and the end
 * of an un-looped queue leaves playback parked on the last frame — VLC's
 * "list finished, player stopped" state.
 *
 * Direct opens (dialog, drag-and-drop, Open Recent) *replace* the queue
 * with the opened file(s) — a visible queue always matches what the user
 * last asked to play (documented deviation: VLC's dialog opens accumulate
 * playlist entries instead). Enqueued additions extend the current queue.
 */
import { get, writable } from "svelte/store";

import { playPause, seekTo } from "../api/player";
import { eofReached, onEndFile, showNotice } from "../stores/player";
import { isMediaPath, openMediaPath } from "../utils/media";
import { t } from "../i18n";

export type LoopMode = "off" | "all" | "one";

export interface PlaylistItem {
  path: string;
  /** Flat display name (basename), matching the recent-files menu. */
  name: string;
}

export const playlistItems = writable<PlaylistItem[]>([]);
/** Position of the playing item in the queue; -1 while idle/stopped. */
export const playlistIndex = writable(-1);
export const loopMode = writable<LoopMode>("off");
/** VLC "random": the queue plays every item once in a shuffled order. */
export const shuffleEnabled = writable(false);
/** Playlist panel visibility (View ▸ Playlist, Ctrl+L). */
export const playlistOpen = writable(false);

/**
 * Shuffled play order as queue indices, consumed item by item; empty while
 * playback is sequential. `advance` owns every mutation.
 */
let pool: number[] = [];

function baseName(path: string): string {
  return path.split(/[\\/]/).pop() ?? path;
}

function nameItems(paths: string[]): PlaylistItem[] {
  return paths.map((path) => ({ path, name: baseName(path) }));
}

/** Returns `indices` shuffled into a new array. */
function shuffledIndices(indices: number[]): number[] {
  const order = [...indices];
  for (let i = order.length - 1; i > 0; i -= 1) {
    const swap = Math.floor(Math.random() * (i + 1));
    [order[i], order[swap]] = [order[swap]!, order[i]!];
  }
  return order;
}

/** Returns indices 0..count-1 uniformly shuffled. */
function shuffledOrder(count: number): number[] {
  return shuffledIndices(Array.from({ length: count }, (_, index) => index));
}

/**
 * Replaces the queue with `paths` and starts the first of them. Dragging
 * several files plays the first immediately and queues the rest.
 */
export function playPaths(paths: string[]): void {
  const media = paths.filter(isMediaPath);
  if (media.length === 0) {
    return;
  }
  playlistItems.set(nameItems(media));
  playlistIndex.set(-1);
  pool = get(shuffleEnabled) ? shuffledOrder(media.length) : [];
  void playAt(0);
}

/**
 * Appends `paths`; a queue with nothing playing starts on them.
 */
export function enqueue(paths: string[]): void {
  const media = paths.filter(isMediaPath);
  if (media.length === 0) {
    return;
  }
  const oldCount = get(playlistItems).length;
  playlistItems.update((items) => [...items, ...nameItems(media)]);
  const count = get(playlistItems).length;
  if (get(playlistIndex) >= 0) {
    // Playing: the additions only extend the list (and the shuffle pool).
    if (get(shuffleEnabled)) {
      pool = [
        ...pool.filter((candidate) => candidate < oldCount),
        ...shuffledIndices(
          Array.from({ length: media.length }, (_, i) => oldCount + i),
        ),
      ];
    }
    return;
  }
  // Nothing is playing: the queue starts on the first added item and the
  // pool is "everything" (irrelevant while playback stays sequential).
  if (get(shuffleEnabled)) {
    pool = shuffledOrder(count);
  }
  void playAt(oldCount);
}

/**
 * Random-play toggle. Rebuilding the pool here instead of inside the
 * keyboard action keeps one owner of pool invariants: with the queue
 * playing, every item except the current one is queued to be visited,
 * mirroring VLC's behavior of re-ordering the rest when random turns on.
 */
export function setShuffle(on: boolean): void {
  shuffleEnabled.set(on);
  if (!on) {
    pool = [];
    return;
  }
  const items = get(playlistItems);
  const current = get(playlistIndex);
  pool = shuffledIndices(
    items.map((_, index) => index).filter((index) => index !== current),
  );
}

/**
 * Wipes the queue. The playing file keeps playing, unmanaged — the drawer
 * only loses its contents (matches removing every item one by one).
 */
export function clearPlaylist(): void {
  playlistItems.set([]);
  playlistIndex.set(-1);
  pool = [];
}

/**
 * Removes queue item `index`, keeping the index and pool consistent with
 * the shifted positions. Removing the playing item stops treating the
 * queue as its owner: it keeps playing, unmanaged (as after a clear).
 */
export function removeAt(index: number): void {
  const current = get(playlistIndex);
  playlistItems.update((items) => items.filter((_, i) => i !== index));
  if (index < current) {
    playlistIndex.set(current - 1);
  } else if (index === current) {
    playlistIndex.set(-1);
  }
  if (get(shuffleEnabled)) {
    // Drop the removed position, then shift everything after it down one.
    pool = pool
      .filter((position) => position !== index)
      .map((position) => (position > index ? position - 1 : position));
  }
}

/**
 * Starts queue item `index`, or does nothing when it is out of range.
 * The index is set *before* the load so reactions to the end of the old
 * file (error skips) cannot advance past the new playback.
 */
export async function playAt(index: number): Promise<void> {
  const item = get(playlistItems)[index];
  if (item === undefined) {
    return;
  }
  playlistIndex.set(index);
  await openMediaPath(item.path);
}

/**
 * Moves the play cursor one step (`1` next, `-1` previous) and returns the
 * item to start, or `null` when staying put is the move:
 * - previous wraps to the last item (first→last verified on VLC 3.0.24,
 *   experiment E3/M8), except in a one-item queue where that wrap would
 *   just restart the same file;
 * - next wraps only with loop "all"; at the end of an un-looped queue it
 *   stays put (VLC: finished list, player stopped);
 * - with shuffle on, the next pick is a not-yet-played item, and the pool
 *   refills only when loop "all" replays the whole queue in a new order
 *   (VLC kept: random plays every item once, then stops without loop).
 */
export function advance(direction: 1 | -1): number | null {
  const items = get(playlistItems);
  const index = get(playlistIndex);
  if (items.length === 0) {
    return null;
  }
  if (direction === -1) {
    if (index > 0) {
      return index - 1;
    }
    return items.length > 1 ? items.length - 1 : null;
  }
  if (get(shuffleEnabled)) {
    const remaining = pool.filter((candidate) => candidate !== index);
    if (remaining.length > 0) {
      const next = remaining[Math.floor(Math.random() * remaining.length)]!;
      pool = remaining.filter((candidate) => candidate !== next);
      return next;
    }
    if (get(loopMode) === "all") {
      pool = shuffledOrder(items.length);
      const next = pool[0] ?? null;
      pool = pool.slice(1);
      return next;
    }
    return null;
  }
  const next = index + 1;
  if (next < items.length) {
    return next;
  }
  return get(loopMode) === "all" ? 0 : null;
}

/**
 * Restarts the current file from the top (loop "one" at end-of-file, and
 * the parked-EOF play button). With `keep-open`, a plain unpause would not
 * replay: seek home first, then resume.
 */
async function replayCurrent(): Promise<void> {
  try {
    await seekTo(0);
    if (get(eofReached)) {
      // The seek may not have un-parked the file yet; an explicit unpause
      // makes the replay immediate either way.
      await playPause();
    }
  } catch (error) {
    showNotice(String(error), "error");
  }
}

/** Runs `advance(1)` and starts whatever it selected. */
async function advanceAndPlay(): Promise<void> {
  const target = advance(1);
  if (target === null) {
    return;
  }
  await playAt(target);
}

/** True while an end-of-file reaction is already in flight. */
let handlingEnd = false;

/**
 * The end-of-file boundary. Natural ends replay (loop "one") or move on;
 * broken files skip to the next playable item. The guard is armed here
 * rather than per-branch because a single file can trip *both* signals the
 * engine sends: `eof-reached` right before a hard failure — two reactions
 * to one boundary must not skip two items.
 */
async function onCurrentEnded(error: string | null): Promise<void> {
  if (handlingEnd) {
    return;
  }
  const index = get(playlistIndex);
  if (index < 0 || index >= get(playlistItems).length) {
    return;
  }
  handlingEnd = true;
  try {
    if (error === null) {
      if (get(loopMode) === "one") {
        await replayCurrent();
        return;
      }
      await advanceAndPlay();
      return;
    }
    // The file cannot be played: VLC auto-skips broken playlist items (E5).
    const name = get(playlistItems)[index]?.name ?? "";
    showNotice(`${name}: ${t("notices.skipped")}`, "error");
    await advanceAndPlay();
  } finally {
    handlingEnd = false;
  }
}

// Module-level wiring (same pattern as stores/chrome.ts): one lifetime for
// the app, fed by the player store's signals.
let eofSignaled = false;
eofReached.subscribe((eof) => {
  // Only the false→true edge is a natural end; a seek away resets first.
  if (eof === eofSignaled) {
    return;
  }
  eofSignaled = eof;
  if (eof) {
    void onCurrentEnded(null);
  }
});

onEndFile((error) => {
  // A clean end-file rides along with `eof-reached` on natural EOF and is
  // what a user `stop` looks like — both handled elsewhere.
  if (error === null) {
    return;
  }
  void onCurrentEnded(error);
});
