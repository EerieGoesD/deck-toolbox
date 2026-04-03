# Deck Toolbox

One-click maintenance and troubleshooting scripts for the Steam Deck.

![Tauri](https://img.shields.io/badge/Tauri-2-24C8D8?logo=tauri) ![Platform](https://img.shields.io/badge/platform-Steam%20Deck-1a9fff) ![Size](https://img.shields.io/badge/size-2.3%20MB-green)

## What is this?

Deck Toolbox is a lightweight desktop app for the Steam Deck that gives you one-click access to common maintenance, troubleshooting, and cleanup tasks. No terminal needed - just open the app, pick a tool, and click Run.

## Install

1. Download **DeckToolbox.flatpak** from [Releases](https://github.com/EerieGoesD/deck-toolbox/releases/latest)
2. Open your Steam Deck in **Desktop Mode**
3. **Double-click** the downloaded file
4. Discover will open - click **Install**
5. Launch from your application menu

To uninstall, open Discover, find Deck Toolbox, and click Uninstall.

## Features

| Category | Tool | What it does |
|---|---|---|
| **Utilities** | Generate .cue | Creates MODE2/2352 `.cue` files for selected `.bin` disc images |
| **Utilities** | Weekly Maintenance | Flatpak updates, journal vacuum, TRIM, temp/thumbnail cleanup, disk checks |
| **Resets** | Reset Steam | Renames Steam directory to backup - fixes boot loops |
| **Resets** | Reset Gamescope | Clears Gamescope state and config - fixes display glitches and boot loops |
| **ROM Tools** | Duplicate ROM Finder | Scans for near-duplicate ROMs with option to delete selected duplicates |
| **ROM Tools** | Find Lost ROMs | Finds ROM files outside standard EmuDeck directories |
| **ROM Tools** | ROM Size Sorter | Lists all ROMs sorted by size (largest first) |
| **ROM Tools** | Remove ROMs Metadata | Clears downloaded media and gamelist.xml files |
| **Storage** | Large File Finder | Finds the largest files and directories on the Deck |
| **Storage** | Deck Declutter | Removes known clutter files (old flatpaks, caches, etc.) |
| **Decky Loader** | Find Decky Leftovers | Searches for leftover Decky Loader files after uninstall |
| **Decky Loader** | Uninstall Decky | Runs official uninstall script and cleans up leftovers |
| **Recovery** | Full Recovery | Steam + Gamescope reset combined - fixes boot loops |

## Community

Made by [EERIE](https://linktr.ee/eeriegoesd)

- [Buy Me a Coffee](https://buymeacoffee.com/eeriegoesd)
- Have a question? Join the [Discussions](https://github.com/EerieGoesD/deck-toolbox/discussions)
- Found a bug? Report it via [Issues](https://github.com/EerieGoesD/deck-toolbox/issues)
- Want a new script added? Submit a [Feature Request](https://github.com/EerieGoesD/deck-toolbox/issues/new?template=feature-request.md)
