#!/usr/bin/env bash
# Steam Deck Weekly Maintenance (EXECUTE & FORGET)

set -u
set -o pipefail
IFS=$'\n\t'
umask 077

# -------------------- config --------------------
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-180}"
LOG_COMPRESS_AFTER_DAYS="${LOG_COMPRESS_AFTER_DAYS:-7}"

TMO_FLATPAK="${TMO_FLATPAK:-45m}"
TMO_JOURNAL="${TMO_JOURNAL:-3m}"
TMO_SYSTEM="${TMO_SYSTEM:-8m}"
TMO_FIND="${TMO_FIND:-4m}"
TMO_REPORT="${TMO_REPORT:-3m}"
USER_JOURNAL_SIZE="${USER_JOURNAL_SIZE:-200M}"
USER_JOURNAL_TIME="${USER_JOURNAL_TIME:-14d}"
SYS_JOURNAL_SIZE="${SYS_JOURNAL_SIZE:-500M}"
SYS_JOURNAL_TIME="${SYS_JOURNAL_TIME:-14d}"
COREDUMP_TIME="${COREDUMP_TIME:-14d}"

TMP_FILE_AGE_DAYS="${TMP_FILE_AGE_DAYS:-7}"
THUMBNAIL_FILE_AGE_DAYS="${THUMBNAIL_FILE_AGE_DAYS:-30}"

WARN_DISK_USE_PCT="${WARN_DISK_USE_PCT:-90}"
WARN_DISK_AVAIL_GB="${WARN_DISK_AVAIL_GB:-10}"

REPORT_STEAM_DIRS="${REPORT_STEAM_DIRS:-1}"

REQUIRE_AC_FOR_HEAVY="${REQUIRE_AC_FOR_HEAVY:-1}"
SKIP_HEAVY_IN_GAMING_MODE="${SKIP_HEAVY_IN_GAMING_MODE:-1}"
SKIP_HEAVY_IF_OFFLINE="${SKIP_HEAVY_IF_OFFLINE:-1}"

EXIT_NONZERO_ON_FAILS="${EXIT_NONZERO_ON_FAILS:-0}"

# -------------------- harden env (avoid pagers/prompts) --------------------
export SYSTEMD_PAGER=cat
export PAGER=cat
export LESS=FRX
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANG=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

START_EPOCH="$(date +%s)"
TS="$(date '+%Y-%m-%d_%H-%M-%S')"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/steamdeck-maintenance"
LOG_DIR="$STATE_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/$TS.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date '+%F %T')" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

with_timeout() {
  local dur="$1"; shift
  if have timeout; then
    timeout --foreground "$dur" "$@"
  else
    "$@"
  fi
}

lowprio() {
  if have ionice; then
    if have nice; then ionice -c2 -n7 nice -n 10 "$@"; else ionice -c2 -n7 "$@"; fi
  else
    if have nice; then nice -n 10 "$@"; else "$@"; fi
  fi
}

FAILS=()
SKIPS=()

run() {
  local desc="$1"; shift
  local tmo="$1"; shift
  local t0 t1 rc
  t0="$(date +%s)"
  log "==> $desc"
  if [[ "$tmo" == "-" ]]; then
    "$@"; rc=$?
  else
    with_timeout "$tmo" "$@"; rc=$?
  fi
  t1="$(date +%s)"

  if (( rc == 0 )); then
    log "OK: $desc (+$((t1 - t0))s)"
  else
    if (( rc == 124 )); then
      warn "TIMEOUT: $desc (+$((t1 - t0))s)"
      SKIPS+=("timeout: $desc")
    else
      warn "FAIL: $desc (exit $rc; +$((t1 - t0))s)"
      FAILS+=("exit $rc: $desc")
    fi
  fi
  return 0
}

# -------------------- single-instance lock --------------------
LOCK_BASE="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FILE="$LOCK_BASE/steamdeck-maintenance.lock"

acquire_lock() {
  if have flock; then
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
      log "Another run is already in progress; exiting."
      exit 0
    fi
    return 0
  fi

  local lockdir="$LOCK_FILE.d"
  if mkdir "$lockdir" 2>/dev/null; then
    printf '%s\n' "$$" >"$lockdir/pid"
    trap 'rm -rf "$lockdir" >/dev/null 2>&1 || true' EXIT INT TERM
    return 0
  fi
  if [[ -f "$lockdir/pid" ]]; then
    local oldpid
    oldpid="$(cat "$lockdir/pid" 2>/dev/null || true)"
    if [[ -n "${oldpid:-}" ]] && ! kill -0 "$oldpid" 2>/dev/null; then
      rm -rf "$lockdir" >/dev/null 2>&1 || true
      if mkdir "$lockdir" 2>/dev/null; then
        printf '%s\n' "$$" >"$lockdir/pid"
        trap 'rm -rf "$lockdir" >/dev/null 2>&1 || true' EXIT INT TERM
        return 0
      fi
    fi
  fi
  log "Another run is already in progress; exiting."
  exit 0
}
acquire_lock

