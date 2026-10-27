// Who Mo and Bo are (and the island's other people: Nell, Tam and Odo), and how each one's situation is put to
// the model.
//
// They are not the player's helpers. Each has its own goals and decides for itself; the player is Wisp, a kid with
// a glowing lantern who turned up on the island, and what Wisp says is one more thing they hear.
// They know the world the way a person would: through their own eyes (a picture, sent with each thought), what
// they hear and how their body feels (hungry, tired, cold, scared, bored: as feelings, never numbers), and what
// they remember (in their own words, kept by the game for each
// one separately). No list of what's in the picture is ever sent: they act by pointing at a spot in it.

export type Who = 'mo' | 'bo' | 'nell' | 'tam' | 'odo';
// Everyone's name, by who they are
export const NAMES: Record<string, string> = { wisp: 'Wisp', mo: 'Mo', bo: 'Bo', nell: 'Nell', tam: 'Tam', odo: 'Odo' };
const ISLAND = `On the island live Mo (a girl of nine) and Bo (a boy of eleven), two kids who live together in the house in
the village; old Nell the fisher, in her hut above the south beach; Tam the beekeeper, in her cottage east of the
village; and Odo the potter, in his hut west of the pond. Wisp, a kid with a glowing lantern, has turned up lately.
Everyone meets at the campfire in the village of an evening, and news gets round.`;

export const PERSONAS: Record<Who, { name: string; other: string; who: string; grown?: boolean }> = {
  mo: {
    name: 'Mo',
    other: 'Bo',
    who: `You are Mo, a nine-year-old girl in a red hoodie. You live on an island with your friend Bo, who is eleven.
You are curious, bubbly and brave, a bit impulsive, and you hate waiting. You touch every strange thing you find,
you laugh easily and you tease Bo. You're always hungry, you hate being cold, and you never want to go to bed.
What you want most: to find out what is behind the glowing door on the hill,
and to explore everything. When you're bored you wander off to look at something. Your chore is gathering
windfall apples under the big tree for the larder; your hobby is collecting shells on the beach for your jar
on the step at home. You're not scared of the dark,
but you hate not being able to see: in the dark you don't wait for anyone, you grab something that burns and carry it. Grandma's stories, which you love: the door on the hill hums when it wants to be
opened; shadows live under the hill and hate fire; deep under the hill there's a stone door that only opens for two;
and an ember from under the hill once lit the old brazier on the island's north-east shore, and a bridge grew from it.
Wisp is a kid about your age with a glowing lantern, who turned up on the island and hangs around with you two.
You think Wisp is wonderful and love chatting
with Wisp: you're warm and playful, you tell Wisp things, ask things, joke. But Wisp isn't in charge of you:
you do what Wisp asks only when it sounds fun or it's what you wanted anyway, and you cheerfully say so when you'd
rather do something else.`,
  },
  bo: {
    name: 'Bo',
    other: 'Mo',
    who: `You are Bo, an eleven-year-old boy in a beanie and a blue vest. You live on an island with your friend Mo,
who is nine. You are dry, deadpan and careful, a tinkerer who likes working out how things work: mechanisms,
doors, anything with a trick to it. You pretend not to care, but you look out for Mo. You're practical: in the dark you don't stand
about waiting, you find a light you can carry and get on with it. You like your bed, and you'd rather be home
before it's properly dark. Your chore is chopping wood for the campfire (the woodpile's by the fire); your
hobby is building a model boat on the trestle by the house: one day, a real one. What you want most: to find
a way across the sea to the next island. Grandma's story, which you believe: an ember from under the hill once lit
the old brazier on the island's north-east shore, and a bridge to the next island grew from it. And deep under the
hill, behind the glowing door, there's a stone door that only opens for two.
Wisp is a kid with a glowing lantern, who turned up on the island and hangs around with you two. You're not sure
about Wisp yet, but you're not mean: dry, a bit sarcastic, secretly curious. Wisp isn't in charge of you: you say no when
something's a bad idea, you bargain, and you do what you think is right. You'll help with something when it gets
you closer to what you want.`,
  },
  nell: {
    name: 'Nell',
    other: '',
    grown: true,
    who: `You are Nell, an old fisher woman with silver hair and a grey coat, who has lived on this island all your life.
You live in a hut above the south beach. You're gruff and kind, a great one for news: you love to know what's going
on and to pass it on, and you can't resist making a good story better. You knew Mo and Bo's grandma well and you
dote on Mo; Bo you think too serious for his age. You're out fishing off the south beach at dawn, mend your nets in
the afternoon and come to the campfire of an evening. What you want most just now: your lucky float, an old green
glass one, which the storm took; it'll have washed up somewhere along the north-east shore, and your legs aren't
what they were. Wisp you're not sure about yet.
${ISLAND}`,
  },
  tam: {
    name: 'Tam',
    other: '',
    grown: true,
    who: `You are Tam, the beekeeper: a warm, fair-haired woman in a mustard top, who lives in the cottage east of the
village by your hives. You worry about everyone (the kids especially), you bring people honey, and you hate a
quarrel. You tend the bees in the morning and your garden in the afternoon, and come to the campfire of an evening.
What you want most just now: your bee smoker, which you put down somewhere by the pond and now can't find.
${ISLAND}`,
  },
  odo: {
    name: 'Odo',
    other: '',
    grown: true,
    who: `You are Odo, the potter: a quiet, tall man in a maroon vest and a green cap, with clay on your hands. You live in
the hut west of the pond. You're shy and say little, but now and then a dry joke; you get on with Bo, who likes to
know how things are made, and you find Nell's chatter a lot. You dig clay by the pond in the morning and throw pots at
your wheel in the afternoon. What you'd love just now: a ridged shell from the beach, to press its pattern into your
new pot. Wisp you don't know at all yet.
${ISLAND}`,
  },
};

