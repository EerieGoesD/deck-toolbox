#!/bin/bash
# Rebalance ROMs: balance disk usage between internal and SD card by moving real files
# in both directions (smart picker, symlink-aware, ES-DE friendly).
# Modes:
#   scan  - report the plan only (read-only)
#   apply - execute the plan
# Strategies:
#   largest  - move the largest real files first (faster, fewer moves) [default]
#   smallest - move the smallest real files first (slower, finer balance)
# Threshold:
#   Percentage-point gap between the two disks' % used below which they are considered
#   already balanced and no plan is produced. Default 2.
# Usage: rebalance_roms.sh <mode> <internal_root> <sd_root> [strategy] [threshold]

set -uo pipefail

MODE="${1:-scan}"
INTERNAL="${2:-/home/deck/Emulation/roms}"
SD="${3:-/run/media/deck/EmuDeck/Emulation/roms}"
STRATEGY="${4:-largest}"
THRESHOLD_PCT="${5:-2}"

if [[ "$MODE" != "scan" && "$MODE" != "apply" ]]; then
  echo "Invalid mode: $MODE (expected scan or apply)"
  exit 1
fi
if [[ "$STRATEGY" != "largest" && "$STRATEGY" != "smallest" ]]; then
  echo "Invalid strategy: $STRATEGY (expected largest or smallest)"
  exit 1
