#!/bin/sh
# Packages build/LidTap.app into a drag-to-install disk image.
#   scripts/make-dmg.sh [output.dmg]      default: build/LidTap.dmg
# Run scripts/build.sh --no-install first. Touches nothing outside the build folder and a temp dir.
set -eu
cd "$(dirname "$0")/.."
APP="build/LidTap.app"
OUT="${1:-build/LidTap.dmg}"
[ -d "$APP" ] || { echo "No $APP. Run scripts/build.sh --no-install first." >&2; exit 1; }

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lidtap-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/LidTap.app"
ln -s /Applications "$STAGE/Applications"
cp ../tools/check_mac.sh "$STAGE/check_mac.sh"
cp ../LICENSE "$STAGE/LICENSE.txt"
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
LidTap: tap zones on your MacBook lid, read from the built-in motion sensor.
Based on LidTap by Yemcube (Instagram @yem.cube, https://www.instagram.com/yem.cube).
Built from source, ad hoc signed, not notarized. Nothing in it talks to the network.

INSTALL
  1. Drag LidTap.app onto the Applications folder next to it.
  2. Optional, before you open it: check this Mac has the motion sensor.
       sh /Volumes/LidTap/check_mac.sh
  3. Open LidTap from Applications. Because the app is not notarized, macOS will
     refuse the first time:
       - macOS 15 or later: click Done, then System Settings > Privacy & Security,
         scroll down, click "Open Anyway", and confirm.
       - macOS 14: right-click LidTap.app > Open > Open.
       - If macOS says the app is "damaged", it is the quarantine flag. In Terminal:
           xattr -dr com.apple.quarantine /Applications/LidTap.app
  4. Allow Input Monitoring when asked. Allow Accessibility when LidTap asks or from
     Settings > Permissions (needed for desktop switching and media keys).
  5. Click Calibrate. Light fingertip flicks only, never press on the display.

REMOVE
  Quit LidTap from the menu bar, delete /Applications/LidTap.app and
  ~/Library/Application Support/LidTap, then remove LidTap from Accessibility,
  Input Monitoring and Automation in System Settings > Privacy & Security.
TXT

rm -f "$OUT"
# hdiutil sometimes fails with "Resource busy" on a busy machine. Retry a few times.
attempt=1
while :; do
  if hdiutil create -quiet -volname LidTap -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT"; then
    break
  fi
  [ "$attempt" -ge 5 ] && { echo "hdiutil failed after $attempt attempts" >&2; exit 1; }
  attempt=$((attempt + 1))
  sleep 3
done
hdiutil verify -quiet "$OUT"
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
shasum -a 256 "$OUT"
