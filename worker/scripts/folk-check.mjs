// The island's other people and gossip in a thought, a plan and a night, with no model call:
//   node --experimental-strip-types scripts/folk-check.mjs
import { NAMES, PERSONAS, reply, situation, system } from '../src/minds.ts';
import { planPrompt } from '../src/planner.ts';
import { parseFeelings, reflectPrompt } from '../src/reflect.ts';

let failed = false;
const check = (ok, what) => { console.log((ok ? 'ok:   ' : 'FAIL: ') + what); if (!ok) failed = true; };
for (const w of ['nell', 'tam', 'odo']) check(system(w).startsWith(`You are ${NAMES[w]}`) && system(w).includes('What you want most just now') || system(w).includes("What you'd love just now"), `${NAMES[w]} is someone of their own, with something they want`);
check(system('nell').includes('Odo the potter') && system('mo').includes('News gets round'), 'everyone knows who lives on the island, and that news gets round');
const body = { who: 'tam', why: 'chat', from: 'nell', text: 'Did you hear about Bo?', feel: [], doing: 'tending the bees', memory: [], people: ['Wisp', 'Mo', 'Bo', 'Nell', 'Odo'],
  news: ['Bo told Mo "I don\'t have the apple", and it was a big fat fib (Nell told you (she had it from Mo))', "Tam has lost her bee smoker (it's what you want)"] };
const s = situation(body);
check(s.includes('Nell just said to you: "Did you hear about Bo?"'), 'Nell talking to Tam is Nell, by name');
check(s.includes('News you could pass on ("tell": its number):\n1. Bo told Mo') && s.includes('\n2. Tam has lost her bee smoker'), 'what they could pass on, numbered, with where they had it');
check(s.includes('People you can name for give: Wisp, Mo, Bo, Nell, Odo'), 'and everyone on the island can be named');
check(!situation({ ...body, news: [] }).includes('News you could pass on'), 'and no news section when there is none');
const r = reply('{"see": "x", "do": "none", "say": "Nell says Bo fibbed to Mo!", "to": "odo", "tell": 1}', body);
check(r.tell === 1 && r.to === 'odo', 'the reply says which news was passed on, and to whom');
check(reply('{"do": "none", "say": "hi", "tell": "nonsense"}', body).tell === 0 && reply('{"do": "none", "say": "hi", "tell": 99}', body).tell === 8, 'a bad number is none, a big one is cut down');
const fmt = system('mo').slice(system('mo').indexOf('Reply with one JSON object'));
check(fmt.includes('"tell": <the number of the news') && fmt.length < 2000, 'a small addition to the reply format');
const p = planPrompt({ who: 'mo', helping: ["find Nell's lucky float on the north-east shore and give it to her"] });
check(p.user.includes("Others want (you've heard), and you could help:\n- find Nell's lucky float"), "someone's want can go into the morning's plan");
const night = reflectPrompt({ who: 'nell', memories: ['Mo found my lucky float and gave it back to me'], bonds: ['Mo: you love being around Mo'] });
check(night.system.includes('wisp, mo, bo, tam, odo') && !night.system.includes('nell,'), "Nell's night: she can feel differently about anyone but herself");
const felt = parseFeelings('{"people": [{"who": "mo", "trust": 1, "fond": 1, "why": "found my float"}, {"who": "zed", "trust": 1}, {"who": "odo", "fond": -1}]}', 0);
check(felt.people.length === 2 && felt.people[0].who === 'mo' && felt.people[1].who === 'odo', 'feelings about anyone on the island are kept; nobody made up');
check(Object.keys(PERSONAS).length === 5, 'five minds in all');
console.log(failed ? 'FAILED' : 'DONE');
process.exit(failed ? 1 : 0);
