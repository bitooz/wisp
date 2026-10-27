// The morning's plan and the plan in each thought, with no model call:
//   node --experimental-strip-types scripts/plan-check.mjs
import { parsePlan, planPrompt } from '../src/planner.ts';
import { reply, situation } from '../src/minds.ts';

let failed = false;
const check = (ok, what) => { console.log((ok ? 'ok:   ' : 'FAIL: ') + what); if (!ok) failed = true; };
const p = planPrompt({ who: 'mo', time: "it's early morning", goals: ["I really, really want to know what's inside the glowing door."], beliefs: ['The door only opens for two.'],
  feel: ['in a good mood', 'a bit peckish'], bonds: ['Bo: you love being around Bo'], yesterday: "did: get something to eat. didn't get to: find out what's inside the glowing door", leftover: ["find out what's inside the glowing door"] });
check(p.system.startsWith('You are Mo') && p.system.includes('"day"'), 'Mo plans her day as herself');
for (const bit of ["Now: it's early morning", 'What you want most:', '- The door only opens for two.', '- a bit peckish', '- Bo: you love being around Bo', "Yesterday: did: get something to eat", "What you didn't get to:"])
  check(p.user.includes(bit), `the plan takes in: ${bit}`);
check(!/image|audio/.test(JSON.stringify(p)) && JSON.stringify(p).length < 6000, 'one small text-only call');
const got = parsePlan('{"day": [{"text": "eat an apple", "why": "peckish"}, "go to the glowing door with Bo", {"text": ""}, {"text": "a"}, {"text": "b"}, {"text": "c"}, {"text": "d"}], "step": "walk to the big tree"}');
check(got.day.length === 5 && got.day[0].text === 'eat an apple' && got.day[1].text === 'go to the glowing door with Bo', 'up to 5 things, in order (plain strings too), empty ones dropped');
check(got.step === 'walk to the big tree', 'and the first step');
check(parsePlan('nope').day.length === 0, 'no plan in the reply: none (the game makes its own)');
const body = { who: 'mo', why: 'idle', feel: [], doing: 'waiting here', memory: [], people: ['Wisp', 'Bo'], plan: 'walk to the big tree',
  day_plan: ['(done) eat an apple', "(now) find out what's inside the glowing door", '(later) be home and in bed by dark'], replan: 'three tries at "find out what\'s inside the glowing door" and it isn\'t working' };
const s = situation(body);
check(s.includes("Your plan for today:\n- (done) eat an apple\n- (now) find out what's inside the glowing door\n- (later) be home and in bed by dark"), "the day's plan goes in every thought");
check(s.includes('Your next step: walk to the big tree'), 'with the next step');
check(s.includes('Time to rethink your plan for today: three tries') && s.includes('Reply with "day"'), 'and a rethink when one is due');
check(!situation({ ...body, replan: '' }).includes('rethink'), 'and not otherwise');
const r = reply('{"see": "x", "do": "none", "next": "ask Bo to stand on the other plate", "activity": "Done", "day": ["find the second plate", {"text": "get Bo to help"}, ""], "say": ""}', body);
check(r.next === 'ask Bo to stand on the other plate' && r.plan === r.next && r.activity === 'done', 'the reply: next step, and the activity done');
check(JSON.stringify(r.day) === JSON.stringify(['find the second plate', 'get Bo to help']), 'and a rethought day');
check(reply('{"do": "none", "plan": "old style step", "say": ""}', body).next === 'old style step', 'a reply in the old way ("plan") still works');
const withRound = planPrompt({ who: 'bo', routine: ['your chore: chop wood for the campfire, in the morning', 'your hobby: work on my model boat, in the afternoon'] });
check(withRound.user.includes('Your usual day:\n- your chore: chop wood for the campfire') && withRound.system.includes('chore and your hobby'), "Bo's usual day (chore, hobby) goes into his morning plan");
{
  const p = planPrompt({ who: 'mo', time: 'mid-morning', today: ['had breakfast at home this morning'] });
  check(p.user.includes("Done already today (don't plan it again):\n- had breakfast at home this morning"), 'what they did already today is in the plan prompt');
}
console.log(failed ? 'FAILED' : 'DONE');
process.exit(failed ? 1 : 0);
