// Mo or Bo thinking with the player's own ChatGPT login, through Codex's app-server (JSON-RPC on stdio): one
// app-server for all, one persistent thread per character, each thought one turn with the picture from their
// eyes. As in Filo, the app-server reads the user's own ~/.codex/config.toml, so what it would bring along is
// turned off at launch: every MCP server it names, the notify program, plugins, apps, skills, the shell, web
// search, the code-mode host, AGENTS.md. Our persona replaces Codex's base instructions. A turn that tries a
// tool anyway (Codex keeps a few of its own) is interrupted: the mind only looks, talks and points.
import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { home, keep, kept, type Settings } from './settings.ts';
import { noUsage, type Engine, type Turn, type Usage } from './engine.ts';

const FEATURES_OFF = [
  'shell_tool', 'unified_exec', 'code_mode_host', 'apps', 'plugins', 'remote_plugin', 'browser_use', 'browser_use_external',
  'in_app_browser', 'computer_use', 'image_generation', 'multi_agent', 'multi_agent_v2', 'sleep_tool', 'goals', 'view_image',
  'tool_suggest', 'skill_search', 'skill_mcp_dependency_install', 'hooks', 'memories', 'default_mode_request_user_input',
];
// Items that are the model doing something other than answering
const TOOL_ITEMS = new Set(['commandExecution', 'fileChange', 'mcpToolCall', 'dynamicToolCall', 'collabAgentToolCall', 'webSearch', 'imageGeneration', 'imageView']);

const toml = (s: string) => JSON.stringify(s);

function codexHome() {
  return process.env.CODEX_HOME || join(homedir(), '.codex');
}

