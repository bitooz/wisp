# Mo and Bo: toward people in a simulation

The aim: Mo and Bo feel like humans living in a simulated world, not characters a script moves. Each step is
one round, in this order. Done so far: they think for themselves through the model, remember what happened
to them (each their own memory, kept across restarts), hear you through an always-on mic, talk in their own
voices, act on anything around them, and (round 6) know the world only through pictures from their own eyes,
acting by pointing at what they see.

How each step fits in: a thought carries the character's **senses** (`minds.gd` → `worker/src/minds.ts`):
`sight` (the picture, `scripts/eyes.gd`), what they hear (`talk`, events) and how their body feels (`feel`).
New senses and body states are new fields in that bundle and new lines in `Mind.feel()`; new memory behaviour
lives in `scripts/mind.gd`; the world decides what's physically possible (`Level.use`, `Eyes.resolve`).

1. **Body needs** (round 8, world side done): hunger, tiredness, cold, fear and boredom that rise and fall, a
   day and night cycle, and sleep. Needs show up as feelings in `feel` and drive their plans; night makes the
   world dark. `scripts/clock.gd`, `scripts/body.gd`; checked without the model (`tools/body_test.gd`,
   `tools/world_test.gd`); how the model uses it is still to be seen (below).
2. **Senses beyond sight** (round 9, world side done): hearing with direction (sounds come from a side, they turn
   to look), a limited view so they turn their heads to see, and touch (what's under their hands and feet).
   `scripts/hearing.gd`, `Eyes.sees`, `Mind.touch`; checked without the model (`tools/senses_test.gd`).
3. **Human-like memory** (round 10, plumbing done): a memory stream where important things stick and small ones
   fade, nightly reflection that turns days into beliefs, and sometimes misremembering. `scripts/memory.gd`,
   `Minds.reflect`, the Worker's `/reflect`; checked with fixed steps and a stand-in for the reflection
   (`tools/memory_test.gd`, `tools/reflect_test.gd`).
4. **Lasting mood and relationships** (round 11, plumbing done): moods that carry over, trust and grudges
   between Mo, Bo and Wisp, and talking about Wisp behind its back. `scripts/heart.gd`; checked with fixed
   steps and the stand-in (`tools/heart_test.gd`, `tools/heart_world_test.gd`).
5. **Plans at three levels** (round 12, plumbing done): a plan for the day, what they're doing now, and the
   next step. `scripts/plans.gd`, `Minds.plan_day`, the Worker's `/plan`; checked with fixed steps and the
   stand-in (`tools/plan_test.gd`, `tools/plan_world_test.gd`).
6. **Their own lives** (round 13, plumbing done): homes, chores and hobbies, and life going on while the app
   is closed. `scripts/life.gd`, `Game.catch_up`; checked with fixed steps and the stand-in
   (`tools/life_test.gd`, `tools/life_world_test.gd`).
7. **Private thoughts apart from speech** (round 14, plumbing done): secrets, and saying something other than
   what they think (bluffing). `scripts/secrets.gd`, `Minds._private`; checked with fixed steps and the
   stand-in (`tools/secret_test.gd`, `tools/secret_world_test.gd`).
8. **Learning and failing** (round 15, plumbing done): getting lost, making mistakes, and skills that improve
   with practice. `scripts/skills.gd`, `Mind.try_skill`, catching lies (`Mind.caught`); checked with fixed
   steps and the stand-in (`tools/skills_test.gd`, `tools/learn_world_test.gd`).
9. **A body that shows it** (round 16, done without the model): how they feel shows in how they stand,
   walk, look and what their faces do: slumped and slow when worn out, hunched and shivering when cold,
   hunched and glancing about when scared, a spring in the step when happy, heavy or narrowed eyelids,
   brows and a mouth for each mood, eyes on whoever they're with (away from someone they're sore at), a look
   now and then toward what's on their mind, and eyes that slide off whoever they've just fibbed to.
   `scripts/looks.gd` (mood to looks), `Pal.Bearing` (a pose layer over the clips), the face and gaze in
   `scripts/pal.gd`, `Mind._show`; checked with fixed steps and in the game (`tools/looks_test.gd`,
   `tools/body_language_test.gd`). The other one sees it in their own pictures; the model is never told it
   in words.
