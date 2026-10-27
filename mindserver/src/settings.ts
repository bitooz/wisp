// The mind server's settings: defaults here, the user's own in mindserver/settings.json (git-ignored; see
// settings.example.json), the server's key and the sessions it keeps in mindserver/.state/ (git-ignored too).
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export type EngineName = 'claude' | 'codex' | 'worker';

export type Settings = {
  port: number;
  host: string;
  // The game's key for this server (x-wisp-key). Empty: one is made and kept in .state/key.
  key: string;
  // Who thinks with what; anyone not named uses "default". The game can pick per character too (body.engine).
  minds: Record<string, EngineName>;
  claude: { model: string; effort: 'low' | 'medium' | 'high' | 'xhigh' | 'max' };
  codex: { model: string; effort: string; program: string };
  // A thinking session starts afresh after this many thoughts or this much context (their memory comes with
  // every thought anyway, so nothing is lost; old pictures stop piling up).
  rotate: { thoughts: number; tokens: number };
  // The Worker (voices, speech-to-text, and whoever thinks on "worker"). Empty: the game's res://brain.json.
  worker: { url: string; key: string };
  // API-equivalent prices per million tokens, for estimating what a Codex thought would cost (Codex reports
  // tokens only). Claude's estimate comes from the Agent SDK itself.
  prices: Record<string, { input: number; cached: number; output: number }>;
  // Keep each thought's body in .state/bodies/ (for scripts/bench.mjs to replay against each engine)
  keepBodies: boolean;
};

const DEFAULTS: Settings = {
  port: 8790,
  host: '0.0.0.0',
  key: '',
  minds: { mo: 'claude', bo: 'codex', default: 'worker' },
  claude: { model: 'claude-sonnet-5-5', effort: 'high' },
  codex: { model: 'gpt-6.1-terra', effort: 'high', program: 'codex' },
  rotate: { thoughts: 40, tokens: 150000 },
  worker: { url: '', key: '' },
  prices: {},
  keepBodies: false,
};

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const STATE = join(ROOT, '.state');

function merge<T>(base: T, over: unknown): T {
  if (!over || typeof over !== 'object' || Array.isArray(over)) return (over ?? base) as T;
  const out: Record<string, unknown> = { ...(base as Record<string, unknown>) };
  for (const [k, v] of Object.entries(over as Record<string, unknown>)) {
    const b = out[k];
    out[k] = b && typeof b === 'object' && !Array.isArray(b) ? merge(b, v) : v;
  }
  return out as T;
}

export function load(): Settings {
  mkdirSync(STATE, { recursive: true });
  const file = process.env.WISP_MINDS_SETTINGS || join(ROOT, 'settings.json');
  let s = DEFAULTS;
  if (existsSync(file)) s = merge(DEFAULTS, JSON.parse(readFileSync(file, 'utf8')));
  if (!s.key) {
    const kf = join(STATE, 'key');
    if (!existsSync(kf)) writeFileSync(kf, randomBytes(18).toString('base64url'), { mode: 0o600 });
    s.key = readFileSync(kf, 'utf8').trim();
  }
  if (!s.worker.url) {
    const bf = join(ROOT, '..', 'brain.json');
    if (existsSync(bf)) {
      const b = JSON.parse(readFileSync(bf, 'utf8')) as { url?: string; key?: string; worker?: { url?: string; key?: string } };
      // A brain.json already pointed at this server keeps the Worker's address under "worker"
      const w = b.worker?.url ? b.worker : b;
      if (w.url && !/:\d+\/?$/.test(w.url)) s.worker = { url: String(w.url).replace(/\/$/, ''), key: String(w.key ?? '') };
    }
  }
  return s;
}

export function engineFor(s: Settings, who: string, asked?: unknown): EngineName {
  const ok = (x: unknown): x is EngineName => x === 'claude' || x === 'codex' || x === 'worker';
  if (ok(asked)) return asked;
  const m = s.minds[who];
  return ok(m) ? m : ok(s.minds.default) ? s.minds.default : 'worker';
}

// The sessions kept between runs: {"claude:mo": {id, thoughts}, "codex:bo": {...}}
type Kept = Record<string, { id: string; thoughts: number }>;
const SESSIONS = join(STATE, 'sessions.json');
export function kept(): Kept {
  try {
    return JSON.parse(readFileSync(SESSIONS, 'utf8')) as Kept;
  } catch {
    return {};
  }
}
export function keep(key: string, v: { id: string; thoughts: number } | null) {
  const k = kept();
  if (v) k[key] = v;
  else delete k[key];
  writeFileSync(SESSIONS, JSON.stringify(k, null, 1));
}

// Each mind's own empty folder to run in: nothing of the game's (or anyone's) files around it.
export function home(engine: string, who: string) {
  const d = join(STATE, 'homes', `${engine}-${who}`);
  mkdirSync(d, { recursive: true });
  return d;
}
