// Mo or Bo thinking with the player's own Claude login, through the Claude Agent SDK: one Claude Code session
// per character, kept running (streaming input), each thought one user message with the picture from their eyes.
// The session is a mind and nothing else: our system prompt instead of Claude Code's, no tools, no MCP servers,
// no settings, CLAUDE.md, skills or @file expansion (verbatimPrompts), run in an empty folder of its own.
import { query, type Query, type SDKMessage, type SDKUserMessage } from '@anthropic-ai/claude-agent-sdk';
import { home, keep, kept, type Settings } from './settings.ts';
import { noUsage, type Engine, type Turn } from './engine.ts';

type Waiting = { onDelta: (d: string) => void; resolve: (t: Turn) => void; reject: (e: Error) => void; t0: number; firstMs: number; text: string };

class Session {
  q: Query | null = null;
  id = '';
  thoughts = 0;
  cost = 0; // the query's running total, to take each thought's share from
  model = '';
  limits: unknown = undefined;
  turn: Waiting | null = null;
  private push: ((m: SDKUserMessage) => void) | null = null;
  private queued: SDKUserMessage[] = [];
  private ended = false;

  s: Settings;
  who: string;
  system: string;
  onEnd: () => void;

  constructor(s: Settings, who: string, system: string, onEnd: () => void) {
    this.s = s;
    this.who = who;
    this.system = system;
    this.onEnd = onEnd;
    const was = kept()[`claude:${who}`];
    if (was) {
      this.id = was.id;
      this.thoughts = was.thoughts;
    }
    const self = this;
    async function* input(): AsyncGenerator<SDKUserMessage> {
      while (!self.ended) {
        const m = self.queued.shift() ?? (await new Promise<SDKUserMessage>((r) => (self.push = r)));
        if (self.ended) return;
        yield m;
      }
    }
    this.q = query({
      prompt: input(),
      options: {
        model: s.claude.model,
        effort: s.claude.effort,
        systemPrompt: system,
        tools: [],
        allowedTools: [],
        settingSources: [],
        skills: [],
        mcpServers: {},
        strictMcpConfig: true,
        permissionMode: 'dontAsk',
        verbatimPrompts: true,
        includePartialMessages: true,
        persistSession: true,
        cwd: home('claude', who),
        ...(this.id ? { resume: this.id } : {}),
        env: { ...process.env, CLAUDE_AGENT_SDK_CLIENT_APP: 'wisp-minds/0.1' },
        stderr: (d: string) => {
          if (/error/i.test(d)) console.error(`[claude ${who}] ${d.trim().slice(0, 300)}`);
        },
      },
    });
    this.pump();
  }

  private send(m: SDKUserMessage) {
    if (this.push) {
      const p = this.push;
      this.push = null;
      p(m);
    } else this.queued.push(m);
  }

  private async pump() {
    try {
      for await (const m of this.q as AsyncIterable<SDKMessage>) this.on(m);
      this.fail(new Error('Claude session ended'));
    } catch (e) {
      this.fail(e as Error);
    }
    this.end();
  }

  private on(m: SDKMessage) {
    if (m.type === 'system' && m.subtype === 'init') {
      this.model = m.model;
      if (m.session_id && m.session_id !== this.id) {
        this.id = m.session_id;
        keep(`claude:${this.who}`, { id: this.id, thoughts: this.thoughts });
      }
      return;
    }
    if (m.type === 'rate_limit_event') {
      this.limits = m.rate_limit_info;
      return;
    }
    const t = this.turn;
    if (!t) return;
    if (m.type === 'stream_event') {
      const e = m.event as { type: string; delta?: { type: string; text?: string } };
      if (e.type === 'content_block_delta' && e.delta?.type === 'text_delta' && e.delta.text) {
        if (!t.firstMs) t.firstMs = Date.now() - t.t0;
        t.text += e.delta.text;
        t.onDelta(e.delta.text);
      }
      return;
    }
    if (m.type === 'result') {
      this.turn = null;
      const u = m.usage as unknown as { input_tokens?: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number; output_tokens?: number; output_tokens_details?: { thinking_tokens?: number } };
      const total = Number(m.total_cost_usd ?? 0);
      const cost = Math.max(0, total - this.cost);
      this.cost = total;
      this.thoughts++;
      keep(`claude:${this.who}`, { id: this.id, thoughts: this.thoughts });
      if (m.subtype !== 'success' && !t.text) return t.reject(new Error(`Claude: ${m.subtype}`));
      const usage = noUsage();
      usage.input = (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0);
      usage.cached = u.cache_read_input_tokens ?? 0;
      usage.cacheWrite = u.cache_creation_input_tokens ?? 0;
      usage.output = u.output_tokens ?? 0;
      usage.reasoning = u.output_tokens_details?.thinking_tokens ?? 0;
      t.resolve({ text: t.text || ('result' in m ? String(m.result ?? '') : ''), model: this.model || this.s.claude.model, usage, cost, firstMs: t.firstMs, session: this.id, thoughts: this.thoughts, limits: this.limits });
    }
  }

