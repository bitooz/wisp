import { field, PERSONAS, spoken, reply, situation, system, type ThinkBody, type Who } from './minds';
import { parseBeliefs, parseFeelings, reflectPrompt, type ReflectBody } from './reflect';
import { parsePlan, planPrompt, type PlanBody } from './planner';

// Wisp's Worker: Mo's and Bo's minds and voices. The keys live here as Wrangler secrets; the game only knows APP_KEY.
//   POST /think   what one of them perceives, remembers and just heard (maybe the player's voice, as a WAV)
//                 → what they heard, say and do, streamed as lines of JSON, with their voice in the same stream
//   POST /hear    {audio: base64 WAV} → what the player said, written down by the model ({heard, junk}): the game
//                 listens all the time, so noise and fillers ("um", "嗯") come back as junk and nobody answers them
//   GET  /speak   ?v=mo|bo&t=<text> → a line in their Fish Audio voice: 16-bit mono PCM at 24 kHz, streamed
//   GET  /voices  ?q=<words> → public Fish Audio voices, for picking theirs
//
// The model is Qwen3.8 Omni Flash on Alibaba (it hears audio itself). Gemini 3.6 Flash answers instead when
// Alibaba refuses, or races it when Qwen hasn't started answering after HEDGE_MS; the first to answer is kept.

type Env = {
  OPENROUTER_API_KEY: string;
  FISH_API_KEY: string;
  APP_KEY: string;
  MODEL: string;
  PROVIDER?: string;
  FALLBACK?: string;
  HEDGE_MS?: string;
  FISH_MODEL: string;
  FISH_LATENCY?: string;
};

// Their Fish Audio voices (public models), with a speed that suits each. Picked by scripts/voices.mjs: Gemini
// heard Mo's as a girl of 7 to 9 and Bo's as a boy of 11 to 13, both clean.
const VOICES: Record<Who, { id: string; speed: number }> = {
  mo: { id: '085081f7c97c4c478f70f59bd8049f2a', speed: 1.05 }, // "little girl"
  bo: { id: 'd9ce1833c191476db346efb50aa20722', speed: 0.97 }, // "boy"
  // The island's other people: picked by their descriptions (a warm senior woman, a warm gentle woman, a calm
  // man); not yet heard (scripts/voices.mjs, which needs the model)
  nell: { id: '8db547ea044f44838bf2f8a039f05b5a', speed: 0.95 }, // "Old woman"
  tam: { id: '57d4a7fa3d944ca5b2407f916ce5f4d5', speed: 1.0 }, // "Woman"
  odo: { id: '48b83695ea7f4b2d8ebcd63a0775a3bd', speed: 0.92 }, // "Man - Mae"
};
const RATE = 24000;

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    if (url.pathname === '/') return json({ ok: true, name: 'wisp' });
    const key = req.headers.get('x-wisp-key') || url.searchParams.get('k');
    if (!env.APP_KEY || key !== env.APP_KEY) return json({ error: 'unauthorized' }, 401);
    try {
      if (url.pathname === '/think' && req.method === 'POST') return think((await req.json()) as ThinkBody, env, ctx);
      if (url.pathname === '/reflect' && req.method === 'POST') return json(await reflect((await req.json()) as ReflectBody, env));
      if (url.pathname === '/plan' && req.method === 'POST') return json(await plan((await req.json()) as PlanBody, env));
      if (url.pathname === '/hear' && req.method === 'POST') {
        const t0 = Date.now();
        const b = (await req.json()) as { audio?: string };
        if (!b.audio) return json({ error: 'no audio' }, 400);
        const h = await transcribe(env, b.audio, t0, async () => {});
        return json({ ...h, junk: junk(h.heard) });
      }
      if (url.pathname === '/speak') {
        const who = url.searchParams.get('v') as Who;
        const text = (url.searchParams.get('t') ?? '').trim().slice(0, 400);
        if (!(who in VOICES) || !text) return json({ error: 'bad request' }, 400);
        const res = await fish(env, who, text, url.searchParams.get('id') ?? undefined);
        if (!res.ok || !res.body) return json({ error: `voice ${res.status}: ${(await res.text()).slice(0, 200)}` }, 502);
        return new Response(res.body, { headers: { 'content-type': `audio/L16;rate=${RATE}`, 'cache-control': 'no-store' } });
      }
      if (url.pathname === '/voices') {
        const q = new URLSearchParams({ title: url.searchParams.get('q') ?? '', page_size: '20', sort_by: 'score' });
        const res = await fetch(`https://api.fish.audio/model?${q}`, { headers: { authorization: `Bearer ${env.FISH_API_KEY}` } });
        const j = (await res.json()) as { items?: { _id: string; title: string; description?: string; languages?: string[]; tags?: string[]; like_count?: number; samples?: { audio?: string }[] }[] };
        return json((j.items ?? []).map((m) => ({ id: m._id, title: m.title, about: (m.description ?? '').slice(0, 120), languages: m.languages, tags: m.tags, likes: m.like_count, sample: m.samples?.[0]?.audio })));
      }
    } catch (e) {
      console.error(JSON.stringify({ event: 'failed', path: url.pathname, error: String(e).slice(0, 500) }));
      return json({ error: String((e as Error)?.message ?? e).slice(0, 300) }, 502);
    }
    return json({ error: 'not found' }, 404);
  },
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

