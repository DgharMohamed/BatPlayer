/**
 * OS file pickers and the "open something" actions shared by menus,
 * shortcuts and drag-and-drop.
 */
import { open } from "@tauri-apps/plugin-dialog";
import { get } from "svelte/store";

import {
  MEDIA_EXTENSIONS,
  SUBTITLE_EXTENSIONS,
  addSubtitleFile,
  loadFile,
} from "../api/player";
import { t } from "../i18n";
import { idle, loadingName, showNotice } from "../stores/player";

function baseName(path: string): string {
  return path.split(/[\\/]/).pop() ?? path;
}

/** True when `path` names one of the subtitle formats `sub-add` accepts. */
function isSubtitlePath(path: string): boolean {
  const lower = path.toLowerCase();
  return SUBTITLE_EXTENSIONS.some((extension) => lower.endsWith(`.${extension}`));
}

/** Attaches a subtitle file to the loaded media, reporting the outcome inline. */
export async function attachSubtitlePath(path: string): Promise<void> {
  const name = baseName(path);
  try {
    await addSubtitleFile(path);
    showNotice(`${name} — ${t("notices.subtitleAttached")}`, "info");
  } catch (error) {
    showNotice(`${name}: ${String(error)}`, "error");
  }
}

/**
 * Opens a media file through the Rust player, reporting failures inline.
 * Subtitle files attach to the playing media instead of being "played".
 */
export async function openMediaPath(path: string): Promise<void> {
  if (isSubtitlePath(path)) {
    if (get(idle)) {
      showNotice(t("notices.subtitleNeedsMedia"), "info");
      return;
    }
    await attachSubtitlePath(path);
    return;
  }

  loadingName.set(baseName(path));
  try {
    await loadFile(path);
  } catch (error) {
    showNotice(`${baseName(path)}: ${String(error)}`, "error");
  }
}

/** Opens the file picker and plays the chosen file if one was picked. */
export async function pickAndOpenMedia(): Promise<void> {
  try {
    const picked = await open({
      multiple: false,
      title: "Open media",
      filters: [
        { name: "Media files", extensions: MEDIA_EXTENSIONS },
        { name: "All files", extensions: ["*"] },
      ],
    });
    if (typeof picked === "string") {
      await openMediaPath(picked);
    }
  } catch (error) {
    showNotice(`${t("notices.pickerFailed")}: ${String(error)}`, "error");
  }
}

/** Opens the subtitle picker and attaches the chosen file to the player. */
export async function pickAndAttachSubtitle(): Promise<void> {
  try {
    const picked = await open({
      multiple: false,
      title: "Open subtitle",
      filters: [
        { name: "Subtitle files", extensions: SUBTITLE_EXTENSIONS },
        { name: "All files", extensions: ["*"] },
      ],
    });
    if (typeof picked === "string") {
      await attachSubtitlePath(picked);
    }
  } catch (error) {
    showNotice(`${t("notices.pickerFailed")}: ${String(error)}`, "error");
  }
}
