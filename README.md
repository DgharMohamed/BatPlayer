# BatPlayer 🦇

A modern cross-platform media player in the class of VLC and PotPlayer, built
with Tauri v2 and libmpv. Dark, minimal, and fast — near-black interface with
an electric-yellow (`#FFD400`) bat-wing accent.

**Status: Milestone 2 of 6 complete** (mpv playback wired end to end). See the
[roadmap](#roadmap) below.

## Tech stack

- **App framework:** Tauri v2 (Rust backend, web frontend)
- **Playback engine:** libmpv via the `libmpv2` crate
- **Frontend:** TypeScript + Vite + Svelte 5, plain CSS variables for theming

## Architecture

BatPlayer renders video into a **native child window** and layers the Tauri
webview **transparently on top** of it, so the HTML control bar overlays the
video (mpv's `wid` embedding):

```
┌─ Tauri window ──────────────────────────────┐
│  ┌─ WebView (transparent HTML UI) ───────┐  │
│  │  controls, overlays, idle watermark   │  │
│  ├───────────────────────────────────────┤  │
│  │  ┌─ Native child window (video) ───┐  │  │
│  │  │  mpv renders here via `wid`     │  │  │
│  │  └─────────────────────────────────┘  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

- The child surface is created in `src-tauri/src/platform/` (one module per
  OS) and is kept at the bottom of the window z-order, sized to the client
  area on every resize.
- **The window itself is opaque; only the webview is transparent.** Tauri's
  window-level `transparent: true` on Windows goes through tao's DWM
  blur-behind mode (`DwmEnableBlurBehindWindow` with an empty region), under
  which native child windows do not composite at all — the video surface
  would be invisible. BatPlayer instead builds the window and webview
  separately (`Window::builder` + `Window::add_child`, the multiwebview API
  behind Tauri's `unstable` feature) with `.transparent(true)` on the
  **webview** only. This is the same approach Tauri's own `add_child` docs
  reference for native-content layering.
- mpv runs on its own thread behind a single `Player` struct
  (`src-tauri/src/player/`) and exposes Tauri commands (`commands.rs`) plus
  `player-event` property events; the UI never touches mpv directly.


## Prerequisites

Common: [Node.js](https://nodejs.org) (LTS), [Rust](https://rustup.rs)
(stable, MSVC toolchain on Windows).

- **libmpv (all platforms):** the DLL/import library are **not** committed;
  fetch them once with a dedicated script or a package manager:

  ```bash
  # Windows (downloads the mpv dev build and generates mpv.lib from its
  # exports with dumpbin + lib.exe, needs 7-Zip and Visual Studio's tools):
  powershell -ExecutionPolicy Bypass -File scripts/fetch-mpv.ps1
  ```

  On Linux/macOS the system package takes over (see below); the vendored
  files are only used on Windows.

- **Windows:** Visual Studio Build Tools with the "Desktop development with
  C++" workload, 7-Zip (only for the fetch script), and the WebView2 runtime
  (preinstalled on Windows 10/11).
- **Linux:** Tauri prerequisites for your distro (see
  [tauri prerequisites](https://tauri.app/start/prerequisites/)); also
  `libmpv` (Debian/Ubuntu: `sudo apt install libmpv-dev`,
  Fedora: `sudo dnf install mpv-devel`, Arch: `sudo pacman -S mpv`).
- **macOS:** Xcode Command Line Tools (`xcode-select --install`). Note: mpv
  embedding and window transparency are **not yet tested on macOS** (the
  build enables Tauri's `macos-private-api` feature, required for
  `transparent: true`).

## Build and run

```bash
npm install
powershell -ExecutionPolicy Bypass -File scripts/fetch-mpv.ps1   # Windows only, once

# Development (hot reload):
npm run tauri dev

# Production build (MSI/NSIS on Windows, deb/AppImage on Linux, dmg on macOS —
# packaging is configured in Milestone 5):
npm run tauri build

# Checks:
npm run check        # svelte-check
npm run build        # vite production build
cargo clippy --all-targets -- -D warnings   # from src-tauri/
cargo fmt                     # from src-tauri/

# End-to-end check (Windows): builds, plays a generated test clip, and
# pixel-checks the window screenshots — see "Autotest" below.
powershell -ExecutionPolicy Bypass -File scripts/autotest.ps1
```

## Autotest

`scripts/autotest.ps1` plays a generated 2.5 s test clip (raw Y4M, no ffmpeg
required) in the debug build and pixel-checks that everything landed on
screen:

1. generates `sample.y4m` (rolling luminance ramp + cycling RGB block),
2. runs the app with `BATPLAYER_AUTOTEST_FILE` pointing at it,
3. collects the mpv `screenshot-to-file` frame via
   `BATPLAYER_AUTOTEST_SHOT` and verifies size, variance and chroma,
4. captures the app window and checks the bat logo, menu bar, play button
   and the composited video surface.

The same hooks are handy for manual debugging:

```
BATPLAYER_AUTOTEST_FILE=<media>   auto-play this file after startup
BATPLAYER_AUTOTEST_SHOT=<file>    dump an mpv screenshot into this path
BATPLAYER_MPV_LOG=<file>          write a verbose mpv log
```

They are no-ops without the env variables and are compiled out of release
builds.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `Ctrl+O` | Open a media file |
| `Space` / `K` | Play / pause |
| `F` / double-click video | Toggle fullscreen (`Esc` leaves) |
| `←` / `→` | Seek −5 s / +5 s (with `Shift`: ±10 s) |
| `↑` / `↓` | Louder / quieter |
| `M` | Mute |
| `[` / `]` / `Backspace` | Slower / faster / normal speed |
| `,` / `.` | Frame back / forward while paused |
| `S` | Save snapshot to Pictures |
| `A` / `V` | Cycle audio / subtitle track |

## Project structure

```
src-tauri/
├─ build.rs          # links libmpv from src-tauri/mpv and copies the DLL
├─ src/
│  ├─ main.rs        # entry point
│  ├─ lib.rs         # Tauri builder/setup (surface + player + commands)
│  ├─ platform/      # native video surface per OS (windows.rs, macos.rs, linux.rs)
│  ├─ commands.rs    # Tauri commands (load/seek/volume/tracks/snapshot)
│  ├─ player/        # mpv wrapper, observed properties, event thread
│  ├─ autotest.rs    # env-var driven e2e hooks (debug builds only)
│  ├─ settings.rs    # persisted config (Milestone 4)
│  └─ history.rs     # resume positions, recent files (Milestone 3)
├─ mpv/              # vendored libmpv (gitignored; fetch-mpv.ps1 fills it)
src/
├─ api/              # typed invoke/listen bindings to the Rust commands
├─ components/       # Svelte components (control bar, logo, topbar/)
├─ stores/           # playback state, chrome auto-hide, window flags
├─ i18n/             # locale files (English first)
├─ styles/           # CSS variables + global styles
└─ utils/            # actions, dialogs/media openers, formatting
scripts/
├─ fetch-mpv.ps1     # vendor libmpv (Windows)
└─ autotest.ps1      # end-to-end visual check (Windows, debug build)
```

## Roadmap

1. ~~**Skeleton** — Tauri v2 project, transparent webview, empty native video
   child window~~ ✅
2. ~~**Playback** — embed mpv via `wid`, open/play/seek/volume/fullscreen,
   property events to the UI~~ ✅
3. **Full MVP UI** — playlist panel, track menus proper, resume position
4. **Playlist and settings**
5. **Packaging and CI** for Linux, Windows, macOS
6. **Polish** — video adjustments, A-B loop, media info, i18n, themes

## Platform notes / known quirks

- **Windows** (current dev platform, verified): the video surface is a plain
  `WS_CHILD` window below the WebView2 host; the webview's own transparency
  composites the native surface correctly, and resize tracking was verified
  programmatically. Known quirk: window-level transparency must NOT be used
  (see Architecture above). DPI scaling: the surface sizes itself from the
  parent's client rect, which is already in physical pixels, so mixed-DPI is
  handled by the existing resize path (multi-monitor DPI-change edge cases
  get exercised in Milestone 3).
- **Linux:** mpv `wid` embedding requires X11/XWayland. A Wayland session
  will need to run the app under XWayland (e.g. `GDK_BACKEND=x11`); this is
  documented and handled in Milestone 2.
- **macOS:** NSView manipulation must happen on the main thread; the video
  surface is a stub there until Milestone 2. Untested.

## Licensing

BatPlayer is MIT-licensed. From Milestone 2 it dynamically links **libmpv**
(LGPL or GPL depending on build), which is kept compliant by dynamic linking;
license notices are shipped with the installers. See [LICENSE](LICENSE).
