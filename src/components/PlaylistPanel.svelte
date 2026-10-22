<script lang="ts">
  import { expoOut } from "svelte/easing";
  import { fly } from "svelte/transition";

  import { t } from "../i18n";
  import {
    clearPlaylist,
    loopMode,
    playAt,
    playlistIndex,
    playlistItems,
    playlistOpen,
    removeAt,
    shuffleEnabled,
  } from "../stores/playlist";
  import { cycleLoop, toggleShuffle } from "../utils/actions";

  /** Feedback still arrives, just without travel, when motion is reduced. */
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
</script>

<!--
  Right-hand drawer over the video surface (chrome stays pinned while it is
  open via stores/chrome). Clicking a row plays it; the playing row carries
  the accent mark.
-->
{#if $playlistOpen}
  <aside
    class="playlist-panel"
    transition:fly={{
      x: reducedMotion.matches ? 0 : 300,
      duration: reducedMotion.matches ? 140 : 200,
      easing: expoOut,
    }}
  >
    <header class="head">
      <h2>{t("playlist.title")}</h2>
      <div class="head-actions">
        <button
          class="chip"
          class:armed={$loopMode !== "off"}
          type="button"
          title={t($loopMode === "one" ? "menu.repeatCurrent" : "menu.loopPlaylist")}
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
          class="chip"
          class:armed={$shuffleEnabled}
          type="button"
          title={t("playlist.shuffle")}
          onclick={() => void toggleShuffle()}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M17 3l4 4-4 4V8h-2.3l-2.2 2.6-1.5-1.7L13.5 6H17V3zm-9.5 0h2.3L21 17h.001V21H14L6 11H3V8h3.2L9 11.6 11 9.3z" />
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
    bottom: 96px;
    width: 300px;
    display: flex;
    flex-direction: column;
    border: 1px solid var(--border);
    border-radius: var(--radius-md) 0 0 var(--radius-md);
    background: linear-gradient(to top, rgba(6, 6, 8, 0.97), rgba(10, 10, 13, 0.92));
    backdrop-filter: blur(16px);
    z-index: 22;
    overflow: hidden;
  }

  .head {
    padding: 10px 12px 8px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    border-bottom: 1px solid var(--border);
  }

  .head h2 {
    margin: 0;
    font-size: 13px;
    letter-spacing: 0.04em;
    color: var(--text);
  }

  .head-actions {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-wrap: wrap;
  }

  .chip {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 4px 8px;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: transparent;
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
    padding: 6px;
    list-style: none;
    overflow-y: auto;
  }

  .queue li {
    display: flex;
    align-items: stretch;
    gap: 2px;
  }

  .row {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 7px 8px;
    border: none;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--text);
    font-size: 13px;
    text-align: left;
    cursor: pointer;
  }

  .row:hover {
    background: rgba(255, 255, 255, 0.07);
  }

  .row:focus-visible {
    outline: 1px solid var(--accent);
    outline-offset: 1px;
  }

  .row .order {
    flex: none;
    min-width: 16px;
    color: var(--text-dim);
    font-size: 12px;
    font-variant-numeric: tabular-nums;
  }

  .row.current {
    color: var(--accent);
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
    width: 24px;
    height: 24px;
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
