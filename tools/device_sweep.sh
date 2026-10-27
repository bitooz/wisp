#!/bin/sh
# Try quality settings on the plugged-in phone: each argument is a JSON object of
# overrides (see Game.quality); prints the frame rate and GPU times on the island.
#   tools/device_sweep.sh '{}' '{"scale": 0.6}'
cd "$(dirname "$0")/.."
PKG=com.bexruz.wispgame
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
for q in "$@"; do
	"$ADB" shell am force-stop $PKG
	"$ADB" shell run-as $PKG sh -c "'mkdir -p files && rm -f files/autoplay && echo '\''$q'\'' > files/quality'"
	"$ADB" logcat -c
	"$ADB" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
	sleep 22
	echo "== $q"
	"$ADB" logcat -d -s godot | grep -E "WISP_PERF|WISP_PROF" | tail -6 | sed "s/^.*WISP_//"
done
"$ADB" shell run-as $PKG sh -c "'rm -f files/quality'"
"$ADB" shell am force-stop $PKG
