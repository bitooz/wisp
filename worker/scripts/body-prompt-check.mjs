// What a thought with body feelings looks like to the model, and which replies pass, with no model call:
//   node --experimental-strip-types scripts/body-prompt-check.mjs
import { situation, reply } from '../src/minds.ts';

const feel = ['hungry: your tummy is rumbling', "cold: you're shivering", "it's night", 'holding the torch in your hand'];
for (let i = 0; i < 9; i++) feel.push(`a place ${i} is about 20 m away, ahead (you know the way: head_to)`);
const body = { who: 'mo', why: 'idle', feel, doing: 'waiting here', memory: [], plan: '', people: ['Wisp', 'Bo'] };
const text = situation(body);
let failed = false;
const check = (ok, what) => { console.log((ok ? 'ok:   ' : 'FAIL: ') + what); if (!ok) failed = true; };
check(feel.every((f) => text.includes(f)), 'every feeling line reaches the model, body first');
check(text.indexOf('hungry') < text.indexOf('a place 0'), 'the body comes before the sense of direction');
for (const v of ['eat', 'rest', 'sleep']) {
  const r = reply(`{"see":"x","do":"${v}","say":""}`, body);
  check(r.do === v && r.checked === 'ok', `"${v}" with no point is a fine reply`);
  const p = reply(`{"see":"x","do":"${v}","at":[500,600],"say":""}`, body);
  check(p.do === v && p.at.length === 2, `"${v}" pointing at a spot is a fine reply`);
}
check(reply('{"do":"go","say":""}', body).checked !== 'ok', '"go" still needs a point');
const look = reply('{"see":"x","do":"look","dir":"left","say":""}', body);
check(look.do === 'look' && look.dir === 'left' && look.checked === 'ok', '"look" left (turning the head) is a fine reply');
const heard = situation({ ...body, why: 'heard', text: 'Over here!', where: 'behind you, close by', talk: [{ who: 'Bo', said: 'Wait up.', where: 'to your left, close by' }] });
check(heard.includes('Wisp just said (behind you, close by): "Over here!"'), "where Wisp's voice came from reaches the model");
check(heard.includes('- Bo (to your left, close by): Wait up.'), "and where each line said came from");
const bonded = situation({ ...body, bonds: ['Bo: you love being around Bo; you trust Bo completely; you and Bo still laugh about the time Bo walked right into you'] });
check(bonded.includes('How you feel about the others:\n- Bo: you love being around Bo'), 'how she feels about the others reaches the model, as words');
console.log(failed ? 'FAILED' : 'DONE');
process.exit(failed ? 1 : 0);
