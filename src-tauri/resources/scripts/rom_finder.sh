#!/bin/bash
# ROM Finder: search for ROM files across the configured ROM roots and print where each one lives.
# Usage: rom_finder.sh <search_term> [path1] [path2] ...

SEARCH="$1"
shift

if [[ -z "$SEARCH" ]]; then
  echo "No search term provided."
  exit 1
fi

if (( $# > 0 )); then
  ROOTS=("$@")
else
  ROOTS=(
    "/home/deck/Emulation/roms"
    "/run/media/deck/EmuDeck/Emulation/roms"
  )
fi

echo "=== ROM Finder ==="
echo "Search:  $SEARCH"
echo "Roots:"
for r in "${ROOTS[@]}"; do echo "  $r"; done
echo ""

found=0
for root in "${ROOTS[@]}"; do
  if [[ ! -d "$root" ]]; then
    continue
  fi
  # Case-insensitive substring match on path. -L follows symlinks so the match resolves to the real size.
  while IFS=$'\t' read -r kind size path target; do
    [[ -z "$path" ]] && continue
    found=$((found + 1))
    # Pretty-print size
    if (( size < 1024 )); then human="${size} B"
    elif (( size < 1024 * 1024 )); then human="$(awk -v b="$size" 'BEGIN{printf "%.1f KB", b/1024}')"
    elif (( size < 1024 * 1024 * 1024 )); then human="$(awk -v b="$size" 'BEGIN{printf "%.1f MB", b/(1024*1024)}')"
    else human="$(awk -v b="$size" 'BEGIN{printf "%.2f GB", b/(1024*1024*1024)}')"
    fi
    if [[ "$kind" == "l" ]]; then
      echo "[symlink] $path  ($human)"
      echo "          -> $target"
    else
      echo "[real]    $path  ($human)"
    fi
  done < <(find "$root" \( -type f -o -type l \) -iname "*${SEARCH}*" -printf '%y\t%s\t%p\t%l\n' 2>/dev/null)
done

echo ""
echo "Found $found match(es)."
