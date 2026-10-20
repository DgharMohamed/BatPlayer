<script lang="ts">
  import BatLogo from "../BatLogo.svelte";
  import { t } from "../../i18n";
  import MenuFlyout from "./MenuFlyout.svelte";
  import {
    cycleAudioTrack,
    cycleSubtitleTrack,
    resetSpeed,
    seekRelative,
    stepFrame,
    stepSpeed,
    stepVolume,
    stopPlayback,
    takeSnapshot,
    toggleMute,
    togglePlayPause,
  } from "../../utils/actions";
  import { clearHistory } from "../../api/history";
  import { chromeHidden, menuOpen, pinChrome } from "../../stores/chrome";
  import { recent } from "../../stores/history";
  import { displayTitle, mediaLoaded, muted, showNotice } from "../../stores/player";
  import { closeWindow, fullscreen, maximized, minimizeWindow, toggleFullscreen, toggleMaximize } from "../../stores/window";
  import { pickAndAttachSubtitle, pickAndOpenMedia } from "../../utils/media";
  import { openMediaPath } from "../../utils/media";
  import { buildMenus, type MenuCallbacks, type MenuDefinition, type MenuEntry } from "./menus";

  /** Id of the open flyout; false when the menubar is closed. */
  let openMenu = $state<string | false>(false);
  let barEl = $state<HTMLElement | null>(null);
  let paneEl = $state<HTMLDivElement | null>(null);

  const menus: MenuDefinition[] = $derived.by(() =>
    buildMenus(
      {
        hasMedia: $mediaLoaded,
        muted: $muted,
        fullscreen: $fullscreen,
        recentFiles: $recent,
      },
      menuCallbacks(),
    ),
  );

  function menuCallbacks(): MenuCallbacks {
    return {
      openFile: () => void pickAndOpenMedia(),
      openRecent: (path) => void openMediaPath(path),
      clearRecent: () => void clearHistory(),
      exit: closeWindow,
      playPause: () => void togglePlayPause(),
      stop: () => void stopPlayback(),
      seekBy: (seconds) => void seekRelative(seconds),
      frameStep: (direction) => void stepFrame(direction),
      changeSpeed: (delta) => void stepSpeed(delta),
      resetSpeed: () => void resetSpeed(),
      changeVolume: (delta) => void stepVolume(delta),
      toggleMute: () => void toggleMute(),
      cycleAudio: () => void cycleAudioTrack(),
      toggleFullscreen: () => void toggleFullscreen(),
      snapshot: () => void takeSnapshot(),
      cycleSubtitle: () => void cycleSubtitleTrack(),
      attachSubtitle: () => void pickAndAttachSubtitle(),
      about: () => showNotice(t("app.about"), "info"),
    };
  }

  function closeMenu(): void {
    openMenu = false;
    menuOpen.set(false);
    pinChrome(false);
  }

  function openMenuFor(id: string): void {
    if (openMenu === id) {
      return;
    }
    openMenu = id;
    menuOpen.set(id);
    pinChrome(true);
  }

  function toggleMenu(id: string): void {
    if (openMenu === id) {
      closeMenu();
    } else {
      openMenuFor(id);
    }
  }

  /** Menubar muscle memory: hovering another label while a flyout is open
   * switches the flyout there. */
  function hoverIntoMenu(id: string): void {
    if (openMenu !== false && openMenu !== id) {
      openMenuFor(id);
    }
  }

  function pick(entry: MenuEntry): void {
    if (entry.kind === "item" && !entry.disabled) {
      closeMenu();
      entry.action();
    }
  }

  /** Roving focus between the enabled entries of the open flyout. */
  function onFlyoutKeydown(event: KeyboardEvent): void {
    if (typeof openMenu !== "string" || paneEl === null) {
      return;
    }
    const items = [
      ...paneEl.querySelectorAll<HTMLButtonElement>("button:not([disabled])"),
    ];
    if (items.length === 0) {
      return;
    }
    const index = items.indexOf(document.activeElement as HTMLButtonElement);
    if (event.key === "ArrowDown") {
      event.preventDefault();
      items[(index + 1) % items.length]?.focus();
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      items[(index - 1 + items.length) % items.length]?.focus();
    } else if (event.key === "Home") {
      event.preventDefault();
      items[0].focus();
    } else if (event.key === "End") {
      event.preventDefault();
      items[items.length - 1].focus();
    } else if (event.key === "Escape") {
      event.preventDefault();
      const id: string = openMenu;
      closeMenu();
      menuButtonFor(id)?.focus();
    }
  }

  /** Closes on Escape anywhere and keeps Tab focus from escaping the flyout. */
  function onWindowKeydown(event: KeyboardEvent): void {
    if (typeof openMenu !== "string") {
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      const id = openMenu;
      closeMenu();
      menuButtonFor(id)?.focus();
    } else if (event.key === "Tab") {
      // Close, but hand the focus back to the menubar button instead of
      // dropping it on <body>.
      event.preventDefault();
      const id = openMenu;
      closeMenu();
      menuButtonFor(id)?.focus();
    }
  }

  /** Closes when a pointer press lands anywhere outside the bar. */
  function onWindowPointerdown(event: PointerEvent): void {
    const insideBar =
      event.target instanceof Element && (barEl?.contains(event.target) ?? false);
    if (openMenu !== false && !insideBar) {
      closeMenu();
    }
  }

  function menuButtonFor(id: string): HTMLButtonElement | null {
    return (
      barEl?.querySelector<HTMLButtonElement>(
        `button[data-menu-id="${CSS.escape(id)}"]`,
      ) ?? null
    );
  }

  /** Double click on drag surfaces (not on menus) achieves maximize/restore. */
  function onBarDblclick(event: MouseEvent): void {
    const target = event.target;
    if (
      target === barEl ||
      (target instanceof HTMLElement && target.hasAttribute("data-tauri-drag-region"))
    ) {
      toggleMaximize();
    }
  }

  /** Focuses the first enabled entry right after a flyout appears. */
  $effect(() => {
    if (typeof openMenu === "string" && paneEl !== null) {
      const first = paneEl.querySelectorAll<HTMLButtonElement>(
        "button:not([disabled])",
      )[0];
      first?.focus();
    }
  });
