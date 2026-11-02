#!/bin/sh
# Read-only check: does this Mac have what LidTap needs?
#   sh tools/check_mac.sh
# Reads hardware and system info only. Changes nothing, needs no sudo, needs no permissions.
set -u

ok=1
pass() { printf '  \342\234\223 %s\n' "$1"; }
fail() { printf '  \342\234\227 %s\n' "$1"; ok=0; }
info() { printf '    %s\n' "$1"; }

echo "LidTap hardware check"
echo
echo "This Mac"
info "Model:  $(sysctl -n hw.model 2>/dev/null || echo unknown)"
info "Chip:   $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
ver="$(sw_vers -productVersion 2>/dev/null || echo 0)"
info "macOS:  $ver ($(sw_vers -productName 2>/dev/null) build $(sw_vers -buildVersion 2>/dev/null))"
echo

echo "Requirements"
case "$(uname -m)" in
  arm64) pass "Apple Silicon" ;;
  *) fail "Not Apple Silicon ($(uname -m)). Intel Macs have no motion sensor." ;;
esac

major="${ver%%.*}"
case "$major" in
  ''|*[!0-9]*) fail "Could not read the macOS version" ;;
  *) if [ "$major" -ge 14 ]; then pass "macOS $ver (14 or later required)"; else fail "macOS $ver is too old: 14 Sonoma or later is required"; fi ;;
esac

# The motion sensor appears as AppleSPUHIDDevice services: usage page 0xFF00 (65280) with usage 3 (accelerometer)
# and 9 (gyroscope). The lid-angle sensor is usage page 0x20 (32), usage 0x8A (138). Same matching as the app.
found="$(ioreg -r -c AppleSPUHIDDevice -d 1 2>/dev/null | awk '
  function flush() {
    if (page == "65280" && usage == "3") a = 1
    if (page == "65280" && usage == "9") g = 1
    if (page == "32" && usage == "138") l = 1
    n++
  }
  /\+-o / { if (seen) flush(); seen = 1; page = ""; usage = "" }
  /"PrimaryUsagePage" =/ { page = $NF }
  /"PrimaryUsage" =/ { usage = $NF }
  END { if (seen) flush(); printf "%d %d %d %d\n", a + 0, g + 0, l + 0, n + 0 }')"
set -- $found
accel="${1:-0}"; gyro="${2:-0}"; lid="${3:-0}"; devices="${4:-0}"

if [ "$devices" -eq 0 ]; then
  fail "No sensor hub devices found (AppleSPUHIDDevice). This Mac has no motion sensor LidTap can read."
else
  info "Sensor hub devices found: $devices"
  if [ "$accel" -eq 1 ]; then pass "Accelerometer (usage 3)"; else fail "Accelerometer not found"; fi
  if [ "$gyro" -eq 1 ]; then pass "Gyroscope (usage 9): this is the sensor taps are detected with"; else fail "Gyroscope not found"; fi
  if [ "$lid" -eq 1 ]; then pass "Lid-angle sensor (optional, used to ignore taps while the lid moves)"; else info "Lid-angle sensor not found (optional)"; fi
fi
echo

echo "Already installed?"
for app in "/Applications/LidTap.app" "$HOME/Applications/LidTap.app"; do
  [ -d "$app" ] && info "Found $app"
done
[ -d "$HOME/Library/Application Support/LidTap" ] && info "Data folder exists: ~/Library/Application Support/LidTap" || info "No LidTap data folder yet"
echo

if [ "$ok" -eq 1 ]; then
  echo "Result: this Mac can run LidTap."
  exit 0
else
  echo "Result: this Mac does not meet LidTap's requirements (see the lines marked with a cross)."
  exit 1
fi
