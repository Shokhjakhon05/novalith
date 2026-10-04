#!/usr/bin/env bash
# Installs the release APK on the running emulator, launches it and checks that the process is
# still alive after a while. Leaves logcat and a screenshot in ./smoke for upload.
set -u
PKG=com.novalith.game
mkdir -p smoke
adb install -r apk/app-release.apk || { echo "install failed"; exit 1; }
adb logcat -c
adb shell am start -W -n $PKG/.MainActivity | tee smoke/start.txt
sleep 12
adb exec-out screencap -p > smoke/screen_12s.png || true
sleep 18
adb exec-out screencap -p > smoke/screen_30s.png || true
PID=$(adb shell pidof $PKG | tr -d '\r')
adb logcat -d > smoke/logcat.txt
grep -E "FATAL EXCEPTION|AndroidRuntime|F libc|F DEBUG|flutter|Abort message|signal [0-9]+" smoke/logcat.txt | tail -120 > smoke/crash_excerpt.txt || true
echo "---- crash excerpt ----"; cat smoke/crash_excerpt.txt
if [ -z "$PID" ]; then echo "SMOKE FAILED: process is not running"; exit 1; fi
echo "SMOKE OK: pid $PID alive after 30 s"
