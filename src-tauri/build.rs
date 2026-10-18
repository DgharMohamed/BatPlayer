use std::path::{Path, PathBuf};

fn main() {
    tauri_build::build();

    let manifest = PathBuf::from(
        std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is always set by cargo"),
    );
    let mpv_dir = manifest.join("mpv");
    let dll = mpv_dir.join("libmpv-2.dll");
    let import_lib = mpv_dir.join("mpv.lib");

    if !dll.exists() || !import_lib.exists() {
        panic!(
            "libmpv is missing from {}. Run scripts/fetch-mpv.ps1 (Windows) or see the README \
             for Linux/macOS instructions before building.",
            mpv_dir.display()
        );
    }

    // Import library for libmpv2-sys's `mpv` link target.
    println!("cargo:rustc-link-search=native={}", mpv_dir.display());

    // Put the runtime DLL next to the executable (target/<profile>/) so both
    // `cargo run` and `tauri dev` find it. OUT_DIR is
    // target/<profile>/build/<crate>-<hash>/out.
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR is always set by cargo"));
    let profile_dir = out_dir
        .ancestors()
        .nth(3)
        .expect("OUT_DIR is always three levels below the profile directory");
    copy_if_changed(&dll, &profile_dir.join("libmpv-2.dll"));

    println!("cargo:rerun-if-changed={}", dll.display());
    println!("cargo:rerun-if-changed={}", import_lib.display());
}

fn copy_if_changed(src: &Path, dest: &Path) {
    let needs_copy = match (src.metadata(), dest.metadata()) {
        (Ok(s), Ok(d)) => s.len() != d.len() || s.modified().ok() != d.modified().ok(),
        _ => true,
    };
    if needs_copy && let Err(err) = std::fs::copy(src, dest) {
        panic!(
            "failed to copy {} to {}: {err}",
            src.display(),
            dest.display()
        );
    }
}
