#!/bin/sh
# The phone's real microphone, always listening: this Mac says a line out loud next to it (the phone must be
# near the Mac's speakers), and the game should hear it and Mo answer:
#   tools/device_mic_test.sh [out_dir]
set -e
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/wisp-mic}"
PKG=com.bexruz.wispgame
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
mkdir -p "$OUT"
"$ADB" shell pm grant $PKG android.permission.RECORD_AUDIO
"$ADB" shell am force-stop $PKG
"$ADB" shell run-as $PKG sh -c "'mkdir -p files && echo --mic --dump-minds > files/autoplay'"
"$ADB" logcat -c
"$ADB" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null
i=0
until "$ADB" logcat -d -s godot | grep -q WISP_MIC_OPEN; do
	i=$((i + 1)); [ $i -gt 60 ] && break; sleep 1
done
say -v Samantha "Mo, what are you doing over there?"
i=0
until "$ADB" logcat -d -s godot | grep -q -E "DONE: |FAILED"; do
	i=$((i + 1)); [ $i -gt 40 ] && break; sleep 2
done
"$ADB" logcat -d -s godot | grep -E "WISP_TALK|WISP_HEAR|WISP_EARS|autoplay" | sed 's/^.*godot *: //' > "$OUT/run.log" || true
"$ADB" exec-out run-as $PKG cat files/last_heard.wav > "$OUT/last_heard.wav" 2>/dev/null || true
"$ADB" exec-out run-as $PKG cat files/last_raw.wav > "$OUT/last_raw.wav" 2>/dev/null || true
"$ADB" shell run-as $PKG sh -c "'rm -f files/autoplay'"
"$ADB" shell am force-stop $PKG
cat "$OUT/run.log"
