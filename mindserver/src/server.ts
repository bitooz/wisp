// Wisp's mind server: Mo and Bo (or anyone) thinking with the player's own Claude login (Agent SDK) or ChatGPT
// login (Codex app-server), on this Mac. It speaks the Worker's protocol (worker/src/index.ts), so the game only
// points at it (brain.json / user://brain.json); whoever is on "worker" is passed through to the Worker, which
// also still makes their voices and writes down what the player said (Claude and Codex don't take audio).
//   node src/server.ts            (settings: settings.json, see settings.example.json)
//
// What a mind gets is what the Worker's model gets: worker/src/minds.ts builds the persona, the rules and the
// situation, and reads the reply. The picture from their own eyes is the only sight; nothing names what's in it.
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { mkdirSync, writeFileSync } from 'node:fs';
import { networkInterfaces } from 'node:os';
import { join } from 'node:path';
import { field, PERSONAS, reply, situation, spoken, system, type ThinkBody, type Who } from '../../worker/src/minds.ts';
import { parseBeliefs, parseFeelings, reflectPrompt, type ReflectBody } from '../../worker/src/reflect.ts';
import { parsePlan, planPrompt, type PlanBody } from '../../worker/src/planner.ts';
import { engineFor, load, STATE, type EngineName } from './settings.ts';
import { hasWorker, hear, pass, speak } from './worker.ts';
import { Claude } from './claude.ts';
import { Codex } from './codex.ts';
import type { Engine, Turn } from './engine.ts';

const s = load();
const engines: Record<'claude' | 'codex', Engine> = { claude: new Claude(s), codex: new Codex(s) };
// One thought at a time per character: a new one waits for the last (which is stopped if nobody's listening)
const lines = new Map<string, Promise<unknown>>();
const log: Record<string, unknown>[] = [];

type Emit = (m: Record<string, unknown>) => void;

const send = (res: ServerResponse, status: number, body: unknown) => {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
};

async function body(req: IncomingMessage): Promise<unknown> {
  const parts: Buffer[] = [];
  for await (const c of req) parts.push(c as Buffer);
  return JSON.parse(Buffer.concat(parts).toString('utf8') || '{}');
}

// Not words to answer (as in the Worker): nothing, a filler, a description of a sound
const named = (n: string, text: string) => new RegExp(`\\b${n}\\b`, 'i').test(text);

async function think(b: ThinkBody & { engine?: string }, engine: Engine, emit: Emit, signal: AbortSignal) {
  const t0 = Date.now();
  const who = b.who as Who;
  let heard = { heard: '', cost: 0, ms: 0 };
  // What the player said, written down first: Claude and Codex take pictures and text, not sound
  if (b.audio) {
    const h = await hear(s, b.audio);
    heard = { heard: h.heard, cost: h.cost, ms: h.ms };
    emit({ type: 'heard', heard: h.heard, ms: Date.now() - t0, model: h.model });
    const me = PERSONAS[who];
    const stop = h.junk ? 'ignored' : me.other && named(me.other, h.heard) && !named(me.name, h.heard) ? 'redirect' : '';
    if (stop) {
      emit({ type: stop, heard: h.heard, ms: Date.now() - t0, cost: h.cost });
      return { stopped: stop, heard: h.heard };
    }
    b = { ...b, text: h.heard };
    delete b.audio;
  }
  let all = '';
  let said: string | null = null;
  let voice: Promise<{ bytes: number; ms: number; firstMs?: number; error?: string }> | null = null;
  let sayMs = 0;
  const sayNow = (text: string, to: string | null, model: string) => {
    said = text;
    sayMs = Date.now() - t0;
    emit({ type: 'say', say: said, to, ms: Date.now() - t0, model });
    if (said.trim() && b.voice !== false && hasWorker(s)) voice = speakTo(who, said.trim(), emit, t0, signal);
  };
  const model = engine.name === 'claude' ? s.claude.model : s.codex.model;
  // A session of its own for a test (bench.mjs), apart from the character's real one
  const key = (b as { session?: string }).session ? `${who}~${String((b as { session?: string }).session).replace(/\W/g, '')}` : who;
  const turn: Turn = await engine.think(key, system(who), b.sight, situation(b), (d) => {
    all += d;
    if (said == null && field(all, 'say') != null) sayNow(spoken(field(all, 'say') as string), field(all, 'to'), model);
  }, signal);
  const r = reply(all || turn.text, b);
  if (said == null) sayNow(r.say, r.to, turn.model);
  r.heard = heard.heard || String(b.text ?? '').slice(0, 300);
  const done = {
    type: 'done',
    ...r,
    ms: Date.now() - t0,
    firstMs: turn.firstMs + (heard.ms || 0),
    sayMs,
    model: turn.model,
    provider: engine.name,
    engine: engine.name,
    cost: turn.cost + heard.cost,
    usage: turn.usage,
    session: turn.session,
    inSession: turn.thoughts,
    ...(b.audio !== undefined || heard.ms ? { hearMs: heard.ms, hearCost: heard.cost } : {}),
  };
  emit(done);
  if (voice) {
    const v = await (voice as Promise<{ bytes: number; ms: number; firstMs?: number; error?: string }>);
    emit({ type: 'audio_end', ...v, chars: new TextEncoder().encode(said ?? '').length });
    return { ...done, voiceMs: v.firstMs, voiceError: v.error };
  }
  return done;
}

