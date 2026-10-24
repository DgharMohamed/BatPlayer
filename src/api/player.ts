/**
 * Thin, typed bindings to the Rust player commands and the `player-event`
 * channel the engine pushes mpv property changes on.
 *
 * The UI must not talk to libmpv directly — everything goes through here
 * (see README's architecture notes).
 */
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

/** Extensions offered by file dialogs, next to the "all files" fallback. */
export const MEDIA_EXTENSIONS = [
  "mkv",
  "mp4",
  "m4v",
  "avi",
  "mov",
  "webm",
  "wmv",
  "flv",
  "ts",
  "m2ts",
  "mts",
  "mpg",
  "mpeg",
  "vob",
  "ogv",
  "mp3",
  "m4a",
  "aac",
  "flac",
  "wav",
  "ogg",
  "opus",
  "wma",
];

/** Subtitle formats accepted by `sub-add`. */
export const SUBTITLE_EXTENSIONS = ["srt", "ass", "ssa", "sub", "vtt", "sup", "srt.gz"];

/** Payload of the `player-event` event emitted by `src-tauri/src/player`. */
export type PlayerEvent =
  | { type: "property"; name: string; value: number | boolean | string }
  | { type: "startFile" }
  | {
      type: "fileLoaded";
      audioTracks: TrackInfo;
      audioVolume: number;
      audioMuted: boolean;
    }
  | { type: "endFile"; error: string | null };

/** The stored resume point of a file about to play, sent back by `load_file`. */
export type ResumeHint = {
  /** Seconds from the previous session; 0 plays from the start. */
  position: number;
  /** Total duration reported with it, 0 when unknown. */
  duration: number;
};

/**
 * Result of expanding mixed inputs (files and folders) into a media queue.
 * `truncated` is set when the scan hit its file or depth cap in Rust.
 */
export type MediaResolve = {
  files: string[];
  truncated: boolean;
};

/** Expands dropped/picked files and folders into a flat media-file queue. */
export const resolveMediaPaths = (paths: string[]): Promise<MediaResolve> =>
  invoke("resolve_media_paths", { paths });

/** Reserves or restores the native video width for the docked playlist. */
export const setPlaylistDock = (width: number): Promise<void> =>
  invoke("set_playlist_dock", { width });

export const loadFile = (path: string): Promise<ResumeHint> =>
  invoke("load_file", { path });

export const playPause = (): Promise<void> => invoke("play_pause");

export const stop = (): Promise<void> => invoke("stop");

export const seekTo = (seconds: number): Promise<void> => invoke("seek_to", { seconds });

export const seekBy = (seconds: number): Promise<void> => invoke("seek_by", { seconds });

export const setVolume = (volume: number): Promise<void> => invoke("set_volume", { volume });

export const setMute = (mute: boolean): Promise<void> => invoke("set_mute", { mute });

export const setSpeed = (speed: number): Promise<void> => invoke("set_speed", { speed });

/** Position after a track cycle; `current` is 0 when the type is off. */
export type TrackInfo = { current: number; total: number };

export const cycleAudio = (): Promise<TrackInfo> => invoke("cycle_audio");

export const cycleSubtitle = (): Promise<TrackInfo> => invoke("cycle_subtitle");

export const addSubtitleFile = (path: string): Promise<void> =>
  invoke("add_subtitle_file", { path });

/** `direction` is +1 for one frame forward, -1 for one frame backward. */
export const frameStep = (direction: 1 | -1): Promise<void> =>
  invoke("frame_step", { direction });

/** Takes a snapshot and resolves with the absolute path of the written file. */
export const screenshot = (): Promise<string> => invoke("screenshot");

/**
 * Best-effort progress save for resume-on-reopen (called before switching
 * files and on a timer while playing; failures degrade silently in Rust).
 */
export const savePosition = (
  path: string,
  position: number,
  duration: number,
): Promise<void> => invoke("save_position", { path, position, duration });

/**
 * Subscribes to player property and lifecycle events. The Rust side pushes
 * one event per observed property change and file lifecycle transition.
 */
export function onPlayerEvent(
  handler: (event: PlayerEvent) => void,
): Promise<UnlistenFn> {
  return listen<PlayerEvent>("player-event", (event) => handler(event.payload));
}
