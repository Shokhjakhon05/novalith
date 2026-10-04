#!/usr/bin/env bash
# Installs the release APK on the running emulator, launches it, plays a few drops and checks
# that the process is still alive. Leaves logcat and screenshots in ./smoke for upload.
set -u
PKG=com.novalith.game
mkdir -p smoke
adb install -r apk/app-release.apk || { echo "install failed"; exit 1; }
adb logcat -c
adb shell am start -W -n $PKG/.MainActivity | tee smoke/start.txt
sleep 14
adb exec-out screencap -p > smoke/1_menu.png || true

# Screen size, so the taps work on any emulator profile.
SIZE=$(adb shell wm size | tr -d '\r' | sed 's/.*: //')
W=${SIZE%x*}; H=${SIZE#*x}
tap() { adb shell input tap $(( W * $1 / 100 )) $(( H * $2 / 100 )); }

tap 50 75          # PLAY (the big button sits at three quarters of the screen height)
sleep 4
adb exec-out screencap -p > smoke/2_game_start.png || true
for x in 20 22 50 52 80 78 35 36 65 64 50 20; do
  tap $x 60        # aim and drop in the board
  sleep 1
done
sleep 2
adb exec-out screencap -p > smoke/3_game_playing.png || true
adb shell input keyevent KEYCODE_BACK   # pause
sleep 2
adb exec-out screencap -p > smoke/4_paused.png || true
adb shell input keyevent KEYCODE_HOME   # background
sleep 3
adb shell am start -n $PKG/.MainActivity >/dev/null   # and back
sleep 4
adb exec-out screencap -p > smoke/5_resumed.png || true

PID=$(adb shell pidof $PKG | tr -d '\r')
adb logcat -d > smoke/logcat.txt
grep -E "FATAL EXCEPTION|AndroidRuntime: |F libc|F DEBUG|Abort message|flutter error|uncaught:" smoke/logcat.txt | tail -150 > smoke/crash_excerpt.txt || true
grep -E " flutter *:" smoke/logcat.txt | tail -80 > smoke/flutter_log.txt || true
echo "---- crash excerpt ----"; cat smoke/crash_excerpt.txt
echo "---- flutter log ----"; cat smoke/flutter_log.txt
if [ -z "$PID" ]; then echo "SMOKE FAILED: process is not running"; exit 1; fi
if grep -q "FATAL EXCEPTION" smoke/crash_excerpt.txt && grep -q "$PKG" smoke/crash_excerpt.txt; then
  echo "SMOKE FAILED: the app crashed at some point"; exit 1
fi
echo "SMOKE OK: pid $PID alive after menu, 12 drops, pause, background and resume"
