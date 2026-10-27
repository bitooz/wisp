// What the mind server still asks the Worker for: their voices (Fish Audio), writing down what the player said
// (Claude and Codex don't take audio), and whole thoughts for whoever thinks on "worker". The keys stay there.
import type { Settings } from './settings.ts';

const headers = (s: Settings) => ({ 'content-type': 'application/json', 'x-wisp-key': s.worker.key });

export function hasWorker(s: Settings) {
  return Boolean(s.worker.url && s.worker.key);
}

// The player's words from a WAV: {heard, junk, cost, ms, model}
export async function hear(s: Settings, audio: string): Promise<{ heard: string; junk: boolean; cost: number; ms: number; model?: string }> {
  if (!hasWorker(s)) throw new Error('no Worker for speech-to-text (set worker in settings.json)');
  const t0 = Date.now();
  const res = await fetch(`${s.worker.url}/hear`, { method: 'POST', headers: headers(s), body: JSON.stringify({ audio }), signal: AbortSignal.timeout(15000) });
  if (!res.ok) throw new Error(`hear ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const j = (await res.json()) as { heard?: string; junk?: boolean; cost?: number; model?: string };
  return { heard: String(j.heard ?? ''), junk: Boolean(j.junk), cost: Number(j.cost ?? 0), ms: Date.now() - t0, model: j.model };
}

// A line in their voice: 16-bit mono PCM at 24 kHz, as it's made.
export async function speak(s: Settings, who: string, text: string, signal?: AbortSignal): Promise<Response> {
  if (!hasWorker(s)) throw new Error('no Worker for voices');
  const q = new URLSearchParams({ v: who, t: text });
  return fetch(`${s.worker.url}/speak?${q}`, { headers: { 'x-wisp-key': s.worker.key }, signal });
}

// Anything else, passed through as it is (a whole /think on the Worker's model, /reflect, /plan, /voices).
export function pass(s: Settings, path: string, init: RequestInit) {
  if (!hasWorker(s)) throw new Error('no Worker set');
  return fetch(`${s.worker.url}${path}`, { ...init, headers: { ...headers(s), ...((init.headers as Record<string, string>) ?? {}) } });
}
