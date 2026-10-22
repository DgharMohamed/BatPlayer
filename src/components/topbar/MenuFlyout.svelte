<script lang="ts">
  import type { MenuEntry } from "./menus";

  interface Props {
    entries: MenuEntry[];
    onpick: (entry: MenuEntry) => void;
    onkeydown?: (event: KeyboardEvent) => void;
  }

  let { entries, onpick, onkeydown }: Props = $props();
</script>

<div
  class="flyout"
  role="menu"
  tabindex="-1"
  onkeydown={(event) => onkeydown?.(event)}
>
  {#each entries as entry, index (index)}
    {#if entry.kind === "separator"}
      <div class="separator"></div>
    {:else}
      <button
        class="menu-item"
        type="button"
        role={entry.checked !== undefined ? "menuitemcheckbox" : "menuitem"}
        aria-checked={entry.checked === true}
        disabled={entry.disabled}
        onclick={() => onpick(entry)}
      >
        {#if entry.checked !== undefined}
          <span class="check" class:set={entry.checked} aria-hidden="true">✓</span>
        {/if}
        <span class="label">{entry.label}</span>
        {#if entry.hint}
          <span class="hint">{entry.hint}</span>
        {/if}
      </button>
    {/if}
  {/each}
</div>

<style>
  .flyout {
    position: absolute;
    top: 100%;
    left: 0;
    min-width: 232px;
    padding: 5px;
    display: flex;
    flex-direction: column;
    background: var(--bg-elevated);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    box-shadow: 0 14px 34px rgba(0, 0, 0, 0.5);
    z-index: 40;
  }

  .menu-item {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 26px;
    width: 100%;
    padding: 6px 10px;
    border: none;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--text);
    font-size: 13px;
    text-align: left;
    cursor: pointer;
    white-space: nowrap;
  }

  /* Check column keeps the labels aligned whether an entry is checked or not. */
  .check {
    width: 14px;
    flex: none;
    align-self: center;
    color: transparent;
    font-size: 12px;
  }

  .check.set {
    color: var(--accent);
  }

  .menu-item:hover:enabled {
    background: rgba(255, 255, 255, 0.08);
  }

  .menu-item:focus-visible {
    outline: 1px solid var(--accent);
    outline-offset: 1px;
  }

  .menu-item:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .hint {
    font-size: 12px;
    color: var(--text-dim);
    letter-spacing: 0.02em;
  }

  .separator {
    height: 1px;
    margin: 5px 6px;
    background: var(--border);
  }
</style>
