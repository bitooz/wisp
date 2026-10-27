# Wisp's mind server

Mo and Bo (or anyone on the island) thinking with **your own** Claude login (through the Claude Agent SDK) or
ChatGPT login (through Codex's app-server), on your Mac, the way Filo desktop runs Claude Code and Codex. It speaks
the Worker's protocol (`worker/src/index.ts`): the game only needs pointing at it. The Worker stays the default
(phones, and anyone set to `worker`); the mind server still asks it for voices (Fish Audio) and for writing down
what you said (Claude and Codex take pictures and text, not sound).

```
cd mindserver && npm install && npm start        # needs Node 24, and `claude` / `codex` signed in
```

On start it prints the addresses to point the game at. The game's key for it is made on first start, in
`.state/key`.

- **On this Mac**: write the game's `user://brain.json` (`~/Library/Application Support/Godot/app_userdata/Wisp/brain.json`):
  `{"url": "http://127.0.0.1:8790", "key": "<.state/key>", "minds": {"mo": "claude", "bo": "codex"}}`, or run the
  game with `-- --brain=http://127.0.0.1:8790 --brain-key=<key> --minds=mo:claude,bo:codex`.
- **On the phone** (same network): `tools/minds_lan.sh [mo:claude,bo:codex]` writes the phone's
  `user://brain.json` with this Mac's address over adb; `tools/minds_lan.sh --off` goes back to the Worker.

`minds` in the game's settings picks what each one thinks with (`claude`, `codex` or `worker`), per character;
anyone the game doesn't name gets the server's own pick (`minds` in `settings.json`).

## Settings

`settings.json` (git-ignored) over the defaults in `src/settings.ts`; see `settings.example.json`:

- `minds`: who thinks with what by default (`mo: claude`, `bo: codex`, everyone else `worker`)
- `claude`: `claude-sonnet-5-5` at `high` effort; `codex`: `gpt-6.1-terra` at `high` effort
- `rotate`: a thinking session starts afresh after 40 thoughts or 150k tokens of context (their memory comes with
  every thought, so nothing is lost; old pictures stop piling up)
- `worker`: the Worker's address and key; empty means the game's `brain.json`
- `prices`: API-equivalent prices per million tokens, to estimate Codex thoughts in dollars (Codex reports tokens)
- `keepBodies`: keep each thought's body in `.state/bodies/` for `scripts/bench.mjs`

## How a mind is kept a mind

What the model gets is exactly what the Worker's model gets: `worker/src/minds.ts` builds the persona, the rules
and the situation, and reads the reply. The picture from their own eyes is their only sight; nothing names what's
in it.

- **Claude** (`src/claude.ts`): one Claude Code session per character, kept running with streaming input, each
  thought one user message (the picture and the text). Our system prompt replaces Claude Code's; no tools, no MCP
  servers, no settings files, CLAUDE.md, skills or `@file` expansion (`verbatimPrompts`), in an empty folder of
  its own (`.state/homes/`). The session id is kept in `.state/sessions.json`, so a restart carries on.
- **Codex** (`src/codex.ts`): one `codex app-server` for all, one persistent thread per character, each thought one
  turn. The app-server reads your own `~/.codex/config.toml`, so, as in Filo, everything it would bring along is
  turned off at launch: each MCP server it names, `notify`, plugins, apps, skills, the shell, web search, the
  code-mode host, AGENTS.md. The persona replaces Codex's base instructions. Codex still lists a few of its own
  tools (its code-mode `exec`, which errors with the host off, and its sub-agent tools): a turn that starts any
  tool is interrupted, and requests for approval or input are refused.
- Each character's session is their own: Mo's thoughts never go into Bo's, and the night's reflection and the
  morning's plan run outside the thinking session, in a one-off session (Claude) or ephemeral thread (Codex) of
  their own.

## Measuring

`node scripts/bench.mjs [--engines=worker,claude,codex] [--n=3] [--who=mo] <bodies...>` sends the same thoughts
to the Worker and to each engine (in sessions of their own, apart from the characters' real ones) and prints when
the line was ready, when the voice started arriving, the first word of the answer, and cost and tokens per thought.
`GET /stats` (with the key) has each engine's totals and where your login's limits stand.
