#!/bin/bash
# Hardware health check for the Steam Deck. Read-only.
# Prints one line per check starting with [OK], [WARN] or [FAIL].

set -u

N_OK=0
N_WARN=0
N_FAIL=0

ok()   { echo "  [OK]    $*";   N_OK=$((N_OK + 1)); }
warn() { echo "  [WARN]  $*";   N_WARN=$((N_WARN + 1)); }
fail() { echo "  [FAIL]  $*";   N_FAIL=$((N_FAIL + 1)); }
info() { echo "          $*"; }
section() { echo ""; echo "$*"; }

# Prints the first hwmon directory whose name matches $1
hwmon_dir() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    [[ "$(cat "$h/name" 2>/dev/null)" == "$1" ]] && { echo "$h"; return 0; }
  done
  return 1
}

# Prints a temperature in whole degrees from a millidegree file
read_temp() {
  local v
  v=$(cat "$1" 2>/dev/null) || return 1
  [[ "$v" =~ ^-?[0-9]+$ ]] || return 1
  echo $((v / 1000))
}

# check_temp <label> <hwmon name> <file> <warn at> <fail at>
check_temp() {
  local label="$1" dir t
  dir=$(hwmon_dir "$2") || { warn "$label temperature: sensor not found"; return; }
  t=$(read_temp "$dir/$3") || { warn "$label temperature: could not read"; return; }
  if (( t >= $5 )); then
    fail "$label temperature: ${t}°C (very hot)"
  elif (( t >= $4 )); then
    warn "$label temperature: ${t}°C (hot)"
  else
    ok "$label temperature: ${t}°C"
  fi
}

echo "=== Steam Deck Health Check ==="
case "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" in
  Galileo) echo "Model: Steam Deck OLED" ;;
  Jupiter) echo "Model: Steam Deck LCD" ;;
  *)       echo "Model: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)" ;;
esac

# ---------------- Battery ----------------
section "Battery"
BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
if [[ -z "$BAT" ]]; then
  fail "Battery: not detected"
else
  cap=$(cat "$BAT/capacity" 2>/dev/null)
  status=$(cat "$BAT/status" 2>/dev/null)
  full=$(cat "$BAT/charge_full" 2>/dev/null || cat "$BAT/energy_full" 2>/dev/null)
  design=$(cat "$BAT/charge_full_design" 2>/dev/null || cat "$BAT/energy_full_design" 2>/dev/null)
  ok "Battery detected: ${cap:-?}% charged, ${status:-unknown}"
  if [[ -n "$full" && -n "$design" && "$design" -gt 0 ]]; then
    health=$(( full * 100 / design ))
    if (( health >= 80 )); then
      ok "Battery health: ${health}% of its original capacity"
    elif (( health >= 60 )); then
      warn "Battery health: ${health}% of its original capacity (worn)"
    else
      fail "Battery health: ${health}% of its original capacity (badly worn)"
    fi
  else
    warn "Battery health: could not read"
  fi
  cycles=$(cat "$BAT/cycle_count" 2>/dev/null)
  [[ -n "$cycles" && "$cycles" -gt 0 ]] && info "Charge cycles: $cycles"
  check_temp "Battery" steamdeck_hwmon temp1_input 45 55
fi
ACAD=$(ls -d /sys/class/power_supply/AC* 2>/dev/null | head -1)
if [[ -n "$ACAD" ]]; then
  if [[ "$(cat "$ACAD/online" 2>/dev/null)" == "1" ]]; then
    ok "Charger: plugged in"
  else
    info "Charger: not plugged in"
  fi
fi

# ---------------- Storage ----------------
section "Storage"
NVME=$(ls /dev/nvme?n1 2>/dev/null | head -1)
if [[ -z "$NVME" ]]; then
  fail "Internal SSD: not detected"
