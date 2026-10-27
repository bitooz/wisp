# Wisp's Worker

Mo's and Bo's minds and voices, so no key ships in the game: a Cloudflare Worker at
`https://wisp.<your-subdomain>.workers.dev` once you deploy it.

- `POST /think`: one of them, with what they see, remember and just heard (the player's voice as a base64
  WAV, or text) and the actions on offer. Streams JSON lines back: what you said (`heard`, written down by its
  own call alongside), their line (`say`) as soon as it's complete, their voice (`audio`, 16-bit mono PCM at
  24 kHz, base64) as Fish Audio makes it, then the whole reply (`done`) with its action checked against what was
  offered, the model, the time and the cost.
- `GET /speak?v=mo|bo&t=…`: a written line in their voice, as PCM (the game keeps each one it gets).
- `GET /voices?q=…`: public Fish Audio voices, for picking.

The model is Qwen3.8 Omni Flash on Alibaba with reasoning off (it hears audio itself). Gemini 3.6 Flash
answers instead when Alibaba refuses, or races it when Qwen hasn't started after `HEDGE_MS`. Voices: Fish
Audio `s2.1-pro-free` at low latency; Mo is "little girl" (`085081f7…`), Bo is "boy" (`d9ce1833…`), picked
with `scripts/voices.mjs` (Gemini listened and judged their age).

```sh
npx wrangler deploy
npx wrangler secret put OPENROUTER_API_KEY   # from ../.env (git-ignored); also FISH_API_KEY, and APP_KEY (../brain.json)
node scripts/try.mjs body.json --wav=../tools/voice/plate.wav   # one thought, event by event
scripts/bench.sh body.json ../tools/voice/plate.wav 6           # timing
node scripts/voices.mjs nell                                     # hear someone's voice (Gemini judges it)
for f in scripts/*-check.mjs; do node --experimental-strip-types $f; done   # the prompts and replies, no model call
```