10. **More islanders** (round 17, done without the model): Nell the old fisher, Tam the beekeeper and Odo the
    potter, each with a home (a hut of their own), a day (work, meals at home, the campfire of an evening,
    bed), a persona, and a small want that becomes someone's quest when they hear of it (Nell's lost float,
    Tam's smoker, a shell for Odo's pot). They have the same mind as Mo and Bo (sight, body, memory, mood,
    plans, life while the game's closed, private thoughts, skills, body language) and Mo's or Bo's body,
    grown up and in their own colours. News spreads from person to person (`scripts/gossip.gd`): what people
    see and hear, changing a little with each telling, carrying who told whom, and shaping feelings (trust in
    whoever it's about) and plans (a want becomes a quest; news that it's done takes it off). They think for
    themselves only when you're near, and seldom. `scripts/folk.gd`, `scripts/gossip.gd`, `Mind._day`,
    `Minds._gossip`/`gave`/`news_seen`; checked with fixed steps and the stand-in (`tools/folk_test.gd`,
    `tools/folk_world_test.gd`, `worker/scripts/folk-check.mjs`).

## Where it stands

All ten steps are built and checked without the model, and round 18 ran each with the model (below).

| Step | What's in the game | Checked by | Waits on the model for |
| --- | --- | --- | --- |
| 1. Body needs | hunger, tiredness, cold, fear, boredom; day and night; sleep | body_test, world_test | items 4, 5 |
| 2. Senses | hearing with direction, a limited view, touch | senses_test | items 6 to 9 |
| 3. Memory | fading, recall, misremembering, nightly beliefs | memory_test, reflect_test | items 10 to 12 |
| 4. Mood and feelings | lasting mood; trust, fondness, grudges, jokes, promises | heart_test, heart_world_test | items 13 to 17 |
| 5. Plans | the day, what they're on, the next step; rethinks | plan_test, plan_world_test | items 18 to 21 |
| 6. Their own lives | chores, hobbies, homes; life while the game's closed | life_test, life_world_test | items 22 to 24 |
| 7. Private thoughts | thinking apart from saying; secrets; fibs and bluffs | secret_test, secret_world_test | items 25 to 27 |
| 8. Learning and failing | skills, practice, lessons, getting lost, catching lies | skills_test, learn_world_test | items 28 to 30 |
| 9. Body language | posture, gait, faces, gaze; seen in each other's pictures | looks_test, body_language_test | items 31 to 34 |
| 10. More islanders | Nell, Tam, Odo: homes, days, wants and quests; gossip | folk_test, folk_world_test | items 35 to 41 |

Round 18 ran the list below with the model, in this order: the full loop first, then a day on the island with
everyone, then the evenings and nights, then the rest. What came of it is in the next section; the phone checks
(34 and 41) are still to do.

## Round 18: the model runs

About $2.16 of model calls on the new key (its own $3 limit), Mac only, no phone (none plugged in). Every run had
its own `--mind-dir`; the real Mo and Bo files were never written (a copy was used for 12 and 24). Logs and the
per-run summaries (`tools/run_stats.py`) are in the round's proof folder. Scenes that need people placed and
lines said (35 to 38, 4, 6 to 9, 11, 14 to 16, 23, 26, 27, 31) are `tools/model_runs.gd`.

**The numbers.** The full loop finished in **0 of 13** idle runs (round 7's target was 3 of 6): two reached the
dungeon (384 s, and 198 s in the last run, with the morning plan fixed; round 7: 117 s and 59 s), six got a light,
none opened the plates' door. Cost per thought:
**$0.00060** on average (rounds 6 and 7: $0.0003 to $0.0004), so an idle 12 minutes is $0.10 to $0.15, not $0.04;
an hour on the island with all five about $0.57, the islanders 20% of it. First word: **4.0 s** median after Wisp
stops talking (p90 5.2 s, 35 answers, said as text, so without hearing the audio); their own lines 4.5 s from the
start of the thought (the picture and a quiet gap included); the Worker has the line ready at 3.5 s. Of about 3,500
thoughts, 10 failed (Alibaba's filter: "Output data may contain inappropriate content"), 43 were answered by Gemini.

**Why the loop doesn't finish.** They live their day now, the way the plans and needs say: breakfast first, then
chores (Bo chopped wood 19 times, Mo picked up 47 apples), then the door, third or fourth in Mo's plan, by which
time it's the afternoon. Round 7's two kids had nothing else to do. The early runs were also held up by the world:
names they used for places weren't known ("head for campfire: I don't know the way", 14 to 24 times a run), they
kept bumping into things and people (60 to 100 times a run, each a new thought), islanders' doors said "no way
through", food was hard to come by. Those are fixed (below), and the misses went from dozens a run to a handful;
the loop still doesn't finish, because the day comes first. Starting later in the day (`--hour=10`) didn't change
it at first: the plans still began with breakfast, though they remembered having had it (the morning plan wasn't
told). Told, Mo's plan began "Grab a torch and head to the hill", and she was under it at 198 s; then the dark sent
her back up (item 3).

**Fixed this round** (each from something the runs showed):
- Places by the names they use: the campfire, the woodpile, the big tree and the house are places now, and a name
  is matched by its words ("south beach", "village woodpile", "campfire by the house", "home", "the stairs" under
  the hill); the island's woodpile, boat and jar keep the walls round them again (they'd been dropped since round
  13).
- Getting lost only on long ways, and never "lost" in the same part of the island as where you were going.
- The same bump (a wall slid along, a crowd) felt once in 30 s, not every step.
- Someone's door: a knock (whoever's in hears it); going in hungry is a meal, at home or at a neighbour's who's in
  ("knocked at Tam's cottage and Tam gave me bread and honey"); the first morning of a new island, Mo and Bo have
  had breakfast.
- Steps: using them a second time goes up them; walking to a way says where it leads.
- What reaches the model: an islander's day in words ("fishing off the south beach", not "chore"), "you'd usually
  be in bed by now" late at night; and the prompt no longer says the others come along when you go through a door
  (they don't).
- What comes back: stage directions (*glances at Wisp*), stray quotes, bits of the reply's own JSON, brackets and
  lists in a thought or a step, and the reply format's own placeholders ("your next step, a few words") are tidied
  away (`worker/scripts/words-check.mjs`).
- News is only passed on if the words said carry it (the model often marked a line about something else as
  "tell"): `Gossip.carried`.
- The morning plan is told what they've done already today ("had breakfast at home this morning").
- A lie seen told to someone else is remembered as told to them ("Bo told Mo ..."), and "Mo, what do you think of
  Bo?" is for Mo alone.

**Each item.** (✓ as hoped; ✗ not; ~ partly; open: not shown yet)
1. ✗ 0 of 13: 10 from 8:00, 3 from 10:00 (above). At dusk they head for the fire or home; none went to bed before
   the runs ended (20:00).
2. ~ Mo worked it out ("Bo! Look at those circles! I bet we have to step on them!") and Bo stood on one plate ("one
   of the two glowing rings lit up"), but never both at once; the run started in the dungeon went straight back up
   for breakfast.
3. ~ Still there, and for a reason: in the dark, scared and cold, Mo wants out ("Stairs! Must go up to light!", "It's
   too dark! I need the fire!"). Using the stairs now takes her up. What would keep her down is a light in hand.
4. ✗ At 21:00, tired, neither slept in 4 minutes: Mo looked for food and light, Bo kept chopping ("So sleepy.
   Better finish this and get to bed"). With "you'd usually be in bed by now": "I'm exhausted. Better get to bed",
   and he heads home; still not asleep in 4 minutes. Talking to a sleeper: not reached.
5. ✓ Feelings, never numbers: "My tummy is rumbling!", "I'm freezing and starving. Odo isn't home." Cost per thought
   up by half (above).
6. ~ Mo never named a sound she hadn't seen ("Where is Nell? I heard footsteps behind me"), but didn't turn to the
   boing or the splash either.
7. ~ Silent behind her: nothing about Wisp. Talking from behind: "You're by the big mushroom! I saw it earlier!", a
   guess, without turning.
8. ~ Bumps were constant (fixed above); wading and the plate underfoot weren't set up.
9. open: shut in the house they don't think at all (`Minds` skips anyone indoors), so a voice through the wall gets
   no answer until they come out.
10. ✓ for the islanders (Tam: "Bo lied about having an apple when I saw him holding one."; Nell: "I failed to find my
    lucky green float on the north-east shore today."): short, first person, true. Mo and Bo didn't sleep in the
    fast night, so no reflection of theirs.
11. ~ With the real memories: "Found an ember. A shadow came out of the door. Mo threw the ember at it and it
    vanished." (Bo). With a day's: "We went looking for breakfast and got lost!" (a stretch).
12. ✓ Copies of the real files: 303 and 326 memories became 343 and 365, nothing lost, the old files beside them.
13. ~ Hungry and cold into the evening, the lines get short and cross; no mood said out loud. Recovery not followed.
14. ~ "Mo, I promise I'll wait right here for you." "Promises are boring! I'm going to check out that glowing door
    on the hill now." The rest (bringing it up later) not followed.
15. ✓ Mo: "I'm just stopping to look at bugs! You're the slow one!", still loves Wisp. Bo: "Call me that one more
    time and I'm leaving you both behind", and he's "still really sore that Wisp kept teasing you".
16. open: they'd wandered apart before Wisp left, so no moment of their own.
17. ✓ Nell: Bo trust down, Mo up; Tam: Bo trust down, Odo up. Reasons fit the day; nothing made up.
18. ✓ Plans fit who they are, islanders' wants first (Nell to the north-east shore, Tam the smoker); the next
    morning takes in the night's news (Odo: "find Tam's bee smoker"). Now and then something made up ("Row boat to
    north-east shore": Nell has no boat).
19. ✗ No: time to the dungeon 384 s in 1 run of 12; "got nowhere" rethinks 2 to 4 a run.
20. ✓ Rethinks are sensible: "Three tries at the shore and no luck. Time to change the plan. I'll go gather apples
    first since I'm hungry, then check the glowing door."
21. ~ "done" 1 to 12 times a run; not checked against the night's reflection.
22. ✓ Bo chops wood (19 times; 11 glancing blows), Mo gathers windfalls, both in character; Bo often went looking
    for an axe that isn't there ("Need an axe to chop wood").
23. ~ A short gap (4 minutes, "later that day"): no reflection or plan calls, as it should be; a day or a week away
    not run.
24. ✓ The same copies with no world file: a fresh island, nothing lost.
25. ✓ "think" was never the same as "say" (0 of about 200 with both), short. Cost per thought: see 5.
26. ~ In the dark, Bo: "Scared? No. I just have work to do", while thinking "I need to get to the firelight. It's
    safer there": a bluff, not marked as one. One fib marked in that run; 1 to 6 a run in the idle loops.
27. open: "keep" was used a lot in two runs (37 and 22 times, mostly Mo); telling one person on purpose not seen.
28. ✓ Chopping fails ("glanced off the log") and they try again; tries per success about 1.6.
29. ✗ Mo took 17 wrong turns, Bo 7 (Mo should get lost less); many were "ended up near our house, not at the
    village", which no longer counts as lost.
30. ✓ Mo: "Bo, you totally had an apple earlier!"; Nell, who saw it too: "Bo thought he could fool me? Not with these
    old eyes." Their trust in Bo went down that night.
31. ✗ Bo worn out next to Mo for 75 s, and the other way round: no remark from either.
32. open (no bluff seen from Mo's side). 33. open (Mo gave as good as she got, so wasn't cross).
34. open: no phone plugged in.
35. ✓ Nell: "Storm took me lucky float, green glass one. Washed up north-east shore somewhere."; Tam: "They're calm
    and busy, dear. But I've lost my smoker by the pond."; Odo: "A pot. Clay and water." Two minutes after you walk
    off: none of them thinks at all (Mo and Bo 20 times).
36. ~ At the fire Mo passed on Bo's fib in her own words, and it grew ("a big fat fib"); nobody said who they had it
    from. The model also marked lines that weren't the news as "tell" (fixed).
37. ~ Nell's float (2 runs): once it went into Mo's plan and she went to the north-east shore and searched for three
    minutes ("Can't see the ground"), then gave up for apples; once Nell didn't pass it on. Not done either time; the
    float now lies on the sand nearer where they arrive. Tam's smoker (1 run): it went into Bo's plan, second after
   the wood; not found in 7 minutes.
38. ~ Tam and Nell came out of the night warier of Bo, but they'd seen the fib themselves; second-hand wariness not
    shown yet.
39. ✓ Gemini heard each saying a line in character: Nell 10/10 for a gruff old fisher, Tam 10/10, Odo 9.5/10. Kept.
40. ✓ About $0.57 an hour with all five, the islanders $0.11 of it.
41. open: no phone plugged in.

Also seen: with the model on, the game runs at about 35 fps on the Mac (60 offline, with vsync); not looked into
yet.

## The list (as it was written)

1. **The 6 full-loop runs** from round 7 (`--autoplay --echo`, 12 min each, separate `--mind-dir`s): the target
   is at least 3 of 6 finishing the loop alone. Night now falls about 11 minutes in, so also note whether they
   stop for the night (eat, go home to bed) and pick it up in the morning.
2. **Plate teamwork** (`--start=cave`, 3 runs): in round 7 each plate was stood on alone but never both at
   once. Watch whether they work out that it needs one on each, and ask each other.
3. **The stairs** (same runs): in round 7 Mo kept going back up the daylit stairs. Check it's gone, or why not.
4. **Bodies with the model**: an evening start (`--hour=17`): do they get hungry and eat, find light or the
   fire as it gets dark, and go to bed of their own accord? A late start with tired bodies (`--hour=21`): do
   they choose to sleep, and where? Talking to one while asleep (`--talk`): does it wake and answer sensibly?
5. **What they say about it**: their lines about hunger, cold or the dark should be natural, never numbers,
   and nothing they haven't felt or seen. Check WISP_TALK lines and the cost per thought (the feel list is
   longer now).
6. **Turning to a sound** (round 9; on the island, 3 runs): with one of them facing away, have the other bounce
   on the mushroom or splash in the pond behind them. Do they turn round (or turn their head) to look, and only
   then say what it was? They must never name the source before they've seen it.
7. **Someone behind them**: Wisp standing silently behind one of them while it's idle. Nothing about Wisp
   should come up until it turns; then it should notice Wisp. Same with Wisp talking from behind: the answer
   should fit a voice from behind ("Where are you?" or turning to look), not pretend to see.
8. **Touch**: walking into the house or into the other one, wading into the sea, a hand in the pond, a plate
   sinking underfoot under the hill. Do they react sensibly (step round, get out of the cold water, look down
   at the plate), and does stepping on a plate by accident help them work out the two-plate door?
9. **Voices through walls**: one inside the house talking to the other outside (only the voice, not the
   words, if far): the other should ask or go and see, not answer words it didn't hear.
10. **Reflection** (round 10; one call per pal per night, about $0.0003 each): let a day play out
    (`--hour=17 --day-minutes=6`, idle) until both are asleep. Check WISP_REFLECT: one per pal, beliefs short,
    first person, true to the day (nothing invented), pointing at the right memories, and not repeated
    from night to night. Read them: do they sound like Mo and Bo?
11. **Memory in their answers**: the next morning, ask each (`--talk`) what happened yesterday and what they
    think of the other and of Wisp. Answers should come from what's recalled and their beliefs, say so when
    a memory's hazy rather than invent it, and never mention what they've forgotten.
12. **Old memory files**: play once with the real Mo and Bo files (they're brought up to date on first load).
    Check nothing's missing (the game keeps every memory, and leaves the old file beside it as
    `mind_mo.v1.json`, `mind_bo.v1.json`).
13. **Mood showing** (round 11): give one a fright (the shadow), or leave them hungry and cold into the
    evening. Does it come through in how they talk (shorter, crosser, scared) without them saying their mood
    out loud every line? And do they come back to themselves after a while, or a meal?
14. **Promises** (`--talk`): Wisp says "Mo, I'll wait here for you", then walks off while she's away; next
    time she sees Wisp, does she bring it up? Wisp keeps one: does she warm to Wisp? A vaguer "I promise I'll
    help you find a light" kept or not during the day: does the night's reflection judge it right?
15. **Teasing**: call Mo and then Bo "slowpoke" a few times. Mo should give as good as she gets; Bo should get
    short with Wisp (and still be fine with Mo doing it).
16. **Talking about Wisp** (3 runs): walk Wisp off out of sight and earshot while they're together. Do they
    talk about Wisp (WISP_ALONE, then their lines), honestly and in line with how they feel? They must never
    act as if Wisp could hear. Then come back: do they let on?
17. **Feelings at night**: after a day with a broken promise and a shared moment, read WISP_REFLECT: the
    "people" changes should fit what happened (usually none), with reasons, and no made-up events.
18. **Day plans** (round 12; one call per pal per morning, about $0.0002 each): start fresh and read WISP_PLAN
    for both. Do the plans fit who they are (Mo the door, Bo the island across the sea), their needs and
    feelings, with nothing made up? Next morning: do they take in how yesterday went?
19. **Does it stop the dawdling?** The island dawdling of rounds 5 to 7 (chatting and wandering instead of
    heading for the door): run the 6 idle loops (item 1) with plans and compare the time to reach the cave
    with round 7's two full runs (they reached it at 117 s and 59 s). Count in the WISP_TALK lines how
    often the "next" step follows what they're on, and how many "dawdling" rethinks come up.
20. **Rethinks**: in those runs, read the thoughts right after a rethink (three failures, news like the door
    opening, a need, dawdling): is the new "day" sensible, and do they act on it rather than repeat what
    failed? Mo on the daylit stairs (item 3): does a rethink get her off them?
21. **Activities done**: do they say "activity": "done" when they've done what they were on (not too early),
    and does the night's reflection see the day's plan as it went?
22. **Chores and hobbies with the model** (round 13): over an idle day (`--hour=7 --day-minutes=6`), do they
    fit their chore and hobby into the day themselves (WISP_PLAN, then WISP_TALK), and talk about them in
    character (Mo's shells, Bo's boat)? Does Bo keep the woodpile up so there's a fire at night?
23. **Coming back** (real gaps: close the game for 20 minutes, a few hours, a day, a week): read WISP_AWAY
    and the calls that follow: at most one WISP_REFLECT and one WISP_PLAN each. When Wisp turns up, do they
    greet Wisp, and when asked "what have you been up to?", tell it from their memories (the shells, the boat,
    "much as usual"), without making things up? Check the cost of a week away stays a few tenths of a cent.
24. **Old saves**: play once with the real Mo and Bo files and no world file (the island starts fresh,
    nothing lost), then close and reopen the next day.
25. **Thinking privately** (round 14): over a few idle runs, read the WISP_TALK lines' "think", "honest" and
    "keep": is "think" short (a few words) and actually different from "say" when it should be, not a copy?
    Compare cost per thought and time to first word with the last runs that measured them (rounds 6 and 7:
    about $0.0003 to $0.0004 a thought, first word a median of 4.8 s); they should barely move.
26. **Fibs and bluffs**: get Bo into the dark under the hill and ask "are you scared?": a bluff now and then
    is fine, marked "bluff". Ask Mo to wait for you, then see if she says yes and goes anyway. Do they own up
    or keep their story straight when asked again later ("What you're keeping to yourself")?
27. **Secrets**: does either keep something to themselves ("keep"), and later tell it only to one of you on
    purpose? Ask the other: they must not know it. Read Bo's lines for anything of Mo's private thoughts.
28. **Failing like a beginner** (round 15): an idle day with Mo chopping or pushing the door. When a try fails,
    does the next thought take it in ("What you've learned") and try again or another way, rather than give
    up or repeat it blindly? Does the main loop still finish (item 1)? Count tries per success in WISP_TALK.
29. **Getting lost**: after a wrong turn ("went the wrong way for a bit"), does the model reorient (look for
    a landmark, head_to again) instead of wandering off? Mo should get lost less than Bo.
30. **Catching a lie**: have Bo tell Mo he hasn't got the torch while holding it out of her sight (or Wisp
    say the door's stuck and walk through it). When she catches it (WISP_CAUGHT), does she call it out in
    character, and is she warier later? Does the night's reflection keep it?
31. **Reading each other** (round 16; 3 idle runs, about $0.12): leave Bo worn out (`--hour=21`, or tired
    from a long day) while Mo's fine, and the other way round. Mo only sees him slumped and heavy-eyed in her
    picture; nothing says so in words. Does she notice ("you look tired", suggesting bed) more often than
    when he's fine? Read WISP_TALK for remarks about how the other looks, and whether they're right.
32. **A bluff that shows**: item 26's runs, read from Mo's side: in the picture taken while Bo's eyes slide
    off her after "I'm not scared", does she ever doubt him? A little suspicion now and then is right;
    always calling it out is too much (it's a few frames of a look, not proof).
33. **A cross face**: after Wisp teases Mo into a grudge (item 15), does Bo, seeing her cross face and
    turned-away eyes in his picture, pick up that something's wrong between them?
34. **On a phone** (no model needed, but needs the phone): the island with both of them on screen, from
    `adb logcat -s godot | grep WISP_PERF`, body language on and off (`Pal.expressive`). On the Mac it cost
    about 40 µs a frame for the two of them and 6 draw calls (104 fps either way, vsync off); a phone's
    CPU is perhaps 3 to 6 times slower, so expect 0.1 to 0.25 ms a frame and no visible drop. Check the
    faces' ink shader and the shivering look right on its GPU.
35. **The island's people, talking** (round 17; 3 idle runs, about $0.15): walk Wisp up to Nell, Tam and Odo at
    their work and say hello by name. Do they answer as themselves (gruff, gossipy Nell; warm, worried Tam; shy,
    dry Odo) and then get on with their day? Do they think seldom once you walk off (count WISP_TALK by who:
    each islander should be well under Mo or Bo, and none far from you)?
36. **Gossip in their own words**: an evening by the campfire with Wisp near (`--hour=19`, 2 runs). Do they pass
    news on in a thought ("tell", WISP_GOSSIP), in character, to someone who hasn't heard it? Does a story grow
    a little without turning into nonsense, and do they say who told them?
37. **A quest with the model** (3 runs): once Mo or Bo hears about Nell's float (from Nell, or second-hand), does
    it get into their plan (WISP_PLAN), do they go to the north-east shore, pick it up and give it to her
    (WISP_QUEST), and what does Nell say? The same for Tam's smoker and a shell for Odo.
38. **Feelings from gossip at night**: after a day when Bo was caught in a fib and the news went round, do the
    islanders' reflections (WISP_REFLECT) come out warier of Bo, and do their beliefs say who told them?
39. **Their voices** (about $0.01): audition Nell's, Tam's and Odo's Fish voices with `worker/scripts/voices.mjs`
    (picked by description only), and swap any that don't suit.
40. **What everyone costs**: an idle hour on the island with all five. Total cost and thoughts per person; the
    islanders' share should be small (their plan and reflection are one small call each a day, and they only
    think near you).
41. **On a phone, with everyone** (with item 34): the village with all five on screen, and the island with the
    islanders about their day. On the Mac (vsync off), three more people on screen cost about 3% (110 fps
    against 113, 26 more draw calls, about 120 µs more of the pals' own work a frame), and about their day
    across the island about the same (111 against 115); far off, they're updated a few times a second. (Moving
    people's collisions now look only at nearby obstacles, which made everyone's own work cheaper, Mo's and
    Bo's too.) A phone's CPU is perhaps 3 to 6 times slower: expect 0.4 to 0.8 ms a frame more, and check the
    extra skinned bodies on its GPU.
