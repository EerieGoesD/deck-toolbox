# 🎮 Deck Toolbox

One-click maintenance and troubleshooting scripts for the Steam Deck.

![Electron](https://img.shields.io/badge/Electron-33-47848F?logo=electron) ![Platform](https://img.shields.io/badge/platform-Steam%20Deck%20%2F%20Linux-1a9fff)

## Features

| Button | What it does |
|---|---|
| **Generate .cue** | Creates MODE2/2352 `.cue` files for selected `.bin` disc images |
| **Weekly Maintenance** | Flatpak updates, journal vacuum, TRIM, temp/thumbnail cleanup, disk checks |
| **Reset Steam** | Renames `~/.local/share/Steam` → `Steam_backup` |
| **Reset Gamescope** | Deletes `~/.local/state/gamescope` and `~/.config/gamescope` |
| **Full Recovery** | Steam + Gamescope reset combined — fixes boot loops |

## Install & Run

```bash
git clone https://github.com/eeriegoesd/deck-toolbox.git
cd deck-toolbox
npm install
npm start
```

## Adding a Script

1. Drop a `.sh` in `scripts/`
2. Add `ipcMain.handle()` in `main.js`
3. Expose in `preload.js`
4. Add a `tool-card` in `index.html`

## Credits
Made by [EERIE](https://linktr.ee/eeriegoesd) · [☕ Buy Me a Coffee](https://buymeacoffee.com/eeriegoesd)
