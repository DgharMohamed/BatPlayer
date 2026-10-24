<script lang="ts">
  import { onMount } from "svelte";
  import { expoOut } from "svelte/easing";
  import { fly } from "svelte/transition";

  import { t } from "../i18n";
  import {
    clearPlaylist,
    loopMode,
    playAt,
    playlistIndex,
    playlistDockWidth,
    playlistItems,
    playlistOpen,
    removeAt,
    shuffleEnabled,
  } from "../stores/playlist";
  import { cycleLoop, toggleShuffle } from "../utils/actions";

  /** Feedback still arrives, just without travel, when motion is reduced. */
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  let resizing = $state(false);
  let controlBarHeight = $state(72);
  let dragStartX = 0;
  let dragStartWidth = 320;

  function clampDockWidth(width: number): number {
    const maxWidth = Math.min(560, Math.max(240, window.innerWidth - 320));
    return Math.max(240, Math.min(maxWidth, Math.round(width)));
  }

  function onResizeStart(event: PointerEvent): void {
    event.preventDefault();
    resizing = true;
    dragStartX = event.clientX;
    dragStartWidth = $playlistDockWidth;
    (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
  }

  function onResizeMove(event: PointerEvent): void {
    if (!resizing) return;
    playlistDockWidth.set(clampDockWidth(dragStartWidth + dragStartX - event.clientX));
  }

  function onResizeEnd(event: PointerEvent): void {
    resizing = false;
    const target = event.currentTarget as HTMLElement;
    if (target.hasPointerCapture(event.pointerId)) {
      target.releasePointerCapture(event.pointerId);
    }
  }

  function onResizeKeydown(event: KeyboardEvent): void {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    const direction = event.key === "ArrowLeft" ? 1 : -1;
    playlistDockWidth.update((width) => clampDockWidth(width + direction * 16));
  }

  onMount(() => {
    const keepWidthInBounds = (): void => {
      playlistDockWidth.update((width) => clampDockWidth(width));
    };
    const controlBar = document.querySelector<HTMLElement>(".control-bar");
    const measureControlBar = (): void => {
      if (controlBar) controlBarHeight = controlBar.getBoundingClientRect().height;
    };
    const observer = controlBar ? new ResizeObserver(measureControlBar) : null;
    observer?.observe(controlBar!);
    measureControlBar();
    window.addEventListener("resize", keepWidthInBounds);
    return () => {
      window.removeEventListener("resize", keepWidthInBounds);
      observer?.disconnect();
    };
  });
</script>

<!--
  Right-hand drawer over the video surface (chrome stays pinned while it is
  open via stores/chrome). Clicking a row plays it; the playing row carries
  the accent mark.
-->
{#if $playlistOpen}
  <aside
    class="playlist-panel"
    class:resizing
    style:width="{$playlistDockWidth}px"
    style:bottom="{controlBarHeight}px"
    transition:fly={{
      x: reducedMotion.matches ? 0 : 300,
      duration: reducedMotion.matches ? 140 : 200,
      easing: expoOut,
    }}
  >
    <div
      class="resize-grip"
      role="separator"
      tabindex="0"
      aria-label={t("playlist.resize")}
      aria-orientation="vertical"
      aria-valuemin="240"
      aria-valuemax={Math.min(560, Math.max(240, window.innerWidth - 320))}
      aria-valuenow={$playlistDockWidth}
      onpointerdown={onResizeStart}
      onpointermove={onResizeMove}
      onpointerup={onResizeEnd}
      onpointercancel={onResizeEnd}
      onkeydown={onResizeKeydown}
    ></div>
    <header class="head">
      <h2>{t("playlist.title")}</h2>
      <div class="head-actions">
        <button
          class="chip"
          class:armed={$loopMode !== "off"}
          type="button"
          title={`${t($loopMode === "one" ? "menu.repeatCurrent" : "menu.loopPlaylist")} (L)`}
          onclick={() => void cycleLoop()}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true">
            {#if $loopMode === "one"}
              <path d="M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4zM13 9H9v1.5h2.5V15H12V9h1z" />
            {:else}
              <path d="M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z" />
            {/if}
          </svg>
          {t($loopMode === "one" ? "menu.repeatCurrent" : "menu.loopPlaylist")}
        </button>
        <button
          class="chip shuffle-chip"
          class:armed={$shuffleEnabled}
          type="button"
          title={`${t("playlist.shuffle")} (R)`}
          onclick={() => void toggleShuffle()}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M18 14l4 4-4 4M18 2l4 4-4 4M2 18h1.5a3 3 0 0 0 2.4-1.2l9.2-12.6A3 3 0 0 1 17.5 3H22M2 6h1.5a3 3 0 0 1 2.4 1.2l9.2 12.6a3 3 0 0 0 2.4 1.2H22" />
          </svg>
          {t("playlist.shuffle")}
        </button>
        {#if $playlistItems.length > 0}
          <button
            class="chip"
            type="button"
            title={t("playlist.clear")}
            onclick={clearPlaylist}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M6 19a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z" />
            </svg>
            {t("playlist.clear")}
          </button>
        {/if}
      </div>
    </header>

    {#if $playlistItems.length === 0}
      <p class="empty">{t("playlist.empty")}</p>
    {:else}
      <ol class="queue" role="listbox" aria-label={t("playlist.title")}>
        {#each $playlistItems as item, index (item.path)}
          <li>
            <button
              class="row"
              class:current={index === $playlistIndex}
              type="button"
              role="option"
              aria-selected={index === $playlistIndex}
              title={item.path}
              onclick={() => void playAt(index)}
            >
              <span class="order">{index === $playlistIndex ? "▶" : index + 1}</span>
              <span class="name">{item.name}</span>
            </button>
            <button
              class="remove"
              type="button"
              title={t("playlist.remove")}
              aria-label={`${t("playlist.remove")}: ${item.name}`}
              onclick={() => removeAt(index)}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 6.4 17.6 5 12 10.6 6.4 5 5 6.4 10.6 12 5 17.6 6.4 19 12 13.4 17.6 19 19 17.6 13.4 12z" /></svg>
            </button>
          </li>
        {/each}
      </ol>
    {/if}
  </aside>
{/if}

<style>
  .playlist-panel {
    position: fixed;
    top: 40px;
    right: 0;
    bottom: 72px;
    width: 320px;
    display: flex;
    flex-direction: column;
    border-left: 1px solid var(--border);
    background: #0b0c10;
    /* The playback bar sits above the dock and remains fully interactive. */
    z-index: 19;
    overflow: hidden;
  }

  .resize-grip {
    position: absolute;
    z-index: 2;
    top: 0;
    bottom: 0;
    left: 0;
    width: 10px;
    cursor: col-resize;
    touch-action: none;
  }

  .resize-grip::after {
    position: absolute;
    top: 0;
    bottom: 0;
    left: 3px;
    width: 2px;
    background: transparent;
    content: "";
    transition: background var(--transition-fast);
  }

  .resize-grip:hover::after,
  .resizing .resize-grip::after,
  .resize-grip:focus-visible::after {
    background: var(--accent);
  }

  .resize-grip:focus-visible { outline: none; }

  .head {
    padding: 14px 14px 12px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    border-bottom: 1px solid var(--border);
  }

  .head h2 {
    margin: 0;
    font-size: 14px;
    font-weight: 650;
    letter-spacing: 0.02em;
    color: var(--text);
  }

  .head-actions {
    display: flex;
    align-items: center;
    gap: 7px;
    flex-wrap: wrap;
  }

  .chip {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    min-height: 30px;
    padding: 5px 9px;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: #111319;
    color: var(--text-dim);
    font-size: 12px;
    cursor: pointer;
    transition:
      color var(--transition-fast),
      border-color var(--transition-fast);
  }

  .chip svg {
    width: 13px;
    height: 13px;
    fill: currentColor;
  }

  .chip.shuffle-chip svg {
    fill: none;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  .chip:hover {
    color: var(--text);
  }

  .chip.armed {
    color: var(--accent);
    border-color: rgba(255, 212, 0, 0.5);
  }

  .chip:focus-visible {
    outline: 1px solid var(--accent);
    outline-offset: 1px;
  }

  .empty {
    padding: 20px 14px;
    margin: 0;
    font-size: 13px;
    color: var(--text-dim);
  }

  .queue {
    flex: 1;
    margin: 0;
    padding: 9px 8px;
    list-style: none;
    overflow-y: auto;
  }

  .queue li {
    display: flex;
    align-items: stretch;
    gap: 4px;
    margin-bottom: 3px;
  }

  .row {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 38px;
    padding: 8px 10px;
    border: 1px solid transparent;
    border-radius: var(--radius-sm);
    background: #101116;
    color: var(--text);
    font-size: 13px;
    text-align: left;
    cursor: pointer;
  }

  .row:hover {
    background: #181a21;
    border-color: var(--border);
  }

  .row:focus-visible {
    outline: 1px solid var(--accent);
    outline-offset: 1px;
  }

  .row .order {
    flex: none;
    min-width: 22px;
    text-align: center;
    color: var(--text-dim);
    font-size: 12px;
    font-variant-numeric: tabular-nums;
  }

  .row.current {
    color: var(--accent);
    border-color: rgba(255, 212, 0, 0.24);
    background: rgba(255, 212, 0, 0.08);
  }

  .row.current .order {
    color: var(--accent);
  }

  .row .name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .remove {
    flex: none;
    align-self: center;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 30px;
    height: 30px;
    padding: 0;
    border: none;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--text-faint);
    cursor: pointer;
    opacity: 0;
    transition:
      opacity var(--transition-fast),
      color var(--transition-fast),
      background var(--transition-fast);
  }

  .queue li:hover .remove,
  .remove:focus-visible {
    opacity: 1;
  }

  .remove:hover {
    color: var(--danger);
    background: rgba(255, 92, 92, 0.12);
  }

  .remove svg {
    width: 12px;
    height: 12px;
    fill: currentColor;
  }

  /* Reduced motion: the drawer still appears and vanishes, just in place. */
  @media (prefers-reduced-motion: reduce) {
    .playlist-panel {
      animation: none;
    }
  }
</style>
