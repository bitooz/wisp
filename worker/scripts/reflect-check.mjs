// The night's reflection request and reply, with no model call:
//   node --experimental-strip-types scripts/reflect-check.mjs
import { parseBeliefs, parseFeelings, reflectPrompt } from '../src/reflect.ts';

let failed = false;
const check = (ok, what) => { console.log((ok ? 'ok:   ' : 'FAIL: ') + what); if (!ok) failed = true; };
const day = ['[earlier today] I picked up the torch', '[earlier today] felt: the stone under your feet sank with a heavy click', '[earlier today] heard a long, deep grinding of stone, muffled, ahead of you, far off'];
const p = reflectPrompt({ who: 'mo', memories: day, beliefs: ['Bo always plays it safe.'], plan: 'find the other plate' });
check(p.system.startsWith('You are Mo'), 'it reflects as Mo, with her persona');
check(day.every((d, i) => p.user.includes(`${i + 1}. ${d}`)), "the day's memories go in, numbered");
check(p.user.includes('- Bo always plays it safe.') && p.user.includes('Your plan was: find the other plate'), 'with what she already believes, and her plan');
check(!/\bimage|audio\b/.test(JSON.stringify(p)), 'text only (no picture, no audio): a cheap call');
const big = reflectPrompt({ who: 'bo', memories: Array.from({ length: 200 }, (_, i) => `memory ${i}`) });
check(big.user.includes('60. memory 59') && !big.user.includes('61. memory 60'), 'never more than 60 memories in one reflection');
const got = parseBeliefs('Sure! {"beliefs": [{"text": "The plates only work with two of us.", "importance": 9, "from": [2, 3, 7]}, {"text": "", "importance": 5}, {"text": "Wisp is braver than I thought.", "importance": 3, "from": [1]}, {"text": "x", "from": []}, {"text": "fourth"}]}', 3);
check(got.length === 3, 'at most 3 beliefs, empty ones dropped');
check(got[0].text === 'The plates only work with two of us.' && got[0].importance === 9 && JSON.stringify(got[0].from) === '[2,3]', '"from" keeps only memories that were in the list');
check(got[1].importance === 6, 'importance is kept between 6 and 10');
check(parseBeliefs('no json here', 3).length === 0 && parseBeliefs('{"beliefs": "nope"}', 3).length === 0, 'a reply that is not beliefs gives none');
const withHeart = reflectPrompt({ who: 'bo', memories: day, mood: 'grumpy', bonds: ['Mo: you like Mo; you mostly trust Mo', 'Wisp: you\'re not sure you can trust Wisp yet'], promises: ['Wisp promised you: "I promise I\'ll find you a light"'] });
check(withHeart.user.includes('Your mood: grumpy') && withHeart.user.includes('- Wisp: you\'re not sure') && withHeart.user.includes('1. Wisp promised you'), 'the night also turns over his mood, how he feels about the others, and promises made to him');
check(withHeart.system.includes('"who": "<one of: wisp, mo, nell, tam, odo>"'), "he can say how he feels about Wisp, Mo or anyone else on the island now");
const felt = parseFeelings('{"beliefs": [], "people": [{"who": "Wisp", "trust": 3, "fond": -1, "why": "never helped"}, {"who": "grandma", "trust": 1}, {"who": "mo", "trust": "x", "fond": 0.6}], "promises": [{"n": 1, "kept": true}, {"n": 4, "kept": false}, {"n": 1, "kept": "yes"}]}', 1);
check(felt.people.length === 2 && felt.people[0].who === 'wisp' && felt.people[0].trust === 1 && felt.people[0].fond === -1, 'feelings come back a step at most, only about Wisp, Mo or Bo');
check(felt.people[1].who === 'mo' && felt.people[1].trust === 0 && felt.people[1].fond === 1, 'odd values are made sensible');
check(felt.promises.length === 2 && felt.promises[0].kept === true && felt.promises[1].kept === false, 'only promises that were in the list, and kept only if it says true');
check(parseFeelings('nothing', 2).people.length === 0, 'no reply, no changes');
console.log(failed ? 'FAILED' : 'DONE');
process.exit(failed ? 1 : 0);
