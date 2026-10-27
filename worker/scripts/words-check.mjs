// What comes back from the model, tidied before anyone hears it (lines from round 18's runs), with no model call:
//   node --experimental-strip-types scripts/words-check.mjs
import { reply, spoken, tidy } from '../src/minds.ts';

let failed = false;
const check = (ok, what) => { console.log((ok ? 'ok:   ' : 'FAIL: ') + what); if (!ok) failed = true; };
const bo = spoken('"Found what? Just some weird rocks." *I glance at Wisp.* "He\'s been quiet."');
check(bo === "Found what? Just some weird rocks. He's been quiet.", `stage directions and quotes come out of what's said: "${bo}"`);
check(spoken('*crunch* Mmm! Breakfast!') === 'Mmm! Breakfast!', 'a sound effect in stars is not a word said');
check(spoken('*sighs*') === '', 'only an action: nothing said');
check(spoken("'Scared? No.") === 'Scared? No.' && spoken("'s fine.") === "'s fine.", 'a stray quote mark goes, a dropped letter stays');
check(spoken("I'm not \"scared\", Mo.") === "I'm not \"scared\", Mo.", 'quotes inside a line are left alone');
check(tidy(', "true": true, "keep": "", "tell": 0, "next": "') === '', 'bits of the reply\'s own JSON in a field: dropped');
check(tidy('Stuck against this wall again.", "true": true') === 'Stuck against this wall again.', 'and cut off where they start');
check(tidy('...') === '' && tidy(', look left for the house and trestle.') === 'look left for the house and trestle.', 'dots alone are nothing; a leading comma goes');
check(tidy('(Up the stairs!)') === 'Up the stairs!' && tidy('[walk to big tree]') === 'walk to big tree' && tidy('<Got another one!>') === 'Got another one!', 'no brackets round a whole thought or step');
check(tidy('["get something to eat", "Gather windfall apples"]') === 'get something to eat', 'a list where one step was wanted: the first');
check(tidy('your next step, a few words') === '' && tidy("*I'll touch the glowing ring.*") === "I'll touch the glowing ring.", 'the format\'s own placeholder is nothing; stars round a whole step go');
const r = reply('{"do": "none", "say": "*yawns* So sleepy.", "think": "*My stomach growls again.*", "next": "..."}', { who: 'bo' });
check(r.say === 'So sleepy.' && r.think === 'My stomach growls again.' && r.next === '', `and the whole reply comes out tidy: "${r.say}", "${r.think}", "${r.next}"`);
console.log(failed ? 'FAILED' : 'DONE');
process.exit(failed ? 1 : 0);