else
  model=$(cat /sys/block/"$(basename "$NVME")"/device/model 2>/dev/null | xargs)
  ok "Internal SSD detected: ${model:-unknown model}"
  SMART=$(sudo -n smartctl -H -A "$NVME" 2>/dev/null)
  if [[ -z "$SMART" ]]; then
    warn "SSD health report: needs the sudo password (Unlock at the top)"
  else
    if grep -q "self-assessment test result: PASSED" <<<"$SMART"; then
      ok "SSD health report: passed"
    else
      fail "SSD health report: did not pass"
    fi
    crit=$(awk -F: '/Critical Warning/{gsub(/ /,"",$2); print $2}' <<<"$SMART")
    [[ -n "$crit" && "$crit" != "0x00" ]] && fail "SSD critical warning flag: $crit"
    used=$(awk -F: '/Percentage Used/{gsub(/[ %]/,"",$2); print $2}' <<<"$SMART")
    if [[ -n "$used" ]]; then
      if (( used >= 100 )); then
        fail "SSD wear: ${used}% of its rated life used"
      elif (( used >= 80 )); then
        warn "SSD wear: ${used}% of its rated life used"
      else
        ok "SSD wear: ${used}% of its rated life used"
      fi
    fi
    spare=$(awk -F: '/Available Spare:/{gsub(/[ %]/,"",$2); print $2}' <<<"$SMART")
    if [[ -n "$spare" ]] && (( spare < 50 )); then
      warn "SSD spare blocks left: ${spare}%"
    fi
    errs=$(awk -F: '/Media and Data Integrity Errors/{gsub(/[ ,]/,"",$2); print $2}' <<<"$SMART")
    if [[ -n "$errs" ]]; then
      if (( errs > 0 )); then
        fail "SSD data errors: $errs"
      else
        ok "SSD data errors: none"
      fi
    fi
    hours=$(awk -F: '/Power On Hours/{gsub(/[ ,]/,"",$2); print $2}' <<<"$SMART")
    [[ -n "$hours" ]] && info "SSD powered on for $hours hours"
  fi
  check_temp "SSD" nvme temp1_input 70 80
fi

read -r _ size used avail pct _ < <(df -P -B1G "$HOME" 2>/dev/null | tail -1)
if [[ -n "${pct:-}" ]]; then
  p=${pct%\%}
  if (( p >= 97 )); then
    fail "Internal storage space: ${p}% full (${avail} GB free of ${size} GB)"
  elif (( p >= 90 )); then
    warn "Internal storage space: ${p}% full (${avail} GB free of ${size} GB)"
  else
    ok "Internal storage space: ${p}% full (${avail} GB free of ${size} GB)"
  fi
fi

SD=$(ls /dev/mmcblk? 2>/dev/null | head -1)
if [[ -z "$SD" ]]; then
  info "SD card: none inserted"
else
  sd_gb=$(( $(cat /sys/block/"$(basename "$SD")"/size 2>/dev/null || echo 0) * 512 / 1000000000 ))
  ok "SD card detected: ${sd_gb} GB"
  mnt=$(lsblk -nro MOUNTPOINT "$SD" 2>/dev/null | grep -m1 .)
  if [[ -n "$mnt" ]]; then
    read -r _ s _ a sp _ < <(df -P -B1G "$mnt" 2>/dev/null | tail -1)
    ok "SD card mounted at $mnt: ${sp} full (${a} GB free of ${s} GB)"
  else
    warn "SD card: inserted but not mounted"
  fi
fi

# ---------------- CPU, GPU, memory, fan ----------------
section "CPU, GPU and cooling"
cpu=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
present=$(nproc --all 2>/dev/null)
online=$(nproc 2>/dev/null)
if [[ -n "$present" && "$present" == "$online" ]]; then
  ok "CPU: ${cpu:-unknown}, all $online threads working"
else
  warn "CPU: ${cpu:-unknown}, only ${online:-?} of ${present:-?} threads online"
fi
check_temp "CPU" k10temp temp1_input 85 95

if lspci 2>/dev/null | grep -qiE "vga|display"; then
  ok "GPU: $(lspci 2>/dev/null | grep -iE 'vga|display' | head -1 | sed 's/.*: //')"
else
  fail "GPU: not detected"
fi
check_temp "GPU" amdgpu temp1_input 85 95

mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
if [[ -n "$mem_kb" ]]; then
  mem_gb=$(( (mem_kb + 524288) / 1048576 ))
  if (( mem_gb >= 14 )); then
    ok "Memory: ${mem_gb} GB usable"
  else
    warn "Memory: only ${mem_gb} GB visible (16 GB expected)"
  fi
fi

