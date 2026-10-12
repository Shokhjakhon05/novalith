#!/usr/bin/env bash
# Installs the release APK on the running emulator, launches it, opens every screen, plays a
# campaign level and checks after each step that the process is still alive. Leaves logcat and screenshots in ./smoke for upload.
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

alive() {
  if [ -z "$(adb shell pidof $PKG | tr -d '\r')" ]; then
    adb logcat -d > smoke/logcat.txt
    echo "SMOKE FAILED: the app died while on: $1"; exit 1
  fi
}

# Every secondary screen is opened once. The collection used to freeze and kill the app on
# real GPUs (it painted every body live each frame), so it gets a longer look and a scroll.
tap 39 93          # Collection tile
sleep 6
adb exec-out screencap -p > smoke/2_collection.png || true
alive "collection"
adb shell input swipe $(( W / 2 )) $(( H * 70 / 100 )) $(( W / 2 )) $(( H * 30 / 100 )) 300
sleep 3
alive "collection after scrolling"
adb shell input keyevent KEYCODE_BACK
sleep 2
tap 61 93          # Achievements tile
sleep 3
alive "achievements"
adb shell input keyevent KEYCODE_BACK
sleep 2
tap 16 94          # Shop tile
sleep 3
alive "shop"
adb shell input keyevent KEYCODE_BACK
sleep 2
tap 50 84          # Weekly goals
sleep 3
adb exec-out screencap -p > smoke/3_goals.png || true
alive "goals"
adb shell input keyevent KEYCODE_BACK
sleep 2
tap 36 62          # Progress card -> campaign map
sleep 4
adb exec-out screencap -p > smoke/4_map.png || true
alive "map"
adb shell input swipe $(( W / 2 )) $(( H * 75 / 100 )) $(( W / 2 )) $(( H * 25 / 100 )) 300
sleep 2
alive "map after scrolling"
adb shell input keyevent KEYCODE_BACK
sleep 2

tap 50 71          # PLAY: the first campaign level
sleep 4
adb exec-out screencap -p > smoke/5_level_start.png || true
for y in 60 63 66 69 72; do
  tap 50 $y        # "how to play" card of a first run: its button sits at one of these heights
  sleep 1
done
adb exec-out screencap -p > smoke/5b_intro_closed.png || true
for x in 20 22 50 52 80 78 35 36 65 64 50 20; do
  tap $x 60        # aim and drop in the board (later taps may land on the result card)
  sleep 1
done
sleep 2
adb exec-out screencap -p > smoke/6_level_playing.png || true
alive "campaign level"
adb shell input keyevent KEYCODE_BACK   # pause, or leave the result card
sleep 2
adb exec-out screencap -p > smoke/7_after_back.png || true
adb shell input keyevent KEYCODE_HOME   # background
sleep 3
adb shell am start -n $PKG/.MainActivity >/dev/null   # and back
sleep 4
adb exec-out screencap -p > smoke/8_resumed.png || true

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
echo "SMOKE OK: pid $PID alive after menu, collection, achievements, shop, goals, map, a campaign level, background and resume"
