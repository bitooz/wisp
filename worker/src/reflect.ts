// A night's reflection: as Mo or Bo falls asleep, what they remember of the day is turned over into a few
// lasting beliefs, in their own words. One short text-only call per pal per night (the game makes sure).
import { NAMES, PERSONAS, type Who } from './minds.ts';

export type ReflectBody = {
  who: Who;
  memories: string[]; // what they remember of the day, as lines, oldest first
  beliefs?: string[]; // what they already believe
  plan?: string;
  mood?: string; // their mood, in words
  bonds?: string[]; // how they feel about each of the others, in words
  promises?: string[]; // promises made to them that the game can't judge ("Bo promised you: ...")
};

export type Belief = { text: string; importance: number; from: number[] };
export type Feeling = { who: string; trust: number; fond: number; why: string };
export type Judged = { n: number; kept: boolean };

const clip = (s: unknown, n: number) => String(s ?? '').slice(0, n);

export function reflectPrompt(b: ReflectBody): { system: string; user: string } {
  const me = PERSONAS[b.who];
  // Who else they might feel differently about
  const others = Object.keys(NAMES).filter((k) => k !== b.who);
  const names = others.map((k) => NAMES[k]).join(', ');
  const system = `${me.who}

It's night and you're falling asleep. You think back over what happened, the way anyone does in bed: what
mattered, what you found out, how you feel about the others. Then you settle on what you now believe.

Reply with one JSON object and nothing else:
{"beliefs": [{"text": "<one thing you now believe, first person, under 20 words>", "importance": <6 to 10>,
"from": [<numbers of the memories it comes from>]}],
 "people": [{"who": "<one of: ${others.join(', ')}>", "trust": -1, 0 or 1, "fond": -1, 0 or 1, "why": "<a few words>"}],
 "promises": [{"n": <number of a promise below>, "kept": true or false}]}
- At most 3 beliefs, only from what's in the memories below: never make anything up.
- Things worth believing: what you learned about how things work, about a place, about the others (${names}),
  and about what you want. Not small stuff like what you had to eat.
- Don't repeat what you already believe, unless the day changed your mind (then say the new view).
- "people": did today make you trust or like any of them more (1), less (-1), or no different (0)?
  Only for what really happened today; usually it's 0.
- "promises": for each promise listed below, only if today shows whether it was kept or broken.`;
  const mem = (b.memories ?? []).slice(0, 60).map((m, i) => `${i + 1}. ${clip(m, 220)}`);
  const lines = [`What you remember of today:\n${mem.join('\n') || '(nothing much)'}`];
  const have = (b.beliefs ?? []).slice(0, 12).map((x) => `- ${clip(x, 160)}`);
  if (have.length) lines.push(`What you already believe:\n${have.join('\n')}`);
  if (b.plan) lines.push(`Your plan was: ${clip(b.plan, 200)}`);
  if (b.mood) lines.push(`Your mood: ${clip(b.mood, 80)}`);
  const bonds = (b.bonds ?? []).slice(-6).map((x) => `- ${clip(x, 400)}`);
  if (bonds.length) lines.push(`How you feel about the others:\n${bonds.join('\n')}`);
  const prom = (b.promises ?? []).slice(0, 8).map((x, i) => `${i + 1}. ${clip(x, 200)}`);
  if (prom.length) lines.push(`Promises made to you:\n${prom.join('\n')}`);
  return { system, user: lines.join('\n\n') };
}

// The beliefs from the reply, checked: at most 3, short, importance 6 to 10, "from" only numbers in the list.
export function parseBeliefs(all: string, count: number): Belief[] {
  let o: { beliefs?: unknown } = {};
  try {
    o = JSON.parse(all.slice(all.indexOf('{'), all.lastIndexOf('}') + 1));
  } catch {
    return [];
  }
  if (!Array.isArray(o.beliefs)) return [];
  return o.beliefs
    .map((x: { text?: unknown; importance?: unknown; from?: unknown }) => ({
      text: clip(x?.text, 200).trim(),
      importance: Math.max(6, Math.min(10, Math.round(Number(x?.importance) || 8))),
      from: Array.isArray(x?.from) ? x.from.map(Number).filter((n: number) => Number.isInteger(n) && n >= 1 && n <= count) : [],
    }))
    .filter((x: Belief) => x.text !== '')
    .slice(0, 3);
}

// How the day changed their feelings (a small step each way at most) and which promises it settled.
export function parseFeelings(all: string, promises: number): { people: Feeling[]; promises: Judged[] } {
  let o: { people?: unknown; promises?: unknown } = {};
  try {
    o = JSON.parse(all.slice(all.indexOf('{'), all.lastIndexOf('}') + 1));
  } catch {
    return { people: [], promises: [] };
  }
  const step = (x: unknown) => Math.max(-1, Math.min(1, Math.round(Number(x) || 0)));
  const people = (Array.isArray(o.people) ? o.people : [])
    .map((x: { who?: unknown; trust?: unknown; fond?: unknown; why?: unknown }) => ({
      who: clip(x?.who, 8).toLowerCase().trim(),
      trust: step(x?.trust),
      fond: step(x?.fond),
      why: clip(x?.why, 120).trim(),
    }))
    .filter((x: Feeling) => x.who in NAMES)
    .slice(0, 3);
  const judged = (Array.isArray(o.promises) ? o.promises : [])
    .map((x: { n?: unknown; kept?: unknown }) => ({ n: Number(x?.n), kept: x?.kept === true }))
    .filter((x: Judged) => Number.isInteger(x.n) && x.n >= 1 && x.n <= promises);
  return { people, promises: judged };
}
