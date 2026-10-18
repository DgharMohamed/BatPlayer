<script lang="ts">
  import { onMount } from "svelte";

  import { getCurrentWebview } from "@tauri-apps/api/webview";
  import ControlBar from "./components/ControlBar.svelte";
  import BatLogo from "./components/BatLogo.svelte";
  import Osd from "./components/Osd.svelte";
  import SpeedChip from "./components/SpeedChip.svelte";
  import TopBar from "./components/topbar/TopBar.svelte";
  import { t } from "./i18n";
  import { keepChromeVisible } from "./stores/chrome";
  import {
    bindPlayerEvents,
    idle,
    mediaLoaded,
    notice,
  } from "./stores/player";
  import { bindWindowState, exitFullscreen, toggleFullscreen } from "./stores/window";
  import {
    cycleAudioTrack,
    cycleSubtitleTrack,
    stepFrame,
    resetSpeed,
    seekRelative,
    stepSpeed,
    stepVolume,
    takeSnapshot,
    toggleMute,
    togglePlayPause,
  } from "./utils/actions";
  import { openMediaPath, pickAndOpenMedia } from "./utils/media";

  /** True while files are dragged over the window (drop preview). */
  let draggingFiles = $state(false);

  onMount(() => {
    const cleanups: Array<() => void> = [];

    void (async () => {
      cleanups.push(await bindPlayerEvents());
      cleanups.push(await bindWindowState());
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
              const [path] = event.payload.paths;
              if (path !== undefined) {
                void openMediaPath(path);
              }
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
      target instanceof HTMLSelectElement
    );
  }

  function onKeydown(event: KeyboardEvent): void {
    if (event.defaultPrevented || isTypingTarget(event.target)) {
      return;
    }

    if (event.ctrlKey || event.metaKey) {
      if (event.code === "KeyO" && !event.shiftKey && !event.altKey) {
        event.preventDefault();
        void pickAndOpenMedia();
      }
      return;
    }

    const playingNow = $mediaLoaded && !$idle;

    switch (event.key) {
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
        void exitFullscreen();
        return;
      case "m":
        void toggleMute();
        return;
      case "s":
        if (playingNow) {
          void takeSnapshot();
        }
        return;
      case "a":
        if (playingNow) {
          void cycleAudioTrack();
        }
        return;
      case "v":
        if (playingNow) {
          void cycleSubtitleTrack();
        }
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
      case "ArrowLeft":
        if (playingNow && !event.shiftKey) {
          event.preventDefault();
          void seekRelative(-5);
        } else if (playingNow) {
          event.preventDefault();
          void seekRelative(-10);
        }
        return;
      case "ArrowRight":
        if (playingNow && !event.shiftKey) {
          event.preventDefault();
          void seekRelative(5);
        } else if (playingNow) {
          event.preventDefault();
          void seekRelative(10);
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
</script>
<svelte:window onkeydown={onKeydown} onpointermove={keepChromeVisible} />

<!--
  The video fills the whole client area (native child window behind this
  transparent webview), so the bars are overlays and the stage itself must
  stay see-through.
-->
<div class="app">
  <TopBar />

  <main class="stage" aria-label={t("video.areaLabel")} ondblclick={onStageDblclick}>
    <div class="idle-mark" class:visible={$idle}>
      <BatLogo size={104} />
      <p class="idle-hint">{t("idle.hint")}</p>
    </div>

    {#if $notice !== null}
      <div
        class="notice"
        class:error={$notice.kind === "error"}
        role="status"
      >
        {$notice.text}
      </div>
    {/if}
  </main>

  <ControlBar />
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
    opacity: 0.5;
    transform: none;
  }

  .idle-hint {
    margin: 0;
    font-size: 14px;
    letter-spacing: 0.02em;
    color: var(--text-dim);
  }

  .notice {
    position: fixed;
    bottom: 94px;
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
</style>