function launchArgs(): string[] {
  const cfg = (() => {
    try {
      return readFileSync(join(codexHome(), 'config.toml'), 'utf8');
    } catch {
      return '';
    }
  })();
  const servers = [...new Set([...cfg.matchAll(/^\[mcp_servers\.(?:"([^"]+)"|([^.\]\s]+))\]/gm)].map((m) => m[1] ?? m[2]))];
  const skills: string[] = [];
  const walk = (d: string, depth: number) => {
    let es: import('node:fs').Dirent[] = [];
    try {
      es = readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of es) {
      const p = join(d, e.name);
      if (e.isDirectory() && depth < 5) walk(p, depth + 1);
      else if (e.name === 'SKILL.md') skills.push(p);
    }
  };
  for (const r of [join(codexHome(), 'skills'), join(homedir(), '.agents', 'skills')]) if (existsSync(r)) walk(r, 0);
  const args = ['app-server', '-c', 'notify=[]', '-c', 'web_search="disabled"', '-c', 'project_doc_max_bytes=0', '-c', 'skills.bundled.enabled=false'];
  if (servers.length) args.push('-c', `mcp_servers={ ${servers.map((n) => `${toml(n)} = { enabled = false }`).join(', ')} }`);
  if (skills.length) args.push('-c', `skills.config=[${skills.map((p) => `{path=${toml(p)},enabled=false}`).join(',')}]`);
  for (const f of FEATURES_OFF) args.push('--disable', f);
  return args;
}

type Running = {
  thread: string;
  turn: string;
  onDelta: (d: string) => void;
  resolve: (t: Turn) => void;
  reject: (e: Error) => void;
  t0: number;
  firstMs: number;
  text: string;
  final: string;
  usage: Usage;
  tool: string;
};

export class Codex implements Engine {
  name = 'codex' as const;
  private p: ChildProcess | null = null;
  private ready: Promise<void> | null = null;
  private id = 0;
  private waiting = new Map<number, { resolve: (r: unknown) => void; reject: (e: Error) => void }>();
  private threads = new Map<string, { id: string; system: string; thoughts: number; starting?: Promise<string> }>();
  private running = new Map<string, Running>(); // by thread
  private limits: unknown = undefined;
  totals = new Map<string, { thoughts: number; cost: number; tokens: number }>();
  s: Settings;
  constructor(s: Settings) {
    this.s = s;
  }

  private start(): Promise<void> {
    if (this.ready) return this.ready;
    const p = spawn(this.s.codex.program, launchArgs(), { stdio: ['pipe', 'pipe', 'pipe'], cwd: home('codex', 'server') });
    this.p = p;
    let buf = '';
    p.stdout!.setEncoding('utf8');
    p.stdout!.on('data', (d: string) => {
      buf += d;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i);
        buf = buf.slice(i + 1);
        try {
          this.on(JSON.parse(line));
        } catch {}
      }
    });
    p.stderr!.setEncoding('utf8');
    p.stderr!.on('data', (d: string) => {
      if (/ERROR/.test(d) && !/code-mode host is disabled/.test(d)) console.error(`[codex] ${d.replace(/\x1b\[[0-9;]*m/g, '').trim().slice(0, 300)}`);
    });
    p.on('exit', (code) => {
      console.error(`[codex] app-server exited (${code})`);
      for (const w of this.waiting.values()) w.reject(new Error('Codex app-server exited'));
      this.waiting.clear();
      for (const r of this.running.values()) r.reject(new Error('Codex app-server exited'));
      this.running.clear();
      this.threads.clear();
      this.ready = null;
      this.p = null;
    });
    this.ready = (async () => {
      await this.req('initialize', {
        clientInfo: { name: 'wisp_minds', title: 'Wisp', version: '0.1.0' },
        capabilities: { experimentalApi: true, optOutNotificationMethods: ['item/reasoning/textDelta', 'item/reasoning/summaryTextDelta', 'turn/diff/updated'] },
      });
      this.write({ jsonrpc: '2.0', method: 'initialized' });
    })();
    return this.ready;
  }

  private write(m: unknown) {
    this.p?.stdin?.write(JSON.stringify(m) + '\n');
  }

  private req(method: string, params: unknown): Promise<any> {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      this.waiting.set(id, { resolve, reject });
      this.write({ jsonrpc: '2.0', id, method, params });
    });
  }

  private on(m: { id?: number | string; method?: string; params?: any; result?: any; error?: { message?: string } }) {
    if (m.id != null && !m.method) {
      const w = this.waiting.get(Number(m.id));
      if (!w) return;
      this.waiting.delete(Number(m.id));
      if (m.error) w.reject(new Error(`Codex: ${m.error.message ?? 'error'}`));
      else w.resolve(m.result);
      return;
    }
    // Its own requests (approvals, questions for a user): nobody's there, and the mind needs none of it
    if (m.id != null && m.method) {
      this.write({ jsonrpc: '2.0', id: m.id, error: { code: -32601, message: 'not available to this mind' } });
      return;
    }
    const p = m.params ?? {};
    if (m.method === 'account/rateLimits/updated') this.limits = p.rateLimits;
    const r = p.threadId ? this.running.get(p.threadId) : undefined;
    if (!r) return;
    switch (m.method) {
      case 'item/agentMessage/delta': {
        const d = String(p.delta ?? '');
        if (!d) return;
        if (!r.firstMs) r.firstMs = Date.now() - r.t0;
        r.text += d;
        r.onDelta(d);
        return;
      }
      case 'item/started':
        if (TOOL_ITEMS.has(p.item?.type)) {
          r.tool = p.item.type;
          console.warn(`[codex] a mind tried a tool (${p.item.type}): interrupted`);
          if (r.turn) this.req('turn/interrupt', { threadId: r.thread, turnId: r.turn }).catch(() => {});
        }
        return;
      case 'item/completed':
        if (p.item?.type === 'agentMessage' && p.item.text) r.final = String(p.item.text);
        return;
      case 'thread/tokenUsage/updated': {
        const l = p.tokenUsage?.last ?? {};
        r.usage = { input: l.inputTokens ?? 0, cached: l.cachedInputTokens ?? 0, cacheWrite: l.cacheWriteInputTokens ?? 0, output: l.outputTokens ?? 0, reasoning: l.reasoningOutputTokens ?? 0 };
        return;
      }
      case 'turn/completed': {
        this.running.delete(r.thread);
        const turn = p.turn ?? {};
        const text = r.final || r.text;
        if (turn.status === 'failed' && !text) return r.reject(new Error(`Codex: ${turn.error?.message ?? 'the turn failed'}`));
        if (r.tool && !text) return r.reject(new Error(`Codex: tried a tool (${r.tool})`));
        r.resolve({ text, model: this.s.codex.model, usage: r.usage, cost: this.price(r.usage), firstMs: r.firstMs, session: r.thread, thoughts: 0, limits: this.limits });
        return;
      }
    }
  }

  private price(u: Usage) {
    const p = this.s.prices[this.s.codex.model];
    if (!p) return 0;
    return ((u.input - u.cached) * p.input + u.cached * p.cached + u.output * p.output) / 1e6;
  }

  private settings(who: string, system: string, ephemeral: boolean) {
    return {
      cwd: home('codex', who),
      model: this.s.codex.model,
      approvalPolicy: 'never',
      sandbox: 'read-only',
      baseInstructions: system,
      personality: 'none',
      ephemeral,
    };
  }

  private async thread(who: string, system: string): Promise<string> {
    await this.start();
    const t = this.threads.get(who);
    if (t && t.system === system) return t.starting ?? t.id;
    const was = kept()[`codex:${who}`];
    const entry = { id: '', system, thoughts: was?.thoughts ?? 0, starting: undefined as Promise<string> | undefined };
    this.threads.set(who, entry);
    entry.starting = (async () => {
      let id = '';
      if (was && !t) {
        try {
          const r = await this.req('thread/resume', { ...this.settings(who, system, false), threadId: was.id, excludeTurns: true });
          id = r?.thread?.id ?? '';
        } catch (e) {
          console.warn(`[codex ${who}] couldn't carry on in thread ${was.id}: ${(e as Error).message}`);
        }
      }
      if (!id) {
        const r = await this.req('thread/start', this.settings(who, system, false));
        id = r.thread.id;
        entry.thoughts = 0;
      }
      entry.id = id;
      entry.starting = undefined;
      keep(`codex:${who}`, { id, thoughts: entry.thoughts });
      return id;
    })();
    return entry.starting;
  }

  warmOnce() {}

  warm(who: string, system: string) {
    this.thread(who, system).catch((e) => console.error(`[codex ${who}] ${e.message}`));
  }

  private turn(thread: string, sight: string | undefined, text: string, onDelta: (d: string) => void, signal?: AbortSignal): Promise<Turn> {
    if (this.running.has(thread)) return Promise.reject(new Error('busy'));
    return new Promise<Turn>((resolve, reject) => {
      const r: Running = { thread, turn: '', onDelta, resolve, reject, t0: Date.now(), firstMs: 0, text: '', final: '', usage: noUsage(), tool: '' };
      this.running.set(thread, r);
      const input: unknown[] = [];
      if (sight) input.push({ type: 'image', url: `data:image/jpeg;base64,${sight}` });
      input.push({ type: 'text', text, text_elements: [] });
      this.req('turn/start', { threadId: thread, input, model: this.s.codex.model, effort: this.s.codex.effort })
        .then((res) => {
          r.turn = res?.turn?.id ?? '';
          if (signal?.aborted && r.turn) this.req('turn/interrupt', { threadId: thread, turnId: r.turn }).catch(() => {});
        })
        .catch((e) => {
          this.running.delete(thread);
          reject(e);
        });
      signal?.addEventListener('abort', () => {
        if (r.turn && this.running.get(thread) === r) this.req('turn/interrupt', { threadId: thread, turnId: r.turn }).catch(() => {});
      });
    });
  }

  async think(who: string, system: string, sight: string | undefined, text: string, onDelta: (d: string) => void, signal: AbortSignal) {
    const thread = await this.thread(who, system);
    const t = await this.turn(thread, sight, text, onDelta, signal);
    const entry = this.threads.get(who);
    if (entry) {
      entry.thoughts++;
      t.thoughts = entry.thoughts;
      keep(`codex:${who}`, { id: thread, thoughts: entry.thoughts });
      if (entry.thoughts >= this.s.rotate.thoughts || t.usage.input >= this.s.rotate.tokens) {
        keep(`codex:${who}`, null);
        this.threads.delete(who);
        this.req('thread/unsubscribe', { threadId: thread }).catch(() => {});
        console.log(`[codex ${who}] new thread after ${entry.thoughts} thoughts (${t.usage.input} tokens in)`);
      }
    }
    const tot = this.totals.get(who) ?? { thoughts: 0, cost: 0, tokens: 0 };
    tot.thoughts++;
    tot.cost += t.cost;
    tot.tokens += t.usage.input + t.usage.output;
    this.totals.set(who, tot);
    return t;
  }

  // An ephemeral thread of its own: the night's reflection, the morning's plan.
  async once(who: string, system: string, user: string): Promise<Turn> {
    await this.start();
    const r = await this.req('thread/start', this.settings(who, system, true));
    const thread = r.thread.id as string;
    try {
      return await this.turn(thread, undefined, user, () => {});
    } finally {
      this.req('thread/unsubscribe', { threadId: thread }).catch(() => {});
    }
  }

  stats() {
    const out: Record<string, unknown> = { limits: this.limits };
    for (const [who, t] of this.totals) out[who] = { ...t, thread: this.threads.get(who)?.id ?? '', inThread: this.threads.get(who)?.thoughts ?? 0 };
    return out;
  }

  close() {
    this.p?.kill();
  }
}
