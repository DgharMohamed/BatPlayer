<script lang="ts">
  import { t } from "../i18n";
  import {
    cycleAudioTrack,
    cycleSubtitleTrack,
    nextTrack,
    prevTrack,
    report,
    seekAbsolute,
    stopPlayback,
    takeSnapshot,
    toggleMute,
    togglePlayPause,
  } from "../utils/actions";
  import { setVolume } from "../api/player";
  import { chromeHidden, pinChrome } from "../stores/chrome";
  import {
    currentTime,
    duration,
    eofReached,
    idle,
    mediaLoaded,
    muted,
    paused,
    volume,
  } from "../stores/player";
  import { loopMode, playlistIndex, playlistItems } from "../stores/playlist";
  import { fullscreen, toggleFullscreen } from "../stores/window";
  import { formatTime } from "../utils/time";

  /** Live (uncommitted) seek position while the range element is dragged. */
  let dragValue = $state<number | null>(null);
  /** Pointer position over the seek bar (0..1), or null when the pointer is away. */
  let hoverRatio = $state<number | null>(null);

  let workable = $derived($mediaLoaded && !$idle);
  /** Next enabled unless the un-looped queue's end is reached. */
  let canNext = $derived(
    $playlistItems.length > 0 &&
      ($playlistIndex < $playlistItems.length - 1 || $loopMode === "all" || $playlistIndex < 0),
  );
  const timeLabel = $derived(
    `${formatTime(dragValue ?? $currentTime)} / ${formatTime($duration)}`,
  );
  const seekStep = $derived(
    $duration > 0 ? Math.min(1, Math.max(0.05, $duration / 600)) : 0.1,
  );
  /** Played share of the bar, painted as the accent fill. */
  const playedPercent = $derived(
    $duration > 0
      ? Math.min(100, Math.max(0, ((dragValue ?? $currentTime) / $duration) * 100))
      : 0,
  );
  /** Volume share of the bar's 130% mpv ceiling. */
  const volumePercent = $derived(Math.min(100, Math.max(0, ($volume / 130) * 100)));
  /** Hover tooltip position, kept just inside the bar edges. */
  const tipPercent = $derived(
    hoverRatio === null ? 0 : Math.min(99, Math.max(1, hoverRatio * 100)),
  );

  function onSeekInput(event: Event): void {
    dragValue = Number((event.target as HTMLInputElement).value);
  }

  function onSeekCommit(event: Event): void {
    const value = Number((event.target as HTMLInputElement).value);
    dragValue = null;
    if (Number.isFinite(value)) {
      void seekAbsolute(value);
    }
  }

  /** Tracks the pointer across the seek bar so the time tooltip can follow it. */
  function onSeekHover(event: PointerEvent): void {
    if (!workable) return;
    const rect = (event.currentTarget as HTMLInputElement).getBoundingClientRect();
    if (rect.width <= 0) return;
    hoverRatio = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width));
  }

  function onSeekLeave(): void {
    hoverRatio = null;
  }

  function onVolumeInput(event: Event): void {
    const value = Math.round(Number((event.target as HTMLInputElement).value));
    void report(() => setVolume(value));
  }
</script>

<!--
  Both bars pin their visibility while the pointer is over them, so a
  stationary cursor never lets the controls slide away mid-interaction.
-->
<footer
  class="control-bar"
  class:hidden={$chromeHidden}
  onpointerenter={() => pinChrome(true)}
  onpointerleave={() => pinChrome(false)}
