# BatPlayer — agent rules

## "Create a release" procedure

When the user asks for a release ("create a release", "make a release",
"publish a release", "release it" ...), run exactly this pipeline —
do not invent alternate steps and do not publish with `gh` locally:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\publish-release.ps1
```

Optional flags: `-SkipBuild` (reuse the newest existing bundle),
`-NoPublish` (dry run: place the files, no commit/push), `-Notes "..."`.

What the script does:

1. `npm run tauri build` — releases the **NSIS installer** bundle
   (`src-tauri\target\release\bundle\nsis\*-setup.exe`). The release artifact
   is the installer, never the bare `target\release\batplayer.exe`
   (the latter needs `libmpv-2.dll` next to it to run).
2. Copies it to **`C:\Users\Moha\Desktop\Projects\BatPack\Releases\BatPlayer.exe`**
   — renamed to exactly `BatPlayer.exe`.
3. Writes `Releases\BatPlayer.json` next to it: app, version (from
   `package.json`), sha256, size, builtAt, notes.
4. Commits + pushes those files to the BatSoft repo
   (`C:\Users\Moha\Desktop\Projects\BatPack`, remote
   `https://github.com/DgharMohamed/BatSoft.git`, default branch `main`).
5. The BatSoft workflow `.github\workflows\publish-release.yml` picks the push
   up, verifies the SHA-256 against the metadata, and creates the GitHub
   Release: tag `batplayer-v<version>`, title `BatPlayer v<version>`, the exe
   as the asset, checksum in the notes. Confirm by watching
   <https://github.com/DgharMohamed/BatSoft/actions> and report the release URL
   <https://github.com/DgharMohamed/BatSoft/releases/tag/batplayer-v<version>>.

Version discipline — a re-release of an already-published version FAILS on
purpose. Before releasing again, bump the version in **all three** places:
`package.json`, `src-tauri\tauri.conf.json`, `src-tauri\Cargo.toml`
(`Cargo.lock` follows).

## Repo notes

- `src-tauri/nsis/installer.nsi` must stay UTF-8 **without BOM**; read
  `INSTALLER_STATUS.md` before touching the installer.
- Do not resurrect `.installer-lab\` (gitignored scratch dir); the keeper
  scripts live in `scripts\installer\`.
