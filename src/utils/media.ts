/**
 * OS file pickers and the "open something" actions shared by menus,
 * shortcuts and drag-and-drop.
 */
import { open } from "@tauri-apps/plugin-dialog";

import {
  MEDIA_EXTENSIONS,
  SUBTITLE_EXTENSIONS,
  addSubtitleFile,
  loadFile,
} from "../api/player";
import { showNotice } from "../stores/player";

/** Opens a media file through the Rust player, reporting failures inline. */
export async function openMediaPath(path: string): Promise<void> {
  try {
    await loadFile(path);
  } catch (error) {
    const name = path.split(/[\\/]/).pop() ?? path;
    showNotice(`${name}: ${String(error)}`, "error");
  }
}

/** Opens the file picker and plays the chosen file if one was picked. */
export async function pickAndOpenMedia(): Promise<void> {
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
}

/** Opens the subtitle picker and attaches the chosen file to the player. */
export async function pickAndAttachSubtitle(): Promise<void> {
  const picked = await open({
    multiple: false,
    title: "Open subtitle",
    filters: [
      { name: "Subtitle files", extensions: SUBTITLE_EXTENSIONS },
      { name: "All files", extensions: ["*"] },
    ],
  });
  if (typeof picked !== "string") {
    return;
  }
  try {
    await addSubtitleFile(picked);
  } catch (error) {
    showNotice(String(error), "error");
  }
}