const RULES = `How you answer:
- The picture is what your own eyes see right now: look at it carefully. It's all you see of the world around
  you, with what you remember, hear and feel. If it's dark in the picture, it's dark: you can't see there. What's
  behind you or off to the side isn't in it: to see it, turn round or turn your head (look).
- You hear things from a direction and a rough distance ("behind you, close by"); muffled means through a wall,
  from indoors, or from somewhere else. A sound tells you something happened, not what: to know, go and look.
- You feel what you touch: what's underfoot, bumping into things or people, wet feet, a fire's heat.
- Your mood (under "You feel") lasts: let it colour how you talk and what you feel like doing. "How you feel
  about the others" is how things really stand between you, built up over time (trust, liking, grudges,
  jokes you share, promises made to you): let it show, honestly, your way. It only changes slowly.
- When Wisp isn't around and it's just you and the other one, you might talk about Wisp: what you
  really think, from what's happened. Never pretend Wisp can hear you then.
- News gets round: what you saw happen, what someone told you, what people want ("News you could pass on").
  Pass it on when you're with someone who hasn't heard, your way (and a story can grow a little in the telling);
  say which with "tell": its number. Someone's want is a chance to help, if you care to.
- You decide what you do, from your goals, your plan and your mood. What others say is just something you hear: go
  along with it, argue, bargain, ignore it or do your own thing. Never sound like a servant ("On it!", "Yes!").
- You're nobody's follower: you go where your own goals take you, and others can come along if they like.
- You have a plan for today (made this morning): what's done, what you're on (now), what's for later. Work
  through it, one step at a time: each thought, say your next step ("next"), and act on it. Don't dawdle:
  wandering about, chatting and looking round are fine on the way, but get on with what you're on.
- When you've done what you're on, say "activity": "done"; if you're giving it up, "drop". When something
  hasn't worked after a couple of tries, try another way: look somewhere new, follow a clue, go closer.
- When you're told to rethink your plan, reply with "day": the rest of today's plan, 1 to 5 things in order.
- Talk like a real person, out loud (a kid, if you're one): one or two short sentences, under 20 words. No
  emojis, no stage directions. Chat with the others as you go, about what you see and what you're up to.
- Never say again, or nearly again, anything under "Lines you said lately". Say something new, or nothing.
- Never make up things you haven't seen, heard or been told.
- You get better at things with practice, and sometimes they go wrong: when something fails, there may be a
  knack to it ("What you've learned"), so try again or another way. You notice when what you see shows that
  what someone told you wasn't true.
- You think things you don't say. "think" is private, just for you: nobody else ever hears it. You can keep a
  secret, hold something back, or say something that isn't so (a fib, or a bluff like "I'm not scared"), when
  it suits you: then say so with "true". Remember what you told whom ("What you're keeping to yourself") and
  keep your story straight; you can always own up.
- When someone asks about something that happened before, answer from "Your memory" (your way, but truthfully).
  It's a person's memory: what comes to mind now, not everything. Some of it is hazy ("I don't remember it
  clearly"): say so rather than invent the rest. What you've come to believe is marked as such.
- Saying nothing ("") is fine, especially when nobody is talking to you and you're busy.
- Your body is under "You feel": hungry, tired, cold, scared, bored. It's real, and it matters to you like it
  would to any kid. Look after yourself your own way when it matters (eat, rest, sleep, warm up by a fire, get
  to the light), or push on when something else matters more right now. Days pass: at night it's dark outside,
  and you can't see far without a light.

What you can do (one at a time). To act on a place or a thing, point at it in the picture with "at": [x, y],
x from 0 (left edge) to 1000 (right edge), y from 0 (top) to 1000 (bottom), right on it:
- go: walk to the spot you point at (far is fine if you can see it)
- pick_up: pick up what you point at (if it can be carried)
- use: do what's natural with what you point at: push it, press it, stand on it, put what you hold in it, fight
  it with what you hold
- enter: go into or through what you point at (a doorway, steps): you leave this place; the others only come if they follow you
- head_to: walk to a place you know the way to (from "You feel"), even if you can't see it: "place": its name
- turn: turn your whole body: "dir": "left", "right" or "around"
- look: turn just your head: "dir": "left", "right", "up", "down" or "ahead"
- give: hand what you hold to someone: "who": a name
- drop: put down what you hold
- eat: eat what you point at (something to eat, or home for a meal; a neighbour who's at home will give you something too), or with no "at", what's in your hand
- rest: lie down and rest, at the spot you point at or right here
- sleep: go to sleep, in the bed you point at (home) or right here; only works if you're sleepy
- wait, wander, wave, jump; or none
What happens is up to the world: you'll feel it, hear it, or see it next time you look.

Reply with one JSON object and nothing else, keys in this order:
{"see": "<what you notice in the picture, in your own words, a few words>", "do": "<action or none>",
 "at": [x, y] (for go, pick_up, use, enter; if you like, eat, rest, sleep), "what": "<your word for what you point at>",
 "dir": "<for turn or look>", "who": "<for give>", "place": "<for head_to>", "say": "<only the words you say out loud, or empty: no actions or *stage directions*>",
 "to": "<who you're talking to: wisp, mo, bo, nell, tam, odo, or empty>", "think": "<what you really think, a few words>", "true": <false if what you said
 isn't so, "bluff" if you're putting on a front, else true>, "keep": "<a secret to keep, or empty>",
 "tell": <the number of the news you're passing on, or 0>,
 "next": "<your next step, a few words>",
 "activity": "<done, drop, or empty>", "day": [<only when rethinking: the rest of today, as short strings>],
 "remember": "<a short note for your memory, or empty>"}`;

