#!/usr/bin/env bash
set -euo pipefail
steam_dir="$HOME/.local/share/Steam"
backup_dir="$HOME/.local/share/Steam_backup"
ts="$(date +%Y%m%d-%H%M%S)"

if [[ -e "$steam_dir" ]]; then
  if [[ -e "$backup_dir" ]]; then
    backup_dir="${backup_dir}_${ts}"
  fi
  echo "Renaming Steam directory:"
  echo "  $steam_dir -> $backup_dir"
  mv "$steam_dir" "$backup_dir"
  echo "Done. Steam will re-create its directory on next launch."
else
  echo "Steam directory not found: $steam_dir"
  exit 1
fi
