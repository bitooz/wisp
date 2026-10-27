#!/bin/sh
# Times /think N times with a spoken WAV: when the line is ready and when the first of the voice arrives (ms).
#   scripts/bench.sh <body.json> <wav> [n]
n=${3:-6}
for i in $(seq $n); do
  node "$(dirname "$0")/try.mjs" "$1" --wav="$2" | awk '/"type":"say"/{s=$1} /first audio/{a=$1} /"type":"done"/{match($0,/"say":"[^"]*"/); t=substr($0,RSTART+6,RLENGTH-7)} END{printf "say %5d  voice %5d  %s\n", s, a, t}'
done
