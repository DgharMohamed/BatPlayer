/**
 * Textual menu data for the VLC-style top bar.
 *
 * Entries are plain data so the component renders them uniformly and
 * can rebuild the tree reactively when the playback state (`hasMedia`,
 * `muted`, `fullscreen`) flips.
 */
import { t } from "../../i18n";
import type { RecentEntry } from "../../api/history";
import type { LoopMode } from "../../stores/playlist";

export interface MenuCallbacks {
  openFile(): void;
  openFolder(): void;
  openRecent(path: string): void;
  clearRecent(): void;
  exit(): void;
  playPause(): void;
  stop(): void;
  previous(): void;
  next(): void;
  loopPlaylist(): void;
  repeatCurrent(): void;
  toggleRandom(): void;
  seekBy(seconds: number): void;
  frameStep(direction: 1 | -1): void;
  changeSpeed(delta: number): void;
  resetSpeed(): void;
  changeVolume(delta: number): void;
  toggleMute(): void;
  cycleAudio(): void;
  toggleFullscreen(): void;
  snapshot(): void;
  cycleSubtitle(): void;
  attachSubtitle(): void;
  togglePlaylist(): void;
  about(): void;
}

export interface MenuState {
  hasMedia: boolean;
  muted: boolean;
  fullscreen: boolean;
  /** Loop mode of the queue ("off"/"all"/"one"). */
  loop: LoopMode;
  /** VLC "random" play order state. */
  shuffle: boolean;
  /** Playlist drawer visibility. */
  playlistOpen: boolean;
  /** Recently opened paths, newest first (may be empty). */
  recentFiles: RecentEntry[];
}

export type MenuEntry =
  | {
      kind: "item";
      label: string;
      hint?: string;
      action: () => void;
      disabled?: boolean;
      /** Checked entries render a check mark and report via aria-checked. */
      checked?: boolean;
    }
  | { kind: "separator" };

export interface MenuDefinition {
  id: string;
  label: string;
  items: MenuEntry[];
}

/** Last path segment, the flat label the recent list shows. */
function baseName(path: string): string {
  return path.split(/[\\/]/).pop() ?? path;
}

/**
 * Flat "Open Recent" section: a caption row, the newest files (clicking
 * one reopens and re-records it) and the "Clear" action. Rendered only
 * when the list is non-empty.
 */
function recentItems(entries: RecentEntry[], a: MenuCallbacks): MenuEntry[] {
  return [
    {
      kind: "item",
      label: t("menu.openRecent"),
      disabled: true,
      action: (): void => {},
    },
    ...entries.map((entry) => ({
      kind: "item" as const,
      label: baseName(entry.path),
      action: () => a.openRecent(entry.path),
    })),
    { kind: "item", label: t("menu.clearRecentFiles"), action: a.clearRecent },
  ];
}

