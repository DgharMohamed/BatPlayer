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
        title={entry.hint ? `${entry.label} (${entry.hint})` : entry.label}
        role={entry.checked !== undefined ? "menuitemcheckbox" : "menuitem"}
        aria-checked={entry.checked === true}
        disabled={entry.disabled}
        onclick={() => onpick(entry)}
      >
        <span class="check" class:set={entry.checked} aria-hidden="true">
          {entry.checked !== undefined ? "✓" : ""}
        </span>
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
    min-width: 252px;
    padding: 6px;
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
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 7px 9px;
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
    width: 16px;
    flex: none;
    color: transparent;
    font-size: 12px;
    text-align: center;
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
    flex: none;
    margin-left: auto;
    font-size: 12px;
    color: var(--text-dim);
    letter-spacing: 0.02em;
    text-align: right;
  }

  .label {
    flex: 1;
    min-width: 0;
    text-align: left;
  }

  .separator {
    height: 1px;
    margin: 6px 5px;
    background: var(--border);
  }
</style>