const fish = (env: Env, who: Who, text: string, id?: string) =>
  fetch('https://api.fish.audio/v1/tts', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.FISH_API_KEY}`, 'content-type': 'application/json', model: env.FISH_MODEL },
    body: JSON.stringify({
      text,
      reference_id: id || VOICES[who].id,
      format: 'pcm',
      sample_rate: RATE,
      latency: env.FISH_LATENCY || 'balanced',
      prosody: { speed: VOICES[who].speed },
    }),
  });

type Emit = (m: Record<string, unknown>) => Promise<void>;

// One line of thought, streamed as JSON lines:
//   {"type":"heard","heard":"…","ms":…}       the player's words, as the model heard them
//   {"type":"say","say":"…","to":"…","ms":…}  their line, as soon as it's complete (empty: they keep quiet)
//   {"type":"audio","pcm":"<base64>"}           the line in their voice, as it's made (16-bit mono, 24 kHz)
//   {"type":"done",…}                           the whole reply, its action checked against what was offered
//   {"type":"audio_end","ms":…,"bytes":…}
//   {"type":"error","error":"…"}
function think(b: ThinkBody, env: Env, ctx: ExecutionContext): Response {
  if (!(b?.who in VOICES)) return json({ error: 'bad character' }, 400);
  const t0 = Date.now();
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const w = writable.getWriter();
  const enc = new TextEncoder();
  const emit: Emit = (m) => w.write(enc.encode(JSON.stringify(m) + '\n'));
  ctx.waitUntil(
    (async () => {
      try {
        await mind(b, env, emit, t0);
      } catch (e) {
        console.error(JSON.stringify({ event: 'think_failed', who: b.who, why: b.why, error: String(e).slice(0, 300) }));
        await emit({ type: 'error', error: String((e as Error)?.message ?? e).slice(0, 300) });
      } finally {
        await w.close();
      }
    })(),
  );
  return new Response(readable, { headers: { 'content-type': 'application/x-ndjson', 'cache-control': 'no-store' } });
}

type Run = { model: string; provider: string; ctrl: AbortController; cost: number; served: string; firstMs: number };

async function mind(b: ThinkBody, env: Env, emit: Emit, t0: number) {
  const text = situation(b);
  // Their senses: the picture from their eyes, the text of what they know and feel, and your voice if you spoke
  const user: unknown[] = [];
  if (b.sight) user.push({ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${b.sight}` } });
  user.push({ type: 'text', text });
  if (b.audio) user.push({ type: 'input_audio', input_audio: { data: b.audio, format: 'wav' } });
  const messages = [
    { role: 'system', content: system(b.who) },
    { role: 'user', content: user },
  ];

  let all = '';
  let said: string | null = null;
  let voice: Promise<{ bytes: number; ms: number; error?: string }> | null = null;
  let winner: Run | null = null;
  const runs: Run[] = [];
  const errors: string[] = [];
  let hedge: number | null = null;

  // What the player said, written down by a call of its own alongside the thought. The line waits for it: if
  // it was only noise or a filler, nobody answers ("ignored"); if it was for the other one by name, they answer
  // instead ("redirect", and the game asks them).
  const hearing = b.audio ? transcribe(env, b.audio, t0, emit) : Promise.resolve({ heard: '', cost: 0, ms: 0 });
  let stopped = '';
  const gate = async () => {
    if (!b.audio) return true;
    const h = await hearing;
    if (stopped) return false;
    const me = PERSONAS[b.who];
    const named = (n: string) => new RegExp(`\\b${n}\\b`, 'i').test(h.heard);
    if (junk(h.heard)) stopped = 'ignored';
    else if (me.other && named(me.other) && !named(me.name)) stopped = 'redirect';
    if (!stopped) return true;
    for (const x of runs) x.ctrl.abort();
    await emit({ type: stopped, heard: h.heard, ms: Date.now() - t0, cost: h.cost + runs.reduce((s, x) => s + x.cost, 0) });
    return false;
  };

  const onDelta = async (r: Run, delta: string) => {
    if (!winner) {
      winner = r;
      if (hedge != null) clearTimeout(hedge);
      for (const o of runs) if (o !== r) o.ctrl.abort();
    }
    if (winner !== r || stopped) return;
    all += delta;
    if (said == null && field(all, 'say') != null) {
      if (!(await gate())) return;
      said = spoken(field(all, 'say') as string);
      const to = field(all, 'to');
      await emit({ type: 'say', say: said, to, ms: Date.now() - t0, model: r.model });
      if (said.trim() && b.voice !== false) voice = speak(env, b.who, said.trim(), emit, t0);
    }
  };

  const start = (model: string, provider: string): Promise<void> => {
    const r: Run = { model, provider, ctrl: new AbortController(), cost: 0, served: '', firstMs: 0 };
    runs.push(r);
    const qwen = model.startsWith('qwen/');
    return (async () => {
      const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        signal: r.ctrl.signal,
        headers: { authorization: `Bearer ${env.OPENROUTER_API_KEY}`, 'content-type': 'application/json', 'x-title': 'Wisp' },
        body: JSON.stringify({
          model,
          stream: true,
          max_tokens: 400,
          temperature: 0.95,
          frequency_penalty: 0.5,
          presence_penalty: 0.4,
          usage: { include: true },
          ...(provider ? { provider: { only: [provider], allow_fallbacks: false } } : {}),
          reasoning: qwen ? { enabled: false } : { effort: 'minimal' },
          messages,
        }),
      });
      if (!res.ok || !res.body) throw new Error(`${model} ${res.status}: ${(await res.text()).slice(0, 200)}`);
      const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
      let sse = '';
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        if (winner && winner !== r) {
          r.ctrl.abort();
          return;
        }
        sse += value;
        let nl;
        while ((nl = sse.indexOf('\n')) >= 0) {
          const line = sse.slice(0, nl).trim();
          sse = sse.slice(nl + 1);
          if (!line.startsWith('data:') || line === 'data: [DONE]') continue;
          let chunk: { choices?: { delta?: { content?: string } }[]; usage?: { cost?: number }; provider?: string; error?: { message?: string } } = {};
          try {
            chunk = JSON.parse(line.slice(5));
          } catch {}
          if (chunk.error) throw new Error(`${model}: ${chunk.error.message ?? 'error'}`);
          if (chunk.provider) r.served = chunk.provider;
          if (chunk.usage?.cost) r.cost += chunk.usage.cost;
          const delta = chunk.choices?.[0]?.delta?.content ?? '';
          if (!delta) continue;
          if (!r.firstMs) r.firstMs = Date.now() - t0;
          await onDelta(r, delta);
        }
      }
    })();
  };

  const primary = { model: b.model || env.MODEL, provider: b.model ? (b.provider ?? '') : (b.provider ?? env.PROVIDER ?? '') };
  const fallback = env.FALLBACK && env.FALLBACK !== primary.model ? { model: env.FALLBACK, provider: '' } : null;
  let fellBack = '';
  const raced = new Promise<void>((resolve, reject) => {
    let live = 0;
    let fallbackStarted = false;
    const go = (m: { model: string; provider: string }) => {
      live++;
      const p = start(m.model, m.provider);
      p.then(
        () => {
          live--;
          if (winner?.model === m.model) resolve();
          else if (!winner && fallback && !fallbackStarted) {
            // It ended without a word
            fallbackStarted = true;
            fellBack = `${m.model}: empty answer`;
            if (hedge != null) clearTimeout(hedge);
            go(fallback);
          } else if (!live && !winner) reject(new Error(errors.join('; ') || 'no answer'));
        },
        (e) => {
          live--;
          if ((e as Error)?.name === 'AbortError' && winner && winner.model !== m.model) return;
          errors.push(String((e as Error)?.message ?? e).slice(0, 200));
          if (winner?.model === m.model) return reject(e);
          if (!winner && fallback && !fallbackStarted) {
            fallbackStarted = true;
            fellBack = errors[errors.length - 1];
            if (hedge != null) clearTimeout(hedge);
            go(fallback);
          } else if (!live && !winner) reject(new Error(errors.join('; ')));
        },
      );
    };
    go(primary);
    if (fallback && !b.model)
      hedge = setTimeout(() => {
        if (!winner && !fallbackStarted) {
          fallbackStarted = true;
          fellBack = `no answer in ${env.HEDGE_MS} ms`;
          go(fallback);
        }
      }, b.why === 'heard' ? 3000 : Number(env.HEDGE_MS ?? 4500));
  });
  try {
    await raced;
  } catch (e) {
    if (stopped) return;
    throw e;
  }
  if (stopped || !(await gate())) return;

  const w = winner as Run | null;
  const r = reply(all, b);
  if (said == null) {
    said = r.say;
    await emit({ type: 'say', say: said, to: r.to, ms: Date.now() - t0, model: w?.model });
    if (said && b.voice !== false) voice = speak(env, b.who, said, emit, t0);
  }
  if (r.checked !== 'ok') console.warn(JSON.stringify({ event: 'action_rejected', who: b.who, why: r.checked }));
  const h = await hearing;
  r.heard = h.heard || (b.audio ? '' : String(b.text ?? '').slice(0, 300));
  const cost = runs.reduce((s, x) => s + x.cost, 0) + h.cost;
  await emit({
    type: 'done',
    ...r,
    ms: Date.now() - t0,
    firstMs: w?.firstMs ?? 0,
    model: w?.model,
    provider: w?.served,
    cost,
    // Every run that was billed, for comparing: the hedge can pay for a second one
    runs: runs.map((x) => ({ model: x.model, cost: x.cost, firstMs: x.firstMs })),
    ...(b.audio ? { hearMs: h.ms, hearCost: h.cost } : {}),
    ...(fellBack ? { fellBack } : {}),
  });
  if (voice) {
    const v = await (voice as Promise<{ bytes: number; ms: number; error?: string }>);
    await emit({ type: 'audio_end', ...v, chars: new TextEncoder().encode(said ?? '').length });
  }
}

