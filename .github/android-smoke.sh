#!/usr/bin/env bash
# Release workflow: installs the APK on the emulator, starts Paattu and checks
# it's still up 20 s later with no crash in the log. Leaves a screenshot and
# the log in $1.
set -euo pipefail

out=${1:-smoke}
mkdir -p "$out"
apk=$(ls dist/*.apk | head -n1)
adb install -r "$apk"
adb logcat -c
adb shell am start -W -n dev.paattu.paattu/.MainActivity
sleep 20
adb exec-out screencap -p >"$out/android.png" || true
adb logcat -d >"$out/logcat.txt" || true

if ! adb shell pidof dev.paattu.paattu >/dev/null; then
  grep -E 'AndroidRuntime|FATAL|flutter' "$out/logcat.txt" | tail -80 || true
  echo "::error::Paattu isn't running 20 s after it started"
  exit 1
fi
if grep -qE 'FATAL EXCEPTION|Unhandled Exception' "$out/logcat.txt"; then
  grep -E -A20 'FATAL EXCEPTION|Unhandled Exception' "$out/logcat.txt" | head -80
  echo "::error::Paattu threw an exception at start"
  exit 1
fi
# The media notification (and the lock screen and launcher widgets with it)
# never appears when resource shrinking drops audio_service's drawables:
# AudioService then fails on every state change (app/.../res/raw/keep.xml).
if grep -qE 'must specify an icon resource id|Resources\$NotFoundException' "$out/logcat.txt"; then
  grep -E -A6 'must specify an icon resource id|Resources\$NotFoundException' "$out/logcat.txt" | head -40
  echo "::error::the media notification can't be built (a drawable is missing from the APK)"
  exit 1
fi
grep -E ' flutter ' "$out/logcat.txt" | tail -20 || true
echo "Paattu is up on the emulator"
