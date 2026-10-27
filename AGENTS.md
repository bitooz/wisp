# Wisp (Godot 4.7, GDScript)

- Run: `godot --path .`. Test: `godot --path . -- --autoplay --shots=<dir>` plays the full loop through
  the touch HUD, prints `ok:`/`FAIL:` checks and exits non-zero on failure; `--shots-limit=N` stops after N screenshots.
  Screenshots come from the game's own viewport (never capture the screen).
- Export: `tools/install.sh` (debug APK to `build/wisp.apk`, installs via adb if a phone is plugged in).
- The world is built in code from the mock's numbers (`scripts/build.gd` mirrors three.js shapes and Euler order).
  Keep the mock's values when porting more of it.
- Colour pipeline: the 3D renders into a see-through SubViewport over the 2D CSS-like backdrop, so the sky keeps
  exact colours while the 3D is tone mapped (ACES at the mock's exposure). Lights use three.js intensities through
  `Build.set_light` (divides by pi). Re-check with `godot --path . res://tools/calib.tscn` after renderer changes.
- Point-light shadows stay off.
- The island's ground is Terrain3D, built at runtime in `scripts/island.gd` (`height_at`, `_terrain`, `_vegetation`);
  query heights with `level.ground(x, z)`. Its shader is our mobile override `shaders/terrain_mobile.gdshader` (control
  map decoded per vertex, only the layers present sampled, one normal map): the standard one runs at 5 fps on the
  Galaxy A16 and the lightweight one at ~25; ours at 45 (the A16's 90 Hz panel paces frames at 90/45/30). Supports 4 layers.
  Re-measure on the phone with `tools/device_test.sh` / `tools/device_sweep.sh` after visual changes.
- Homes are `scripts/houses.gd` (Mo and Bo's `house`, each islander's `hut_<id>`; `Island.homes`, `home_of`): walls with a
  real doorway, roof, room and belongings. You walk in (walls are segments for you, a rounded block that everyone else
  slides round), the floor is `level.ground` there, and while you're in, the roof and near walls go on
  `Houses.CUT_LAYER` (the main camera skips it; their eyes don't) and the camera ray ignores that house
  (`Level.cam_exclude`). Pals who `go_in` show in the room (`Island.inside_spot`: bed when asleep, else the table;
  `Pal.lift`). Each part is baked to one vertex-coloured mesh (`Houses.bake`, `use_vcol` in the lit shader) to keep
  draw calls down; do the same for new scenery (`scripts/village.gd`). Props by a house go flush against its walls
  (no obstacle of their own): small obstacles next to a house make notches walkers stall in.
- Background sound (everything through `Sfx`) is on the "World" bus, muted by the HUD's speaker button or M
  (`Sfx.set_muted`, kept in `user://settings.cfg`); voices aren't on it. Keep new game sounds going through `Sfx`.
- `tools/tour.gd` walks set stops (island, homes, dusk, night, cave) for screenshots and frame rates.
- Trees and bushes come with a far LOD: `tools/bake_impostors.tscn` renders each to `assets/quaternius_nature/impostors/`
  (re-run it after changing the trees); `Props.with_impostor` packs LOD0 + LOD1 for Terrain3D's instancer.
- Mo and Bo think through the Worker in `worker/` (Qwen3.8 Omni Flash on Alibaba, Gemini 3.6 Flash as fallback;
  Fish Audio voices). Their personas and the reply format are in `worker/src/minds.ts`; the game side is
  `scripts/minds.gd` (when they think, checks, voices) and `scripts/mind.gd` (memory, perception, wandering).
  They are not the player's helpers: no "obey" framing, and no scripted beats or written lines: the story moves
  only by what they (or you) do. Their goals come from their memory seeds (`Mind.SEEDS`). Actions are an open set
  on anything perceived (`Mind.actions`/`start`); what an action does is the level's (`Level.use`, `way`,
  `use_reach`, `label_of`, thing flags carry/light); they may only mention what they've perceived (`Minds.unseen`).
- They perceive only through pictures from their own eyes (`scripts/eyes.gd`): never send the model object names,
  tags, lists of what's in view, or outcome texts that name things they haven't named themselves. They act by
  pointing (`Eyes.resolve`/`reach`); the game only enforces what's physically possible. New senses go in the
  thought's senses (`Mind.feel()`, `sight`); see docs/roadmap.md.
- Each pal has a place (`Pal.place_id`); only the current level is in the tree, and only pals in it are shown,
  move and think (`Game.here()`). `Game.go_through` sends one pal; `Game.follow_to` moves you (and the view).
  Levels persist between visits (`Game.levels`). Things' boxes leave out glows (`Level.box_of`); carryable things
  get a grab volume so a look at them lands on them.
- The mic is always on (`scripts/ears.gd`): a noise-following voice detector, deaf while their voices play (Godot's
  Android mic has no echo cancelling). Keep any new sound they make inside `Minds._voices_playing`.
- The player is the kid (`scripts/kid.gd`, from the character session): `Game.kid` stands at `wisp_g`, faces
  `heading`, and the light (`wisp`: glow and omni light) sits at `Kid.lantern`. Mo and Bo call the player Wisp and see
  the kid (actor tag "you"). Left idle, you walk after them (`Game.watch_point`).
- On a Mac, Mo and Bo can think with the player's own Claude (Agent SDK) or ChatGPT (Codex app-server) login
  instead: `mindserver/` (`npm start`), which speaks the Worker's protocol and reuses `worker/src/minds.ts`
  (persona, rules, situation, reply); one persistent session/thread per character, no tools, sight only from
  their eyes. The game picks it per character (`Brain.minds`, `user://brain.json`, `--brain=`/`--minds=`;
  phone: `tools/minds_lan.sh`). Voices and speech-to-text still come from the Worker. `mindserver/scripts/bench.mjs`
  compares it with the Worker; see `mindserver/README.md`.
- Deploy the Worker with `cd worker && npx wrangler deploy`; keys are Wrangler secrets. `worker/scripts/try.mjs`
  and `bench.sh` time one thought; `voices.mjs` auditions Fish voices.
- The autoplay tests depend on the model and network: runs differ, and the idle loop can take several minutes.
  `--offline` keeps the minds off (no Worker calls at all); `tools/body_test.gd` (headless, fixed steps) and
  `tools/world_test.gd` (in the game, a scripted stand-in pointing for them, `tools/standin.gd`) check the
  world's mechanics without the model.
- Time of day is `Game.clock` (`scripts/clock.gd`); the island's light, sky, haze and fires follow it
  (`Island._daylight`). Bodies are `Mind.body` (`scripts/body.gd`), stepped every frame wherever they are
  (`Mind.live`) from what's around them (`Level.surroundings`: `light_at`, `chill`, `warmth_at`). Needs reach the
  model only as feelings (`Body.feel`), never numbers. Food and shelter are the level's (`edible`, `eat_at`,
  `shelter`, `new_day` each morning).
- Senses: anything they'd only know by seeing goes through `Eyes.sees` (in front of them, not hidden, lit), e.g.
  `Minds.saw(p, text, at)`; never tell them about something behind them. Sounds go through `Game.hearing.make`
  (described as sounds, with a reach in metres; `Hearing` adds direction, distance and muffling; between places
  through `Level.way_to`); continuous ones are `Level.sounds_around`. Touch is `Mind.touch` (bumps come from
  `Pal.bumped`, what was hit from `Level.touch_at`; `underfoot`, `in_water`). Tests' memories stay in
  `user://offline/` (`--offline`).
- Memory is `Mind.mem` (`scripts/memory.gd`): add with `Mind.remember(kind, text)` (importance is worked out,
  or pass one); never trim or edit `Mind.memory` by hand. Time in it is time lived (`life_h`, `day`), not the
  wall clock. Thoughts get `Memory.recall(on_mind)`; reflection is `Minds.reflect` (once a night per pal;
  tests set `Minds.reflector`). Files are versioned (`Memory.VERSION`); keep `from_save` able to read every
  older version with nothing lost.
- Mood and feelings are `Mind.heart` (`scripts/heart.gd`, saved in the same file under "heart"): change them
  through its verbs (`feel`, `helped`, `teased`, `shared`, `left_behind`, `promised`/`resolve`, `change`), never
  by setting numbers from outside; they reach the model only as `Heart.about`/`mood_words` text. Speech goes
  through `Minds._heard_from` (promises, teasing, talk about someone).
- Plans are `Mind.plans` (`scripts/plans.gd`, saved under "plans"; `Mind.plan` is the next step). The day's
  plan is made only by `Minds.plan_day` (once a morning per pal; tests set `Minds.planner`); thoughts move it
  on through `Minds._plan_reply` ("next", "activity", and "day" only when a rethink is due).
- Their daily round, chores and hobbies are `Life` (`scripts/life.gd`); the island's own things (woodpile,
  boat, jar, larder, apples, shells) are `Island.life_state`/`set_life_state`, saved with the clock in
  `Game.world_file()`. Catching up after the game was closed is `Game.catch_up` → `Life.catch_up`: keep it a
  summary (no per-frame simulation) and keep the model calls it leads to at one reflection and one plan per
  pal, however long the gap.