</script>

<svelte:window onpointerdown={onWindowPointerdown} onkeydown={onWindowKeydown} />

<!--
  The title bar also acts as Tauri's custom drag region (`data-tauri-drag-region`),
  so pointerdown/dblclick here are mouse-only interactions by design.
-->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<header
  bind:this={barEl}
  class="top-bar"
  class:hidden={$chromeHidden}
  data-tauri-drag-region
  ondblclick={onBarDblclick}
>
  <span class="logo" data-tauri-drag-region>
    <BatLogo size={22} />
  </span>

  <nav class="menubar" aria-label={t("controls.menuBar")}>
    {#each menus as menu (menu.id)}
      <div class="menu-anchor">
        <button
          class="menu-btn"
          class:armed={openMenu === menu.id}
          type="button"
          data-menu-id={menu.id}
          aria-haspopup="menu"
          aria-expanded={openMenu === menu.id}
          onclick={() => toggleMenu(menu.id)}
          onpointerenter={() => hoverIntoMenu(menu.id)}
        >
          {menu.label}
        </button>
        {#if openMenu === menu.id}
          <div class="flyout-slot" bind:this={paneEl}>
            <MenuFlyout
              entries={menu.items}
              onpick={pick}
              onkeydown={onFlyoutKeydown}
            />
          </div>
        {/if}
      </div>
    {/each}
  </nav>

  <span class="window-title">
    {$displayTitle || t("app.name")}
  </span>

  <div class="window-controls">
    <button
      class="control"
      type="button"
      title={t("topBar.minimize")}
      aria-label={t("topBar.minimize")}
      onclick={minimizeWindow}
    >
      <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M1.5 6h9" /></svg>
    </button>
    <button
      class="control"
      type="button"
      title={$maximized ? t("topBar.restore") : t("topBar.maximize")}
      aria-label={$maximized ? t("topBar.restore") : t("topBar.maximize")}
      onclick={toggleMaximize}
    >
      <svg viewBox="0 0 12 12" aria-hidden="true">
        {#if $maximized}
          <path d="M2 4.5h5.5v5.5H2z" />
          <path d="M4.5 2H9v4" />
        {:else}
          <path d="M2 2h8v8H2z" />
        {/if}
      </svg>
    </button>
    <button
      class="control close"
      type="button"
      title={t("topBar.close")}
      aria-label={t("topBar.close")}
      onclick={closeWindow}
    >
      <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 2l8 8M10 2l-8 8" /></svg>
    </button>
  </div>
</header>

<style>
  .top-bar {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    height: 40px;
    display: flex;
    align-items: center;
    gap: 2px;
    padding-left: 10px;
    z-index: 30;
    background: linear-gradient(to bottom, rgba(6, 6, 8, 0.94), rgba(10, 10, 13, 0.88));
    border-bottom: 1px solid var(--border);
    backdrop-filter: blur(16px);
    color: var(--text-dim);
    user-select: none;
    -webkit-user-select: none;
    transition:
      transform var(--transition-medium),
      opacity var(--transition-medium);
  }

  .top-bar.hidden {
    transform: translateY(-100%);
    opacity: 0;
    pointer-events: none;
  }

  .logo {
    display: inline-flex;
    align-items: center;
    padding: 0 8px 0 0;
    cursor: default;
  }

  .menubar {
    display: flex;
    align-items: center;
    height: 100%;
  }

  .menu-anchor {
    position: relative;
    display: flex;
    align-items: center;
    height: 100%;
  }

  .flyout-slot {
    position: absolute;
    top: 100%;
    left: 0;
  }

  .menu-btn {
    height: 100%;
    padding: 0 10px;
    border: none;
    background: transparent;
    color: var(--text-dim);
    font-size: 13px;
    cursor: pointer;
  }

  .menu-btn:hover,
  .menu-btn.armed {
    background: rgba(255, 255, 255, 0.08);
    color: var(--text);
  }

  .menu-btn:focus-visible {
    outline: 1px solid var(--accent);
    outline-offset: -3px;
  }

  .window-title {
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    max-width: 40%;
    font-size: 12.5px;
    letter-spacing: 0.01em;
    color: var(--text-dim);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    pointer-events: none;
  }

  .window-controls {
    display: flex;
    align-items: stretch;
    height: 100%;
    margin-left: auto;
    flex: none;
  }

  .control {
    width: 46px;
    border: none;
    background: transparent;
    color: var(--text-dim);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
  }

  .control svg {
    width: 12px;
    height: 12px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1;
    stroke-linecap: round;
  }

  .control:hover {
    background: rgba(255, 255, 255, 0.08);
    color: var(--text);
  }

  .control:focus-visible {
    outline: 1px solid var(--accent);
    outline-offset: -3px;
  }

  .control.close:hover {
    background: #e81123;
    color: #ffffff;
  }

  /* Reduced motion: the bar still appears and vanishes, just without travel. */
  @media (prefers-reduced-motion: reduce) {
    .top-bar {
      transition: opacity var(--transition-fast);
    }

    .top-bar.hidden {
      transform: none;
    }
  }
</style>
