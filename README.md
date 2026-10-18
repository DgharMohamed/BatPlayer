# BatPlayer 🦇

A modern cross-platform media player in the class of VLC and PotPlayer, built
with Tauri v2 and libmpv. Dark, minimal, and fast — near-black interface with
an electric-yellow (`#FFD400`) bat-wing accent.

**Status: Milestone 1 of 6 complete** (project skeleton). See the
[roadmap](#roadmap) below.

## Tech stack

- **App framework:** Tauri v2 (Rust backend, web frontend)
- **Playback engine:** libmpv via the `libmpv2` crate (Milestone 2)
- **Frontend:** TypeScript + Vite + Svelte 5, plain CSS variables for theming

## Architecture

BatPlayer renders video into a **native child window** and layers the Tauri
webview **transparently on top** of it, so the HTML control bar overlays the
video (this is mpv's `wid` embedding, wired up in Milestone 2):

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
- In Milestone 2, mpv runs on its own thread behind a single `Player` struct
  and exposes Tauri commands/events; the UI never touches mpv directly.

## Prerequisites

Common: [Node.js](https://nodejs.org) (LTS), [Rust](https://rustup.rs)
(stable, MSVC toolchain on Windows).

- **Windows:** Visual Studio Build Tools with the "Desktop development with
  C++" workload, and the WebView2 runtime (preinstalled on Windows 10/11).
- **Linux:** Tauri prerequisites for your distro (see
  [tauri prerequisites](https://tauri.app/start/prerequisites/)); from
  Milestone 2 also `libmpv-dev` (Debian/Ubuntu: `sudo apt install libmpv-dev`,
  Fedora: `sudo dnf install mpv-devel`, Arch: `sudo pacman -S mpv`).
- **macOS:** Xcode Command Line Tools (`xcode-select --install`). Note: mpv
  embedding and window transparency are **not yet tested on macOS** (the
  build enables Tauri's `macos-private-api` feature, required for
  `transparent: true`).

## Build and run

```bash
npm install

# Development (hot reload):
npm run tauri dev

# Production build (MSI/NSIS on Windows, deb/AppImage on Linux, dmg on macOS —
# packaging is configured in Milestone 5):
npm run tauri build

# Checks:
npm run check        # svelte-check
npm run build        # vite production build
cargo clippy -- -D warnings   # from src-tauri/
cargo fmt                     # from src-tauri/
```

## Project structure

```
src-tauri/src/
├─ main.rs          # entry point
├─ lib.rs           # Tauri builder/setup (video surface + resize wiring)
├─ platform/        # native video surface per OS (windows.rs, macos.rs, linux.rs)
├─ commands.rs      # Tauri commands (Milestone 2)
├─ player/          # mpv wrapper, property observers (Milestone 2)
├─ settings.rs      # persisted config (Milestone 4)
└─ history.rs       # resume positions, recent files (Milestone 3)
src/
├─ components/      # Svelte components (control bar, logo, ...)
├─ stores/          # frontend playback state
├─ i18n/            # locale files (English first)
├─ styles/          # CSS variables + global styles
└─ utils/
```

## Roadmap

1. ~~**Skeleton** — Tauri v2 project, transparent webview, empty native video
   child window~~ ✅
2. **Playback** — embed mpv via `wid`, open/play/seek/volume/fullscreen,
   property events to the UI
3. **Full MVP UI** — control bar logic, track menus, subtitles, shortcuts,
   drag-and-drop, resume position
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