- Privacy: a thought's "think", "keep" and "true" are the speaker's alone (`Minds._private`, `Mind.secrets`,
  memory kinds thought/lied/secret). Only the spoken words go anywhere else (`Minds.line_said`); never pass a
  pal's private memory, secrets or thoughts into the other's thought, memory, heart or reflection, or onto the
  screen.
- Skills are `Mind.skills` (`scripts/skills.gd`); anything that takes skill goes through `Mind.try_skill`
  (practice, the lesson on failure). Keep tries deterministic (`Skills.roll`) and never let a skill block the
  main loop (`Skills.MOST_FAILS`; walking in through a way never takes skill). Lie-catching is
  `Mind.heard_claim`/`_check_claims`/`saw_through`/`caught`: only from what they actually see.
- Body language: `Looks.of` (`scripts/looks.gd`) turns body, mood and feelings toward whoever they're with
  into looks; `Mind._show` feeds it to the pal 4 times a second; `scripts/pal.gd` draws it (`Pal.Bearing`, a
  pose layer between the foot lock and the head turn; the face strokes on the head, placed through the
  skin's bind pose; where the eyes go, `Pal._mood_gaze`). It only moves the head: their pictures still look
  where `Pal.gaze` says (`Eyes.pose`), so it never changes what they see. Never tell the model about it in
  words: the other one sees it in their picture. Glances use `Skills.roll` (the same every run).
  `Pal.expressive = false` (or `--still`) turns it all off, for measuring.
- The island's other people are `Game.folk` / `Minds.folk` (`scripts/folk.gd`: homes, days, wants, bodies,
  bonds). They are full minds (`Mind`, files `mind_<id>.json`) with `Pal.folk` set: never following Wisp, living
  their day (`Mind._day`, `Island.life_spot`, `Life.doing`) whenever they've nothing else to do, and thinking
  through the model only near Wisp (`Minds.FOLK_NEAR`, `IDLE.folk`). Loops over people go through
  `Game.people()` / `Minds.all()` (Mo and Bo are `game.mo`/`game.bo` only where it's really about the two of
  them: the HUD, following Wisp, ways between places). Far from Wisp they update a few times a second
  (`Pal.set_far`). Their bodies are Mo's or Bo's models scaled and recoloured in `shaders/pal.gdshader`
  (`art/pals/*_skin.png` keeps skin out of it: `tools/skin_mask.gd`).
