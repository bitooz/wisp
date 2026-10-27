// What each way of thinking (Claude through the Agent SDK, Codex through its app-server) gives the server.

export type Usage = { input: number; cached: number; cacheWrite: number; output: number; reasoning: number };

export type Turn = {
  text: string;
  model: string;
  usage: Usage;
  // Estimated API-equivalent cost of this one thought in USD (on a subscription login it's usage, not a bill)
  cost: number;
  // From sending it to the first word of the answer
  firstMs: number;
  session: string;
  // How many thoughts this session has had, with this one
  thoughts: number;
  // Where the login's limits stand, if the engine says (Claude: utilization; Codex: usedPercent)
  limits?: unknown;
};

export interface Engine {
  name: 'claude' | 'codex';
  // One thought in the character's own persistent session: the picture from their eyes and the text of the rest.
  think(who: string, system: string, sight: string | undefined, text: string, onDelta: (d: string) => void, signal: AbortSignal): Promise<Turn>;
  // A one-off text call outside the session (the night's reflection, the morning's plan): their own, kept apart.
  once(who: string, system: string, user: string): Promise<Turn>;
  // Start the character's session ahead of the first thought (the process takes seconds to start).
  warm(who: string, system: string): void;
  // Get ready for once() with this system prompt (Claude starts its process ahead).
  warmOnce(who: string, system: string): void;
  stats(): Record<string, unknown>;
  close(): void;
}

export const noUsage = (): Usage => ({ input: 0, cached: 0, cacheWrite: 0, output: 0, reasoning: 0 });
