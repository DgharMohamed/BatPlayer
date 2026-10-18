<script lang="ts">
  import BatLogo from "./components/BatLogo.svelte";
  import ControlBar from "./components/ControlBar.svelte";
  import { t } from "./i18n";
</script>

<main class="app">
  <!--
    Video plays in a native child window *behind* this transparent webview
    (see src-tauri/src/platform/). This area must stay transparent so the
    video surface shows through; the bat mark is just the idle watermark.
  -->
  <section class="video-area" aria-label={t("video.areaLabel")}>
    <div class="idle-mark">
      <BatLogo size={104} />
      <p class="idle-hint">{t("idle.hint")}</p>
    </div>
  </section>

  <ControlBar />
</main>

<style>
  .app {
    display: flex;
    flex-direction: column;
    height: 100%;
  }

  /* Overlays the native video surface; must stay transparent. */
  .video-area {
    flex: 1;
    min-height: 0;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .idle-mark {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 20px;
    opacity: 0.5;
    animation: idle-fade-in 600ms ease both;
  }

  .idle-hint {
    margin: 0;
    font-size: 14px;
    letter-spacing: 0.02em;
    color: var(--text-dim);
  }

  @keyframes idle-fade-in {
    from {
      opacity: 0;
      transform: translateY(8px);
    }
    to {
      opacity: 0.5;
      transform: none;
    }
  }
</style>
