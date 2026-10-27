// Private thoughts, secrets and fibs in a thought, with no model call:
//   node --experimental-strip-types scripts/secret-check.mjs
import { reply, situation, system } from '../src/minds.ts';

let failed = false;
const check = (ok, what) => { console.log((ok ? 'ok:   ' : 'FAIL: ') + what); if (!ok) failed = true; };
const sys = system('mo');
const fmt = sys.slice(sys.indexOf('Reply with one JSON object'));
check(fmt.indexOf('"say"') < fmt.indexOf('"think"') && fmt.indexOf('"say"') < fmt.indexOf('"true"') && fmt.indexOf('"say"') < fmt.indexOf('"keep"'), 'the private part comes after what they say (their voice starts no later)');
check(sys.includes('"think" is private') && sys.includes('keep your story straight'), 'they know their thoughts are private, and to keep their story straight');
const body = { who: 'mo', why: 'idle', feel: [], doing: 'waiting here', memory: [], people: ['Wisp', 'Bo'],
  inner: ['a secret: I found a shiny key under the mushroom (you haven\'t told anyone)', 'you told Bo "I\'ll wait here", and it isn\'t true: I\'m going in alone'] };
const s = situation(body);
check(s.includes("What you're keeping to yourself (only you know this):\n- a secret: I found a shiny key") && s.includes('- you told Bo "I\'ll wait here", and it isn\'t true'), 'their own secrets and fibs go into their thoughts');
check(!situation({ ...body, inner: [] }).includes('keeping to yourself'), 'and nothing when there are none');
const r = reply('{"see": "x", "do": "none", "say": "Sure, I\'ll wait here.", "to": "bo", "think": "no way, I\'m going in alone", "true": false, "keep": "the key under the mushroom", "next": "sneak off"}', body);
check(r.say === "Sure, I'll wait here." && r.think === "no way, I'm going in alone" && r.true === 'false' && r.keep === 'the key under the mushroom', 'the reply: what she said, what she thinks, that it was a fib, and a secret');
check(reply('{"do": "none", "say": "I\'m not scared.", "true": "bluff"}', body).true === 'bluff', 'a bluff');
check(reply('{"do": "none", "say": "Hi."}', body).true === 'true', 'nothing said about it: true');
check(reply('{"do":"none","say":"I\'m fine.","think":"I\'m not","true":false,"keep":"" broken', body).true === 'false', 'read even from a broken reply');
const extra = '"think": "<what you really think, a few words>", "true": <false if what you said isn\'t so, "bluff" if you\'re putting on a front, else true>, "keep": "<a secret to keep, or empty>",';
check(extra.length < 200, `a small addition to the reply (${extra.length} characters of format; a few words in each reply)`);
const sk = situation({ ...body, inner: [], skills: ["you're new to chopping wood and still learning"], learned: ['chopping wood: line the axe up with the crack in the log, and don\'t rush the swing'] });
check(sk.includes("How good you are at this:\n- you're new to chopping wood") && sk.includes("What you've learned from trying before:\n- chopping wood: line the axe up"), 'their skill and lessons at what matters here go into the thought');
check(!situation({ ...body, inner: [], skills: [], learned: [] }).includes('How good you are'), 'and nothing when nothing matters here');
console.log(failed ? 'FAILED' : 'DONE');
process.exit(failed ? 1 : 0);
