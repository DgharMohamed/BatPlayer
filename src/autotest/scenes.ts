/**
 * Playlist-semantics scenes for the autotest harness (acceptance items 2-7
 * of docs/vlc-behavior-reference.md; orchestrated by scripts/autotest.ps1's
 * scene run).
 *
 * Each scene drives the real plumbing — the playlist/player stores, the
 * shared event handler and the live engine — and emits exactly two log
 * lines through the Rust relay command `autotest_log`, which surfaces on
 * stderr as `autotest: scene: ...` for PowerShell to collect:
 *
 *   | qN | start |        (scene begins)
 *   | qN | PASS/FAIL ...   (checked assertions)
 *   | done | <names>      (µ scenes finished)
 *
 * Dormant by design: without `BATPLAYER_AUTOTEST_SCENE` the Rust
 * `autotest_scene_names` command answers no scene, so normal user runs and
 * release builds never execute anything here.
 */
import { invoke } from "@tauri-apps/api/core";
import { get } from "svelte/store";

import { onPlayerEvent, stop, type PlayerEvent } from "../api/player";
import {
  advance,
  clearPlaylist,
  loopMode,
  playPaths,
  playlistIndex,
  setShuffle,
} from "../stores/playlist";
import { currentPath, eofReached, handlePlayerEvent, notice } from "../stores/player";

const SCENES = ["q2", "q3", "q4", "q5", "q6", "q7"] as const;
type Scene = (typeof SCENES)[number];

/** The clips the harness generates (scripts/autotest.ps1). */
let clipA = "";
let clipB = "";
let clipC = "";
let brokenMkv = "";

async function log(line: string): Promise<void> {
  try {
    await invoke("autotest_log", { line });
  } catch {
    // Missing relay (release build?): the scene runs on but leaves no
    // markers, so the harness fails by timeout — the honest outcome.
  }
}

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/** Waves `check` until true or `timeoutMs` elapses; returns the final value. */
async function waitFor(check: () => boolean, timeoutMs: number): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (check()) {
      return true;
    }
    await sleep(250);
  }
  return check();
}

/** Readable event labels for the replay scene's event-stream assertions. */
function labelEvent(event: PlayerEvent): string {
  switch (event.type) {
    case "property":
      return `property:${event.name}`;
    case "startFile":
      return "startFile";
    case "fileLoaded":
      return "fileLoaded";
    case "endFile":
      return `endFile(error=${event.error})`;
  }
}

/** Event stream captured since the current scene started. */
const events: string[] = [];

/** Index/value transitions of one store as `[whenMs, value]` pairs. */
type Transition<T> = { atMs: number; value: T };
function transitions<T>(store: { subscribe(fn: (value: T) => void): () => void }): {
  list: Transition<T>[];
  stop: () => void;
} {
  const list: Transition<T>[] = [];
  const started = Date.now();
  let previous: T | null = null;
  const stop = store.subscribe((value) => {
    if (value !== previous) {
      previous = value;
      list.push({ atMs: Date.now() - started, value });
    }
  });
  return { list, stop };
}

function baseName(path: string): string {
  return path.split(/[\\/]/).pop() ?? path;
}

/** Stops everything and resets queue state so scenes start equivalent. */
async function reset(): Promise<void> {
  await stop();
  clearPlaylist();
  loopMode.set("off");
  setShuffle(false);
  // Direct write (the engine re-syncs on the next file's events): the next
  // scene must see a clean false→true end-of-file edge.
  eofReached.set(false);
  await sleep(700);
}

/**
 * The end-of-file edge. A natural end advances and plays the next item
 * (confirmed by the real second file actually becoming current).
 * Acceptance 2.
 */
async function sceneQ2(): Promise<void> {
  playPaths([clipA, clipB]);
  const advanced = await waitFor(
    () => get(playlistIndex) === 1 && get(currentPath) === clipB,
    30_000,
  );
  log(
    `| q2 | ${advanced ? "PASS" : "FAIL"} | index=${
      get(playlistIndex)
    } current=${baseName(get(currentPath) ?? "null")}`,
  );
}

