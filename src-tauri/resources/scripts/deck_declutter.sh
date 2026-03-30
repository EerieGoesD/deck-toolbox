#!/bin/bash
# Removes known clutter files from the Steam Deck.
# Non-interactive version for Deck Toolbox GUI.

TARGETS=(
  "/home/deck/fresh.flatpak"
  "/home/deck/com.eerie.readervaultpro.flatpak"
  "/home/deck/Applications/ES-DE.AppImage_3.3.0.OLD"
  "/home/deck/deck-toolbox/.flatpak-builder"
  "/home/deck/yay/src/gopath/pkg/mod/cache"
  "/home/deck/.cache/go-build"
  "/home/deck/.local/share/ULWGL/ULWGL-launcher.tar.gz"
  "/home/deck/.cache/winetricks/directx9"
  "/run/media/deck/EmuDeck/Emulation/bios/Citron-0.7.1-anylinux-x86_64.AppImage"
)

echo "=== Steam Deck Declutter ==="
echo ""

# Show what was found
found=()
for path in "${TARGETS[@]}"; do
  if [ -e "$path" ]; then
    found+=("$path")
    if [ -d "$path" ]; then
      size=$(du -sh "$path" 2>/dev/null | cut -f1)
      echo "  [$size]  $path/"
    else
      size=$(du -h "$path" 2>/dev/null | cut -f1)
      echo "  [$size]  $path"
    fi
  fi
done

if (( ${#found[@]} == 0 )); then
  echo "No clutter found."
  exit 0
fi

echo ""

deleted=0
for path in "${found[@]}"; do
  rm -rf "$path"
  echo "  Deleted: $path"
  ((deleted++))
done

echo ""
echo "Deleted $deleted item(s)."
