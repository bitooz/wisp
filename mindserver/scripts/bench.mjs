// Times the same thoughts on the Worker and on the mind server's engines: when the line is ready (say), when
// their voice starts arriving, the first word of the model's answer, and what each thought cost and used.
//   node scripts/bench.mjs [--engines=worker,claude,codex] [--n=3] [--who=mo] <body.json | folder of bodies>...
// Bodies are what the game sends (keepBodies in settings.json keeps them in .state/bodies/). Each body goes to
// every engine in turn (the Worker directly, with res://brain.json's key; the others through the mind server).
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const brain = JSON.parse(readFileSync(join(root, '..', 'brain.json'), 'utf8'));
const worker = brain.worker?.url ? brain.worker : brain;
const minds = { url: `http://127.0.0.1:${process.env.PORT || 8790}`, key: readFileSync(join(root, '.state', 'key'), 'utf8').trim() };
const opt = Object.fromEntries(process.argv.slice(2).filter((a) => a.startsWith('--')).map((a) => a.slice(2).split('=')));
const engines = (opt.engines || 'worker,claude,codex').split(',');
const n = Number(opt.n || 1);
let files = process.argv.slice(2).filter((a) => !a.startsWith('--'));
files = files.flatMap((f) => (statSync(f).isDirectory() ? readdirSync(f).filter((x) => x.endsWith('.json')).sort().map((x) => join(f, x)) : [f]));
if (opt.who) files = files.filter((f) => f.split('/').pop().startsWith(opt.who + '-'));
if (opt.limit) files = files.slice(-Number(opt.limit));

async function one(engine, body) {
  const to = engine === 'worker' ? worker : minds;
  // Its own sessions, apart from the characters' real ones
  const b = { ...body, engine, session: opt.session || 'bench' };
  const t0 = Date.now();
  const res = await fetch(`${to.url}/think`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-wisp-key': to.key }, body: JSON.stringify(b) });
  const out = { engine, status: res.status, say: -1, audio: -1, firstMs: 0, ms: 0, cost: 0, usage: null, line: '', do: '', model: '', error: '' };
  let buf = '';
  const dec = new TextDecoder();
  for await (const c of res.body) {
    buf += dec.decode(c, { stream: true });
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const m = JSON.parse(buf.slice(0, nl));
      buf = buf.slice(nl + 1);
      if (m.type === 'say' && out.say < 0) {
        out.say = Date.now() - t0;
        out.line = m.say;
      } else if (m.type === 'audio' && out.audio < 0) out.audio = Date.now() - t0;
      else if (m.type === 'done') Object.assign(out, { firstMs: m.firstMs, ms: Date.now() - t0, cost: m.cost, usage: m.usage ?? null, do: m.do, model: m.model, line: m.say });
      else if (m.type === 'error') out.error = m.error;
    }
  }
  return out;
}

const rows = [];
// One thought each first, not counted: the bench's own sessions start (a Claude process takes seconds)
if (files.length) for (const e of engines) await one(e, JSON.parse(readFileSync(files[0], 'utf8')));
for (const f of files) {
  const body = JSON.parse(readFileSync(f, 'utf8'));
  delete body.engine;
  for (let i = 0; i < n; i++)
    for (const e of engines) {
      const r = await one(e, body);
      rows.push({ file: f.split('/').pop(), ...r });
      const u = r.usage ? ` in ${r.usage.input} (cached ${r.usage.cached}) out ${r.usage.output}` : '';
      console.log(`${e.padEnd(6)} say ${String(r.say).padStart(5)}  voice ${String(r.audio).padStart(5)}  first ${String(r.firstMs).padStart(5)}  $${Number(r.cost).toFixed(5)}${u}  ${r.do}  "${r.line}"${r.error ? '  ERROR ' + r.error : ''}`);
    }
}

const med = (a) => {
  const x = a.filter((v) => v >= 0).sort((p, q) => p - q);
  return x.length ? x[Math.floor(x.length / 2)] : -1;
};
console.log('\nengine  n  say(med)  voice(med)  first(med)  $/thought(mean)  tokens in/out (mean)');
for (const e of engines) {
  const r = rows.filter((x) => x.engine === e && !x.error);
  if (!r.length) continue;
  const mean = (f) => r.reduce((s, x) => s + f(x), 0) / r.length;
  console.log(`${e.padEnd(7)} ${String(r.length).padStart(2)}  ${String(med(r.map((x) => x.say))).padStart(8)}  ${String(med(r.map((x) => x.audio))).padStart(10)}  ${String(med(r.map((x) => x.firstMs))).padStart(10)}  ${mean((x) => Number(x.cost)).toFixed(5).padStart(15)}  ${r[0].usage ? `${Math.round(mean((x) => x.usage?.input ?? 0))}/${Math.round(mean((x) => x.usage?.output ?? 0))}` : '-'}`);
}
if (opt.json) console.log(JSON.stringify(rows));