/**
 * Loop "one" at a natural end-of-file replays: seek to 0 (unpark if
 * needed), never a reload. Proven against the captured engine event
 * stream: no new `startFile` after the end that parked the file, the same
 * file stays current, playback resumes and the parked EOF clears.
 * Acceptance 3.
 */
async function sceneQ3(): Promise<void> {
  loopMode.set("one");
  playPaths([clipA]);
  // Stage 1: reach the parked end-of-file; stage 2: replay clears it.
  const parked = await waitFor(
    () => get(eofReached) && get(playlistIndex) === 0 && get(currentPath) === clipA,
    30_000,
  );
  const replayed = await waitFor(
    () => !get(eofReached) && get(currentPath) === clipA,
    30_000,
  );
  const lastEnd = events.lastIndexOf(events.find((e) => e === "endFile(error=null)") ?? "");
  const startFilesAfterEnd = events
    .map((e, i) => ({ e, i }))
    .filter(({ e, i }) => e === "startFile" && i > lastEnd).length;
  const ok =
    parked && replayed && get(playlistIndex) === 0 && lastEnd >= 0 && startFilesAfterEnd === 0;
  log(
    `| q3 | ${
      ok ? "PASS" : "FAIL"
    } | parked=${parked} eofCleared=${!get(eofReached)} startFilesAfterEnd=${startFilesAfterEnd}`,
  );
  loopMode.set("off");
}

/**
 * With loop "all" the next wraps from the last item back to the first and
 * keeps playing (real engine run: two files, watched index transitions).
 * Acceptance 4.
 */
async function sceneQ4(): Promise<void> {
  const crossed = transitions(playlistIndex);
  playPaths([clipA, clipB]);
  // The wrap IS a 0 again after a 1 in the transition history (the first
  // 0 is just the play start).
  const wrapped = await waitFor(() => {
    const values = crossed.list.map((t) => t.value);
    const last1 = values.lastIndexOf(1);
    return last1 >= 0 && values.some((value, i) => i > last1 && value === 0);
  }, 45_000);
  log(
    `| q4 | ${wrapped ? "PASS" : "FAIL"} | index path=${JSON.stringify(
      crossed.list.map((t) => t.value),
    )}`,
  );
  loopMode.set("off");
}

/**
 * VLC random: the queue's unseen items in a shuffled order, consumed once;
 * with an un-looped queue the pick pool exhausts and stays put, with loop
 * "all" it refills. Also a full shuffled engine run: three files ended
 * naturally must be visited once each, no repeats, and end parked.
 * Acceptance 5.
 */
async function sceneQ5(): Promise<void> {
  let ok = true;
  const detail: string[] = [];
  playPaths([clipA, clipB, clipC]);
  setShuffle(true);
  // Pool probe: pick all unlooped targets — a permutation of the two
  // non-current items, no repeats, then nothing.
  const picks: number[] = [];
  for (let i = 0; i < 5; i += 1) {
    const target = advance(1);
    if (target === null) break;
    picks.push(target);
  }
  const poolOk =
    picks.length === 2 &&
    picks.includes(1) &&
    picks.includes(2) &&
    !picks.includes(0) &&
    picks[0] !== picks[1] &&
    advance(1) === null;
  ok = ok && poolOk;
  detail.push(`pool=${JSON.stringify(picks)}`);

  // Refill: turning loop "all" rebuilds the pool and picks continue.
  loopMode.set("all");
  const refilled = advance(1) !== null;
  ok = ok && refilled;
  detail.push(`refill=${refilled}`);
  log(`| q5 | ${ok ? "PASS" : "FAIL"} | ${detail.join(" ")}`);
  loopMode.set("off");

  // Full shuffled run against the engine: each file ends once.
  await reset();
  setShuffle(true);
  const visited = transitions(playlistIndex);
  playPaths([clipA, clipB, clipC]);
  await waitFor(
    () =>
      get(eofReached) && visited.list.length >= 4,
    60_000,
  );
  const seen = visited.list.slice(1).map((t) => t.value);
  const unique = new Set(seen);
  const runOk =
    seen.length === 3 && unique.has(0) && unique.has(1) && unique.has(2);
  log(
    `| q5-run | ${
      runOk ? "PASS" : "FAIL"
    } | order=${JSON.stringify(seen)} eof=${get(eofReached)}`,
  );
  setShuffle(false);
}

