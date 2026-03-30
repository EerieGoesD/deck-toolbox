#!/bin/bash
# Scans all ROM directories and lists ROMs sorted by size (largest to smallest).
# Usage: rom_size_sorter.sh [count] (default: show all)

count="${1:-}"

ROMS_DIRS=(
  "/home/deck/Emulation/roms"
  "/run/media/deck/EmuDeck/Emulation/roms"
)

echo "=== ROM Size Sorter ==="
echo ""
echo "ROM directories:"
for dir in "${ROMS_DIRS[@]}"; do
  echo "  $dir"
done
echo ""

# Check that at least one directory exists
found_dir=false
for dir in "${ROMS_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    found_dir=true
    break
  fi
done

if ! $found_dir; then
  echo "No ROM directories found. Make sure at least one of the above paths exists."
  exit 1
fi

echo "Scanning ROMs... (this may take a moment)"
echo ""

results=$(
  for dir in "${ROMS_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      find "$dir" -type f -print0 2>/dev/null
    fi
  done | xargs -0 du -h 2>/dev/null | sort -rh
)

total=$(echo "$results" | wc -l)

if [[ -z "$results" ]]; then
  echo "No ROM files found."
  exit 0
fi

echo "=== ROMs by size (largest first) ==="
echo ""

if [[ -z "$count" || "$count" =~ ^[Aa](ll)?$ ]]; then
  echo "$results"
  echo ""
  echo "Showing all $total ROM files."
else
  echo "$results" | head -"$count"
  echo ""
  shown=$((count < total ? count : total))
  echo "Showing top $shown of $total ROM files."
fi