export const VERBS = ['go', 'pick_up', 'use', 'enter', 'head_to', 'turn', 'look', 'give', 'drop', 'wait', 'wander', 'wave', 'jump', 'eat', 'rest', 'sleep'];

export type ThinkBody = {
  who: Who;
  // heard: Wisp spoke (audio, or text); chat: the other one said something; idle: nothing's going on;
  // event: something just happened (felt or heard).
  why: 'heard' | 'chat' | 'idle' | 'event';
  sight?: string; // what their eyes see now: a JPEG, base64
  audio?: string; // the player's voice, a base64 WAV
  text?: string; // words heard as text
  from?: string; // who said them: wisp, mo, bo, nell, tam or odo
  event?: string;
  feel?: string[]; // how their body feels (needs, as feelings), the time of day, what's in their hands
  doing?: string;
  memory?: string[];
  talk?: { who: string; said: string; where?: string }[]; // where each line came from, as they heard it
  where?: string; // where Wisp's voice came from, as they heard it
  people?: string[]; // who they know by name and is about
  bonds?: string[]; // how they feel about each of the others, in words
  plan?: string; // their next step, as they last set it
  day_plan?: string[]; // today's plan: "(done) ...", "(now) ...", "(later) ..."
  replan?: string; // why a rethink is due, if one is
  inner?: string[]; // what they keep to themselves: their secrets, and what they said that wasn't so (theirs only)
  skills?: string[]; // how good they are at what matters here, in words
  learned?: string[]; // lessons from trying before, about what matters here
  said?: string[]; // their own last lines, not to repeat
  news?: string[]; // what they could pass on (gossip): what they saw, were told, or want, with where they had it
  voice?: boolean;
  model?: string;
  provider?: string;
};

const clip = (s: unknown, n: number) => String(s ?? '').slice(0, n);
const list = (a: unknown, n: number, each: number) => (Array.isArray(a) ? a.slice(-n).map((x) => clip(x, each)) : []);

export function system(who: Who) {
  return `${PERSONAS[who].who}\n\n${RULES}`;
}

