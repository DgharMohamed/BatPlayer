# VLC 3.0.24 behavioral reference (observed) and BatPlayer mapping

Evidence sources, in order of reliability:

1. **Scripted experiments against the installed VLC 3.0.24** (`C:\Program Files\VideoLAN\VLC`). Each
   experiment ran a fresh `vlc.exe --intf dummy --extraintf http` instance driven over the HTTP
   API with wall-clock logging. Logs live under `%TEMP%\vlctest\logs` (`E1`–`E7`,
   `E7-dir-enqueue-playlist.json`, `E7-dir-play-playlist.json`, `M1`–`M6`, `M1b`, `M7`, `M8`).
2. **Defaults read from VLC's own config template** `%APPDATA%\vlc\vlcrc` (written by this build;
   every unset option shows its shipped default in a commented line). The file contained exactly
   two user-set values (`qt-privacy-ask=0`, `metadata-network-access=1`), so hotkey/jump defaults
   below are the stock build's.
3. **VLC 3.0.24 public source** `modules/control/hotkeys.c`
   (https://github.com/videolan/vlc/tree/3.0.24) for the loop tri-state cycle, rate/OSD messages
   and volume-step behavior.

Nothing below is derived from unverified assumptions; items marked *(design choice)* are
BatPlayer decisions informed by VLC rather than VLC rules.

## Keyboard defaults (VLC 3.0.24, obs. from this build's `vlcrc`)

| Action | VLC default key | Size/notes |
| --- | --- | --- |
| Play/pause | `Space` | |
| Fullscreen toggle | `f` | |
| Leave fullscreen | `Esc` | |
| Volume up/down | `Ctrl+Up` / `Ctrl+Down` | step 5 % (`volume-step=12.8` on VLC's 256 = 100 % scale, confirmed in `hotkeys.c` `playlist_VolumeUp/Down`) |
| Mute | `m` | OSD shows mute icon; unmute shows the restored level (`DisplayVolume`) |
| Faster / slower (coarse) | `+` / `-` | |
| Rate normal / fine | `=` / `]` / `[` | fine steps are 0.1 and clamped (rate in 0.03..~31, UI-facing sane band) |
| Next / Previous media | `n` / `p` | see playlist rules |
| Stop | `s` | |
| Frame next | `e` | VLC 3 has **no** frame-back key |
| Snapshot | `Shift+s` | |
| Audio track cycle | `b` | |
| Subtitle track cycle | `v` (reverse: `Alt+v`, toggle off/on: `Shift+v`) | |
| Audio delay | `j` / `k`, subtitle delay `g` / `h` | |
| Very short jump ± | `Shift+Left/Right` | 3 s (`extrashort-jump-size=3`) |
| Short jump ± | `Alt+Left/Right` | 10 s (`short-jump-size=10`) |
| Medium jump ± | `Ctrl+Left/Right` | 60 s |
| Long jump ± | `Ctrl+Alt+Left/Right` | 300 s |
| Loop | `l` | OSD "Loop: Off / All / One" |
| Random | `r` | OSD "Random: On / Off" |

Plain `Up/Down/Left/Right` are **not** seek/volume keys in VLC's hotkey module (`key-nav-*`).

## Engine / playlist rules (verified by experiments)

| Rule | Evidence |
| --- | --- |
| Pause is a toggle; time freezes while paused | `E1`, `M1` |
| Seeking works while paused and keeps the paused state (t 1 → 4 absolute, −3 relative) | `M1b` |
| Rate applies live (2× → ~2 s of media per s; 0.5× → half speed) and persists on the current input | `E1` |
| Volume: unsigned value = absolute set, signed = relative; >125 % accepted by the engine (600/256 ≈ 234 % observed). Village slider caps at `qt-max-volume=125` | `M2`, vlcrc |
| Playlist auto-advance at EOF: immediate transition **playing → playing**, no stopped gap, time resets to 0 | `E2` |
| End of playlist (loop off, last item): state → `stopped`, current item cleared, playlist contents retained | `M3`, `M4` |
| `repeat` (loop one): the same item restarts itself at EOF (same playlist id, time resets) | `E4` |
| `loop` (all): items wrap at the end of the list; a single-item playlist repeats itself | `M7` |
| `random`: advances through shuffled items; **stops only after every item was played once** (3 × 12 s items → stop at ≈36 s); works with manual near-EOF seeks too | `M4`, `M4b` |
| One-off anomaly: in one mixed-seek/repeat/random sequence VLC stopped instead of advancing (`E4`); not reproducible in `M4b` — not treated as a rule | `E4` |
| Broken (corrupt) item in the middle of the playlist: **skipped automatically**, never becomes current, playback continues on the next playable item | `E5` |
| Nonexistent path passed on the command line: silently dropped | path handling in `E1` first pass |
| `en_enqueue`: adds to the playlist **without interrupting** the current item | `M5` |
| `in_play` ("open"): appends the file **and** starts playing it, moving the current item to it | `M5` |
| Next/Previous are raw playlist hops. Previous wraps from the first to the last item; with a single-item playlist both do nothing visible | `E3`, `M8` |
| Paused state persists across end-of-item: a paused file parked at EOF does not auto-advance until unpaused (VLC 3 quirk) | `M6` |
| Fresh item from "a file just opened always auto-plays" (VLC `in_play` starts playback) | `M5` |
| VLC 3 does **not** have a "seek to previous position on reopen" core option; the feature is `qt-continue=1` ("Continue playback?" — default 'ask', always/ask/never) | vlcrc line 1654 |
| `volume-save=1`: the last-used volume is restored across app runs (initial 154/256 observed without command-line override) | vlcrc line 4055, `E1` pre-fix run |
| `qt-recentplay=1`: recently played items are remembered | vlcrc line 1648 |

### Folder inputs (E7)

Enqueueing (≈ dropping / "Open Folder") a **directory** with VLC:

| Rule | Evidence |
| --- | --- |
| The folder enters the playlist as a **single lazy leaf** (`name: "e7"`, no expansion) | `E7-dir-enqueue-playlist.json` |
| When played, the leaf **expands in place, recursively** — nested `sub\m2.wav` appeared — and one of the expanded items starts playing; non-media files inside are dropped | `E7-dir-play-playlist.json` |
| Within-folder ordering at expansion: not derivable from a single sample (the nested file played first); no ordering rule is claimed | `E7-dir-play-playlist.json` |
| No default "Open Folder" hotkey ships in VLC's core options (nothing in `vlcrc`; Qt menu shortcuts are not exposed there) | this build's `vlcrc` |

## VLC-vs-BatPlayer matrix (Phase 3)

Status legend: ✔ implemented & correct · ◐ partial · ✘ missing · — nah/not wanted.

| Feature | VLC | BatPlayer before | Status before | Action taken |
| --- | --- | --- | --- | --- |
| Open file (dialog, drop, recent) | ✔ | ✔ | ✔ | — |
| Play/pause, stop, seek±, volume, mute, speed, frame step | ✔ | ✔ | ✔ | key parity additions |
| Seek sizes | 3/10/60/300 s | 5/10 s | ◐ | matched VLC: Shift=±3, Alt=±10, Ctrl=±60, Ctrl+Alt=±300, plain stays 5 s |
| Volume step (keyboard) | 5 % | 5 % | ✔ | added `Ctrl+Up/Down` alias |
| Volume ceiling | slider 125 % (engine goes higher) | slider 130 % (mpv default) | ◐ | kept 130 % *(identity decision)* |
| Volume/mute persistence | ✔ (`volume-save=1`) | ✘ | ✘ | implemented (`settings.rs`) |
| Recent files | ✔ | ✔ | ✔ | — |
| Resume playback position | ✔ (`qt-continue`) | ✘ | ✘ | implemented (auto-resume + watch-through resets) |
| Playlist queue | ✔ | ✘ (first dropped file won) | ✘ | playlist store + panel + next/prev buttons + menu + Ctrl+L |
| Auto-advance | ✔ | ✘ | ✘ | on EOF / on unloadable item |
| Loop: Off/All/One tri-state | ✔ | ✘ | ✘ | VLC cycle via `l` + menu checkboxes |
| Random/shuffle | ✔ (plays all once, then stop) | ✘ | ✘ | same semantics |
| Multi-file drop → queue | ✔ | ✘ (only first file) | ✘ | first plays, rest enqueued |
| Folder open (dialog ↑) / folder drop → queue | ✔ (lazy leaf; expands recursively at play, `E7`) | ✘ (dropped folder failed the extension filter, mpv refused the directory) | ✘ | implemented: Rust `resolve_media_paths` scan (recursive, per-level case-insensitive sort, depth 32, 5000-file cap) + Media ▸ Open Folder… (no hint — see E7) + drop; deviates: eager expansion (deviations list) |
| Open file while playing replaces current | ✔ (`in_play`) | ✔ (loadfile replaces) | ✔ | routed through playlist |
| Error recovery: skip broken playlist item | ✔ | ✘ | ✘ | end-file error advances the queue |
| Loading/unsupported file notice | dialog | inline notice plate + Esc/Cancel | ✔ | — |
| OSD on volume/mute/rate/seek | ✔ | ✔ | ✔ | added loop/random OSDs |
| Click on video toggles pause | — (VLC does not by default) | ✘ | — | not added (VLC parity) |
| Mouse wheel volume | default config value `0`; GUI behavior unverified headlessly | ✘ | ✘ | added *(mainstream convention, marked as BatPlayer extension)* |
| Stop hotkey `s` | ✔ | ✘ (was snapshot) | — | kept BatPlayer mapping (`s`=snapshot, `Shift+s` alias added); `s`-=stop not taken *(identity decision)* |
| Frame back (`,`) | ✘ in VLC | ✔ | ✔ (extra) | kept |
| Single-instance routing (`one-instance-when-started-from-file=1`) | ✔ | ✘ | ✘ | **future work** (needs Tauri single-instance plugin) |
| Resize window to native video size (`qt-video-autoresize=1`) | ✔ | ✘ | ✘ | **future work** |
| Audio/subtitle delay keys (`j`/`k`, `g`/`h`) | ✔ | ✘ | ✘ | **future work** (needs delay property plumbing) |
| Chapters, title navigation | ✔ | ✘ | ✘ | **future work** |
| Aspect/zoom/crop keys | ✔ | ✘ | ✘ | **future work** (milestone 6) |
| Equalizer, effects, renderer | ✔ | ✘ | ✘ | out of scope |
| Window title shows media name | ✔ | ✔ (title bar) | ✔ | — |
| Go to time (Ctrl+T) | ✔ (dialog) | ✘ | ✘ | **future work** (needs a text input dialog) |

## Acceptance criteria (Phase 5 uses these as test cases)

1. **Pause/seek:** pause → time frozen; seek absolute/relative while paused relocates and stays paused
   (`M1b` numbers mirrored by mpv property events in BatPlayer).
2. **Auto-advance:** two queued files: at EOF of the first the second starts ≈ immediately; UI shows
   the second title and time 0; no gap between files.
3. **Loop-one:** with loop = One and one queued item, EOF re-plays the same item (time returns to 0 ›
   progresses under the same file name).
4. **Loop-all:** with two queued items, EOF at the last wraps to the first.
5. **Random:** queue of three items: order varies; after every item has played once, playback parks
   at EOF instead of looping; toggling loop=all re-fills the "unplayed" pool.
6. **Skip broken:** a corrupt file queued between two good ones is skipped automatically; the next
   playable item's OSD/notice shows the failure once.
7. **Prev/Next:** Previous on the first item wraps to the last (VLC rule); Next with a single
   item does nothing except restart that item.
8. **Resume:** watch a file to ≥ 5 s, close the app, reopen → playback resumes near the saved point
   and a notice says so; watched-through positions (> 95 %) resume from 0; nothing resumes for
   < 5 s or unseekable streams.
9. **Persisted volume:** set 80 %, quit, restart → volume bar shows 80 % (and mute state persists).
10. **Playlist persistence inside a session** is *not* required to survive restarts (VLC keeps the
    playlist in one session; older VLC saved playlists only via explicit save).
11. **Folder drop/Open Folder:** dropping a folder (or Media ▸ Open Folder…) queues every media
    file inside it recursively; non-media files are ignored; files land in a deterministic
    alphabetical order per level; the first file plays and replaces the queue (same rule as any
    direct open); mixed drops (files + folders) resolve through the same scan.
12. **Folder scan limits:** a folder tree deeper than 32 levels or exceeding 5000 files queues
    what was found and shows a truncation notice; an empty (no-media) folder or picker shows the
    "no playable media found in this folder" notice.
13. **Window responsiveness (frameless window):** the window keeps its
    `WS_SIZEBOX`/`WS_MAXIMIZEBOX`/`WS_MINIMIZEBOX` styles while decorations are off; a click on any
    edge/corner band engages the OS modal sizing loop and the window follows the cursor exactly
    until release (respecting the min size 640×360); minimize/restore round-trips; maximize covers
    the monitor work area with the taskbar visible; after an external snap-like resize the webview
    and the mpv surface follow the new client area with the chrome intact.

### Phase 5 result (implementation status per criterion)

| # | Status | Verified |
| --- | --- | --- |
| 1 | ✔ pre-existing (M1b semantics already current) | e2e autotest boots+plays; review |
| 2 | ✔ implemented (`playlist.ts` eof edge → `advance` → `playAt`) | review; needs hand check |
| 3 | ✔ implemented (replay via seek-to-0 + unpause, no reload) | review; needs hand check |
| 4 | ✔ implemented (wrap in `advance`, loop "all") | review; needs hand check |
| 5 | ✔ implemented (shuffle pool consumed once, refill only on loop "all") | review; needs hand check |
| 6 | ✔ implemented (`endFile` error → skip with "skipped" notice; double-signal guard) | review; needs hand check |
| 7 | ✔ implemented (prev wraps when >1 items; single-item no-op for prev/next unlooped) | review; needs hand check |
| 8 | ✔ implemented (`update_position` thresholds + Rust unit tests; resume hint returned by `load_file`) | 8 unit tests PASS |
| 9 | ✔ implemented (`settings.rs` debounce writer, applied at mpv init) | 4 unit tests PASS |
| 10 | ✔ by design — queue lives in frontend state only | — |
| 11 | ✔ implemented (`media_scan.rs` recursive case-insensitive sort scan, drop routing) | 5 `media_scan` unit tests PASS |
| 12 | ✔ implemented (depth/file caps + truncation + empty notices) | caps covered by `media_scan` unit tests |
| 13 | ✔ implemented (Tauri drag-resize ring replicated for `WindowChild`, see deviations below) | `scripts/window-probe.ps1`: 36 runtime checks PASS ("PROBE ALL PASS"), incl. real scripted edge drags, OS cursor confirmation, sizing-loop engagement via `GetGUIThreadInfo`, exact geometry deltas, minimize/restore/maximize/Snap-follow |

## Implementation decisions needing visibility (deviations, Phase 4)

- **Dialog/drop/Open Recent opens *replace* the queue** — a visible queue always reflects what the
  user last asked to play. (VLC may accumulate entries instead; unverified for GUI drops in our
  experiments, so the simpler rule was chosen and documented.)
- **`e` is a stop alias (BatPlayer addition)**; `s` stays "snapshot" (BatPlayer identity) where VLC
  uses `s` for stop — `Shift+s` also snapshots via lowercase normalization.
- **Resume is silent-by-default**: VLC 3.0's `qt-continue` default asks via a dialog; BatPlayer
  always continues and shows an inline "Resuming playback from m:ss" notice instead.
- **Keyboard `l`/`r` and the loop/random menu entries share one OSD path** (loop cycle: off → all →
  one → off; the two menu entries set a specific target state and clear the other, VLC-style).
- **Folders expand eagerly and sorted (folder-support phase)**: VLC keeps a dropped/Open Folder
  directory as one lazy playlist leaf and expands it in place at play time (`E7`); BatPlayer
  scans Rust-side and queues every contained media file immediately, ordered per level
  case-insensitively — so the panel shows the whole queue up front (the E7 sample was too small
  to establish VLC's expansion order, and a lazy directory row would not fit the flat queue
  model). Depth cap 32 / file cap 5000 guard junction loops and mega-drops, reported as a
  truncation notice rather than an error.
- **Open Folder carries no hotkey hint**: no folder-open key is verifiable in this build's
  `vlcrc` (Qt menu shortcuts are not part of the core options file), so the menu entry ships
  without a hint instead of a guessed key.
- **The drag-resize ring is replicated for `WindowChild` windows (responsibility note)**:
  tauri-runtime-wry attaches its invisible resize ring (`undecorated_resizing`: the
  `TAURI_DRAG_RESIZE_BORDERS` child window that answers `WM_NCHITTEST` and forwards
  `WM_NCLBUTTONDOWN` to the parent so `DefWindowProc` runs the modal sizing loop, plus the parent
  subclass that strips the ring while maximized) **only for `WindowContent` windows**. BatPlayer
  builds its window via `Window::add_child` (the `WindowChild` sibling style), which that code
  path never reaches, so `src-tauri/src/platform/windows.rs` reproduces the same mechanism with
  the same class/window names, DPI-aware band sizes (`GetSystemMetricsForDpi(SM_CXFRAME/
  SM_CYFRAME)`), and the maximized-strip behavior (the child is shrunk to 0×0 while
  `IsZoomed`). Sources: tao `0.37.1` `event_loop.rs` (parent `WM_NCLBUTTONDOWN` only emits
  `DecorationsClick`; sizing comes from the `DefWindowProc` chain) and
  `tauri-runtime-wry 2.12.2` `src/undecorated_resizing.rs`. The attach is soft-fail: if it fails,
  a stderr note is logged and only edge resizing is disabled. Runtime proof lives in
  `scripts/window-probe.ps1` (styles, ring hit-tests, real scripted drags in the OS sizing loop,
  minimize/restore/maximize/Snap-follow).

