<script lang="ts">
  import { onMount } from "svelte";
  import { get } from "svelte/store";

  import { getCurrentWebview } from "@tauri-apps/api/webview";
  import { onOpenFiles, takePendingOpenFiles } from "./api/open-with";
  import { setPlaylistDock } from "./api/player";
  import ControlBar from "./components/ControlBar.svelte";
  import BatLogo from "./components/BatLogo.svelte";
  import LoadingOverlay from "./components/LoadingOverlay.svelte";
  import Osd from "./components/Osd.svelte";
  import PlaylistPanel from "./components/PlaylistPanel.svelte";
  import SpeedChip from "./components/SpeedChip.svelte";
  import TopBar from "./components/topbar/TopBar.svelte";
  import { t } from "./i18n";
  import {
    bindWindowState,
    enterMiniPlayer,
    exitFullscreen,
    exitMiniPlayer,
    fullscreen,
    miniPlayer,
    toggleFullscreen,
  } from "./stores/window";
  import { runPlaylistScenes } from "./autotest/scenes";
  import { keepChromeVisible, pinChromeFocus } from "./stores/chrome";
  import { bindHistory } from "./stores/history";
  import { playlistDockWidth, playlistOpen } from "./stores/playlist";
  import {
    bindPlayerEvents,
    idle,
    loading,
    mediaLoaded,
    muted,
    notice,
  } from "./stores/player";
  import {
    cycleAudioTrack,
    cycleLoop,
    cycleSubtitleTrack,
    nextTrack,
    prevTrack,
    stepFrame,
    resetSpeed,
    seekRelative,
    stepSpeed,
    stepVolume,
    stopPlayback,
    takeSnapshot,
    toggleMute,
    togglePlaylist,
    togglePlayPause,
    toggleShuffle,
  } from "./utils/actions";
  import {
    openMediaPath,
    pickAndOpenMedia,
    playDroppedSources,
    startProgressSaver,
  } from "./utils/media";

  /** True while files are dragged over the window (drop preview). */
  let draggingFiles = $state(false);
  let contextMenu = $state<{ x: number; y: number } | null>(null);
  let playlistDockFrame: number | null = null;
  let pendingDockWidth = 0;

  function syncPlaylistDock(width: number): void {
    pendingDockWidth = width;
    if (playlistDockFrame !== null) return;
    playlistDockFrame = requestAnimationFrame(() => {
      playlistDockFrame = null;
      void setPlaylistDock(pendingDockWidth).catch((error: unknown) => {
        console.error("Could not resize the video for the playlist", error);
      });
    });
  }

  /**
   * One pipeline for every external path arrival — drag-and-drop, the OS
   * "Open with" boot pull and second-launch forwards alike: files and
   * folders expand Rust-side into a sorted media queue and play; subtitle
   * (or unknown) paths keep the attach/fail notices.
   */
  function playDroppedOrAttach(paths: string[]): void {
    void (async () => {
      if (await playDroppedSources(paths)) {
        return;
      }
      const [first] = paths;
      if (first !== undefined) {
        await openMediaPath(first);
      }
    })();
  }

  onMount(() => {
    const cleanups: Array<() => void> = [];

    void (async () => {
      cleanups.push(await bindPlayerEvents());
      cleanups.push(await bindWindowState());
      cleanups.push(await bindHistory());
      // OS "Open with". Subscribe BEFORE the boot pull: the pull flips later
      // arrivals from queued to pushed, so the listener must exist first.
      cleanups.push(await onOpenFiles((paths) => playDroppedOrAttach(paths)));
      const pendingFiles = await takePendingOpenFiles();
      if (pendingFiles.length > 0) {
        playDroppedOrAttach(pendingFiles);
      }
      cleanups.push(
        playlistOpen.subscribe((open) => {
          syncPlaylistDock(open ? get(playlistDockWidth) : 0);
        }),
      );
      cleanups.push(
        playlistDockWidth.subscribe((width) => {
          if (get(playlistOpen)) {
            syncPlaylistDock(width);
          }
        }),
      );
      cleanups.push(() => {
        if (playlistDockFrame !== null) cancelAnimationFrame(playlistDockFrame);
      });
      // Resume saves on a timer so a crash mid-file still resumes nearby.
      cleanups.push(startProgressSaver());
      // Playlist-scene harness (scripts/autotest.ps1): dormant without
      // BATPLAYER_AUTOTEST_SCENE; see src/autotest/scenes.ts.
      void runPlaylistScenes();
      cleanups.push(
        await getCurrentWebview().onDragDropEvent((event) => {
          switch (event.payload.type) {
            case "enter":
              draggingFiles = true;
              break;
            case "over":
              draggingFiles = true;
              break;
            case "drop": {
              draggingFiles = false;
              playDroppedOrAttach(event.payload.paths);
              break;
            }
            case "leave":
              draggingFiles = false;
              break;
          }
        }),
      );
    })();

    return () => {
      for (const cleanup of cleanups) {
        cleanup();
      }
    };
  });

  function isTypingTarget(target: EventTarget | null): boolean {
    return (
      target instanceof HTMLInputElement ||
      target instanceof HTMLTextAreaElement ||
      target instanceof HTMLSelectElement ||
      (target instanceof HTMLElement &&
        (target.isContentEditable || target.getAttribute("role") === "textbox"))
    );
  }

  /** Buttons, menu items and links activate on Space natively — never hijack it. */
  function ownsSpace(target: EventTarget | null): boolean {
    return (
      target instanceof Element &&
      target.closest("button, [role='menuitem'], a[href]") !== null
    );
  }

  function onKeydown(event: KeyboardEvent): void {
    if (event.key === "Escape" && contextMenu !== null) {
      event.preventDefault();
      contextMenu = null;
      return;
    }

    if (event.defaultPrevented || isTypingTarget(event.target)) {
      return;
    }

    if (event.key === " " && ownsSpace(event.target)) {
      return;
    }

    const playingNow = $mediaLoaded && !$idle;

    // Ctrl/meta bindings (VLC: Ctrl+O open, Ctrl+Up/Down volume,
    // Ctrl+Left/Right large jumps, Ctrl+Alt even larger ones).
    if (event.ctrlKey || event.metaKey) {
      switch (event.code) {
        case "KeyO":
          if (!event.shiftKey && !event.altKey) {
            event.preventDefault();
            void pickAndOpenMedia();
          }
          return;
        case "KeyL":
          if (!event.altKey) {
            event.preventDefault();
            void togglePlaylist();
          }
          return;
        case "ArrowUp":
          if (!event.altKey) {
            event.preventDefault();
            void stepVolume(5);
          }
          return;
        case "ArrowDown":
          if (!event.altKey) {
            event.preventDefault();
            void stepVolume(-5);
          }
          return;
        case "ArrowLeft":
        case "ArrowRight": {
          const delta = event.code === "ArrowLeft" ? -1 : 1;
          const jump = event.altKey ? 300 : 60;
          if (playingNow && !event.shiftKey) {
            event.preventDefault();
            void seekRelative(delta * jump);
          }
          return;
        }
        default:
          return;
      }
    }

    // VLC keys match lowercase letters only; normalizing here also fixes
    // Shift+letter chords never firing (Shift+S snapshot, Shift+K pause).
    const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;

    if (key === "F11") {
      event.preventDefault();
      void toggleFullscreen();
      return;
    }

    // VLC seek distances: Shift ±3s, Alt ±10s, Ctrl ±60s, Ctrl+Alt ±300s.
    // Plain arrows use VLC's short jump (10s).
    if (key === "ArrowLeft" || key === "ArrowRight") {
      if (!playingNow) {
        return;
      }
      event.preventDefault();
      const delta = key === "ArrowLeft" ? -1 : 1;
      const jump = event.shiftKey ? 3 : 10;
      void seekRelative(delta * jump);
      return;
    }

    switch (key) {
      case " ":
      case "k":
        event.preventDefault();
        void togglePlayPause();
        return;
      case "f":
        event.preventDefault();
        void toggleFullscreen();
        return;
      case "Escape":
        event.preventDefault();
        // A load in flight claims Escape first: pressing it again leaves
        // fullscreen, so a hung open never traps the user.
        if ($loading) {
          void stopPlayback();
        } else {
          void exitFullscreen();
        }
        return;
      case "m":
        void toggleMute();
        return;
      case "s":
        if (event.shiftKey && playingNow) {
          void takeSnapshot();
        } else if (!event.shiftKey) {
          void stopPlayback();
        }
        return;
      case "e":
        if (playingNow) {
          void stepFrame(1);
        }
        return;
      case "a":
        if (playingNow) {
          void cycleAudioTrack();
        }
        return;
      case "b":
        // VLC: audio track cycle binds to b rather than a.
        if (playingNow) {
          void cycleAudioTrack();
        }
        return;
      case "v":
        if (playingNow) {
          void cycleSubtitleTrack();
        }
        return;
      case "n":
        void nextTrack();
        return;
      case "p":
        void prevTrack();
        return;
      case "l":
        event.preventDefault();
        void cycleLoop();
        return;
      case "r":
        void toggleShuffle();
        return;
      case "[":
        if (playingNow) {
          void stepSpeed(-0.25);
        }
        return;
      case "]":
        if (playingNow) {
          void stepSpeed(0.25);
        }
        return;
      case "=":
        if (playingNow) {
          void resetSpeed();
        }
        return;
      case "+":
        // VLC: plus/minus change speed; brackets make fine adjustments.
        if (playingNow) {
          void stepSpeed(1);
        }
        return;
      case "-":
        if (playingNow) {
          void stepSpeed(-1);
        }
        return;
      case ",":
        if (playingNow) {
          void stepFrame(-1);
        }
        return;
      case ".":
        if (playingNow) {
          void stepFrame(1);
        }
        return;
      case "Backspace":
        if (playingNow) {
          void resetSpeed();
        }
        return;
      case "ArrowUp":
        event.preventDefault();
        void stepVolume(5);
        return;
      case "ArrowDown":
        event.preventDefault();
        void stepVolume(-5);
        return;
      default:
        break;
    }
  }

  function onContextMenu(event: MouseEvent): void {
    event.preventDefault();
    if (event.target instanceof Element && event.target.closest(".player-context-menu")) {
      return;
    }
    const menuWidth = 224;
    const menuHeight = 470;
    contextMenu = {
      x: Math.max(8, Math.min(event.clientX, window.innerWidth - menuWidth - 8)),
      y: Math.max(8, Math.min(event.clientY, window.innerHeight - menuHeight - 8)),
    };
  }

  function closeContextMenuOnOutside(event: PointerEvent): void {
    if (
      event.target instanceof Element &&
      event.target.closest(".player-context-menu") !== null
    ) {
      return;
    }
    contextMenu = null;
  }

  function runContextAction(action: () => unknown): void {
    contextMenu = null;
    void action();
  }

  /** Double-clicking the video toggles fullscreen, as in every player. */
  function onStageDblclick(): void {
    void toggleFullscreen();
  }

  /**
   * Wheel over the video steps the volume (a BatPlayer extension, noted in
   * the keyboard table): hands never leave the playback area. Only discrete
   * notches react, so touchpads do not sweep the volume away. No
   * preventDefault: the stage cannot scroll, and Svelte's delegated wheel
   * listeners are passive.
   */
  function onStageWheel(event: WheelEvent): void {
    if (Math.abs(event.deltaY) < 10) {
      return;
    }
    void stepVolume(event.deltaY < 0 ? 2 : -2);
  }

  /**
   * Keyboard focus inside a bar holds it open (Pointer focus after a click
   * must not, or the bars would never auto-hide during playback).
   */
  function onFocusIn(event: FocusEvent): void {
    const target = event.target;
    pinChromeFocus(
      target instanceof Element &&
        target.matches(":focus-visible") &&
        target.closest(".top-bar, .control-bar") !== null,
    );
  }

  function onFocusOut(event: FocusEvent): void {
    const target = event.target;
    if (target instanceof Element && target.closest(".top-bar, .control-bar") !== null) {
      pinChromeFocus(false);
    }
  }
