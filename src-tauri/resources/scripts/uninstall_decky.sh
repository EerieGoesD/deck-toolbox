#!/bin/bash
# Uninstalls Decky Loader and cleans up leftover files.
# Non-interactive version for Deck Toolbox GUI.
# https://github.com/SteamDeckHomebrew/decky-loader

echo "=== Uninstalling Decky Loader ==="
echo ""
curl -L https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/uninstall.sh | sh

echo ""
echo "=== Cleaning up leftovers ==="
echo ""

TARGETS=(
  "/home/deck/homebrew/services"
  "/home/deck/homebrew/logs"
  "/home/deck/homebrew/settings/loader.json"
  "/home/deck/homebrew/plugins/decky-plugin-template"
  "/home/deck/homebrew/data/decky-plugin-template"
  "/home/deck/homebrew/settings/decky-plugin-template"
  "/etc/previous/systemd/system/plugin_loader.service"
  "/etc/previous/systemd/system/multi-user.target.wants/plugin_loader.service"
)

found=false
for path in "${TARGETS[@]}"; do
  if [ -e "$path" ]; then
    found=true
    if [ -d "$path" ]; then
      size=$(du -sh "$path" 2>/dev/null | cut -f1)
      echo "  [$size]  $path/"
    else
      size=$(du -h "$path" 2>/dev/null | cut -f1)
      echo "  [$size]  $path"
    fi
  fi
done

if ! $found; then
  echo "No leftovers found."
  exit 0
fi

echo ""
echo "Deleting leftovers..."

for path in "${TARGETS[@]}"; do
  if [ -e "$path" ]; then
    sudo rm -rf "$path"
    echo "  Deleted: $path"
  fi
done

echo ""
echo "Decky Loader fully removed."