/**
 * A file that fails mid-play is skipped exactly once (VLC's broken-item
 * skip), notice shown; a second signal at the same boundary must not
 * advance again (the double-signal guard). The two signals are fed the
 * same way the Rust event relay feeds the app: one handler call each,
 * the same shape the engine sends at that boundary.
 * Acceptance 6.
 */
async function sceneQ6(): Promise<void> {
  playPaths([brokenMkv, clipC]);
  await waitFor(() => get(notice) !== null, 15_000);
  const loadFailure = get(notice);
  const loadFailedOk =
    loadFailure !== null && loadFailure.text.includes(baseName(brokenMkv));
  // Reset the notice so the skip notice is unambiguous.
  notice.set(null);

  // The boundary's double signal: `eof-reached` right before the engine
  // gives up, then the failing `end-file`. Both arriving now must collapse
  // into ONE advance (see onCurrentEnded's guard).
  handlePlayerEvent({ type: "property", name: "eof-reached", value: true });
  handlePlayerEvent({ type: "endFile", error: "synthetic: cannot decode" });
  const skipped = await waitFor(
    () => get(playlistIndex) === 1 && get(currentPath) === clipC,
    20_000,
  );
  await sleep(500);
  const finalIndex = get(playlistIndex);
  const skipNotice = get(notice);
  const ok =
    loadFailedOk &&
    skipped &&
    finalIndex === 1 &&
    skipNotice !== null &&
    skipNotice.text.includes(baseName(brokenMkv));
  log(
    `| q6 | ${ok ? "PASS" : "FAIL"} | loadNotice=${loadFailedOk} index=${finalIndex} skipNotice=${
      skipNotice === null ? "none" : "shown"
    }`,
  );
}

/**
 * Previous wraps first→last when the queue has more than one item (VLC
 * E3/M8); a one-item queue does nothing for prev/next when un-looped.
 * Acceptance 7.
 */
async function sceneQ7(): Promise<void> {
  playPaths([clipA, clipB]);
  await waitFor(() => get(currentPath) === clipA, 15_000);
  const wrapped = advance(-1) === 1;
  await reset();
  playPaths([clipA]);
  await waitFor(() => get(currentPath) === clipA, 15_000);
  const nextStuck = advance(1) === null;
  const prevStuck = advance(-1) === null;
  log(
    `| q7 | ${
      wrapped && nextStuck && prevStuck ? "PASS" : "FAIL"
    } | wrap=${wrapped} nextStuck=${nextStuck} prevStuck=${prevStuck}`,
  );
  await reset();
}

async function runScene(scene: Scene): Promise<void> {
  await log(`| ${scene} | start |`);
  events.length = 0;
  await reset();
  try {
    switch (scene) {
      case "q2":
        await sceneQ2();
        break;
      case "q3":
        await sceneQ3();
        break;
      case "q4":
        await sceneQ4();
        break;
      case "q5":
        await sceneQ5();
        break;
      case "q6":
        await sceneQ6();
        break;
      case "q7":
        await sceneQ7();
        break;
    }
  } catch (error) {
    await log(`| ${scene} | FAIL | scene crashed: ${String(error)}`);
  }
}

/**
 * Ran by App.svelte's boot. Without the harness env vars this returns
 * before doing anything; with them, runs the requested scenes and marks
 * the run done (`| done | ...`), which is the harness's termination
 * signal inside the app log.
 */
export async function runPlaylistScenes(): Promise<void> {
  let requested: string[];
  try {
    requested = await invoke<string[]>("autotest_scene_names");
  } catch {
    return;
  }
  if (requested.length === 0) {
    return;
  }
  // The module's own event tap (independent of the app's binding): the
  // scenes need the raw event stream for their assertions.
  const unlisten = await onPlayerEvent((event) => {
    events.push(labelEvent(event));
  });
  await log(`| boot | ${requested.join(",")}`);
  for (const scene of SCENES) {
    if (requested.includes(scene) || requested.includes("all")) {
      await runScene(scene);
    }
  }
  await log(`| done |`);
  unlisten();
}