/** Menu definitions in classic player (VLC) order. */
export function buildMenus(state: MenuState, a: MenuCallbacks): MenuDefinition[] {
  const { hasMedia, muted, fullscreen, loop, shuffle, playlistOpen, recentFiles } = state;

  return [
    {
      id: "media",
      label: t("menus.media"),
      items: [
        { kind: "item", label: t("menu.openFile"), hint: "Ctrl+O", action: a.openFile },
        // VLC's Media ▸ "Open Folder…" queues the folder's media; this
        // build's verifiable config carries no default hotkey for it, so
        // the entry ships without a hint rather than a guessed key.
        { kind: "item", label: t("menu.openFolder"), action: a.openFolder },
        ...(recentFiles.length > 0 ? recentItems(recentFiles, a) : []),
        { kind: "separator" },
        { kind: "item", label: t("menu.exit"), hint: "Alt+F4", action: a.exit },
      ],
    },
    {
      id: "playback",
      label: t("menus.playback"),
      items: [
        {
          kind: "item",
          label: t("menu.playPause"),
          hint: "Space",
          disabled: !hasMedia,
          action: a.playPause,
        },
        {
          kind: "item",
          label: t("menu.stop"),
          hint: "S",
          disabled: !hasMedia,
          action: a.stop,
        },
        { kind: "separator" },
        {
          kind: "item",
          label: t("menu.previous"),
          hint: "P",
          action: a.previous,
        },
        {
          kind: "item",
          label: t("menu.next"),
          hint: "N",
          action: a.next,
        },
        { kind: "separator" },
        {
          kind: "item",
          label: t("menu.loopPlaylist"),
          hint: "L (cycles)",
          checked: loop === "all",
          action: a.loopPlaylist,
        },
        {
          kind: "item",
          label: t("menu.repeatCurrent"),
          hint: "L (cycles)",
          checked: loop === "one",
          action: a.repeatCurrent,
        },
        {
          kind: "item",
          label: t("menu.random"),
          hint: "R",
          checked: shuffle,
          action: a.toggleRandom,
        },
        { kind: "separator" },
        {
          kind: "item",
          label: t("menu.seekBackward"),
          hint: "Shift+Left",
          disabled: !hasMedia,
          action: () => a.seekBy(-3),
        },
        {
          kind: "item",
          label: t("menu.seekForward"),
          hint: "Shift+Right",
          disabled: !hasMedia,
          action: () => a.seekBy(3),
        },
        {
          kind: "item",
          label: t("menu.frameBack"),
          disabled: !hasMedia,
          action: () => a.frameStep(-1),
        },
        {
          kind: "item",
          label: t("menu.frameStep"),
          hint: "E",
          disabled: !hasMedia,
          action: () => a.frameStep(1),
        },
        { kind: "separator" },
        {
          kind: "item",
          label: t("menu.speedDown"),
          hint: "[ or -",
          disabled: !hasMedia,
          action: () => a.changeSpeed(-0.25),
        },
        {
          kind: "item",
          label: t("menu.speedUp"),
          hint: "] or +",
          disabled: !hasMedia,
          action: () => a.changeSpeed(+0.25),
        },
        {
          kind: "item",
          label: t("menu.resetSpeed"),
          hint: "=",
          disabled: !hasMedia,
          action: a.resetSpeed,
        },
      ],
    },
    {
      id: "audio",
      label: t("menus.audio"),
      items: [
        {
          kind: "item",
          label: t("menu.volumeUp"),
          hint: "Ctrl+Up",
          disabled: !hasMedia,
          action: () => a.changeVolume(5),
        },
        {
          kind: "item",
          label: t("menu.volumeDown"),
          hint: "Ctrl+Down",
          disabled: !hasMedia,
          action: () => a.changeVolume(-5),
        },
        {
          kind: "item",
          label: t(muted ? "menu.unmute" : "menu.mute"),
          hint: "M",
          disabled: !hasMedia,
          action: a.toggleMute,
        },
        { kind: "separator" },
        {
          kind: "item",
          label: t("menu.audioTrack"),
          hint: "B",
          disabled: !hasMedia,
          action: a.cycleAudio,
        },
      ],
    },
    {
      id: "video",
      label: t("menus.video"),
      items: [
        {
          kind: "item",
          label: t(fullscreen ? "menu.leaveFullscreen" : "menu.fullscreen"),
          hint: "F",
          action: a.toggleFullscreen,
        },
        { kind: "separator" },
        {
          kind: "item",
          label: t("menu.snapshot"),
          hint: "Shift+S",
          disabled: !hasMedia,
          action: a.snapshot,
        },
      ],
    },
    {
      id: "view",
      label: t("menus.view"),
      items: [
        {
          kind: "item",
          label: t("menu.playlist"),
          hint: "Ctrl+L",
          checked: playlistOpen,
          action: a.togglePlaylist,
        },
      ],
    },
    {
      id: "subtitle",
      label: t("menus.subtitle"),
      items: [
        {
          kind: "item",
          label: t("menu.subtitleTrack"),
          hint: "V",
          disabled: !hasMedia,
          action: a.cycleSubtitle,
        },
        {
          kind: "item",
          label: t("menu.loadSubtitle"),
          disabled: !hasMedia,
          action: a.attachSubtitle,
        },
      ],
    },
    {
      id: "help",
      label: t("menus.help"),
      items: [{ kind: "item", label: t("menu.about"), action: a.about }],
    },
  ];
}