// Their line in their voice, from the Worker (Fish Audio), sent on in pieces of about a fifth of a second.
async function speakTo(who: string, text: string, emit: Emit, t0: number, signal: AbortSignal) {
  try {
    const res = await speak(s, who, text, signal);
    if (!res.ok || !res.body) return { bytes: 0, ms: Date.now() - t0, error: `voice ${res.status}` };
    let held = Buffer.alloc(0);
    let bytes = 0;
    let first = 0;
    const flush = (all: boolean) => {
      const n = all ? held.length & ~1 : held.length >= 9600 ? held.length & ~1 : 0;
      if (!n) return;
      if (!first) first = Date.now() - t0;
      emit({ type: 'audio', pcm: held.subarray(0, n).toString('base64'), ...(bytes ? {} : { ms: first }) });
      bytes += n;
      held = held.subarray(n);
    };
    for await (const c of res.body as unknown as AsyncIterable<Uint8Array>) {
      held = Buffer.concat([held, c]);
      flush(false);
    }
    flush(true);
    return { bytes, ms: Date.now() - t0, firstMs: first };
  } catch (e) {
    return { bytes: 0, ms: Date.now() - t0, error: String((e as Error).message ?? e).slice(0, 200) };
  }
}

async function onThink(req: IncomingMessage, res: ServerResponse) {
  const b = (await body(req)) as ThinkBody & { engine?: string };
  if (!(b?.who in PERSONAS)) return send(res, 400, { error: 'bad character' });
  const name: EngineName = engineFor(s, b.who, b.engine);
  if (s.keepBodies) {
    const d = join(STATE, 'bodies');
    mkdirSync(d, { recursive: true });
    writeFileSync(join(d, `${b.who}-${b.why}-${Date.now()}.json`), JSON.stringify(b));
  }
  if (name === 'worker') return passThink(b, res);
  const engine = engines[name];
  res.writeHead(200, { 'content-type': 'application/x-ndjson', 'cache-control': 'no-store' });
  const ctrl = new AbortController();
  res.on('close', () => {
    if (!res.writableFinished) ctrl.abort();
  });
  const emit: Emit = (m) => {
    if (!res.writableEnded) res.write(JSON.stringify(m) + '\n');
  };
  const line = `${b.who}~${(b as { session?: string }).session ?? ''}`;
  const before = lines.get(line) ?? Promise.resolve();
  const mine = before.catch(() => {}).then(async () => {
    if (ctrl.signal.aborted) return;
    const t0 = Date.now();
    try {
      const d = (await think(b, engine, emit, ctrl.signal)) as Record<string, unknown>;
      const rec = { at: new Date().toISOString(), who: b.who, why: b.why, engine: name, model: d.model, ms: d.ms, firstMs: d.firstMs, sayMs: d.sayMs, voiceMs: d.voiceMs, voiceError: d.voiceError, cost: d.cost, usage: d.usage, say: d.say, do: d.do, stopped: d.stopped };
      log.push(rec);
      console.log(JSON.stringify({ event: 'think', ...rec }));
    } catch (e) {
      const error = String((e as Error)?.message ?? e).slice(0, 300);
      console.error(JSON.stringify({ event: 'think_failed', who: b.who, engine: name, error, ms: Date.now() - t0 }));
      emit({ type: 'error', error });
    } finally {
      res.end();
    }
  });
  lines.set(line, mine);
}

async function passThink(b: unknown, res: ServerResponse) {
  const up = await pass(s, '/think', { method: 'POST', body: JSON.stringify(b) });
  res.writeHead(up.status, { 'content-type': up.headers.get('content-type') ?? 'application/x-ndjson', 'cache-control': 'no-store' });
  if (up.body) for await (const c of up.body as unknown as AsyncIterable<Uint8Array>) res.write(c);
  res.end();
}

