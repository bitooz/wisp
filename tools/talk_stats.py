#!/usr/bin/env python3
"""Sums up Mo's and Bo's thoughts from logs (the WISP_TALK lines): time to their first word, and cost.
    python3 tools/talk_stats.py run.log [more.log ...]
Time to first word runs from the end of what you said (the talk button let go, or the phrase tapped) to the
first sound of their voice on the device. Voice cost is at Fish Audio's paid s2.1-pro price ($15 per million
UTF-8 bytes); the free tier the Worker uses (s2.1-pro-free) costs nothing."""
import json, statistics, sys

FISH_PER_BYTE = 15 / 1e6
rows = []
for path in sys.argv[1:]:
    for line in open(path, errors="replace"):
        if "WISP_TALK " in line:
            rows.append(json.loads(line.split("WISP_TALK ", 1)[1]))

def q(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else None

def show(name, sel):
    firsts = [r["ms_first_word"] for r in sel if r.get("ms_first_word")]
    says = [r["ms_say"] for r in sel if r.get("ms_say", -1) > 0]
    if not sel:
        return
    print(f"{name:28} n={len(sel):3}  first word: median {q(firsts, .5)} ms, p90 {q(firsts, .9)} ms"
          f"  (line ready: median {q(says, .5)} ms)")

done = [r for r in rows if r.get("model")]
print(f"{len(rows)} thoughts, {len(done)} answered, {len(rows) - len(done)} cut off or failed "
      f"({', '.join(sorted(set(r.get('error', '') for r in rows if not r.get('model'))))})")
show("you spoke (mic / WAV)", [r for r in done if r["why"] == "heard" and r.get("audio_in")])
show("you tapped a phrase", [r for r in done if r["why"] == "heard" and not r.get("audio_in")])
show("their own (idle/event/chat)", [r for r in done if r["why"] != "heard"])
spoken = [r for r in done if r.get("say") and not r.get("dropped")]
model = [r.get("cost", 0) for r in done]
voice = [r.get("voice_chars", 0) for r in spoken]
print(f"model cost per thought: mean ${statistics.mean(model):.5f}" if model else "")
audio = [r.get("cost", 0) for r in done if r.get("audio_in")]
if audio:
    print(f"  per thought hearing your voice (incl. writing down your words): mean ${statistics.mean(audio):.5f}")
if voice:
    vb = statistics.mean(voice)
    per_line = statistics.mean([r.get("cost", 0) for r in spoken]) + vb * FISH_PER_BYTE
    print(f"voice: {vb:.0f} bytes a line, $0 on s2.1-pro-free, ${vb * FISH_PER_BYTE:.5f} on s2.1-pro")
    print(f"per spoken line, model + voice: ${per_line:.5f} with paid voice, ${per_line - vb * FISH_PER_BYTE:.5f} as run")
print(f"fell back to Gemini: {sum(1 for r in done if 'gemini' in r.get('model', ''))}; "
      f"hedge started: {sum(1 for r in done if r.get('fell_back'))}")
print(f"lines held back: {sum(1 for r in rows if r.get('dropped'))} "
      f"({', '.join(sorted(set(str(x) for r in rows for x in r.get('dropped', []))))}); "
      f"actions refused: {sum(1 for r in rows if r.get('checked', 'ok') != 'ok' or r.get('rejected'))}")
