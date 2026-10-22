//! Native video surface hosting.
//!
//! BatPlayer renders video into a **native child window** (mpv's `wid`
//! embedding, Milestone 2) that sits *below* the transparent Tauri webview,
//! so HTML controls overlay the video. Each platform module creates and
//! manages that child surface.

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "linux")]
pub use linux::VideoSurface;
#[cfg(target_os = "macos")]
pub use macos::VideoSurface;
#[cfg(target_os = "windows")]
pub use windows::VideoSurface;

#[cfg(target_os = "windows")]
pub use windows::attach_resize_ring;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// A platform windowing error.
    #[error("windowing error: {0}")]
    Platform(String),

    /// The video surface is not implemented on this platform yet.
    #[error("the video surface is not implemented on this platform yet")]
    Unsupported,
}
