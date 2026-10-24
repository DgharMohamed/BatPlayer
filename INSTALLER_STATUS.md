# BatPlayer NSIS Modern Dark Installer - Status & Handover Guide

> **Date:** October 24, 2026
> **Status:** ALL REPORTED BUGS FIXED AND VERIFIED with real mouse input. Production template at `src-tauri/nsis/installer.nsi` compiles clean and passes the full end-to-end click-through matrix.

---

## 1. Project Overview

BatPlayer is a media player built with **Tauri v2 + Svelte**, shipping with a **fully custom NSIS installer UI**:

- **Borderless window, 760 × 540 px**, centered, `18px` rounded corners.
- **Dark Charcoal `#1E1E1E`** background + **Vibrant Yellow `#FFC107`** accents.
- Custom pages: Welcome (`Install Now`), Maintenance/Reinstall (`Continue`), instfiles progress chrome, Finish (`Finish` + dark launch checkbox).
- Publisher **BatSoft**, EULA/Privacy links, `hero_ring.bmp` hero graphic.

All click handlers are `${NSD_OnClick}` callbacks on static/link labels styled as buttons (yellow pills via `BatPlayerCreateYellowPill`).

---

## 2. Bugs Reported & Root Causes (all FIXED)

### Bug 1 - "Install Now closes the window without installing" (original report)
**Root cause:** `${NSD_Create*}` macros were called on the instfiles page, which has **no nsDialogs context** (`nsDialogs::Create` was never called there). That is undefined behavior and killed the process right after the click.
**Fix:** `ShowInstallerChrome` was rewritten to build the progress-page chrome with raw `user32::CreateWindowEx` calls (no nsDialogs macros). This page intentionally has **no click callbacks**.

### Bug 2 - "Finish button doesn't close the installer" (second report)
There were **two independent problems**:

1. **`RunMainBinary` used `nsis_tauri_utils::RunAsUser`, which HANGS forever** when invoked from the finish-page click handler (the spawned app never appeared, `Quit` was never reached). The currentUser install runs non-elevated, so `RunAsUser` adds nothing.
   **Fix:** plain non-blocking `Exec '"$INSTDIR\${MAINBINARYNAME}.exe"'`.
   *Note:* the passive/silent `/R` path in `.onInstSuccess` still uses `RunAsUser` on purpose (elevated silent installs need it) and works there.

2. **Installer shutdown escape from the FINAL page.** Empirically proven:
   - A bare `Quit` inside an `nsDialogs` OnClick handler does **not** escape the `nsDialogs::Show` message pump (the handler finishes, but the window stays open forever).
   - `SendMessage $HWNDPARENT ${WM_CLOSE}` is **page-dependent**: it closes the installer from mid-flow pages (the close X buttons on welcome/reinstall work) but does **nothing** on the last page of the wizard.
   - Deferred `PostMessage WM_CLOSE` leaves the window resident for many seconds (some runs never closed).
   **Fix:** the native escape used by stock NSIS finish pages - click the wizard's own hidden Next button, which on the final page NIS treats as "Finish"/Done:
   ```nsis
   GetDlgItem $0 $HWNDPARENT 1
   EnableWindow $0 1
   SendMessage $0 ${BM_CLICK} 0 0
   ```
   This is exactly how the reinstall page's `Continue` pill advances pages (`OnClickReinstallContinue`). Verified: installer closes in **5-7 ms** after a real mouse click on Finish.

### Bug 3 - "X button not working too"
This was a **cascade of bug 2**: while the finish handler was hung inside `RunAsUser`, the pump never freed up, so every click (including the X) queued and never processed.
Additionally the finish-page X shares the `WM_CLOSE`-based close handler, which is dead on the last page (see above).
**Fix:** the finish page's X is wired to a dedicated `BatPlayerFinishCloseClick` using the same ID-1 `BM_CLICK` escape (without launching the app). Welcome/reinstall page X buttons keep `BatPlayerCloseClick` (`WM_CLOSE`), which is correct for mid-flow pages and verified working.

### Bug 4 - "Style the checkboxes on the installation"
Real `BS_AUTOCHECKBOX` controls paint an **opaque white face** that cannot be themed here because the nsDialogs page proc never forwards `WM_CTLCOLORBTN`.
**Fix:** the "Launch BatPlayer now" toggle is drawn as a **static-glyph toggle pair**:
- Glyph static (checked: U+2611 ballotted check, `THEME_ACCENT`; unchecked: U+2610 empty ballot, `THEME_TEXT_MUTED`) + label static, both `NSD_OnClick`-wired to `BatPlayerLaunchToggleClick`.
- The handler flips `$FinishLaunchState` (default `1` = checked) and swaps glyph/colors; `BatPlayerFinishClick` reads `$FinishLaunchState`.
- Verified visually (no white patch) and interactively (real click toggles state; OFF prevents app launch).

