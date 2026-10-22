<script lang="ts">
  import { onMount } from "svelte";

  import { getCurrentWebview } from "@tauri-apps/api/webview";
  import ControlBar from "./components/ControlBar.svelte";
  import BatLogo from "./components/BatLogo.svelte";
  import LoadingOverlay from "./components/LoadingOverlay.svelte";
  import Osd from "./components/Osd.svelte";
  import PlaylistPanel from "./components/PlaylistPanel.svelte";
  import SpeedChip from "./components/SpeedChip.svelte";
  import TopBar from "./components/topbar/TopBar.svelte";
  import { t } from "./i18n";
  import { keepChromeVisible, pinChromeFocus } from "./stores/chrome";
  import { bindHistory } from "./stores/history";
  import {
    bindPlayerEvents,
    idle,
    loading,
    mediaLoaded,
    notice,
  } from "./stores/player";
  import { bindWindowState, exitFullscreen, toggleFullscreen } from "./stores/window";
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

  onMount(() => {
    const cleanups: Array<() => void> = [];

    void (async () => {
      cleanups.push(await bindPlayerEvents());
      cleanups.push(await bindWindowState());
      cleanups.push(await bindHistory());
      // Resume saves on a timer so a crash mid-file still resumes nearby.
      cleanups.push(startProgressSaver());
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
              const paths = event.payload.paths;
              void (async () => {
                // Files and folders alike expand Rust-side into a sorted
                // media queue; a plain file-only drop keeps this behavior.
                if (await playDroppedSources(paths)) {
                  return;
                }
                // Subtitle (or unknown) drops keep the attach/fail notices.
                const [first] = paths;
                if (first !== undefined) {
                  await openMediaPath(first);
                }
              })();
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

    // Arrows are handled before the letter switch: size depends on Shift
    // (extrashort ±3s) and Alt (short ±10s); plain is the BatPlayer ±5s.
    if (key === "ArrowLeft" || key === "ArrowRight") {
      if (!playingNow) {
        return;
      }
      event.preventDefault();
      const delta = key === "ArrowLeft" ? -1 : 1;
      const jump = event.shiftKey ? 3 : event.altKey ? 10 : 5;
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
        if (playingNow) {
          void takeSnapshot();
        }
        return;
      case "e":
        // BatPlayer alias: stop (VLC parity for the classic "end" mnemonic).
        void stopPlayback();
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
      case "+":
        // VLC's +/- jump the rate by 1 in either direction.
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
  onpointermove={keepChromeVisible}
  onfocusin={onFocusIn}
  onfocusout={onFocusOut}
/>

<!--
  The video fills the whole client area (native child window behind this
  transparent webview), so the bars are overlays and the stage itself must
  stay see-through.
-->
<div class="app">
  <TopBar />

  <main
    class="stage"
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

  .stage {
    height: 100%;
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
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
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