async function onText(kind: 'reflect' | 'plan', req: IncomingMessage, res: ServerResponse) {
  const raw = await body(req);
  const b = raw as (ReflectBody | PlanBody) & { engine?: string };
  const name = engineFor(s, b.who, b.engine);
  if (name === 'worker') {
    const up = await pass(s, `/${kind}`, { method: 'POST', body: JSON.stringify(raw) });
    return send(res, up.status, await up.json());
  }
  const t0 = Date.now();
  const p = kind === 'reflect' ? reflectPrompt(b as ReflectBody) : planPrompt(b as PlanBody);
  try {
    const t = await engines[name].once(b.who, p.system, p.user);
    const extra = kind === 'reflect'
      ? { beliefs: parseBeliefs(t.text, ((b as ReflectBody).memories ?? []).length), ...parseFeelings(t.text, ((b as ReflectBody).promises ?? []).length) }
      : parsePlan(t.text);
    const out = { ...extra, cost: t.cost, usage: t.usage, model: t.model, engine: name, ms: Date.now() - t0 };
    console.log(JSON.stringify({ event: kind, who: b.who, engine: name, model: t.model, ms: out.ms, cost: t.cost }));
    send(res, 200, out);
  } catch (e) {
    send(res, 200, { error: String((e as Error)?.message ?? e).slice(0, 300) });
  }
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', 'http://x');
  try {
    if (url.pathname === '/') return send(res, 200, { ok: true, name: 'wisp-minds' });
    const key = req.headers['x-wisp-key'] || url.searchParams.get('k');
    if (key !== s.key) return send(res, 401, { error: 'unauthorized' });
    if (url.pathname === '/think' && req.method === 'POST') return await onThink(req, res);
    if (url.pathname === '/reflect' && req.method === 'POST') return await onText('reflect', req, res);
    if (url.pathname === '/plan' && req.method === 'POST') return await onText('plan', req, res);
    if (url.pathname === '/hear' && req.method === 'POST') return send(res, 200, await hear(s, ((await body(req)) as { audio: string }).audio));
    if (url.pathname === '/stats') return send(res, 200, { minds: s.minds, claude: engines.claude.stats(), codex: engines.codex.stats(), thoughts: log.slice(-50) });
    if (url.pathname === '/speak' || url.pathname === '/voices') {
      url.searchParams.delete('k');
      const up = await pass(s, `${url.pathname}?${url.searchParams}`, { method: 'GET' });
      res.writeHead(up.status, { 'content-type': up.headers.get('content-type') ?? 'application/octet-stream', 'cache-control': 'no-store' });
      if (up.body) for await (const c of up.body as unknown as AsyncIterable<Uint8Array>) res.write(c);
      return res.end();
    }
    send(res, 404, { error: 'not found' });
  } catch (e) {
    console.error(JSON.stringify({ event: 'failed', path: url.pathname, error: String(e).slice(0, 300) }));
    if (!res.headersSent) send(res, 502, { error: String((e as Error)?.message ?? e).slice(0, 300) });
    else res.end();
  }
});

server.listen(s.port, s.host, () => {
  const ips = Object.values(networkInterfaces()).flat().filter((a) => a && a.family === 'IPv4' && !a.internal).map((a) => a!.address);
  console.log(`wisp-minds on :${s.port}  ${Object.entries(s.minds).map(([k, v]) => `${k}=${v}`).join(' ')}`);
  console.log(`  claude ${s.claude.model} (${s.claude.effort})  codex ${s.codex.model} (${s.codex.effort})  worker ${s.worker.url || '(none)'}`);
  console.log(`  the game's user://brain.json on this Mac: {"url": "http://127.0.0.1:${s.port}", "key": "<.state/key>"}`);
  for (const ip of ips) console.log(`  on a phone on this network:   {"url": "http://${ip}:${s.port}", "key": "<.state/key>"}`);
  // Their sessions take seconds to start: start the ones that will be asked for
  for (const [who, e] of Object.entries(s.minds)) {
    if (!(who in PERSONAS) || (e !== 'claude' && e !== 'codex')) continue;
    engines[e].warm(who, system(who as Who));
    // The night's and the morning's prompts only depend on who they are
    engines[e].warmOnce(who, reflectPrompt({ who } as ReflectBody).system);
    engines[e].warmOnce(who, planPrompt({ who } as PlanBody).system);
  }
});

const bye = () => {
  for (const e of Object.values(engines)) e.close();
  process.exit(0);
};
process.on('SIGINT', bye);
process.on('SIGTERM', bye);
