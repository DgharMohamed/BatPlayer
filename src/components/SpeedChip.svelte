<script lang="ts">
  import { expoOut } from "svelte/easing";
  import { fly } from "svelte/transition";

  import { speed } from "../stores/player";
  import { formatSpeed } from "../utils/time";

  /** Persistent marker: set while playback runs at anything but 1×. */
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
</script>

{#if $speed !== 1}
  <div
    class="speed-chip"
    class:reduced={$speed < 1}
    in:fly={{
      x: reducedMotion.matches ? 0 : 8,
      duration: reducedMotion.matches ? 140 : 170,
      easing: expoOut,
    }}
    out:fly={{ duration: 120 }}
  >
    {formatSpeed($speed)}
  </div>
{/if}

<style>
  .speed-chip {
    position: fixed;
    top: 56px;
    right: 18px;
    z-index: 25;
    padding: 6px 10px;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--bg-elevated);
    color: var(--accent);
    font-size: 12px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.35);
    pointer-events: none;
  }

  /* Slower-than-normal playback reads as a quiet state, not an accent. */
  .speed-chip.reduced {
    color: var(--text-dim);
  }
</style>