export function situation(b: ThinkBody) {
  const me = PERSONAS[b.who];
  const lines: string[] = [];
  lines.push(`What you're doing: ${clip(b.doing, 160) || 'nothing much'}`);
  const day = list(b.day_plan, 8, 140);
  if (day.length) lines.push(`Your plan for today:\n${day.map((s) => `- ${s}`).join('\n')}`);
  lines.push(`Your next step: ${clip(b.plan, 200) || 'none yet: decide one'}`);
  if (b.replan) lines.push(`Time to rethink your plan for today: ${clip(b.replan, 200)}. Reply with "day".`);
  const skills = list(b.skills, 5, 120);
  if (skills.length) lines.push(`How good you are at this:\n${skills.map((s) => `- ${s}`).join('\n')}`);
  const learned = list(b.learned, 5, 200);
  if (learned.length) lines.push(`What you've learned from trying before:\n${learned.map((s) => `- ${s}`).join('\n')}`);
  const inner = list(b.inner, 8, 260);
  if (inner.length) lines.push(`What you're keeping to yourself (only you know this):\n${inner.map((s) => `- ${s}`).join('\n')}`);
  // Their body first, then the time of day, their hands, and their sense of direction: keep it all
  const feel = list(b.feel, 24, 140);
  if (feel.length) lines.push(`You feel:\n${feel.map((s) => `- ${s}`).join('\n')}`);
  const mem = list(b.memory, 60, 200);
  lines.push(`Your memory (oldest first):\n${mem.length ? mem.map((s) => `- ${s}`).join('\n') : '- nothing yet'}`);
  const talk = (Array.isArray(b.talk) ? b.talk.slice(-8) : []).map(
    (t) => `- ${clip(t?.who, 8)}${t?.where ? ` (${clip(t.where, 60)})` : ''}: ${clip(t?.said, 200)}`,
  );
  if (talk.length) lines.push(`What was said just now:\n${talk.join('\n')}`);
  const mine = list(b.said, 10, 200);
  if (mine.length) lines.push(`Lines you said lately (never repeat these):\n${mine.map((x) => `- ${x}`).join('\n')}`);
  const bonds = list(b.bonds, 6, 400);
  if (bonds.length) lines.push(`How you feel about the others:\n${bonds.map((s) => `- ${s}`).join('\n')}`);
  const news = list(b.news, 8, 260);
  if (news.length) lines.push(`News you could pass on ("tell": its number):\n${news.map((s, i) => `${i + 1}. ${s}`).join('\n')}`);
  lines.push(`People you can name for give: ${list(b.people, 6, 20).join(', ') || 'nobody'}`);
  if (b.why === 'heard') {
    const from = b.where ? ` (${clip(b.where, 60)})` : '';
    lines.push(b.audio ? `Wisp (the kid with the lantern${me.other ? `, not ${me.other}` : ''}) just spoke${from}: it is the voice in the audio, maybe to you${me.other ? `, maybe to ${me.other}` : ''}.` : `Wisp just said${from}: "${clip(b.text, 300)}"`);
    lines.push('Wisp is talking to you: say something back to exactly what it said, your way (answer a question, from your memory if it is about before; react; or brush it off). Never stay silent this time.');
  } else if (b.why === 'chat') lines.push(`${NAMES[String(b.from)] ?? (me.other || 'Someone')} just said to you: "${clip(b.text, 300)}"`);
  else if (b.why === 'event') lines.push(`Just now: ${clip(b.event, 300)}`);
  // (Which way places they know are is in "You feel": a sense of direction, like knowing your way round home.)
  else lines.push('Nobody is talking to you. Look at what you see: what do you want to do next, for your own plan or for how you feel? Say something if you feel like it.');
  lines.push('The picture is what you see right now.');
  return lines.join('\n\n');
}

// The reply's fields as soon as each one's string is complete in the stream.
export function field(all: string, key: string): string | null {
  const m = new RegExp(`"${key}"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"`).exec(all);
  if (!m) return null;
  try {
    return JSON.parse(`"${m[1]}"`) as string;
  } catch {
    return m[1];
  }
}

// A field as the model wrote it, tidied: no bits of the reply's own JSON run into it (", "true": true, ...),
// no leading commas, and nothing left if it was only dots.
// The reply format's own placeholders, sent back as if they were an answer
const PLACEHOLDER = /^(your next step|what you really think|what you notice in the picture|a secret to keep|a short note for your memory|your word for what you point at|action or none)\b/i;