---

## 3. Empirical Lessons (do not re-derive these!)

1. **`Quit` does not escape `nsDialogs::Show`** inside an OnClick handler. Use the ID-1 `BM_CLICK` escape (final page) or WM_CLOSE (mid-flow pages).
2. **WM_CLOSE on the last wizard page is a no-op.** Never use it for the finish page.
3. **Repo template must stay UTF-8 WITHOUT BOM.** Tauri's bundler adds a BOM when staging `src-tauri\target\release\nsis\x64\installer.nsi`; direct makensis compilations of the *staged* file REQUIRE that BOM or the ballot-box/close glyphs (U+2611/U+2610/U+2715) mojibake into `锟絚e锟斤拷`-style garbage.
4. **Checkbox controls can't be themed dark** on these pages (no `WM_CTLCOLORBTN` forwarding) - use the glyph-toggle pattern.
5. **nsis_tauri_utils::RunAsUser hangs from the finish click handler** - use `Exec` for non-elevated launches.
6. **Automated GUI test flakiness was environmental, not installer-related:**
   - A background test driver cannot steal foreground (`SetForegroundWindow` returns False); clicks land on whatever is above (VS Code / IDE windows at the same screen coordinates). Driver must raise the installer with `SetWindowPos(HWND_TOPMOST, SWP_NOMOVE|NOSIZE|NOACTIVATE)` + re-resolve control rects before each real click.
   - The installer window was observed parked at `-32000,-32000` (minimized) *during* the window's presence while the user was actively using the machine; it self-restored and the install completed fine. Not a template bug.
   - Clicks occasionally process late (>2.5 s) when the UI thread is briefly busy at launch - test drivers must poll for page transitions instead of hard-waiting 2.5 s.

---

## 4. Build & Test Workflow

### Full production build
```powershell
cd C:\Users\Moha\Desktop\Projects\BatPlayer
npm run tauri build
# -> src-tauri\target\release\bundle\nsis\BatPlayer_<version>_x64-setup.exe
```
Tauri stages the template at `src-tauri\target\release\nsis\x64\installer.nsi` (adds BOM) and compiles from there.

### Fast splice+compile harness (no Rust build)
`scripts\installer\compile_prod.ps1` splices Tauri placeholder values (`defines`, `{{#each language_files}}` -> English/Arabic `!include`) from the last staged file into the repo template, writes it (+BOM) into the staging dir, and runs makensis in-place there (so `${__FILEDIR__}\..\..\..\..` resolves the assets). Output: `src-tauri\target\release\nsis\x64\nsis-output.exe` (34.7 MB). A pristine copy of the bundler's staged file is kept at `src-tauri\target\release\nsis\x64\installer.pre-splice.nsi` while it still holds placeholder tokens.

Remaining benign makensis warnings:
- `6155: !undef MUI_PAGE_CUSTOMFUNCTION_SHOW not defined` (page decl bookkeeping)
- `6010: install function "SkipIfPassive" not referenced` (stock; dead code in currentUser mode)

### Real-input test driver
`scripts\installer\real_click_test.ps1` uses **only real mouse input** (`SetCursorPos` + `mouse_event`) - no `PostMessage` shortcuts. It auto-resolves the newest `*-setup.exe` under `src-tauri\target\release\bundle\nsis` (or pass `-ExePath`) and writes screenshots to `%TEMP%\batplayer-installer-shots` (or `-ShotDir`). Phase list:
- `install` - fresh install: click Install Now -> wait progress -> wait finish -> click launch-label to toggle OFF -> click Finish -> assert closed + app NOT launched.
- `reinstallFull` - second run: Install Now -> Continue -> Finish (default ON) -> assert closed + batplayer launched & alive after 8 s.
- `reinstallX` / `welcomeX` / `finishX` - real-click X on that page -> assert closed.
- `probes` - control-tree dump + `WindowFromPoint`/foreground diagnostics (z-order debugging).

Between phases run `scripts\installer\reset_test_state.ps1` (kills processes, silent-uninstalls, clears `%LOCALAPPDATA%\BatPlayer`, uninstall registry keys, app-data dirs).

**Driver supports multiple phases run back-to-back:** install-phase leaves the registry state that reinstall phases depend on.

---

## 5. Verified (oct 24, real mouse input, shipping-equivalent exe)

