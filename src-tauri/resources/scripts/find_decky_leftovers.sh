#!/bin/bash
# Searches the Steam Deck for leftover Decky Loader files after uninstall.

echo "Searching for Decky Loader leftovers..."
echo ""

found=0

print_result() {
  local path="$1"
  if (( found == 0 )); then
    echo "=== Decky Loader leftovers found ==="
  fi
  if [ -d "$path" ]; then
    size=$(du -sh "$path" 2>/dev/null | cut -f1)
    echo "  [$size]  $path/"
  else
    size=$(du -h "$path" 2>/dev/null | cut -f1)
    echo "  [$size]  $path"
  fi
  ((found++))
}

# Everything Decky Loader installs. uninstall_decky.sh deletes this same list,
# so keep the two in sync.
KNOWN_PATHS=(
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

# Files with "decky" in the name that belong to other software, not Decky
NOT_DECKY=(
  "/home/deck/.config/EmuDeck"
  "/home/deck/Emulation"
  "/home/deck/.cache/deck-toolbox"
  "/home/deck/.var/app/io.github.EerieGoesD.DeckToolbox"
  "/home/deck/.local/share/flatpak/app/io.github.EerieGoesD.DeckToolbox"
  "/home/deck/Documents/GitHub/deck-toolbox"
  "/home/deck/Documents/GitHub/steam-deck-utility-scripts"
)

for path in "${KNOWN_PATHS[@]}"; do
  if [ -e "$path" ]; then
    print_result "$path"
  fi
done

# Anything else named after Decky or its service, skipping the paths above
prune=()
for path in "${KNOWN_PATHS[@]}" "${NOT_DECKY[@]}"; do
  prune+=(-path "$path" -o)
done
unset 'prune[${#prune[@]}-1]'

while IFS= read -r file; do
  print_result "$file"
done < <(find /home/deck /etc /tmp \( "${prune[@]}" \) -prune -o \
  \( -iname "*decky*" -o -iname "*plugin_loader*" \) -print 2>/dev/null)

if (( found == 0 )); then
  echo "No Decky Loader leftovers found. Clean uninstall!"
else
  echo ""
  echo "Found $found leftover(s)."
fi
