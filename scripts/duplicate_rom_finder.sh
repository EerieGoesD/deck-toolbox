#!/bin/bash
# Finds duplicate ROM files within each console folder and shows their locations.
# Usage: duplicate_rom_finder.sh [path1] [path2] ...
# Uses normalized filenames (stripped of all punctuation, case-insensitive)
# to catch near-duplicates. Only flags duplicates within the same console folder.

if (( $# > 0 )); then
  ROMS_DIRS=("$@")
else
  ROMS_DIRS=("/run/media/EmuDeck/Emulation/roms")
fi

found_any=false
for d in "${ROMS_DIRS[@]}"; do
  if [[ -d "$d" ]]; then found_any=true; break; fi
done

if ! $found_any; then
  echo "No ROM directories found:"
  for d in "${ROMS_DIRS[@]}"; do echo "  $d"; done
  exit 1
fi

total_dupes=0

for ROMS_DIR in "${ROMS_DIRS[@]}"; do
[[ ! -d "$ROMS_DIR" ]] && continue
for console_dir in "$ROMS_DIR"/*/; do
  console=$(basename "$console_dir")
  declare -A seen=()

  while IFS= read -r filepath; do
    filename="${filepath##*/}"
    norm=$(echo "$filename" | tr '[:upper:]' '[:lower:]' | sed "s/[^a-z0-9]//g")
    seen["$norm"]+="$filepath"$'\n'
  done < <(find "$console_dir" -type f \( -name "*.7z" -o -name "*.zip" -o -name "*.chd" -o -name "*.iso" -o -name "*.bin" -o -name "*.cue" \))

  for norm in "${!seen[@]}"; do
    deduped=$(echo -n "${seen[$norm]}" | sort -u)
    count=$(echo -n "$deduped" | grep -c '^')
    if (( count > 1 )); then
      echo "=== [$console] Possible duplicates (normalized: $norm) ==="
      echo "$deduped"
      echo ""
      ((total_dupes++))
    fi
  done

  unset seen
done
done

if (( total_dupes == 0 )); then
  echo "No duplicate ROMs found."
fi
