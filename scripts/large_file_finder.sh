#!/bin/bash
# Finds the largest files and directories on the Steam Deck, sorted by size.
# Usage: large_file_finder.sh [exclude_roms: y/n] [mode: 1=files/2=dirs/3=both] [count]

exclude_roms="${1:-n}"
mode="${2:-3}"
count="${3:-50}"

ROMS_DIRS=(
  "/home/deck/Emulation/roms"
  "/run/media/deck/EmuDeck/Emulation/roms"
)

if [[ "$exclude_roms" =~ ^[Yy]$ ]]; then
  echo "Excluding ROMs directories from results."
else
  echo "Including ROMs directories in results."
fi

echo "Mode: $([ "$mode" = "1" ] && echo "files only" || ([ "$mode" = "2" ] && echo "directories only" || echo "both"))"
echo "Showing top $count results."
echo ""
echo "Scanning... (this may take a moment)"
echo ""
echo "=== Largest items ==="
echo ""

# Build prune args for find/du
PRUNE_ARGS=()
if [[ "$exclude_roms" =~ ^[Yy]$ ]]; then
  for dir in "${ROMS_DIRS[@]}"; do
    PRUNE_ARGS+=(-path "$dir" -prune -o)
  done
fi

case "$mode" in
  1)
    find /home/deck /run/media/deck "${PRUNE_ARGS[@]}" -type f -print0 2>/dev/null \
      | xargs -0 du -h 2>/dev/null \
      | sort -rh | head -"$count"
    ;;
  2)
    {
      for dir in /home/deck /run/media/deck; do
        if [[ "$exclude_roms" =~ ^[Yy]$ ]]; then
          du -h --max-depth=3 "$dir" 2>/dev/null | grep -Ev "$(printf '%s|' "${ROMS_DIRS[@]}" | sed 's/|$//')"
        else
          du -h --max-depth=3 "$dir" 2>/dev/null
        fi
      done
    } | sort -rh | head -"$count"
    ;;
  *)
    {
      if [[ "$exclude_roms" =~ ^[Yy]$ ]]; then
        du -ah /home/deck /run/media/deck 2>/dev/null | grep -Ev "$(printf '%s|' "${ROMS_DIRS[@]}" | sed 's/|$//')"
      else
        du -ah /home/deck /run/media/deck 2>/dev/null
      fi
    } | sort -rh | head -"$count"
    ;;
esac
