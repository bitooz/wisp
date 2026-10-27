#!/bin/sh
# Export the debug APK and, if an Android phone is plugged in, install and start it.
set -e
cd "$(dirname "$0")/.."
godot --headless --path . --export-debug "Android" build/wisp.apk
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
if "$ADB" devices | grep -q "device$"; then
	"$ADB" install -r build/wisp.apk
	"$ADB" shell monkey -p com.bexruz.wispgame -c android.intent.category.LAUNCHER 1
else
	echo "No phone plugged in: build/wisp.apk is ready to install."
fi
