#!/bin/bash
# Fix ROM Paths: find ROMs sitting in the wrong system folder, suggest the correct one (majority rule).
# Modes:
#   scan  - report misplaced files with the suggested destination
#   apply - move each flagged file to its suggested destination on the same disk
# Usage: fix_rom_paths.sh <mode> <root1> [root2] ...

MODE="${1:-scan}"
shift

if [[ "$MODE" != "scan" && "$MODE" != "apply" ]]; then
  echo "Invalid mode: $MODE (expected scan or apply)"
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

echo "=== Fix ROM Paths ($MODE) ==="
echo "Roots:"
for r in "${ROOTS[@]}"; do echo "  $r"; done
echo ""

# Skip these top folders (not ROM content) and these extensions (metadata/saves/scripts/images)
SKIP_TOPS_RE='^(emulators|cloud|desktop|store|tools|ports)$'
SKIP_EXTS_RE='\.(log|bak|tmp|old|srm|sav|save|state|st[0-9]|dat|cue|gdi|m3u|ccd|sub|sh|bat|cmd|ps1|txt|md|ini|cfg|conf|png|jpg|jpeg|gif|webp|bmp|svg|mp3|wav|ogg|mp4|webm|xml|json|yaml|yml|html|htm|csv|pat|ips|ups|bps|xdelta|exe|dll|so|lua|ps|filepart|part|crdownload|aria2)$'

# Pass 1: build per-(root,system) extension distribution
declare -A COUNT  # COUNT[root|sys|ext]=count
declare -A TOTAL  # TOTAL[root|sys]=total

scan_root() {
  local root="$1"
  [[ -d "$root" ]] || return
  while IFS=$'\t' read -r relpath; do
    [[ -z "$relpath" ]] && continue
    # Only files exactly at depth 2 (system/file)
    local sys="${relpath%%/*}"
    local rest="${relpath#*/}"
    [[ "$sys" == "$relpath" ]] && continue   # no slash, root-level file
    [[ "$rest" == */* ]] && continue         # deeper than system/file
    local sys_lc="${sys,,}"
    [[ "$sys_lc" =~ $SKIP_TOPS_RE ]] && continue
    local fname="${relpath##*/}"
    local fname_lc="${fname,,}"
    [[ "$fname_lc" == "metadata.txt" || "$fname_lc" == "systeminfo.txt" || "$fname_lc" == "gamelist.xml" ]] && continue
    # Extension
    local ext=""
    if [[ "$fname_lc" == *.* ]]; then
      ext=".${fname_lc##*.}"
    fi
    [[ -z "$ext" ]] && continue
    [[ "$ext" =~ $SKIP_EXTS_RE ]] && continue
    COUNT["$root|$sys_lc|$ext"]=$((${COUNT["$root|$sys_lc|$ext"]:-0} + 1))
    TOTAL["$root|$sys_lc"]=$((${TOTAL["$root|$sys_lc"]:-0} + 1))
  done < <(cd "$root" && find . -mindepth 2 -maxdepth 2 \( -type f -o -type l \) -printf '%P\n' 2>/dev/null)
}

for root in "${ROOTS[@]}"; do
  scan_root "$root"
done

# Pass 2: build canonical map: for each (root, ext), the folder where it is majority (>= 50%)
declare -A CANONICAL  # CANONICAL[root|ext]=sys (only if exactly one folder has majority)
for key in "${!COUNT[@]}"; do
  local_root="${key%%|*}"
  rest="${key#*|}"
  sys="${rest%%|*}"
  ext="${rest#*|}"
  c=${COUNT["$key"]}
  t=${TOTAL["$local_root|$sys"]:-1}
  share=$((c * 100 / t))
  if (( share >= 50 )); then
    if [[ -z "${CANONICAL["$local_root|$ext"]:-}" ]]; then
      CANONICAL["$local_root|$ext"]="$sys"
    else
      CANONICAL["$local_root|$ext"]="__MULTI__"
    fi
  fi
done

# Pass 3: walk every file again; flag misplaced ones; optionally move them
flagged=0
moved=0
failed=0
for root in "${ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  while IFS=$'\t' read -r relpath; do
    [[ -z "$relpath" ]] && continue
    sys="${relpath%%/*}"
    rest="${relpath#*/}"
    [[ "$sys" == "$relpath" ]] && continue
    [[ "$rest" == */* ]] && continue
    sys_lc="${sys,,}"
    [[ "$sys_lc" =~ $SKIP_TOPS_RE ]] && continue
    fname="${relpath##*/}"
    fname_lc="${fname,,}"
    [[ "$fname_lc" == "metadata.txt" || "$fname_lc" == "systeminfo.txt" || "$fname_lc" == "gamelist.xml" ]] && continue
    ext=""
    [[ "$fname_lc" == *.* ]] && ext=".${fname_lc##*.}"
    [[ -z "$ext" ]] && continue
    [[ "$ext" =~ $SKIP_EXTS_RE ]] && continue

    # Compute this file's extension share in its current folder
    c=${COUNT["$root|$sys_lc|$ext"]:-0}
    t=${TOTAL["$root|$sys_lc"]:-1}
    share=$((c * 100 / t))
    (( share >= 5 )) && continue                          # not rare enough
    [[ "$sys_lc" == "${ext#.}" ]] && continue              # folder name matches ext (eg .gb in gb/)

    target="${CANONICAL["$root|$ext"]:-}"
    [[ -z "$target" || "$target" == "__MULTI__" ]] && continue
    [[ "$target" == "$sys_lc" ]] && continue

    src="$root/$relpath"
    dst="$root/$target/$fname"

    if [[ "$MODE" == "scan" ]]; then
      echo "[misplaced] $root :: $sys/$fname -> $target/"
      flagged=$((flagged + 1))
    else
      if [[ -e "$dst" ]]; then
        echo "[skip] $relpath - destination already exists"
        failed=$((failed + 1))
        continue
      fi
      mkdir -p "$(dirname "$dst")"
      if mv -n "$src" "$dst"; then
        echo "[ok]   moved $sys/$fname -> $target/"
        moved=$((moved + 1))
      else
        echo "[fail] $sys/$fname mv failed"
        failed=$((failed + 1))
      fi
    fi
  done < <(cd "$root" && find . -mindepth 2 -maxdepth 2 \( -type f -o -type l \) -printf '%P\n' 2>/dev/null)
done

echo ""
if [[ "$MODE" == "scan" ]]; then
  echo "Flagged: $flagged"
else
  echo "Moved: $moved, Failed: $failed"
fi