| Flow | Step | Result |
| --- | --- | --- |
| Fresh install | `Install Now` click | PASS (advance 49-71 ms) |
| Fresh install | dark toggle flip (OFF) | PASS |
| Fresh install | `Finish` click | PASS - closed in 5-6 ms |
| Fresh install | app behavior (toggle OFF) | PASS - batplayer NOT launched |
| Reinstall | `Continue` click | PASS |
| Reinstall | `Finish` click (toggle ON) | PASS - closed in 7 ms |
| Reinstall | app behavior (toggle ON) | PASS - batplayer launched, alive after 8 s |
| X page | welcome | PASS - closed |
| X page | reinstall | PASS - closed |
| X page | finish | PASS - closed (ID-1 escape) |

Registry targets verified: `HKCU\Software\BatSoft\BatPlayer` (`MANUPRODUCTKEY`), `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\BatPlayer` (`UNINSTKEY`); files in `$LOCALAPPDATA\BatPlayer` (batplayer.exe, libmpv-2.dll, uninstall.exe).

---

## 6. File Inventory

- `src-tauri/nsis/installer.nsi` - production template (UTF-8, no BOM) with all fixes.
- `scripts/installer/compile_prod.ps1` - splice+compile harness (BOM-critical).
- `scripts/installer/real_click_test.ps1` - real-input driver (phases above).
- `scripts/installer/reset_test_state.ps1` - machine-state reset for tests.
- `scripts/installer/click_once.ps1`, `scripts/installer/get_controls_lib.ps1` - one-shot click / control-dump helpers.
- `scripts/installer/rect_tracer.ps1` - outer-window rect/state sampler (caught the -32000 minimize event).
- `scripts/installer/dump_tree.ps1` - full control tree dump (incl. hidden controls).
- `scripts/preview-welcome.ps1` + `scripts/welcome-preview.nsi` - welcome-page visual preview (compile + screenshot without installing).
- `scripts/generate-installer-art.ps1` - regenerates the installer bitmaps in `src-tauri/icons/` from `batplayer-logo-source.png` (theme tokens mirrored from `src/styles/variables.css`).
- `scripts/generate-windows-branding.ps1` - regenerates the Windows app icon/branding set.

The old `.installer-lab\` scratch dir (test exe copy, probe binaries, stale nsis, screenshots) was deleted and gitignored; the reusable scripts above live in `scripts/installer/` now, and test artifacts land in `%TEMP%` instead of the workspace.

### Critical reminder for template edits
Always write `src-tauri/nsis/installer.nsi` as **UTF-8 WITHOUT BOM**:
```powershell
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
```
Do NOT use editors/tools that inject a UTF-8 BOM - and remember direct makensis runs against a *BOM-less* file will mojibake the glyph characters.

---

## 7. File associations ("Open with" visibility, added v0.1.1)

Install and uninstall manage BatPlayer's shell visibility additively — the
extension's own **default value is never written**, so double-click stays with
the user's existing player and "Open with" can still list BatPlayer:

- `HKCU\Software\Classes\BatPlayer.Media` — ProgID (`DefaultIcon`,
  `shell\open\command` = `"…\batplayer.exe" "%1"`).
- `HKCU\Software\Classes\.<ext>\OpenWithProgids` — one value per extension,
  the list source of Explorer's "Open with" submenu.
- `HKCU\Software\BatSoft\BatPlayer\Capabilities` (+ per-ext `FileAssociations`)
  and the `HKCU\Software\RegisteredApplications` "BatPlayer" value — the pair
  Windows Settings ▸ "Default apps" and "Choose another app" enumerate.
- Uninstall removes: every `OpenWithProgids` value (and the ext key
  `/ifempty`), the ProgID, the `Capabilities` subtree and the
  `RegisteredApplications` value. **`Software\Classes\.ext` keys of other
  apps are never touched.** `!insertmacro UPDATEFILEASSOC` (SHChangeNotify)
  fires on both paths so Explorer refreshes without a logoff.
- The 23 registered extensions mirror `src/utils/media.ts` `MEDIA_EXTENSIONS`
  (what the player accepts) and `tauri.conf.json` `bundle.fileAssociations`
  (`ext` array — the MSI target's own registration). **Keep all three in
  sync** when a new format is added; the exact same list appears in
  `installer.nsi` as `AssocRegisterExt`/`AssocUnregisterExt` calls after the
  defines at the top of the template.

Post-install verification (read-only):
```powershell
powershell -ExecutionPolicy Bypass -File scripts\installer\probe_assoc.ps1
# 0 failure(s) expected; also confirms no default was taken over.
```
Verified 2026-10-24 on a fresh v0.1.1 install (all checks OK, `.mp4` default
still `PotPlayerMini64.MP4`) and after a silent uninstall (every association
surface deleted; foreign extension keys intact).