// Not words to answer: nothing, a filler sound, or only punctuation.
const FILLERS = new Set(['嗯', '啊', '哦', '呃', '唔', 'um', 'umm', 'uh', 'uhh', 'hmm', 'hm', 'mm', 'mhm', 'ah', 'oh', 'eh', 'er', 'erm']);
function junk(heard: string) {
  const low = heard.toLowerCase();
  // The model saying there's nothing there, or describing a sound instead of words
  if (/\(none\)|no speech|no spoken|no words|only (a )?(noise|sound)|sound effect|\[.*\]/.test(low)) return true;
  const bare = low.replace(/[\p{P}\p{S}\s]+/gu, ' ').trim();
  if (!bare) return true;
  // Noise heard as Chinese (the game is in English; Qwen fills silence with it)
  if (/^[\p{Script=Han}\s]+$/u.test(bare)) return true;
  return bare.split(' ').every((w) => FILLERS.has(w));
}

// The player's words, as text: for the HUD and for their memories. Qwen writes them down; if it hasn't within
// 2.5 s (Alibaba stalls now and then) or fails, Gemini does too, and the first answer is kept.
// One short text call (the night's reflection, the morning's plan): the main model, then the fallback if it fails.
async function textCall(env: Env, system: string, user: string, maxTokens: number) {
  const errors: string[] = [];
  for (const [model, provider] of [[env.MODEL, env.PROVIDER ?? ''], [env.FALLBACK, '']] as [string, string][]) {
    if (!model) continue;
    try {
      const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        signal: AbortSignal.timeout(15000),
        headers: { authorization: `Bearer ${env.OPENROUTER_API_KEY}`, 'content-type': 'application/json', 'x-title': 'Wisp' },
        body: JSON.stringify({
          model,
          max_tokens: maxTokens,
          temperature: 0.7,
          usage: { include: true },
          ...(provider ? { provider: { only: [provider], allow_fallbacks: false } } : {}),
          reasoning: model.startsWith('qwen/') ? { enabled: false } : { effort: 'minimal' },
          messages: [
            { role: 'system', content: system },
            { role: 'user', content: user },
          ],
        }),
      });
      if (!res.ok) throw new Error(`${model} ${res.status}: ${(await res.text()).slice(0, 200)}`);
      const j = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: { cost?: number } };
      return { text: j.choices?.[0]?.message?.content ?? '', cost: j.usage?.cost ?? 0, model };
    } catch (e) {
      errors.push(String(e).slice(0, 200));
    }
  }
  return { error: errors.join(' | ') || 'no model' };
}

