# Deck Toolbox

One-click maintenance and troubleshooting scripts for the Steam Deck.

![Tauri](https://img.shields.io/badge/Tauri-2-24C8D8?logo=tauri) ![Rust](https://img.shields.io/badge/Rust-1.94-DEA584?logo=rust) ![Platform](https://img.shields.io/badge/platform-Steam%20Deck%20%2F%20Linux-1a9fff)

## Features

| Section | Button | What it does |
|---|---|---|
| **Utilities** | Generate .cue | Creates MODE2/2352 `.cue` files for selected `.bin` disc images |
| **Utilities** | Weekly Maintenance | Flatpak updates, journal vacuum, TRIM, temp/thumbnail cleanup, disk checks |
| **Resets** | Reset Steam | Renames `~/.local/share/Steam` to `Steam_backup` with option to delete backups |
| **Resets** | Reset Gamescope | Deletes `~/.local/state/gamescope` and `~/.config/gamescope` |
| **ROM Tools** | Duplicate ROM Finder | Scans for near-duplicate ROMs per console folder |
| **ROM Tools** | Find Lost ROMs | Finds ROM files outside standard EmuDeck directories |
| **ROM Tools** | ROM Size Sorter | Lists all ROMs sorted by size (largest first) |
| **ROM Tools** | Remove ROMs Metadata | Clears downloaded media and gamelist.xml files |
| **Storage** | Large File Finder | Finds the largest files and directories on the Deck |
| **Storage** | Deck Declutter | Removes known clutter files (old flatpaks, caches, etc.) |
| **Decky Loader** | Find Decky Leftovers | Searches for leftover Decky Loader files |
| **Decky Loader** | Uninstall Decky | Runs official uninstall script and cleans up leftovers |
| **Recovery** | Full Recovery | Steam + Gamescope reset combined - fixes boot loops |

## Install & Run

```bash
git clone https://github.com/eeriegoesd/deck-toolbox.git
cd deck-toolbox
cargo tauri dev
```

## Build for Release

```bash
cargo tauri build
```

The binary will be in `src-tauri/target/release/`.

## Adding a Script

1. Drop a `.sh` in `src-tauri/resources/scripts/`
2. Add a `#[tauri::command]` function in `src-tauri/src/commands/scripts.rs`
3. Register it in `src-tauri/src/lib.rs`
4. Add a `tool-card` in `src/index.html`

## Credits
Made by [EERIE](https://linktr.ee/eeriegoesd) - [Buy Me a Coffee](https://buymeacoffee.com/eeriegoesd)
