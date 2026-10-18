/** Format seconds as m:ss, or h:mm:ss for media an hour or longer. */
export function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return "0:00";
  }
  const total = Math.floor(seconds);
  const s = total % 60;
  const m = Math.floor(total / 60) % 60;
  const h = Math.floor(total / 3600);
  const mm = h > 0 ? String(m).padStart(2, "0") : String(m);
  const ss = String(s).padStart(2, "0");
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

/** Format a playback speed factor for the OSD and the speed chip ("1.5×"). */
export function formatSpeed(speed: number): string {
  return `${Number(speed.toFixed(2))}×`;
}