// A night's reflection (reflect.ts).
async function reflect(b: ReflectBody, env: Env) {
  const t0 = Date.now();
  const p = reflectPrompt(b);
  const r = await textCall(env, p.system, p.user, 400);
  if ('error' in r) return r;
  const beliefs = parseBeliefs(r.text, (b.memories ?? []).length);
  const felt = parseFeelings(r.text, (b.promises ?? []).length);
  console.log(JSON.stringify({ event: 'reflect', who: b.who, model: r.model, beliefs: beliefs.length, people: felt.people.length, ms: Date.now() - t0 }));
  return { beliefs, ...felt, cost: r.cost, model: r.model, ms: Date.now() - t0 };
}

// The morning's plan (planner.ts).
async function plan(b: PlanBody, env: Env) {
  const t0 = Date.now();
  const p = planPrompt(b);
  const r = await textCall(env, p.system, p.user, 250);
  if ('error' in r) return r;
  const got = parsePlan(r.text);
  console.log(JSON.stringify({ event: 'plan', who: b.who, model: r.model, items: got.day.length, ms: Date.now() - t0 }));
  return { ...got, cost: r.cost, model: r.model, ms: Date.now() - t0 };
}

async function transcribe(env: Env, audio: string, t0: number, emit: Emit) {
  const one = async (model: string, provider: string, signal: AbortSignal) => {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      signal,
      headers: { authorization: `Bearer ${env.OPENROUTER_API_KEY}`, 'content-type': 'application/json', 'x-title': 'Wisp' },
      body: JSON.stringify({
        model,
        max_tokens: 120,
        temperature: 0,
        usage: { include: true },
        ...(provider ? { provider: { only: [provider], allow_fallbacks: false } } : {}),
        reasoning: model.startsWith('qwen/') ? { enabled: false } : { effort: 'minimal' },
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: 'Write down exactly the words a person speaks in this audio, and nothing else. If there are no clear spoken words (only noise, a sound, music, a hum), write exactly: (none)' },
              { type: 'input_audio', input_audio: { data: audio, format: 'wav' } },
            ],
          },
        ],
      }),
    });
    if (!res.ok) throw new Error(`${model} ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const j = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: { cost?: number } };
    return { heard: (j.choices?.[0]?.message?.content ?? '').trim().replace(/^"|"$/g, '').slice(0, 300), cost: j.usage?.cost ?? 0, model };
  };
  const ctrls = [new AbortController(), new AbortController()];
  const tries: Promise<{ heard: string; cost: number; model: string }>[] = [one(env.MODEL, env.PROVIDER ?? '', ctrls[0].signal)];
  const second = () => {
    if (tries.length < 2 && env.FALLBACK) tries.push(one(env.FALLBACK, '', ctrls[1].signal));
  };
  const timer = setTimeout(second, 2500);
  let got: { heard: string; cost: number; model: string } | null = null;
  const errors: string[] = [];
  while (!got) {
    const live = tries.map((p, i) => p.then((r) => ({ r, i }), (e) => ({ e, i })));
    const first = (await Promise.race(live)) as { r?: { heard: string; cost: number; model: string }; e?: unknown; i: number };
    if (first.r) got = first.r;
    else {
      errors.push(String(first.e).slice(0, 200));
      tries[first.i] = new Promise(() => {});
      if (tries.length < 2) second();
      else if (errors.length >= tries.length) break;
    }
  }
  clearTimeout(timer);
  for (const c of ctrls) c.abort();
  if (!got) console.warn(JSON.stringify({ event: 'transcribe_failed', errors }));
  const heard = got?.heard ?? '';
  const ms = Date.now() - t0;
  await emit({ type: 'heard', heard, ms, model: got?.model });
  return { heard, cost: got?.cost ?? 0, ms };
}

// The line in their voice, sent along the same stream in pieces of about a fifth of a second.
async function speak(env: Env, who: Who, text: string, emit: Emit, t0: number) {
  const res = await fish(env, who, text);
  if (!res.ok || !res.body) {
    const error = `voice ${res.status}: ${(await res.text()).slice(0, 200)}`;
    console.error(JSON.stringify({ event: 'voice_failed', error }));
    return { bytes: 0, ms: Date.now() - t0, error };
  }
  const reader = res.body.getReader();
  let held = new Uint8Array(0);
  let bytes = 0;
  let first = 0;
  const flush = async (all: boolean) => {
    const n = all ? held.length & ~1 : held.length >= 9600 ? held.length & ~1 : 0;
    if (!n) return;
    if (!first) first = Date.now() - t0;
    await emit({ type: 'audio', pcm: b64(held.subarray(0, n)), ...(bytes ? {} : { ms: first }) });
    bytes += n;
    held = held.slice(n);
  };
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    const next = new Uint8Array(held.length + value.length);
    next.set(held);
    next.set(value, held.length);
    held = next;
    await flush(false);
  }
  await flush(true);
  return { bytes, ms: Date.now() - t0, firstMs: first };
}

function b64(a: Uint8Array) {
  let s = '';
  for (let i = 0; i < a.length; i += 8192) s += String.fromCharCode(...a.subarray(i, i + 8192));
  return btoa(s);
}
