<script lang="ts">
  import { expoOut } from "svelte/easing";
  import { fly } from "svelte/transition";

  import { t } from "../i18n";
  import { loading, loadingName } from "../stores/player";
  import { stopPlayback } from "../utils/actions";

  /** Quick loads never flash the plate: it only appears after this delay. */
  const APPEAR_AFTER_MS = 150;

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  let visible = $state(false);
  /** True after Cancel was pressed but the engine has not confirmed yet. */
  let cancelling = $state(false);

  $effect(() => {
    if (!$loading) {
      visible = false;
      cancelling = false;
      return;
    }
    const timer = setTimeout(() => (visible = true), APPEAR_AFTER_MS);
    return () => clearTimeout(timer);
  });

  function cancelLoad(): void {
    cancelling = true;
    void stopPlayback();
  }
</script>

{#if visible}
  <div class="loading-layer">
    <div
      class="loading-plate"
      transition:fly={{
        y: reducedMotion.matches ? 0 : 6,
        duration: 180,
        easing: expoOut,
      }}
    >
      <span class="spinner" aria-hidden="true"></span>
      <span class="file-name" role="status">{$loadingName || t("loading.title")}</span>
      <button
        class="cancel"
        type="button"
        title={t(cancelling ? "loading.cancelling" : "loading.cancel")}
        disabled={cancelling}
        onclick={cancelLoad}
      >
        {t(cancelling ? "loading.cancelling" : "loading.cancel")}
      </button>
    </div>
  </div>
{/if}

<style>
  /* Full-area flex layer keeps the plate centered without touching its own
     transform (which the fly transition animates); the layer is transparent
     to the pointer so the stage keeps its own interactions. */
  .loading-layer {
    position: fixed;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 45;
    pointer-events: none;
  }

  .loading-plate {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background: var(--bg-elevated);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    pointer-events: auto;
  }

  .spinner {
    flex: none;
    width: 18px;
    height: 18px;
    border: 2px solid rgba(255, 255, 255, 0.14);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spinner-spin 0.9s linear infinite;
  }

  @keyframes spinner-spin {
    to {
      transform: rotate(360deg);
    }
  }

  /* Rotation itself is the feedback; under reduced motion it just turns slower. */
  @media (prefers-reduced-motion: reduce) {
    .spinner {
      animation-duration: 2.8s;
    }
  }

  .file-name {
    max-width: min(420px, 50vw);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13px;
    color: var(--text);
  }

  .cancel {
    flex: none;
    min-width: 88px;
    padding: 5px 12px;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--text-dim);
    font-family: inherit;
    font-size: 12.5px;
    text-align: center;
    cursor: pointer;
    transition:
      background var(--transition-fast),
      border-color var(--transition-fast),
      color var(--transition-fast);
  }

  .cancel:hover:enabled {
    background: rgba(255, 255, 255, 0.07);
    border-color: rgba(255, 255, 255, 0.16);
    color: var(--text);
  }

  .cancel:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .cancel:focus-visible {
    outline: 1px solid var(--accent);
    outline-offset: 2px;
  }
</style>
