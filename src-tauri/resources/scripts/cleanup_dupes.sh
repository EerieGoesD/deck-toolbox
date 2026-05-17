#!/bin/bash
# Cleanup ROMs: find files that are REAL on BOTH disks (left over from interrupted rebalance).
# Modes:
#   scan  - report duplicates, do not delete
#   apply - delete the INTERNAL copy when sizes match (SD side kept because ES-DE scans SD)
# Usage: cleanup_dupes.sh <mode> <internal_root> <sd_root>

MODE="${1:-scan}"
INTERNAL="${2:-/home/deck/Emulation/roms}"
SD="${3:-/run/media/deck/EmuDeck/Emulation/roms}"

if [[ "$MODE" != "scan" && "$MODE" != "apply" ]]; then
  echo "Invalid mode: $MODE (expected scan or apply)"
  exit 1
fi

echo "=== Cleanup Duplicate ROMs ($MODE) ==="
echo "Internal: $INTERNAL"
echo "SD:       $SD"
echo ""

if [[ ! -d "$INTERNAL" || ! -d "$SD" ]]; then
  echo "Both roots must exist."
  exit 1
fi

# Find files (NOT symlinks) under each root, store as relative_path<TAB>size
tmp_internal=$(mktemp)
tmp_sd=$(mktemp)
trap "rm -f \"$tmp_internal\" \"$tmp_sd\"" EXIT

(cd "$INTERNAL" && find . -type f -printf '%p\t%s\n' 2>/dev/null | sed 's|^\./||') | sort > "$tmp_internal"
(cd "$SD"       && find . -type f -printf '%p\t%s\n' 2>/dev/null | sed 's|^\./||') | sort > "$tmp_sd"

# Join on relative path, keep entries where both sides have a real file AND sizes match
dup_count=0
total_bytes=0
ok_count=0
fail_count=0

while IFS=$'\t' read -r relpath size_i size_s; do
  [[ -z "$relpath" ]] && continue
  if [[ "$size_i" != "$size_s" ]]; then
    echo "[skip] $relpath  (size mismatch internal=$size_i sd=$size_s)"
    continue
  fi
  dup_count=$((dup_count + 1))
  total_bytes=$((total_bytes + size_i))
  if [[ "$MODE" == "scan" ]]; then
    echo "[dupe] $relpath  ($size_i bytes)"
  else
    src="$INTERNAL/$relpath"
    if [[ ! -f "$src" || -L "$src" ]]; then
      echo "[fail] $relpath - source no longer a regular file"
      fail_count=$((fail_count + 1))
      continue
    fi
    actual=$(stat -c '%s' "$src" 2>/dev/null)
    if [[ "$actual" != "$size_i" ]]; then
      echo "[fail] $relpath - size changed since scan (now $actual)"
      fail_count=$((fail_count + 1))
      continue
    fi
    if rm -f "$src"; then
      echo "[ok]   removed internal/$relpath"
      ok_count=$((ok_count + 1))
    else
      echo "[fail] $relpath - rm failed"
      fail_count=$((fail_count + 1))
    fi
  fi
done < <(join -t $'\t' "$tmp_internal" "$tmp_sd")

echo ""
gb=$(awk -v b="$total_bytes" 'BEGIN{printf "%.2f", b/(1024*1024*1024)}')
echo "Exact-path duplicates: $dup_count ($gb GB wasted on internal storage)"
if [[ "$MODE" == "apply" ]]; then
  echo "Cleaned: $ok_count, Failed: $fail_count"
fi

# Second pass: report cross-format duplicates (same stem, different extension).
# Example: snes/Mario.zip and snes/Mario.7z living together. Reported only;
# auto-delete is unsafe here because we cannot guess which format the user wants.
echo ""
echo "=== Cross-format duplicates (same game, different extension) ==="
echo "(Read-only report. Pick which to delete manually.)"
echo ""

# Build a list of (system, normalized_stem, disk_label, abs_path, size) for every regular file
# at exactly depth 2 (system/file) under both roots.
tmp_all=$(mktemp)
trap "rm -f \"$tmp_internal\" \"$tmp_sd\" \"$tmp_all\"" EXIT

emit_for_root() {
  local label="$1" root="$2"
  [[ ! -d "$root" ]] && return
  # Saves, emulator configs, scripts, executables, metadata - never count as ROMs.
  local skip_re='^\.(log|bak|tmp|old|srm|sav|save|state|st[0-9]|dat|cue|gdi|m3u|ccd|sub|sh|bat|cmd|ps1|txt|md|ini|cfg|conf|png|jpg|jpeg|gif|webp|bmp|svg|mp3|wav|ogg|mp4|webm|xml|json|yaml|yml|html|htm|csv|pat|ips|ups|bps|xdelta|exe|dll|so|lua|ps|filepart|part|crdownload|aria2)$'
  while IFS=$'\t' read -r rel sz; do
    [[ -z "$rel" ]] && continue
    local sys="${rel%%/*}"
    local fname="${rel##*/}"
    local sys_lc="${sys,,}"
    case "$sys_lc" in
      emulators|cloud|desktop|store|tools|ports) continue ;;
    esac
    local stem="${fname%.*}"
    [[ "$stem" == "$fname" ]] && continue
    local ext_lc=".${fname##*.}"
    ext_lc="${ext_lc,,}"
    [[ "$ext_lc" =~ $skip_re ]] && continue
    local fname_lc="${fname,,}"
    [[ "$fname_lc" == "metadata.txt" || "$fname_lc" == "systeminfo.txt" || "$fname_lc" == "gamelist.xml" ]] && continue
    local norm
    norm=$(echo "$stem" | tr '[:upper:]' '[:lower:]' | sed "s/[^a-z0-9]//g")
    [[ -z "$norm" ]] && continue
    printf "%s\t%s\t%s\t%s\t%s\n" "$sys_lc" "$norm" "$label" "$root/$rel" "$sz"
  done < <(cd "$root" && find . -mindepth 2 -maxdepth 2 -type f -printf '%P\t%s\n' 2>/dev/null)
}

emit_for_root "internal" "$INTERNAL" > "$tmp_all"
emit_for_root "sd"       "$SD"       >> "$tmp_all"

# Sort by (system, stem) and stream-group. A group is reported when it has at least 2
# rows AND at least 2 distinct extensions.
cross_groups=0
sort -t $'\t' -k1,1 -k2,2 "$tmp_all" | awk -F'\t' '
function flush(   i, exts_seen, parts, ext, distinct) {
  if (n > 1) {
    distinct = 0
    delete exts_seen
    for (i = 1; i <= n; i++) {
      split(rows[i], parts, "\t")
      ext = ""
      if (match(parts[4], /\.[^./]+$/)) ext = tolower(substr(parts[4], RSTART, RLENGTH))
      if (!(ext in exts_seen)) { exts_seen[ext] = 1; distinct++ }
    }
    if (distinct > 1) {
      groups_found++
      split(rows[1], parts, "\t")
      print "  [" parts[1] "] " parts[2]
      for (i = 1; i <= n; i++) {
        split(rows[i], parts, "\t")
        printf "    (%s) %s  (%s bytes)\n", parts[3], parts[4], parts[5]
      }
      print ""
    }
  }
  delete rows; n = 0
}
{
  key = $1 "\t" $2
  if (key != prev && NR > 1) flush()
  rows[++n] = $0
  prev = key
}
END {
  flush()
  print "Cross-format groups found: " (groups_found + 0)
}
'

