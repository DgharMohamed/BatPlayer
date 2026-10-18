<script lang="ts">
  import { expoOut } from "svelte/easing";
  import { fly } from "svelte/transition";

  import { t } from "../i18n";
  import { osd } from "../stores/osd";
  import { formatSpeed, formatTime } from "../utils/time";

  /** Feedback still arrives, just without travel, when motion is reduced. */
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  function formatDelta(seconds: number): string {
    return seconds > 0 ? `+${seconds}s` : `${seconds}s`;
  }

  function trackLabel(prefix: string, current: number, total: number): string {
    return current > 0 && total > 0
      ? `${prefix} ${current}/${total}`
      : `${prefix} ${t("osd.off")}`;
  }
</script>

{#if $osd !== null}
  <!-- Visual echo of actions whose controls already expose the same state. -->
  <div
    class="osd"
    aria-hidden="true"
    transition:fly={{
      x: reducedMotion.matches ? 0 : -10,
      duration: reducedMotion.matches ? 140 : 180,
      easing: expoOut,
    }}
  >
    {#if $osd.kind === "volume"}
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M3 9v6h4l5 5V4L7 9H3zM16.5 12a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4z" />
      </svg>
      <span>{t("osd.volume")} {$osd.value}%</span>
    {:else if $osd.kind === "muted"}
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path
          d="M16.5 12a4.5 4.5 0 0 0-2.5-4v2.2l2.5 2.5V12zM19 12a7.5 7.5 0 0 1-.54 2.64l1.51 1.51A9.8 9.8 0 0 0 21 12a9.78 9.78 0 0 0-7-8.77v2.06A7.86 7.86 0 0 1 19 12zM4.27 3 3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25A7.5 7.5 0 0 1 12 19.5a7.57 7.57 0 0 1-.76-.05v2.03A9.8 9.8 0 0 0 12 21.5 9.78 9.78 0 0 0 19.73 21 21 21 0 0 1 4.27 3zM12 4 9.91 6.09 12 8.18V4z"
        />
      </svg>
      <span>{t("osd.muted")}</span>
    {:else if $osd.kind === "speed"}
      <span class="value">{formatSpeed($osd.speed)}</span>
    {:else if $osd.kind === "seek"}
      <span>{formatDelta($osd.delta)} → {formatTime($osd.target)}</span>
    {:else if $osd.kind === "audio"}
      <span>{trackLabel(t("osd.audio"), $osd.current, $osd.total)}</span>
    {:else}
      <span>{trackLabel(t("osd.subtitle"), $osd.current, $osd.total)}</span>
    {/if}
  </div>
{/if}

<style>
  .osd {
    position: fixed;
    top: 56px;
    left: 18px;
    z-index: 25;
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 9px 14px;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background: var(--bg-elevated);
    color: var(--text);
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    pointer-events: none;
  }

  .osd svg {
    width: 16px;
    height: 16px;
    flex: none;
    fill: var(--accent);
  }

  .osd .value {
    color: var(--accent);
    font-weight: 600;
  }
</style>