- Gossip is `Mind.news` (`scripts/gossip.gd`, saved under "news"): stories start with `Gossip.witness` (or
  `Minds.news_seen` for something everyone who sees it will know) and only travel by `Gossip.chat`/`tell` (live:
  `Minds._gossip`, a thought's "tell"; closed: `Life._fireside`). Never give a story to someone who couldn't
  have seen or heard it, and keep private thoughts and secrets out of it. Wants (`Folk.WANTS`) are done by
  `Minds.gave` (the thing put in the wanter's hands).
- Places they know are `Level.places` (shown in "You feel"), matched to what they call them by `Mind.place_key`
  (by words; other words for the same place in `Level.place_words`). A place they keep asking for and not finding
  in a run's log ("I don't know the way") belongs in one of the two. Doors of homes are shelters: entering one is a
  knock, or a meal when hungry (`Mind._knock`, `Level.eat_at`).
- A thought's "tell" only passes a story on if the words said carry it (`Gossip.carried`); the model marks lines
  about something else too.
- Runs with the model: `tools/model_runs.gd` sets up a scene (`--run=folk|fire|quest|...`, always with
  `--mind-dir`), `tools/run_stats.py` sums up logs. The OpenRouter key is in `.env` (git-ignored, never committed);
  it goes into the Worker with `wrangler secret put`. What the model writes is tidied in the Worker
  (`minds.ts` `tidy`/`spoken`), checked by `worker/scripts/words-check.mjs`.
- Offline (`--offline`, or no Worker), `Minds._send` cancels every thought before it goes out: nothing may
  reach the model in tests, not even an answer to the other one.
- Coordinate before using the phone over adb if another session is working in this tree.
