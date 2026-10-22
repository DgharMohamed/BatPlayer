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
  resolveMediaPaths,
  savePosition,
} from "../api/player";
import { t } from "../i18n";
import { playPaths } from "../stores/playlist";
import {
  currentPath,
  currentTime,
  duration,
  idle,
  loadingName,
  queueResume,
  showNotice,
} from "../stores/player";
import { formatTime } from "./time";

function baseName(path: string): string {
  return path.split(/[\\/]/).pop() ?? path;
}

/** True when `path` names one of the media formats the player accepts. */
export function isMediaPath(path: string): boolean {
  const lower = path.toLowerCase();
  if (SUBTITLE_EXTENSIONS.some((extension) => lower.endsWith(`.${extension}`))) {
    return false;
  }
  return MEDIA_EXTENSIONS.some((extension) => lower.endsWith(`.${extension}`));
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
 * Records the loaded file's progress for resume-on-reopen. A `null` current
 * path (nothing open) or an idle engine short-circuits; failures are
 * swallowed on purpose — a missed save costs one resume window at worst.
 */
export async function saveCurrentProgress(): Promise<void> {
  const path = get(currentPath);
  if (path === null || get(idle)) {
    return;
  }
  try {
    await savePosition(path, get(currentTime), get(duration));
  } catch {
    // Best-effort by design (see above).
  }
}

/** Periodic progress save while a file is loaded (resume parity with VLC). */
const PROGRESS_SAVE_INTERVAL_MS = 5000;

/** Starts the periodic saver; returns its cleanup. */
export function startProgressSaver(): () => void {
  const timer = setInterval(() => void saveCurrentProgress(), PROGRESS_SAVE_INTERVAL_MS);
  return () => clearInterval(timer);
}

/**
 * Opens a media file through the Rust player, reporting failures inline.
 * Subtitle files attach to the playing media instead of being "played".
 * The outgoing file's progress is recorded first, while its playback state
 * is still recoverable; after `load_file` the engine forgets time-pos.
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

  await saveCurrentProgress();
  loadingName.set(baseName(path));
  try {
    const resume = await loadFile(path);
    currentPath.set(path);
    // Reopened files resume like VLC's `qt-continue`: the exact point was
    // normalized and stored Rust-side with every progress save.
    if (resume.position > 0) {
      queueResume(path, resume.position);
      showNotice(`${t("notices.resumedAt")} ${formatTime(resume.position)}`, "info");
    }
  } catch (error) {
    showNotice(`${baseName(path)}: ${String(error)}`, "error");
  }
}

/**
 * Opens the file picker and plays the chosen file if one was picked. Media
 * replaces the queue with the file ("play now"); subtitles attach instead.
 */
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
      if (isSubtitlePath(picked)) {
        await openMediaPath(picked);
      } else {
        playPaths([picked]);
      }
    }
  } catch (error) {
    showNotice(`${t("notices.pickerFailed")}: ${String(error)}`, "error");
  }
}

/**
 * Expands drop/pick inputs — plain files, or whole folders scanned
 * recursively in Rust — into a media queue and plays it ("play now", the
 * same replace-queue rule as every direct open).
 *
 * Returns false when nothing playable was found, so callers can fall back
 * (subtitle drops) or report an empty folder (the folder picker).
 */
export async function playDroppedSources(paths: string[]): Promise<boolean> {
  let resolved;
  try {
    resolved = await resolveMediaPaths(paths);
  } catch (error) {
    // The scan is Rust-side and pure; a failure here loses the drop.
    showNotice(`${t("notices.resolverFailed")}: ${String(error)}`, "error");
    return false;
  }
  if (resolved.files.length === 0) {
    return false;
  }
  if (resolved.truncated) {
    // Huge scans stop at the queue limit in Rust; say so rather than
    // silently dropping the tail of the folder.
    showNotice(t("notices.queueTruncated"), "info");
  }
  playPaths(resolved.files);
  return true;
}

/**
 * Opens the folder picker and queues every media file inside, recursively.
 * A folder without playable media reports inline instead of queueing
 * nothing quietly.
 */
export async function pickAndOpenFolder(): Promise<void> {
  try {
    const picked = await open({
      multiple: false,
      directory: true,
      title: "Open folder",
    });
    if (typeof picked === "string") {
      const queued = await playDroppedSources([picked]);
      if (!queued) {
        showNotice(t("notices.folderEmpty"), "info");
      }
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