FAN_DIR=$(hwmon_dir steamdeck_hwmon)
if [[ -n "$FAN_DIR" && -r "$FAN_DIR/fan1_input" ]]; then
  rpm=$(cat "$FAN_DIR/fan1_input")
  if (( rpm > 0 )); then
    ok "Fan: spinning at $rpm RPM"
  else
    fail "Fan: not spinning"
  fi
else
  warn "Fan: sensor not found"
fi

# ---------------- Screen ----------------
section "Screen"
PANEL=$(ls -d /sys/class/drm/card*-eDP-* 2>/dev/null | head -1)
if [[ -n "$PANEL" && "$(cat "$PANEL/status" 2>/dev/null)" == "connected" ]]; then
  mode=$(head -1 "$PANEL/modes" 2>/dev/null)
  ok "Built-in screen detected: ${mode:-unknown resolution}"
else
  fail "Built-in screen: not detected"
fi
BL=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
if [[ -n "$BL" ]]; then
  b=$(cat "$BL/brightness" 2>/dev/null); m=$(cat "$BL/max_brightness" 2>/dev/null)
  if [[ -n "$b" && -n "$m" && "$m" -gt 0 ]]; then
    ok "Brightness control: working, set to $(( b * 100 / m ))%"
  else
    warn "Brightness control: could not read"
  fi
else
  warn "Brightness control: not found"
fi
if grep -q "FTS3528\|Touchscreen\|touchscreen" /proc/bus/input/devices 2>/dev/null; then
  ok "Touchscreen detected"
else
  fail "Touchscreen: not detected"
fi

# ---------------- Audio ----------------
section "Audio"
SINKS=$(pactl list short sinks 2>/dev/null)
if grep -q "Speaker" <<<"$SINKS"; then
  ok "Speakers detected"
else
  fail "Speakers: not detected"
fi
if grep -q "Headphones" <<<"$SINKS"; then
  ok "Headphone output detected"
else
  warn "Headphone output: not detected"
fi
if grep -q "Headset Jack" /proc/bus/input/devices 2>/dev/null; then
  ok "Headphone jack detected"
else
  warn "Headphone jack: not detected"
fi
if pactl list short sources 2>/dev/null | grep -qi "mic"; then
  ok "Microphone detected"
else
  fail "Microphone: not detected"
fi
vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
if [[ "$vol" == *MUTED* ]]; then
  warn "Output volume: muted"
elif [[ -n "$vol" ]]; then
  v=$(awk '{printf "%d", $2 * 100}' <<<"$vol")
  if (( v == 0 )); then
    warn "Output volume: 0%"
  else
    ok "Output volume: ${v}%"
  fi
fi

# ---------------- Controls ----------------
section "Controls"
if grep -qi "000028DE:00001205" /sys/class/hidraw/hidraw*/device/uevent 2>/dev/null; then
  ok "Built-in controller detected"
else
  fail "Built-in controller: not detected"
fi

# ---------------- Wireless ----------------
section "Wireless"
WIFI=$(ls -d /sys/class/net/wl* 2>/dev/null | head -1)
if [[ -z "$WIFI" ]]; then
  fail "Wi-Fi: not detected"
else
  w=$(basename "$WIFI")
  if rfkill list wlan 2>/dev/null | grep -q "blocked: yes"; then
    warn "Wi-Fi: turned off"
  else
    state=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | awk -F: -v d="$w" '$1==d{print $2}')
    if [[ "$state" == "connected" ]]; then
      ok "Wi-Fi: working, connected"
    else
      ok "Wi-Fi: working, ${state:-state unknown}"
    fi
  fi
  check_temp "Wi-Fi chip" ath11k_hwmon temp1_input 80 90
fi
if [[ -d /sys/class/bluetooth/hci0 ]]; then
  if rfkill list bluetooth 2>/dev/null | grep -q "blocked: yes"; then
    warn "Bluetooth: turned off"
  elif bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    ok "Bluetooth: working, on"
  else
    ok "Bluetooth: detected, off"
  fi
else
  fail "Bluetooth: not detected"
fi

# ---------------- Summary ----------------
echo ""
echo "=== Summary ==="
plural() { (( $1 == 1 )) && echo "$1 $2" || echo "$1 $3"; }
echo "$N_OK passed, $(plural "$N_WARN" warning warnings), $(plural "$N_FAIL" problem problems)"
echo "Screen, speakers and buttons need you: use the tests below the health check."
[[ $N_FAIL -gt 0 ]] && exit 1
exit 0