# -------------------- environment detectors --------------------
in_gaming_mode() {
  pgrep -x gamescope-session >/dev/null 2>&1 && return 0
  pgrep -f 'steam.*-gamepadui' >/dev/null 2>&1 && return 0
  return 1
}

on_ac_power() {
  local p
  for p in /sys/class/power_supply/*; do
    [[ -r "$p/type" ]] || continue
    if [[ "$(cat "$p/type" 2>/dev/null || true)" =~ ^(Mains|USB|USB_C)$ ]]; then
      [[ -r "$p/online" ]] || continue
      [[ "$(cat "$p/online" 2>/dev/null || true)" == "1" ]] && return 0
    fi
  done
  return 1
}

net_ok() {
  if have curl; then
    with_timeout 6s curl -fsSI --max-time 5 https://flathub.org/ >/dev/null 2>&1 && return 0
  fi
  if have getent; then
    getent hosts flathub.org >/dev/null 2>&1 && return 0
  fi
  if have ping; then
    with_timeout 4s ping -c1 -W2 flathub.org >/dev/null 2>&1 && return 0
  fi
  return 1
}

HEAVY_OK=1
if [[ "$SKIP_HEAVY_IN_GAMING_MODE" == "1" ]] && in_gaming_mode; then
  HEAVY_OK=0
  SKIPS+=("heavy tasks skipped: Gaming Mode detected")
fi
if [[ "$REQUIRE_AC_FOR_HEAVY" == "1" ]] && ! on_ac_power; then
  HEAVY_OK=0
  SKIPS+=("heavy tasks skipped: running on battery")
fi
if [[ "$SKIP_HEAVY_IF_OFFLINE" == "1" ]] && ! net_ok; then
  SKIPS+=("network appears offline: Flatpak updates will be skipped")
fi

# -------------------- sudo --------------------
ROOT_OK=0
SUDO_KA_PID=""
if have sudo; then
  if sudo -n true >/dev/null 2>&1; then
    ROOT_OK=1
  else
    if sudo -v; then
      ROOT_OK=1
    fi
  fi

  if [[ "$ROOT_OK" -eq 1 ]]; then
    ( while sleep 60; do sudo -n true >/dev/null 2>&1 || exit 0; done ) &
    SUDO_KA_PID="$!"
    trap '[[ -n "${SUDO_KA_PID:-}" ]] && kill "$SUDO_KA_PID" >/dev/null 2>&1 || true' EXIT INT TERM
  fi
fi

# -------------------- header --------------------
log "Steam Deck maintenance start"
log "Log: $LOG_FILE"
log "User: $(id -un) UID: $(id -u) Host: $(hostname)"
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  log "OS: ${PRETTY_NAME:-unknown}"
fi
log "Kernel: $(uname -r)"
have uptime && log "Uptime: $(uptime -p 2>/dev/null || true)"
log "Root tasks enabled: $([[ $ROOT_OK -eq 1 ]] && echo yes || echo no)"
log "Heavy tasks enabled: $([[ $HEAVY_OK -eq 1 ]] && echo yes || echo no)"

# -------------------- prune/compress old maintenance logs --------------------
run "Prune old maintenance logs (>${LOG_RETENTION_DAYS}d)" "$TMO_FIND" \
  bash -c "find \"$LOG_DIR\" -type f -name '*.log' -mtime +\"$LOG_RETENTION_DAYS\" -delete 2>/dev/null || true"

if have gzip; then
  run "Compress older maintenance logs (>${LOG_COMPRESS_AFTER_DAYS}d)" "$TMO_FIND" \
    bash -c "find \"$LOG_DIR\" -type f -name '*.log' -mtime +\"$LOG_COMPRESS_AFTER_DAYS\" -print0 2>/dev/null | xargs -0 -r gzip -9n 2>/dev/null || true"
fi

# -------------------- quick snapshots --------------------
run "Disk usage (df -hT)" "-" df -hT
have lsblk && run "Block devices (lsblk)" "-" lsblk
have free  && run "Memory usage (free -h)" "-" free -h

check_disk_pressure() {
  local target="$1"
  local line usep avail_kb
  line="$(df -Pk "$target" 2>/dev/null | tail -n1 || true)"
  [[ -z "$line" ]] && return 0
  usep="$(awk '{gsub(/%/,"",$5); print $5}' <<<"$line" 2>/dev/null || true)"
  avail_kb="$(awk '{print $4}' <<<"$line" 2>/dev/null || true)"
  [[ -z "$usep" || -z "$avail_kb" ]] && return 0
  local avail_gb=$(( avail_kb / 1024 / 1024 ))
  if [[ "$usep" =~ ^[0-9]+$ ]] && (( usep >= WARN_DISK_USE_PCT )); then
    warn "High disk usage on $target: ${usep}% used"
  fi
  if [[ "$avail_gb" =~ ^[0-9]+$ ]] && (( avail_gb <= WARN_DISK_AVAIL_GB )); then
    warn "Low free space on $target: ~${avail_gb} GB available"
  fi
}

run "Disk pressure checks" "-" bash -c 'true'
check_disk_pressure "/"
check_disk_pressure "/home"

if [[ -d /run/media ]]; then
  while IFS= read -r mp; do
    check_disk_pressure "$mp"
  done < <(find /run/media -mindepth 2 -maxdepth 2 -type d 2>/dev/null || true)
fi

have systemctl && run "System services failed (systemctl --failed)" "-" systemctl --failed --no-pager
have systemctl && run "User services failed (systemctl --user --failed)" "-" systemctl --user --failed --no-pager

if have journalctl; then
  run "Journal disk usage (system)" "$TMO_REPORT" journalctl --no-pager --disk-usage
  run "Journal disk usage (user)" "$TMO_REPORT" journalctl --user --no-pager --disk-usage
fi

if [[ "$REPORT_STEAM_DIRS" == "1" ]] && have du; then
  STEAM_BASE="${HOME}/.local/share/Steam"
  if [[ -d "$STEAM_BASE" ]]; then
    run "Steam size report (no deletion): shadercache/compatdata/logs" "$TMO_REPORT" \
      bash -c "
        set -u
        base=\"$STEAM_BASE\"
        for p in \
          \"\$base/steamapps/shadercache\" \
          \"\$base/steamapps/compatdata\" \
          \"\$base/logs\" \
          \"\$base/steamapps\" \
        ; do
          [[ -e \"\$p\" ]] && du -sh \"\$p\" 2>/dev/null || true
        done
      "
  fi
fi

# -------------------- Flatpak (forced non-interactive) --------------------
if have flatpak; then
  if [[ "$HEAVY_OK" -eq 1 ]] && ( [[ "$SKIP_HEAVY_IF_OFFLINE" != "1" ]] || net_ok ); then
    run "Flatpak (user): update appstream" "$TMO_FLATPAK" lowprio flatpak --user update --appstream -y --noninteractive
    run "Flatpak (user): update installed apps/runtimes" "$TMO_FLATPAK" lowprio flatpak --user update -y --noninteractive
    run "Flatpak (user): uninstall unused runtimes" "$TMO_FLATPAK" lowprio flatpak --user uninstall --unused -y --noninteractive

    if [[ "$(date +%d)" == "01" ]]; then
      run "Flatpak (user): repair (monthly)" "$TMO_FLATPAK" lowprio flatpak repair --user -y --noninteractive
    else
      log "Flatpak (user): repair skipped (runs on day 01)"
    fi

    if [[ $ROOT_OK -eq 1 ]]; then
      run "Flatpak (system): update appstream (sudo -n)" "$TMO_FLATPAK" lowprio sudo -n flatpak --system update --appstream -y --noninteractive
      run "Flatpak (system): update installed apps/runtimes (sudo -n)" "$TMO_FLATPAK" lowprio sudo -n flatpak --system update -y --noninteractive
      run "Flatpak (system): uninstall unused runtimes (sudo -n)" "$TMO_FLATPAK" lowprio sudo -n flatpak --system uninstall --unused -y --noninteractive
      if [[ "$(date +%d)" == "01" ]]; then
        run "Flatpak (system): repair (monthly, sudo -n)" "$TMO_FLATPAK" lowprio sudo -n flatpak repair --system -y --noninteractive
      else
        log "Flatpak (system): repair skipped (runs on day 01)"
      fi
    else
      log "Flatpak (system): skipped (no sudo validated)."
    fi
  else
    log "Flatpak: skipped (heavy tasks disabled and/or offline)."
  fi
else
  log "Flatpak not found; skipping Flatpak maintenance"
fi

# -------------------- journald vacuum (user) --------------------
if have journalctl; then
  run "User journal rotate" "$TMO_JOURNAL" journalctl --user --no-pager --rotate
  run "User journal vacuum (size ${USER_JOURNAL_SIZE})" "$TMO_JOURNAL" \
    journalctl --user --no-pager --vacuum-size="$USER_JOURNAL_SIZE"
  run "User journal vacuum (time ${USER_JOURNAL_TIME})" "$TMO_JOURNAL" \
    journalctl --user --no-pager --vacuum-time="$USER_JOURNAL_TIME"
fi

# -------------------- root tasks (sudo -n only; never prompt) --------------------
if [[ $ROOT_OK -eq 1 ]]; then
  if [[ "$HEAVY_OK" -eq 1 ]]; then
    have fstrim && run "TRIM mounted filesystems (fstrim -av)" "$TMO_SYSTEM" lowprio sudo -n fstrim -av
    have systemd-tmpfiles && run "systemd-tmpfiles --clean" "$TMO_SYSTEM" sudo -n systemd-tmpfiles --clean
  else
    log "Root heavy tasks skipped (heavy tasks disabled)."
  fi

  if have journalctl; then
    run "System journal rotate" "$TMO_SYSTEM" sudo -n journalctl --no-pager --rotate
    run "System journal vacuum (size ${SYS_JOURNAL_SIZE})" "$TMO_SYSTEM" \
      sudo -n journalctl --no-pager --vacuum-size="$SYS_JOURNAL_SIZE"
    run "System journal vacuum (time ${SYS_JOURNAL_TIME})" "$TMO_SYSTEM" \
      sudo -n journalctl --no-pager --vacuum-time="$SYS_JOURNAL_TIME"
  fi

  have coredumpctl && run "Core dump vacuum (keep ${COREDUMP_TIME})" "$TMO_SYSTEM" \
    sudo -n coredumpctl --no-pager --vacuum-time="$COREDUMP_TIME"

  if have smartctl && have findmnt && have lsblk; then
    run "SMART health (if supported)" "$TMO_SYSTEM" bash -c '
      set -u
      src="$(findmnt -no SOURCE / 2>/dev/null || true)"
      [[ "$src" != /dev/* ]] && exit 1
      parent="$(lsblk -no PKNAME "$src" 2>/dev/null || true)"
      if [[ -n "$parent" ]]; then dev="/dev/$parent"; else dev="$src"; fi
      sudo -n smartctl -H "$dev" 2>/dev/null || exit 1
    '
  fi
else
  log "Root tasks skipped."
fi

# -------------------- temp cleanup ---------------------
if [[ -d /tmp ]]; then
  run "Temp cleanup in /tmp (user-owned f/l >${TMP_FILE_AGE_DAYS}d)" "$TMO_FIND" \
    bash -c "find /tmp -xdev -mindepth 1 \\( -type f -o -type l \\) -user \"$(id -un)\" -mtime +\"$TMP_FILE_AGE_DAYS\" -print -delete >/dev/null 2>&1 || true"
fi

THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"
if [[ -d "$THUMB_DIR" ]]; then
  run "Thumbnail cache cleanup (>${THUMBNAIL_FILE_AGE_DAYS}d)" "$TMO_FIND" \
    bash -c "find \"$THUMB_DIR\" -type f -mtime +\"$THUMBNAIL_FILE_AGE_DAYS\" -print -delete >/dev/null 2>&1 || true"
fi

# -------------------- finish --------------------
END_EPOCH="$(date +%s)"
log "Steam Deck maintenance complete (elapsed $((END_EPOCH - START_EPOCH))s)"
run "Disk usage after (df -hT)" "-" df -hT

if (( ${#SKIPS[@]} > 0 )); then
  log "Summary: skipped:"
  for s in "${SKIPS[@]}"; do log " - $s"; done
fi

if (( ${#FAILS[@]} > 0 )); then
  log "Summary: failures:"
  for f in "${FAILS[@]}"; do log " - $f"; done
else
  log "Summary: all steps completed successfully."
fi

have sudo && sudo -n -k >/dev/null 2>&1 || true

if (( ${#FAILS[@]} > 0 )) && [[ "$EXIT_NONZERO_ON_FAILS" == "1" ]]; then
  exit 1
fi
exit 0
