<script lang="ts">
  import { t } from "../i18n";
  import { currentTime, duration, mediaLoaded } from "../stores/player";
  import { formatTime } from "../utils/time";

  const timeLabel = $derived(`${formatTime($currentTime)} / ${formatTime($duration)}`);
</script>

<footer class="control-bar">
  <input
    class="seek-bar"
    type="range"
    min="0"
    max="100"
    step="0.1"
    value="0"
    aria-label={t("controls.seekBar")}
    disabled={!$mediaLoaded}
  />

  <div class="button-row">
    <div class="group">
      <button
        class="icon-btn"
        type="button"
        disabled
        title={t("controls.previous")}
        aria-label={t("controls.previous")}
      >
        <svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zM18 6v12l-8.5-6z" /></svg>
      </button>
      <button
        class="icon-btn play-btn"
        type="button"
        disabled
        title={t("controls.play")}
        aria-label={t("controls.play")}
      >
        <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
      </button>
      <button
        class="icon-btn"
        type="button"
        disabled
        title={t("controls.next")}
        aria-label={t("controls.next")}
      >
        <svg viewBox="0 0 24 24"><path d="M16 6h2v12h-2zM6 6v12l8.5-6z" /></svg>
      </button>
      <span class="time-label">{timeLabel}</span>
    </div>

    <div class="group">
      <button
        class="icon-btn"
        type="button"
        disabled
        title={t("controls.mute")}
        aria-label={t("controls.mute")}
      >
        <svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3zM16.5 12a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4z" /></svg>
      </button>
      <input
        class="volume-bar"
        type="range"
        min="0"
        max="100"
        value="100"
        aria-label={t("controls.volume")}
        disabled
      />
      <button
        class="icon-btn"
        type="button"
        disabled
        title={t("controls.playlist")}
        aria-label={t("controls.playlist")}
      >
        <svg viewBox="0 0 24 24"><path d="M3 6h13v2H3zM3 10h13v2H3zM3 14h9v2H3zM19 9v6.2a3 3 0 1 0 2 2.8V9h-2z" /></svg>
      </button>
      <button
        class="icon-btn"
        type="button"
        disabled
        title={t("controls.fullscreen")}
        aria-label={t("controls.fullscreen")}
      >
        <svg viewBox="0 0 24 24"><path d="M4 4h6v2H6v4H4V4zm10 0h6v6h-2V6h-4V4zM4 14h2v4h4v2H4v-6zm14 0h2v6h-6v-2h4v-4z" /></svg>
      </button>
    </div>
  </div>
</footer>

<style>
  .control-bar {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 10px 16px 12px;
    background: linear-gradient(to top, rgba(5, 5, 7, 0.97), rgba(10, 10, 13, 0.88));
    border-top: 1px solid var(--border);
    backdrop-filter: blur(16px);
    z-index: 10;
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
    gap: 4px;
  }

  .icon-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
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
    width: 20px;
    height: 20px;
    fill: currentColor;
  }

  .icon-btn:hover:enabled {
    background: rgba(255, 255, 255, 0.07);
    color: var(--text);
  }

  .icon-btn:disabled {
    opacity: 0.35;
    cursor: default;
  }

  .play-btn {
    width: 42px;
    height: 42px;
    color: var(--accent);
  }

  .play-btn svg {
    width: 24px;
    height: 24px;
  }

  .time-label {
    margin-left: 10px;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    color: var(--text-dim);
    white-space: nowrap;
  }

  input[type="range"] {
    -webkit-appearance: none;
    appearance: none;
    height: 4px;
    border-radius: 2px;
    background: rgba(255, 255, 255, 0.14);
    outline: none;
  }

  input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 13px;
    height: 13px;
    border-radius: 50%;
    background: var(--accent);
    box-shadow: 0 0 0 4px rgba(255, 212, 0, 0.14);
    transition: box-shadow var(--transition-fast);
  }

  input[type="range"]:hover:enabled::-webkit-slider-thumb {
    box-shadow: 0 0 0 6px rgba(255, 212, 0, 0.2);
  }

  input[type="range"]:disabled::-webkit-slider-thumb {
    background: var(--text-faint);
    box-shadow: none;
  }

  .seek-bar {
    width: 100%;
  }

  .volume-bar {
    width: 90px;
    margin: 0 4px;
  }
</style>