  think(sight: string | undefined, text: string, onDelta: (d: string) => void, signal: AbortSignal): Promise<Turn> {
    if (this.ended) return Promise.reject(new Error('Claude session ended'));
    if (this.turn) return Promise.reject(new Error('busy'));
    return new Promise<Turn>((resolve, reject) => {
      this.turn = { onDelta, resolve, reject, t0: Date.now(), firstMs: 0, text: '' };
      const content: unknown[] = [];
      if (sight) content.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: sight } });
      content.push({ type: 'text', text });
      this.send({ type: 'user', message: { role: 'user', content }, parent_tool_use_id: null, session_id: this.id } as SDKUserMessage);
      signal.addEventListener('abort', () => {
        if (this.turn?.resolve === resolve) this.q?.interrupt().catch(() => {});
      });
    });
  }

  private fail(e: Error) {
    const t = this.turn;
    this.turn = null;
    t?.reject(e);
  }

  end() {
    if (this.ended) return;
    this.ended = true;
    this.push?.({} as SDKUserMessage);
    try {
      this.q?.close();
    } catch {}
    this.onEnd();
  }
}

export class Claude implements Engine {
  name = 'claude' as const;
  sessions = new Map<string, Session>();
  totals = new Map<string, { thoughts: number; cost: number; tokens: number }>();
  s: Settings;
  constructor(s: Settings) {
    this.s = s;
  }

  private session(who: string, system: string) {
    let x = this.sessions.get(who);
    if (!x || x.system !== system) {
      x?.end();
      x = new Session(this.s, who, system, () => {
        if (this.sessions.get(who) === x) this.sessions.delete(who);
      });
      this.sessions.set(who, x);
    }
    return x;
  }

  warm(who: string, system: string) {
    this.session(who, system);
  }

  async think(who: string, system: string, sight: string | undefined, text: string, onDelta: (d: string) => void, signal: AbortSignal) {
    const x = this.session(who, system);
    const t = await x.think(sight, text, onDelta, signal);
    const tot = this.totals.get(who) ?? { thoughts: 0, cost: 0, tokens: 0 };
    tot.thoughts++;
    tot.cost += t.cost;
    tot.tokens += t.usage.input + t.usage.output;
    this.totals.set(who, tot);
    // Starting afresh after a while: their memory comes with every thought anyway
    if (t.thoughts >= this.s.rotate.thoughts || t.usage.input >= this.s.rotate.tokens) {
      keep(`claude:${who}`, null);
      x.end();
      console.log(`[claude ${who}] new session after ${t.thoughts} thoughts (${t.usage.input} tokens in)`);
      // Started now, so the next thought doesn't wait for the process
      this.session(who, system);
    }
    return t;
  }

  // Outside their thinking session, and not kept: the night's reflection, the morning's plan. Each is a fresh
  // one-off session of the character's own; one is kept started ahead (a spare), as starting takes seconds.
  private spares = new Map<string, { q: Query; give: (m: SDKUserMessage) => void }>();

  private spare(who: string, system: string) {
    let give: (m: SDKUserMessage) => void = () => {};
    const first = new Promise<SDKUserMessage>((r) => (give = r));
    async function* input(): AsyncGenerator<SDKUserMessage> {
      yield await first;
    }
    const q = query({
      prompt: input(),
      options: {
        model: this.s.claude.model,
        effort: this.s.claude.effort,
        systemPrompt: system,
        tools: [],
        allowedTools: [],
        settingSources: [],
        skills: [],
        mcpServers: {},
        strictMcpConfig: true,
        permissionMode: 'dontAsk',
        verbatimPrompts: true,
        includePartialMessages: true,
        persistSession: false,
        cwd: home('claude', who),
        env: { ...process.env, CLAUDE_AGENT_SDK_CLIENT_APP: 'wisp-minds/0.1' },
      },
    });
    return { q, give };
  }

  warmOnce(who: string, system: string) {
    const k = `${who}\n${system}`;
    if (!this.spares.has(k)) this.spares.set(k, this.spare(who, system));
  }

  async once(who: string, system: string, user: string): Promise<Turn> {
    const k = `${who}\n${system}`;
    const x = this.spares.get(k) ?? this.spare(who, system);
    this.spares.set(k, this.spare(who, system));
    const t0 = Date.now();
    let text = '';
    let firstMs = 0;
    let model = this.s.claude.model;
    x.give({ type: 'user', message: { role: 'user', content: user }, parent_tool_use_id: null, session_id: '' } as SDKUserMessage);
    try {
      for await (const m of x.q) {
        if (m.type === 'system' && m.subtype === 'init') model = m.model;
        if (m.type === 'stream_event') {
          const e = m.event as { type: string; delta?: { type: string; text?: string } };
          if (e.type === 'content_block_delta' && e.delta?.type === 'text_delta' && e.delta.text) {
            if (!firstMs) firstMs = Date.now() - t0;
            text += e.delta.text;
          }
        }
        if (m.type === 'result') {
          const u = m.usage as unknown as { input_tokens?: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number; output_tokens?: number };
          const usage = noUsage();
          usage.input = (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0);
          usage.cached = u.cache_read_input_tokens ?? 0;
          usage.output = u.output_tokens ?? 0;
          return { text: text || String((m as { result?: string }).result ?? ''), model, usage, cost: Number(m.total_cost_usd ?? 0), firstMs, session: '', thoughts: 1 };
        }
      }
    } finally {
      x.q.close();
    }
    throw new Error('Claude gave no answer');
  }

  stats() {
    const out: Record<string, unknown> = {};
    for (const [who, t] of this.totals) out[who] = { ...t, session: this.sessions.get(who)?.id ?? '', inSession: this.sessions.get(who)?.thoughts ?? 0, limits: this.sessions.get(who)?.limits };
    return out;
  }

  close() {
    for (const x of this.sessions.values()) x.end();
    for (const x of this.spares.values()) x.q.close();
  }
}
