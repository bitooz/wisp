// The morning's plan: as Mo or Bo starts the day, a short list of what they mean to do today, from what they
// want, how they are, what they believe and feel, and how yesterday went. One small text-only call per pal per
// morning (the game makes sure); the rest of the day, their thoughts keep it up and rethink it when needed.
import { PERSONAS, type Who } from './minds.ts';

export type PlanBody = {
  who: Who;
  time?: string; // the time of day, as they'd know it
  goals?: string[]; // what they want most
  beliefs?: string[];
  feel?: string[]; // mood and body, in words
  bonds?: string[]; // how they feel about the others
  yesterday?: string; // how yesterday's plan went
  leftover?: string[]; // what they didn't get to
  routine?: string[]; // their usual day: chore, hobby, evenings
  helping?: string[]; // what others want that they've heard about and could help with
  today?: string[]; // what they've done already today (breakfast, before you turned up)
};

export type PlanItem = { text: string; why: string };

const clip = (s: unknown, n: number) => String(s ?? '').slice(0, n);
const list = (a: unknown, n: number, each: number) => (Array.isArray(a) ? a.slice(0, n).map((x) => `- ${clip(x, each)}`) : []);

export function planPrompt(b: PlanBody): { system: string; user: string } {
  const me = PERSONAS[b.who];
  const system = `${me.who}

You've just got up. Think about your day, the way anyone does first thing: what you want to get done today,
and in what order. Your own goals come first, unless your body or your feelings get in the way.

Reply with one JSON object and nothing else:
{"day": [{"text": "<one thing to do today, a few words>", "why": "<a few words>"}], "step": "<the very first thing you'll do>"}
- 3 to 5 things, in the order you'll do them; real things you can do on the island (or under the hill).
- Only from what you know: your goals, what you believe, what you remember; nothing made up.
- If you're hungry, tired, cold or scared, deal with that first.
- Fit in your chore and your hobby (from your usual day), unless something matters more today.
- If someone you care about wants something you could help with, you might fit that in too.`;
  const lines: string[] = [];
  if (b.time) lines.push(`Now: ${clip(b.time, 80)}`);
  const goals = list(b.goals, 4, 160);
  if (goals.length) lines.push(`What you want most:\n${goals.join('\n')}`);
  const beliefs = list(b.beliefs, 12, 160);
  if (beliefs.length) lines.push(`What you believe:\n${beliefs.join('\n')}`);
  const feel = list(b.feel, 8, 120);
  if (feel.length) lines.push(`How you are:\n${feel.join('\n')}`);
  const bonds = list(b.bonds, 6, 400);
  if (bonds.length) lines.push(`How you feel about the others:\n${bonds.join('\n')}`);
  const usual = list(b.routine, 4, 160);
  if (usual.length) lines.push(`Your usual day:\n${usual.join('\n')}`);
  if (b.yesterday) lines.push(`Yesterday: ${clip(b.yesterday, 400)}`);
  const help = list(b.helping, 3, 160);
  if (help.length) lines.push(`Others want (you've heard), and you could help:\n${help.join('\n')}`);
  const today = list(b.today, 4, 120);
  if (today.length) lines.push(`Done already today (don't plan it again):\n${today.join('\n')}`);
  const left = list(b.leftover, 5, 120);
  if (left.length) lines.push(`What you didn't get to:\n${left.join('\n')}`);
  return { system, user: lines.join('\n\n') || 'A new day.' };
}

// The day's plan from the reply: 1 to 5 things, short; the first step if there is one.
export function parsePlan(all: string): { day: PlanItem[]; step: string } {
  let o: { day?: unknown; step?: unknown } = {};
  try {
    o = JSON.parse(all.slice(all.indexOf('{'), all.lastIndexOf('}') + 1));
  } catch {
    return { day: [], step: '' };
  }
  const day = (Array.isArray(o.day) ? o.day : [])
    .map((x: unknown) => (typeof x === 'string' ? { text: x, why: '' } : { text: clip((x as { text?: unknown })?.text, 120), why: clip((x as { why?: unknown })?.why, 120) }))
    .map((x: PlanItem) => ({ text: x.text.trim(), why: x.why.trim() }))
    .filter((x: PlanItem) => x.text !== '')
    .slice(0, 5);
  return { day, step: clip(o.step, 160).trim() };
}