>
  <div class="seek">
    <input
      class="seek-bar"
      type="range"
      min="0"
      max={$duration}
      step={seekStep}
      value={dragValue ?? $currentTime}
      style="--progress: {playedPercent}%"
      aria-label={t("controls.seekBar")}
      aria-valuetext={timeLabel}
      disabled={!workable}
      onpointermove={onSeekHover}
      onpointerleave={onSeekLeave}
      oninput={onSeekInput}
      onchange={onSeekCommit}
    />
    {#if hoverRatio !== null && $duration > 0 && workable}
      <div class="seek-tip" style="left: {tipPercent}%">
        {formatTime(hoverRatio * $duration)}
      </div>
    {/if}
  </div>

  <div class="button-row">
    <div class="group">
      <button
        class="icon-btn"
        type="button"
        disabled={$playlistItems.length === 0}
        title={t("controls.previous")}
        aria-label={t("controls.previous")}
        onclick={() => void prevTrack()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          {#if $playlistIndex > 0}
            <path d="M6 6h2v12H6zm3.5 6 5.5 4V8z" />
          {:else}
            <path d="M6 6h2v12H6zM20 6l-8.5 6 8.5 6z" />
          {/if}
        </svg>
      </button>

      <button
        class="icon-btn play-btn"
        type="button"
        disabled={!workable}
        title={t(
          $eofReached ? "controls.replay" : $paused ? "controls.play" : "controls.pause",
        )}
        aria-label={t(
          $eofReached ? "controls.replay" : $paused ? "controls.play" : "controls.pause",
        )}
        onclick={() => void togglePlayPause()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          {#if $eofReached}
            <path
              d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"
            />
          {:else if $paused}
            <path d="M8 5v14l11-7z" />
          {:else}
            <path d="M6 5h4v14H6zM14 5h4v14h-4z" />
          {/if}
        </svg>
      </button>

      <button
        class="icon-btn"
        type="button"
        disabled={!canNext}
        title={t("controls.next")}
        aria-label={t("controls.next")}
        onclick={() => void nextTrack()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          {#if canNext && $playlistIndex < $playlistItems.length - 1}
            <path d="M16 6h2v12h-2zM6 18l8.5-6L6 6z" />
          {:else}
            <path d="M16 6h2v12h-2zM6 6l8.5 6L6 18z" />
          {/if}
        </svg>
      </button>

      <button
        class="icon-btn"
        type="button"
        disabled={!workable}
        title={t("controls.stop")}
        aria-label={t("controls.stop")}
        onclick={() => void stopPlayback()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7h10v10H7z" /></svg>
      </button>

      <span class="time-label">{timeLabel}</span>
    </div>

    <div class="group">
      <button
        class="icon-btn"
        type="button"
        disabled={!workable}
        title={t($muted ? "controls.unmute" : "controls.mute")}
        aria-label={t($muted ? "controls.unmute" : "controls.mute")}
        onclick={() => void toggleMute()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          {#if $muted}
            <path
              d="M16.5 12a4.5 4.5 0 0 0-2.5-4v2.2l2.5 2.5V12zM19 12a7.5 7.5 0 0 1-.54 2.64l1.51 1.51A9.8 9.8 0 0 0 21 12a9.78 9.78 0 0 0-7-8.77v2.06A7.86 7.86 0 0 1 19 12zM4.27 3 3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25A7.5 7.5 0 0 1 12 19.5a7.57 7.57 0 0 1-.76-.05v2.03A9.8 9.8 0 0 0 12 21.5 9.78 9.78 0 0 0 19.73 21 21 21 0 0 1 4.27 3zM12 4 9.91 6.09 12 8.18V4z"
            />
          {:else}
            <path d="M3 9v6h4l5 5V4L7 9H3zM16.5 12a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4z" />
          {/if}
        </svg>
      </button>

      <input
        class="volume-bar"
        type="range"
        min="0"
        max="130"
        step="1"
        value={$volume}
        style="--progress: {volumePercent}%"
        aria-label={t("controls.volume")}
        aria-valuetext={`${$volume}%`}
        disabled={!workable}
        oninput={onVolumeInput}
      />

      <button
        class="icon-btn"
        type="button"
        disabled={!workable}
        title={t("controls.audioTrack")}
        aria-label={t("controls.audioTrack")}
        onclick={() => void cycleAudioTrack()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v10.55A4 4 0 1 0 14 17V7h4V3h-6z" /></svg>
      </button>

      <button
        class="icon-btn"
        type="button"
        disabled={!workable}
        title={t("controls.subtitleTrack")}
        aria-label={t("controls.subtitleTrack")}
        onclick={() => void cycleSubtitleTrack()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path
            d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zM4 12h4v2H4v-2zm10 6H4v-2h10v2zm6 0h-4v-2h4v2zm0-4H10v-2h10v2z"
          />
        </svg>
      </button>

      <button
        class="icon-btn"
        type="button"
        disabled={!workable}
        title={t("controls.snapshot")}
        aria-label={t("controls.snapshot")}
        onclick={() => void takeSnapshot()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path
            d="M9 2 7.17 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2h-3.17L15 2H9zm3 15c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5z"
          />
        </svg>
      </button>

      <button
        class="icon-btn"
        type="button"
        title={t($fullscreen ? "controls.leaveFullscreen" : "controls.fullscreen")}
        aria-label={t($fullscreen ? "controls.leaveFullscreen" : "controls.fullscreen")}
        onclick={() => void toggleFullscreen()}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          {#if $fullscreen}
            <path d="M9 9h6v6H9z" />
          {:else}
            <path d="M4 4h6v2H6v4H4V4zm10 0h6v6h-2V6h-4V4zM4 14h2v4h4v2H4v-6zm14 0h2v6h-6v-2h4v-4z" />
          {/if}
        </svg>
      </button>
    </div>
  </div>
</footer>

<style>
  .control-bar {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 6px 14px 6px;
    z-index: 20;
    background: linear-gradient(to top, rgba(5, 5, 7, 0.97), rgba(10, 10, 13, 0.86));
    border-top: 1px solid var(--border);
    backdrop-filter: blur(16px);
    transition:
      transform var(--transition-medium),
      opacity var(--transition-medium);
  }

  .control-bar.hidden {
    transform: translateY(100%);
    opacity: 0;
    pointer-events: none;
  }

  .button-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .group {
    display: flex;
    align-items: center;
    gap: 2px;
  }

  .icon-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 30px;
    height: 30px;
    padding: 0;
    border: none;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--text-dim);
    cursor: pointer;
    transition:
      background var(--transition-fast),
      color var(--transition-fast);
  }

  .icon-btn svg {
    width: 18px;
    height: 18px;
    fill: currentColor;
  }

  .icon-btn:hover:enabled {
    background: rgba(255, 255, 255, 0.07);
    color: var(--text);
  }

  .icon-btn:focus-visible {
    outline: 1px solid var(--accent);
    outline-offset: 1px;
  }

  .icon-btn:disabled {
    opacity: 0.35;
    cursor: default;
  }

  .play-btn {
    width: 36px;
    height: 36px;
    color: var(--accent);
  }

  .play-btn svg {
    width: 22px;
    height: 22px;
  }

  .time-label {
    margin-left: 8px;
    font-size: 12px;
    font-variant-numeric: tabular-nums;
    color: var(--text-dim);
    white-space: nowrap;
  }

  /*
   * Sliders keep a thin 4px ink but a 24px hit area, paint the played share
   * in the accent, and expand slightly while hovered. `--progress` is set
   * inline per render.
   */
  input[type="range"] {
    -webkit-appearance: none;
    appearance: none;
    height: 20px;
    background-color: transparent;
    background-image: linear-gradient(
      to right,
      var(--accent) var(--progress, 0%),
      rgba(255, 255, 255, 0.24) var(--progress, 0%)
    );
    background-size: 100% 4px;
    background-position: center;
    background-repeat: no-repeat;
    outline: none;
    cursor: pointer;
    transition: background-size var(--transition-fast);
  }

  /* Neutralize the engine's default track paint; the stripe above is the ink. */
  input[type="range"]::-webkit-slider-runnable-track {
    background: transparent;
  }

  input[type="range"]:hover:enabled {
    background-size: 100% 6px;
  }

  input[type="range"]:disabled {
    background-image: linear-gradient(
      rgba(255, 255, 255, 0.1),
      rgba(255, 255, 255, 0.1)
    );
    cursor: default;
  }

  input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 13px;
    height: 13px;
    border-radius: 50%;
    background: var(--accent);
    box-shadow:
      0 1px 3px rgba(0, 0, 0, 0.5),
      0 0 0 4px rgba(255, 212, 0, 0.14);
    transition: box-shadow var(--transition-fast);
  }

  input[type="range"]:hover:enabled::-webkit-slider-thumb {
    box-shadow:
      0 1px 3px rgba(0, 0, 0, 0.5),
      0 0 0 6px rgba(255, 212, 0, 0.22);
  }

  input[type="range"]:focus-visible::-webkit-slider-thumb {
    box-shadow:
      0 1px 3px rgba(0, 0, 0, 0.5),
      0 0 0 6px rgba(255, 212, 0, 0.4);
  }

  input[type="range"]:disabled::-webkit-slider-thumb {
    background: var(--text-faint);
    box-shadow: none;
  }

  .seek {
    position: relative;
  }

  .seek-bar {
    display: block;
    width: 100%;
  }

  /* Floating time preview that follows the pointer over the seek bar. */
  .seek-tip {
    position: absolute;
    bottom: calc(100% + 6px);
    transform: translateX(-50%);
    padding: 3px 8px;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--bg-elevated);
    color: var(--text);
    font-size: 12px;
    font-variant-numeric: tabular-nums;
    pointer-events: none;
    white-space: nowrap;
  }

  .volume-bar {
    width: 76px;
    margin: 0 4px;
  }

  /* Reduced motion: the bar still appears and vanishes, just without travel. */
  @media (prefers-reduced-motion: reduce) {
    .control-bar {
      transition: opacity var(--transition-fast);
    }

    .control-bar.hidden {
      transform: none;
    }
  }
</style>
