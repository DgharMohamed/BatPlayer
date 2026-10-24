//! Linux video surface.
//!
//! Milestone 2 will create a native child surface for mpv's `wid` embedding.
//! Under X11 this is an X11 subwindow of the Tauri window; on Wayland mpv
//! embedding needs XWayland (run with `GDK_BACKEND=x11`, documented in the
//! README). Until then the surface is unavailable on Linux.

use super::Error;

#[derive(Clone)]
pub struct VideoSurface {
    _private: (),
}

impl VideoSurface {
    pub fn attach(_window: &tauri::Window) -> Result<Self, Error> {
        Err(Error::Unsupported)
    }

    pub fn resize_to_fit(&self) -> Result<(), Error> {
        Ok(())
    }

    pub fn set_playlist_width(&self, _logical_width: f64) -> Result<(), Error> {
        Ok(())
    }

    /// Window id for mpv's `wid` option (an X11 window id). Unavailable until
    /// the X11 subwindow is implemented.
    pub fn wid(&self) -> Result<i64, Error> {
        Err(Error::Unsupported)
    }
}