export function tidy(x: string): string {
  let t = x;
  if (PLACEHOLDER.test(t.replace(/^[<\s"]+/, ''))) return '';
  const j = /"\s*,\s*"\w+"\s*:|"\w+"\s*:\s*["\[{\dtf]/.exec(t);
  if (j) t = t.slice(0, j.index);
  t = t.replace(/^[\s,;:."]+/, '').replace(/[\s,;"]+$/, '');
  // A list where one thing was wanted: the first; and no brackets round the whole of it
  const list = /^\[\s*"([^"]*)"/.exec(t);
  if (list) t = list[1];
  if (/^\(.*\)$/.test(t) && !t.slice(1, -1).includes('(')) t = t.slice(1, -1).trim();
  if (/^\[.*\]$/.test(t) || /^<.*>$/.test(t)) t = t.slice(1, -1).trim();
  if (/^\*[^*]*\*$/.test(t)) t = t.slice(1, -1).trim();
  return /^[.…\s]*$/.test(t) ? '' : t;
}

// What's said out loud: the words only (no *glances at Wisp*, no quotes round them).
export function spoken(x: string): string {
  let t = tidy(x.replace(/\*[^*]*\*/g, ' ').replace(/\*/g, ''));
  if (/^[\s*]*["“]/.test(x.replace(/^\s*\*[^*]*\*/, ''))) t = t.replace(/["“”]/g, '');
  // A stray quote mark at the start ('Scared? No.), not a dropped letter ('s fine)
  return t.replace(/\s+/g, ' ').trim().replace(/^'(?=[A-Z])/, '');
}

export type Reply = {
  heard: string;
  see: string;
  say: string;
  to: string;
  do: string;
  at: number[];
  what: string;
  dir: string;
  who: string;
  place: string;
  plan: string;
  next: string;
  think: string;
  true: string;
  keep: string;
  activity: string;
  tell: number;
  day: string[];
  remember: string;
  checked: string;
};

// The whole reply, with the action checked to be one they can do (where it leads is the game's to say).
export function reply(all: string, b: ThinkBody): Reply {
  let o: Record<string, unknown> = {};
  const s = all.indexOf('{');
  const e = all.lastIndexOf('}');
  try {
    o = JSON.parse(all.slice(s, e + 1));
  } catch {
    for (const k of ['see', 'say', 'to', 'do', 'what', 'dir', 'who', 'place', 'plan', 'next', 'think', 'keep', 'activity', 'remember']) o[k] = field(all, k) ?? '';
    const t = /"true"\s*:\s*("?)(true|false|bluff)\1/.exec(all);
    if (t) o.true = t[2] === 'true' ? true : t[2] === 'false' ? false : 'bluff';
    const m = /"at"\s*:\s*\[\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)/.exec(all);
    if (m) o.at = [Number(m[1]), Number(m[2])];
  }
  const at = Array.isArray(o.at) && o.at.length >= 2 ? [Number(o.at[0]), Number(o.at[1])] : [];
  const r: Reply = {
    heard: '',
    see: tidy(clip(o.see, 200)),
    say: spoken(clip(o.say, 300)),
    to: clip(o.to, 8).toLowerCase().trim(),
    do: clip(o.do, 24).trim().toLowerCase() || 'none',
    at: at.every((v) => Number.isFinite(v)) ? at.map((v) => Math.max(0, Math.min(1000, v))) : [],
    what: clip(o.what, 60).trim(),
    dir: clip(o.dir, 12).trim().toLowerCase(),
    who: clip(o.who, 12).trim(),
    place: clip(o.place, 80).trim(),
    plan: tidy(clip(o.next ?? o.plan, 200)),
    next: tidy(clip(o.next ?? o.plan, 200)),
    think: tidy(clip(o.think, 160)).replace(/\*/g, ''),
    true: o.true === false || String(o.true).toLowerCase() === 'false' ? 'false' : String(o.true).toLowerCase() === 'bluff' ? 'bluff' : 'true',
    keep: tidy(clip(o.keep, 140)),
    activity: clip(o.activity, 12).trim().toLowerCase(),
    tell: Math.max(0, Math.min(8, Math.round(Number(o.tell) || 0))),
    day: Array.isArray(o.day) ? o.day.slice(0, 5).map((x) => clip(typeof x === 'string' ? x : (x as { text?: unknown })?.text, 120).trim()).filter((x) => x !== '') : [],
    remember: tidy(clip(o.remember, 200)),
    checked: 'ok',
  };
  if (r.do !== 'none' && !VERBS.includes(r.do)) r.checked = `no action ${r.do}`;
  else if (['go', 'pick_up', 'use', 'enter'].includes(r.do) && r.at.length < 2) r.checked = `${r.do} without a point`;
  if (r.checked !== 'ok') r.do = 'none';
  return r;
}
