#!/bin/bash
# Uninstalls Decky Loader and cleans up leftover files.
# Non-interactive version for Deck Toolbox GUI.
# https://github.com/SteamDeckHomebrew/decky-loader

echo "=== Uninstalling Decky Loader ==="
echo ""
# Run the official script from a file through our sudo. Piping it into sh
# makes it re-run itself with the real sudo, which has no way to get the password.
UNINSTALLER="$(mktemp)"
if ! curl -fL https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/uninstall.sh -o "$UNINSTALLER"; then
  echo "Could not download the Decky uninstall script." >&2
  rm -f "$UNINSTALLER"
  exit 1
fi
sudo sh "$UNINSTALLER"
rm -f "$UNINSTALLER"

echo ""
echo "=== Cleaning up leftovers ==="
echo ""

# Everything Decky Loader installs, including its plugins and their settings.
# find_decky_leftovers.sh checks this same list, so keep the two in sync.
TARGETS=(
  "/home/deck/homebrew"
  "/home/deck/.local/share/decky"
  "/home/deck/.config/decky"
  "/home/deck/.config/systemd/user/plugin_loader.service"
  "/home/deck/.steam/steam/.cef-enable-remote-debugging"
  "/home/deck/.var/app/com.valvesoftware.Steam/data/Steam/.cef-enable-remote-debugging"
  "/etc/systemd/system/plugin_loader.service"
  "/etc/systemd/system/multi-user.target.wants/plugin_loader.service"
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
