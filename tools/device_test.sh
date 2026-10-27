#!/bin/sh
# Play the whole loop by itself on the plugged-in phone and report frame rate:
#   tools/device_test.sh [out_dir] [autoplay args, e.g. --memory or --mic]
# Installs build/wisp.apk, starts it in autoplay mode, collects WISP_PERF lines and the
# autoplay checks from logcat, and pulls its screenshots into out_dir.
set -e
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/wisp-device}"
shift 2>/dev/null || true
EXTRA="$*"
PKG=com.bexruz.wispgame
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
mkdir -p "$OUT"
"$ADB" install -r build/wisp.apk >/dev/null
"$ADB" shell am force-stop $PKG
"$ADB" shell run-as $PKG sh -c "'mkdir -p files && rm -rf files/shots && echo --shots=user://shots $EXTRA > files/autoplay'"
"$ADB" logcat -c
"$ADB" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null
# Wait for the run to finish (or give up after 15 minutes: left alone, the whole loop takes several)
i=0
until "$ADB" logcat -d -s godot | grep -q -E "DONE: |FAILED"; do
	i=$((i + 1)); [ $i -gt 450 ] && break; sleep 2
done
"$ADB" logcat -d -s godot > "$OUT/logcat.txt"
grep -E "WISP_PERF|WISP_TALK|WISP_HEAR|WISP_STAGE|WISP_MINDS|WISP_EARS|autoplay" "$OUT/logcat.txt" | sed 's/^.*godot *: //' > "$OUT/run.log" || true
"$ADB" shell run-as $PKG sh -c "'rm -f files/autoplay'"
rm -rf "$OUT/shots"; mkdir -p "$OUT/shots"
for f in $("$ADB" shell run-as $PKG ls files/shots 2>/dev/null); do
	"$ADB" exec-out run-as $PKG cat "files/shots/$f" > "$OUT/shots/$f"
done
"$ADB" shell am force-stop $PKG
cat "$OUT/run.log"