fi
if ! [[ "$THRESHOLD_PCT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Invalid threshold: $THRESHOLD_PCT (expected a non-negative number, e.g. 2 or 1.5)"
  exit 1
fi

echo "=== Rebalance ROMs ($MODE) ==="
echo "Internal: $INTERNAL"
echo "SD:       $SD"

if [[ ! -d "$INTERNAL" || ! -d "$SD" ]]; then
  echo "Both roots must exist."
  exit 1
fi

# Disk usage (bytes). df --output=size,used returns 1K blocks; -B1 returns bytes.
read i_total i_used <<<"$(df -B1 --output=size,used "$INTERNAL" | tail -1)"
read s_total s_used <<<"$(df -B1 --output=size,used "$SD" | tail -1)"
i_free=$((i_total - i_used))
s_free=$((s_total - s_used))

# Compute net target and direction. Solve for x s.t. final % free equal.
#   if internal is more crowded: x bytes move internal->SD
#     x = (T_i * F_s - T_s * F_i) / (T_s + T_i)
i_free_pct=$(awk -v f="$i_free" -v t="$i_total" 'BEGIN{printf "%.4f", f/t}')
s_free_pct=$(awk -v f="$s_free" -v t="$s_total" 'BEGIN{printf "%.4f", f/t}')
pct_diff=$(awk -v a="$i_free_pct" -v b="$s_free_pct" 'BEGIN{d=a-b; if(d<0)d=-d; printf "%.4f", d*100}')

if (( $(echo "$i_free_pct < $s_free_pct" | bc -l) )); then
  PRIMARY="to_sd"
  net=$(awk -v ti="$i_total" -v fs="$s_free" -v ts="$s_total" -v fi="$i_free" 'BEGIN{printf "%.0f", (ti*fs - ts*fi) / (ts + ti)}')
else
  PRIMARY="to_internal"
  net=$(awk -v ts="$s_total" -v fi="$i_free" -v ti="$i_total" -v fs="$s_free" 'BEGIN{printf "%.0f", (ts*fi - ti*fs) / (ts + ti)}')
fi
[[ -z "$net" || "$net" -lt 0 ]] && net=0

echo "Internal used: $(awk -v b="$i_used" 'BEGIN{printf "%.2f GB", b/(1024^3)}') / $(awk -v b="$i_total" 'BEGIN{printf "%.2f GB", b/(1024^3)}')"
echo "SD used:       $(awk -v b="$s_used" 'BEGIN{printf "%.2f GB", b/(1024^3)}') / $(awk -v b="$s_total" 'BEGIN{printf "%.2f GB", b/(1024^3)}')"
echo "Net target:    $(awk -v b="$net" 'BEGIN{printf "%.2f GB", b/(1024^3)}')  Direction: $PRIMARY  Pct diff: ${pct_diff}%"

# Balance threshold: skip if net < 500 MB OR pct diff < $THRESHOLD_PCT percentage points
THRESHOLD=$((500 * 1024 * 1024))
if (( net < THRESHOLD )) || (( $(echo "$pct_diff < $THRESHOLD_PCT" | bc -l) )); then
  echo ""
  echo "Disks already balanced (net target below 500 MB or % difference below $THRESHOLD_PCT)."
  exit 0
fi

primary_budget=$(awk -v n="$net" 'BEGIN{printf "%.0f", n*1.3}')
reverse_budget=$(awk -v n="$net" 'BEGIN{printf "%.0f", n*0.3}')

# Skip rules same as Fix ROM Paths
SKIP_TOPS_RE='^(emulators|cloud|desktop|store|tools|ports)$'
SKIP_EXTS_RE='\.(log|bak|tmp|old|srm|sav|save|state|st[0-9]|dat|cue|gdi|m3u|ccd|sub|sh|bat|cmd|ps1|txt|md|ini|cfg|conf|png|jpg|jpeg|gif|webp|bmp|svg|mp3|wav|ogg|mp4|webm|xml|json|yaml|yml|html|htm|csv|pat|ips|ups|bps|xdelta|exe|dll|so|lua|ps|filepart|part|crdownload|aria2|bin|img|iso)$'

# Returns relpath<TAB>size for real files at depth 2 under $1 that pass the skip filter.
list_real_candidates() {
  local root="$1"
  cd "$root" || return
  find . -mindepth 2 -maxdepth 2 -type f -not -type l -printf '%P\t%s\n' 2>/dev/null | while IFS=$'\t' read -r rel sz; do
    [[ -z "$rel" ]] && continue
    local sys="${rel%%/*}"; local rest="${rel#*/}"
    [[ "$sys" == "$rel" ]] && continue
    [[ "$rest" == */* ]] && continue
    local sys_lc="${sys,,}"; [[ "$sys_lc" =~ $SKIP_TOPS_RE ]] && continue
    local fname="${rel##*/}"; local fn_lc="${fname,,}"
    [[ "$fn_lc" == "metadata.txt" || "$fn_lc" == "systeminfo.txt" || "$fn_lc" == "gamelist.xml" ]] && continue
    local ext=""; [[ "$fn_lc" == *.* ]] && ext=".${fn_lc##*.}"
    [[ -z "$ext" ]] && continue
    [[ "$ext" =~ $SKIP_EXTS_RE ]] && continue
    echo -e "$rel\t$sz"
  done
}

# Build a set of "exists as real on $2" relpaths (for collision filtering)
build_real_set() {
  local root="$1"
  (cd "$root" && find . -mindepth 2 -maxdepth 2 -type f -not -type l -printf '%P\n' 2>/dev/null) | sort -u
}

real_on_internal=$(build_real_set "$INTERNAL")
real_on_sd=$(build_real_set "$SD")

# Primary-direction picks: real on source, NOT real on destination, ordered by STRATEGY.
if [[ "$PRIMARY" == "to_sd" ]]; then
  src_root="$INTERNAL"; dst_root="$SD"; dst_set="$real_on_sd"
else
  src_root="$SD"; dst_root="$INTERNAL"; dst_set="$real_on_internal"
fi

# sort -k2,2n  = ascending (smallest first)
# sort -k2,2nr = descending (largest first)
if [[ "$STRATEGY" == "largest" ]]; then
  SORT_FLAGS="-k2,2nr"
else
  SORT_FLAGS="-k2,2n"
fi

primary_plan=$(mktemp)
trap "rm -f \"$primary_plan\"" EXIT

# Filter source candidates by "not real on destination" and sort by size ascending
list_real_candidates "$src_root" \
  | awk -v dst_real="$dst_set" -F'\t' 'BEGIN{ while ((getline l < ENVIRON["DST_SET_FILE"]) > 0) D[l]=1 } !D[$1] {print}' >/dev/null 2>&1 || true

# Simpler: use grep -F to exclude
dst_set_file=$(mktemp); echo "$dst_set" > "$dst_set_file"
list_real_candidates "$src_root" | awk -F'\t' -v sf="$dst_set_file" '
BEGIN { while ((getline l < sf) > 0) D[l]=1 }
!($1 in D) { print }
' | sort -t $'\t' $SORT_FLAGS > "$primary_plan"

# Pick smallest first until primary_budget reached
primary_picks=$(mktemp)
awk -v budget="$primary_budget" -F'\t' '
{
  if (moved >= budget) exit
  if ($2+0 == 0) next
  print $0
  moved += $2
}' "$primary_plan" > "$primary_picks"

# Reverse-direction picks: round-robin smallest first per system from the OPPOSITE side
if [[ "$PRIMARY" == "to_sd" ]]; then
  rev_src="$SD"; rev_dst="$INTERNAL"; rev_dst_set="$real_on_internal"
else
  rev_src="$INTERNAL"; rev_dst="$SD"; rev_dst_set="$real_on_sd"
fi
rev_dst_file=$(mktemp); echo "$rev_dst_set" > "$rev_dst_file"

reverse_picks=$(mktemp)
list_real_candidates "$rev_src" | awk -F'\t' -v sf="$rev_dst_file" '
BEGIN { while ((getline l < sf) > 0) D[l]=1 }
!($1 in D) { print }
' | awk -F'\t' -v strategy="$STRATEGY" '
{
  sys = $1; sub(/\/.*/, "", sys)
  per_sys[sys] = (per_sys[sys] ? per_sys[sys] ORS : "") $0
  count[sys]++
  if (count[sys] > max_d) max_d = count[sys]
  if (!(sys in seen)) { systems[++ns] = sys; seen[sys] = 1 }
}
END {
  for (s in per_sys) {
    n = split(per_sys[s], arr, ORS)
    # Sort each system list by size (asc for smallest-first, desc for largest-first).
    for (i = 1; i <= n; i++) {
      for (j = i+1; j <= n; j++) {
        split(arr[i], a, "\t"); split(arr[j], b, "\t")
        if (strategy == "largest") {
          if ((a[2]+0) < (b[2]+0)) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }
        } else {
          if ((a[2]+0) > (b[2]+0)) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }
        }
      }
    }
    sorted[s] = arr[1]
    for (i = 2; i <= n; i++) sorted[s] = sorted[s] ORS arr[i]
    cnt[s] = n
  }
  # Round-robin by depth
  for (d = 1; d <= max_d; d++) {
    for (k = 1; k <= ns; k++) {
      s = systems[k]
      if (d <= cnt[s]) {
        split(sorted[s], parts, ORS)
        print parts[d]
      }
    }
  }
}' | awk -v budget="$reverse_budget" -F'\t' '
{
  if (moved >= budget) exit
  if ($2+0 == 0) next
  print $0
  moved += $2
}' > "$reverse_picks"

primary_n=$(wc -l < "$primary_picks")
reverse_n=$(wc -l < "$reverse_picks")
primary_bytes=$(awk -F'\t' '{s+=$2} END{print s+0}' "$primary_picks")
reverse_bytes=$(awk -F'\t' '{s+=$2} END{print s+0}' "$reverse_picks")
gb() { awk -v b="$1" 'BEGIN{printf "%.2f GB", b/(1024^3)}'; }

echo ""
echo "Plan:"
echo "  Strategy: $STRATEGY first"
echo "  $PRIMARY (primary):  $primary_n files, $(gb "$primary_bytes")"
echo "  $([[ $PRIMARY == to_sd ]] && echo to_internal || echo to_sd) (variety): $reverse_n files, $(gb "$reverse_bytes")"
echo "  Total moves: $((primary_n + reverse_n)) files, $(gb $((primary_bytes + reverse_bytes)))"

if [[ "$MODE" == "scan" ]]; then
  echo ""
  echo "--- Primary picks ($PRIMARY) ---"
  awk -F'\t' '{printf "  %s  (%.1f MB)\n", $1, $2/(1024*1024)}' "$primary_picks"
  echo ""
  echo "--- Variety picks ---"
  awk -F'\t' '{printf "  %s  (%.1f MB)\n", $1, $2/(1024*1024)}' "$reverse_picks"
  echo ""
  echo "Re-run with mode=apply to execute this plan."
  exit 0
fi

# Apply moves
move_one() {
  local src="$1" dst="$2" direction="$3"
  if [[ ! -f "$src" || -L "$src" ]]; then echo "[fail] $src: not a real file"; return 1; fi
  if [[ -e "$dst" && ! -L "$dst" ]]; then echo "[fail] $dst: real file already exists"; return 1; fi
  mkdir -p "$(dirname "$dst")"
  local tmp="$dst.dttmp.$$"
  if ! cp -a "$src" "$tmp"; then echo "[fail] $src: cp"; rm -f "$tmp"; return 1; fi
  local s1 s2
  s1=$(stat -c '%s' "$src")
  s2=$(stat -c '%s' "$tmp")
  if [[ "$s1" != "$s2" ]]; then echo "[fail] $src: size mismatch"; rm -f "$tmp"; return 1; fi
  if ! mv -fT "$tmp" "$dst"; then echo "[fail] $dst: mv"; rm -f "$tmp"; return 1; fi
  if ! rm -f "$src"; then echo "[fail] $src: rm"; return 1; fi
  if [[ "$direction" == "to_internal" ]]; then
    if ! ln -s "$dst" "$src"; then echo "[warn] $src: symlink failed"; fi
  fi
  echo "[ok] $direction $src -> $dst"
}

ok=0; fail=0
while IFS=$'\t' read -r rel sz; do
  [[ -z "$rel" ]] && continue
  if move_one "$src_root/$rel" "$dst_root/$rel" "$PRIMARY"; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
done < "$primary_picks"

if [[ "$PRIMARY" == "to_sd" ]]; then rev_dir="to_internal"; else rev_dir="to_sd"; fi
while IFS=$'\t' read -r rel sz; do
  [[ -z "$rel" ]] && continue
  if move_one "$rev_src/$rel" "$rev_dst/$rel" "$rev_dir"; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
done < "$reverse_picks"

rm -f "$dst_set_file" "$rev_dst_file"

echo ""
echo "Done: $ok ok, $fail failed."
