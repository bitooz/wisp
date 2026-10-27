#!/usr/bin/env python3
"""What a run with the model shows, from its log (the WISP_* lines), for the roadmap's model runs:
    python3 tools/run_stats.py run.log [more.log ...]
Per log: how far the loop got, thoughts and cost by who, plans, rethinks, what didn't work, wrong turns,
gossip and quests, reflections. Then all logs together: completion, first word, cost per thought."""
import collections, json, re, statistics, sys

MILESTONES = ["cave", "light", "opening", "gloom", "ember", "exit", "home", "end"]


def rows(path, tag):
    out = []
    for line in open(path, errors="replace"):
        if tag + " " in line:
            try:
                out.append(json.loads(line.split(tag + " ", 1)[1]))
            except json.JSONDecodeError:
                pass
    return out


def q(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else None


everything = []
finished = 0
for path in sys.argv[1:]:
    text = open(path, errors="replace").read()
    talk = rows(path, "WISP_TALK")
    everything += talk
    reached = dict(re.findall(r"\] reached (\w+) at (\d+) s", text))
    if "end" in reached:
        finished += 1
    print(f"== {path.split('/')[-1]}: reached {', '.join(f'{k} {v} s' for k, v in reached.items()) or 'nothing'}")
    by = collections.Counter(r["who"] for r in talk)
    cost = collections.defaultdict(float)
    for r in talk:
        cost[r["who"]] += r.get("cost", 0)
    plans = rows(path, "WISP_PLAN")
    refl = rows(path, "WISP_REFLECT")
    extra = sum(r.get("cost", 0) for r in plans + refl)
    print(f"  thoughts {len(talk)} ({', '.join(f'{w} {n}' for w, n in by.most_common())}); cost ${sum(cost.values()):.4f} thoughts"
          f" + ${extra:.4f} plans/reflections ({', '.join(f'{w} ${c:.3f}' for w, c in sorted(cost.items(), key=lambda x: -x[1]))})")
    for p in plans:
        print(f"  plan {p.get('who')} day {p.get('day')}: {'; '.join(p.get('plan', [])) or p.get('error', '')}")
    ev = collections.Counter()
    for r in talk:
        e = r.get("event", "")
        for k, pat in [("rethinks", r"time to rethink"), ("dawdling", r"rethink[^;]*(a while and got nowhere|dawdl)"),
                       ("don't know the way", r"don't know the way"), ("no way through", r"no way through"),
                       ("nothing to lift", r"nothing there I could lift"), ("wrong turns", r"went the wrong way"),
                       ("bumps", r"bumped|stumbled"), ("knocks", r"knocked at")]:
            ev[k] += len(re.findall(pat, e))
    wrong = collections.Counter(r["who"] for r in talk if "went the wrong way" in r.get("event", ""))
    print(f"  events: {dict(ev)}; wrong turns by who: {dict(wrong)}")
    done = sum(1 for r in talk if r.get("activity") == "done")
    thinks = [r for r in talk if r.get("think") and r.get("say")]
    same = sum(1 for r in thinks if r["think"].strip().lower() == r["say"].strip().lower())
    print(f"  activity done: {done}; thought and said both: {len(thinks)} (identical {same}); bluffs/fibs: "
          f"{sum(1 for r in talk if r.get('honest') in ('false', 'bluff'))}; kept: {sum(1 for r in talk if r.get('keep'))}; told news: {sum(1 for r in talk if int(r.get('tell', 0) or 0) > 0)}")
    goss = rows(path, "WISP_GOSSIP")
    quests = rows(path, "WISP_QUEST")
    print(f"  gossip passed {len(goss)}; quests done {len(quests)} {[(x['by'], x['who']) for x in quests]}; reflections {len(refl)}"
          f"; caught out {text.count('WISP_CAUGHT')}; alone moments {text.count('WISP_ALONE')}")
    errs = collections.Counter(r.get("error", "")[:60] for r in talk if r.get("error"))
    if errs:
        print(f"  errors: {dict(errs)}")

print("== all")
answered = [r for r in everything if r.get("model")]
heard = [r["ms_first_word"] for r in answered if r.get("why") == "heard" and r.get("ms_first_word")]
own = [r["ms_first_word"] for r in answered if r.get("why") != "heard" and r.get("ms_first_word")]
ready = [r["ms_say"] for r in answered if r.get("ms_say", -1) > 0]
if len(sys.argv) > 2:
    print(f"loop finished: {finished} of {len(sys.argv) - 1}")
print(f"thoughts {len(everything)}, answered {len(answered)} ({len(everything) - len(answered)} failed or cut off)")
if answered:
    print(f"cost per thought: mean ${statistics.mean(r.get('cost', 0) for r in answered):.5f}, median ${q([r.get('cost', 0) for r in answered], .5):.5f}")
if heard:
    print(f"first word after you stop talking: median {q(heard, .5)} ms, p90 {q(heard, .9)} ms (n={len(heard)})")
if own:
    print(f"first word of their own lines (from when the thought began, incl. the picture and a quiet gap): median {q(own, .5)} ms (n={len(own)})")
if ready:
    print(f"line ready (Worker): median {q(ready, .5)} ms")
print(f"Gemini answered: {sum(1 for r in answered if 'gemini' in r.get('model', ''))}; hedge started: {sum(1 for r in answered if r.get('fell_back'))}")
