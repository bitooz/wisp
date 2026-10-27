#!/bin/sh
# Point the phone's game at the mind server on this Mac (mindserver/, over the local network), or back at the
# Worker. Writes the phone's user://brain.json (Brain: it goes over res://brain.json) through adb.
#   tools/minds_lan.sh [mo:claude,bo:codex]    this Mac's address on the network, the mind server's key
#   tools/minds_lan.sh --off                   back to the Worker
# The phone and the Mac need to be on the same network, and the mind server running (cd mindserver && npm start).
set -e
cd "$(dirname "$0")/.."
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
PKG=com.bexruz.wispgame
if [ "$1" = "--off" ]; then
	"$ADB" shell run-as $PKG rm -f files/brain.json
	echo "The phone thinks with the Worker again."
	exit 0
fi
IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
KEY=$(cat mindserver/.state/key)
PORT=$(node -e "try{console.log(require('./mindserver/settings.json').port||8790)}catch{console.log(8790)}")
MINDS=$(node -e "const o={};for(const p of (process.argv[1]||'mo:claude,bo:codex').split(',')){const [k,v]=p.split(':');o[k]=v}console.log(JSON.stringify(o))" "$1")
echo "{\"url\": \"http://$IP:$PORT\", \"key\": \"$KEY\", \"minds\": $MINDS}" | "$ADB" shell run-as $PKG sh -c "'cat > files/brain.json'"
echo "The phone now thinks through http://$IP:$PORT ($MINDS). Restart the game on the phone."
