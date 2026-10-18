//! macOS video surface.
//!
//! Milestone 2 will create an NSView child of the Tauri window for mpv's
//! `wid` embedding. That work must happen on the main thread with AppKit
//! (see the platform notes in the README); until then the surface is
//! unavailable on macOS.

use super::Error;

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
}
