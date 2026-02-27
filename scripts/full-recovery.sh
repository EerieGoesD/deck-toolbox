#!/usr/bin/env bash
set -euo pipefail
steam_dir="$HOME/.local/share/Steam"
backup_dir="$HOME/.local/share/Steam_backup"
ts="$(date +%Y%m%d-%H%M%S)"

echo "Steam Deck Recovery Script"
echo

# 1) Steam reset (rename Steam dir)
if [[ -e "$steam_dir" ]]; then
  if [[ -e "$backup_dir" ]]; then
    backup_dir="${backup_dir}_${ts}"
  fi
  echo "Renaming Steam directory:"
  echo "  $steam_dir -> $backup_dir"
  mv "$steam_dir" "$backup_dir"
else
  echo "Steam directory not found, skipping:"
  echo "  $steam_dir"
fi

echo

# 2) Gamescope reset (clear state/config)
echo "Clearing Gamescope state/config:"
rm -rf "$HOME/.local/state/gamescope" "$HOME/.config/gamescope"

echo
echo "Done."
echo "Recommended: reboot, then launch Steam (you will need to sign in again)."