</script>
<svelte:window
  onkeydown={onKeydown}
  oncontextmenu={onContextMenu}
  onpointerdown={closeContextMenuOnOutside}
  onpointermove={keepChromeVisible}
  onfocusin={onFocusIn}
  onfocusout={onFocusOut}
/>

<!--
  The video fills the whole client area (native child window behind this
  transparent webview), so the bars are overlays and the stage itself must
  stay see-through.
-->
<div class="app" class:mini-player={$miniPlayer}>
  <TopBar />

  <main
    class="stage"
    style:width={$playlistOpen && !$miniPlayer
      ? `calc(100% - ${$playlistDockWidth}px)`
      : "100%"}
    aria-label={t("video.areaLabel")}
    ondblclick={onStageDblclick}
    onwheel={onStageWheel}
  >
    <div class="idle-mark" class:visible={$idle}>
      <span class="idle-logo"><BatLogo size={104} /></span>
      <p class="idle-hint">{t("idle.hint")}</p>
    </div>

    {#if $notice !== null}
      <div
        class="notice"
        class:error={$notice.kind === "error"}
        role={$notice.kind === "error" ? "alert" : "status"}
      >
        {$notice.text}
      </div>
    {/if}
  </main>

  <LoadingOverlay />
  <ControlBar />
  <PlaylistPanel />
  <Osd />
  <SpeedChip />

  {#if $miniPlayer}
    <div class="mini-drag-region" data-tauri-drag-region aria-hidden="true">
      <span data-tauri-drag-region></span>
    </div>
    <button
      class="mini-exit"
      type="button"
      title={t("controls.exitMiniPlayer")}
      aria-label={t("controls.exitMiniPlayer")}
      onclick={() => void exitMiniPlayer()}
    >
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M4 4h6v2H6v4H4V4zm10 0h6v6h-2V6h-4V4zM4 14h2v4h4v2H4v-6zm14 0h2v6h-6v-2h4v-4z" />
      </svg>
    </button>
  {/if}

  {#if contextMenu !== null}
    <div
      class="player-context-menu"
      role="menu"
      aria-label={t("video.areaLabel")}
      style:left="{contextMenu.x}px"
      style:top="{contextMenu.y}px"
      oncontextmenu={(event) => event.preventDefault()}
    >
      <button role="menuitem" title={`${t("menu.playPause")} (Space)`} disabled={!$mediaLoaded} onclick={() => runContextAction(togglePlayPause)}>
        {t("menu.playPause")}
      </button>
      <button role="menuitem" title={`${t("menu.stop")} (S)`} disabled={!$mediaLoaded} onclick={() => runContextAction(stopPlayback)}>
        {t("menu.stop")}
      </button>
      <button role="menuitem" title={`${t("menu.previous")} (P)`} disabled={!$mediaLoaded} onclick={() => runContextAction(prevTrack)}>
        {t("menu.previous")}
      </button>
      <button role="menuitem" title={`${t("menu.next")} (N)`} disabled={!$mediaLoaded} onclick={() => runContextAction(nextTrack)}>
        {t("menu.next")}
      </button>
      <div class="context-divider" role="separator"></div>
      <button role="menuitem" title={`${t("controls.slower")} ([ / -)`} disabled={!$mediaLoaded} onclick={() => runContextAction(() => stepSpeed(-0.25))}>
        {t("controls.slower")}
      </button>
      <button role="menuitem" title={`${t("menu.resetSpeed")} (=)`} disabled={!$mediaLoaded} onclick={() => runContextAction(resetSpeed)}>
        {t("menu.resetSpeed")}
      </button>
      <button role="menuitem" title={`${t("controls.faster")} (] / +)`} disabled={!$mediaLoaded} onclick={() => runContextAction(() => stepSpeed(0.25))}>
        {t("controls.faster")}
      </button>
      <div class="context-divider" role="separator"></div>
      <button role="menuitem" title={`${t($muted ? "menu.unmute" : "menu.mute")} (M)`} disabled={!$mediaLoaded} onclick={() => runContextAction(toggleMute)}>
        {t($muted ? "menu.unmute" : "menu.mute")}
      </button>
      <button role="menuitem" title={`${t("menu.audioTrack")} (B)`} disabled={!$mediaLoaded} onclick={() => runContextAction(cycleAudioTrack)}>
        {t("menu.audioTrack")}
      </button>
      <button role="menuitem" title={`${t("menu.subtitleTrack")} (V)`} disabled={!$mediaLoaded} onclick={() => runContextAction(cycleSubtitleTrack)}>
        {t("menu.subtitleTrack")}
      </button>
      <div class="context-divider" role="separator"></div>
      <button role="menuitem" title={`${t("menu.snapshot")} (Shift+S)`} disabled={!$mediaLoaded} onclick={() => runContextAction(takeSnapshot)}>
        {t("menu.snapshot")}
      </button>
      <button role="menuitem" title={`${t("menu.playlist")} (Ctrl+L)`} onclick={() => runContextAction(togglePlaylist)}>
        {t("menu.playlist")}
      </button>
      <button role="menuitem" title={t("controls.miniPlayer")} disabled={!$mediaLoaded} onclick={() => runContextAction(() => void enterMiniPlayer())}>
        {t("controls.miniPlayer")}
      </button>
      <button role="menuitem" title={`${t($fullscreen ? "menu.leaveFullscreen" : "menu.fullscreen")} (F)`} onclick={() => runContextAction(() => toggleFullscreen())}>
        {t($fullscreen ? "menu.leaveFullscreen" : "menu.fullscreen")}
      </button>
    </div>
  {/if}

  {#if draggingFiles}
    <div class="drop-overlay" aria-hidden="true">
      <p>{t("drop.overlay")}</p>
    </div>
  {/if}
</div>

<style>
  .app {
    height: 100%;
    background: transparent;
  }

  :global(.mini-player .top-bar),
  :global(.mini-player .playlist-panel) {
    display: none !important;
  }

  .mini-exit {
    position: fixed;
    top: 5px;
    right: 5px;
    z-index: 45;
    display: grid;
    width: 22px;
    height: 22px;
    padding: 3px;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: rgba(12, 12, 15, 0.82);
    color: var(--text);
    cursor: pointer;
  }

  .mini-exit svg {
    width: 14px;
    height: 14px;
    fill: currentColor;
  }

  .mini-exit:hover { color: var(--accent); }

  .mini-drag-region {
    position: fixed;
    top: 5px;
    left: 50%;
    z-index: 44;
    display: grid;
    width: 72px;
    height: 18px;
    place-items: center;
    transform: translateX(-50%);
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 999px;
    background: rgba(12, 12, 15, 0.62);
    cursor: move;
  }

  .mini-drag-region span {
    width: 26px;
    height: 3px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.72);
  }

  .player-context-menu {
    position: fixed;
    z-index: 80;
    display: flex;
    flex-direction: column;
    width: 224px;
    max-height: calc(100vh - 16px);
    overflow-y: auto;
    padding: 5px;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background: rgba(18, 18, 22, 0.97);
    color: var(--text);
    box-shadow: 0 12px 32px rgba(0, 0, 0, 0.55);
    backdrop-filter: blur(16px);
  }

  .player-context-menu button {
    min-height: 30px;
    padding: 5px 9px;
    border: 0;
    border-radius: var(--radius-sm);
    background: transparent;
    color: inherit;
    font: inherit;
    text-align: left;
    cursor: pointer;
  }

  .player-context-menu button:hover:enabled,
  .player-context-menu button:focus-visible {
    outline: none;
    background: rgba(255, 255, 255, 0.09);
    color: var(--accent);
  }

  .player-context-menu button:disabled {
    opacity: 0.42;
    cursor: default;
  }

  .context-divider {
    height: 1px;
    margin: 4px 5px;
    background: var(--border);
  }

  .stage {
    height: 100%;
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  /* Idle watermark: bat mark + hint, fading back in whenever there is no file */
  .idle-mark {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 20px;
    opacity: 0;
    transform: translateY(8px);
    transition:
      opacity var(--transition-medium),
      transform var(--transition-medium);
  }

  .idle-mark.visible {
    opacity: 1;
    transform: none;
  }

  /* The artwork itself stays a faint watermark; the hint next to it carries
     the actual contrast (dimming the whole mark buried it below 3:1). */
  .idle-logo {
    opacity: 0.5;
  }

  .idle-hint {
    margin: 0;
    font-size: 14px;
    letter-spacing: 0.02em;
    color: var(--text-dim);
  }

  .notice {
    position: fixed;
    bottom: 82px;
    left: 50%;
    transform: translateX(-50%);
    max-width: min(560px, 80vw);
    padding: 10px 16px;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background: var(--bg-elevated);
    color: var(--text);
    font-size: 13px;
    white-space: normal;
    overflow-wrap: anywhere;
    z-index: 40;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    animation: notice-in 180ms ease both;
  }

  .notice.error {
    border-color: rgba(255, 92, 92, 0.55);
    color: var(--danger);
  }

  .drop-overlay {
    position: fixed;
    inset: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 2px dashed var(--accent);
    border-radius: var(--radius-md);
    background: rgba(10, 10, 12, 0.72);
    color: var(--accent);
    font-size: 20px;
    letter-spacing: 0.04em;
    z-index: 60;
    pointer-events: none;
  }

  @keyframes notice-in {
    from {
      opacity: 0;
      transform: translate(-50%, 6px);
    }
    to {
      opacity: 1;
      transform: translate(-50%, 0);
    }
  }

  /* Reduced motion: state changes stay, travel goes. */
  @media (prefers-reduced-motion: reduce) {
    .idle-mark {
      transform: none;
      transition: opacity var(--transition-fast);
    }

    .notice {
      animation: none;
    }
  }
</style>
