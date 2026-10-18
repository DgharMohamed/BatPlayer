/**
 * Textual menu data for the VLC-style top bar.
 *
 * Entries are plain data so the component renders them uniformly and
 * can rebuild the tree reactively when the playback state (`hasMedia`,
 * `muted`, `fullscreen`) flips.
 */
import { t } from "../../i18n";

export interface MenuCallbacks {
  openFile(): void;
  exit(): void;
  playPause(): void;
  stop(): void;
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
  about(): void;
}

export interface MenuState {
  hasMedia: boolean;
  muted: boolean;
  fullscreen: boolean;
}

export type MenuEntry =
  | {
      kind: "item";
      label: string;
      hint?: string;
      action: () => void;
      disabled?: boolean;
    }
  | { kind: "separator" };

export interface MenuDefinition {
  id: string;
  label: string;
  items: MenuEntry[];
}

/** Menu definitions in classic player (VLC) order. */
export function buildMenus(state: MenuState, a: MenuCallbacks): MenuDefinition[] {
  const { hasMedia, muted, fullscreen } = state;

  return [
    {
      id: "media",
      label: t("menus.media"),
      items: [
        { kind: "item", label: t("menu.openFile"), hint: "Ctrl+O", action: a.openFile },
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
          disabled: !hasMedia,
          action: a.stop,
        },
        { kind: "separator" },
        {
          kind: "item",
          label: t("menu.seekBackward"),
          hint: "Shift+Left",
          disabled: !hasMedia,
          action: () => a.seekBy(-10),
        },
        {
          kind: "item",
          label: t("menu.seekForward"),
          hint: "Shift+Right",
          disabled: !hasMedia,
          action: () => a.seekBy(10),
        },
        {
          kind: "item",
          label: t("menu.frameBack"),
          hint: ",",
          disabled: !hasMedia,
          action: () => a.frameStep(-1),
        },
        {
          kind: "item",
          label: t("menu.frameStep"),
          hint: ".",
          disabled: !hasMedia,
          action: () => a.frameStep(1),
        },
        { kind: "separator" },
        {
          kind: "item",
          label: t("menu.speedDown"),
          hint: "[",
          disabled: !hasMedia,
          action: () => a.changeSpeed(-0.25),
        },
        {
          kind: "item",
          label: t("menu.speedUp"),
          hint: "]",
          disabled: !hasMedia,
          action: () => a.changeSpeed(+0.25),
        },
        {
          kind: "item",
          label: t("menu.resetSpeed"),
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
          hint: "Up",
          disabled: !hasMedia,
          action: () => a.changeVolume(5),
        },
        {
          kind: "item",
          label: t("menu.volumeDown"),
          hint: "Down",
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
          hint: "A",
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
          hint: "S",
          disabled: !hasMedia,
          action: a.snapshot,
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
