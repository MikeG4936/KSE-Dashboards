# Release packaging

Build end-user release archives from the following allowlist, preserving these repository-relative paths and capitalization. Include both dashboards so users can choose either; each dashboard folder remains independently installable under `/WIDGETS/`. The archive also contains desktop tools and documentation, so users should follow `README.md` rather than copy the entire archive to the SD card.

| Include | End-user purpose |
| --- | --- |
| `KSE4/main.lua`, `KSE5/main.lua` | Complete generated dashboards; no runtime dependency on `src/` or assembly tools. |
| `KSE4/default.png`, `KSE5/default.png` | Default model pictures. |
| `KSE4/default1.png`, `KSE5/default1.png` | Optional alternate pictures, selected by renaming as explained in the README. |
| In **each** of `KSE4/BatterySounds/` and `KSE5/BatterySounds/`: `0%.wav`, `10%.wav`, `20%.wav`, `30%.wav`, `40%.wav`, `50%.wav`, `dead.wav`, `fuel.wav` | Spoken battery warnings and Nitro fuel reminder. Keep all eight clips with each dashboard. |
| `README.md` | Installation, updating, settings, telemetry setup, troubleshooting and disclaimer. |
| `flights-count.csv` | Optional starter/example for local flight history, not a runtime prerequisite. Use only on a fresh setup; never overwrite an existing radio history file. |
| `theme-gallery/README.md`, `theme-gallery/index.html`, `theme-gallery/styles.css`, `theme-gallery/themes.js`, `theme-gallery/gallery.js`, `theme-gallery/assets/*.png` | Offline theme selection, including both preview sheets and all individual theme samples. |
| `tools/images/README.md`, `tools/images/KSE Image Resizer.html` | Documented offline browser tool for preparing model pictures. |
| `tools/images/resize_kse_images.py`, `tools/images/Resize KSE Images.bat`, `tools/images/Resize KSE Images.command` | Optional command-line/batch resizer and Windows/macOS launchers. Keep these three together; this alternative needs Python and Pillow, with internet access for the launchers' initial Pillow installation. |

Keep maintainer-only files out of the release: `AGENTS.md`, `.gitignore`, `src/`, `docs/`, `tests/`, `tools/assemble.py`, `tools/edgetx/`, `theme-gallery/generate_previews.py` and `theme-gallery/validate_gallery.py`. Include only the listed files under `tools/images/`, not virtual environments or resized user pictures. Exclude Git/editor/OS metadata, caches, compiled `main.luac`, personal flight histories and `.bak`/`.tmp` recovery files. Rotorflight's Lua package is a separately installed prerequisite for Rotorflight models; obtain it through the official release link in the README rather than bundling a local radio copy.

Before packaging, require `python3 tools/assemble.py --check` to pass. Check the staged archive against this allowlist, verify the README's local links and gallery assets resolve, and retain executable permission on the macOS `.command` launcher. Re-evaluate this list when runtime dependencies or end-user utilities change; a whole-repository ZIP is not the curated release package.
