// Tries Fish voices for anyone (Mo, Bo, Nell, Tam, Odo): each says a line in character through the Worker's /speak, then Gemini listens
// and says how old the speaker sounds, which sex, and how natural. Needs OPENROUTER_API_KEY in the environment.
//   node scripts/voices.mjs mo|bo|nell|tam|odo [<fish id>...]   (no ids: the voice they have now)
import { readFileSync } from 'node:fs';
const cfg = JSON.parse(readFileSync(new URL('../../brain.json', import.meta.url)));
const [who, ...ids] = process.argv.slice(2);
const LINES = {
  mo: ["Ooh, what's that? I'm gonna touch it. Bo, come look, it's glowing!", 'a curious, bubbly 9-year-old girl'],
  bo: ["Don't touch it, Mo. It's a pressure plate. Probably opens something. Probably.", 'a dry, deadpan 11-year-old boy'],
  nell: ["Well now, you'll never guess what I heard down at the beach this morning. Lost my lucky float, too.", 'a gruff, gossipy old woman, a fisher all her life'],
  tam: ["Oh, hello, dear! Mind the bees. Have you seen my smoker anywhere? I'm in such a fluster.", 'a warm, motherly beekeeper who worries a lot'],
  odo: ["Hm. A pot. For soup, probably. Or for keeping things in. It's a pot.", 'a shy, quiet potter with a dry sense of humour'],
};
const [line, suits] = LINES[who];
if (!ids.length) ids.push('');
const wav = (pcm, rate = 24000) => {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVEfmt ', 8); h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28);
  h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
};
for (const id of ids) {
  const t0 = Date.now();
  const r = await fetch(`${cfg.url}/speak?v=${who}${id ? `&id=${id}` : ''}&t=${encodeURIComponent(line)}`, { headers: { 'x-wisp-key': cfg.key } });
  const pcm = Buffer.from(await r.arrayBuffer());
  const ms = Date.now() - t0;
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: { authorization: `Bearer ${process.env.OPENROUTER_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model: 'google/gemini-3.6-flash',
      temperature: 0,
      messages: [{ role: 'user', content: [
        { type: 'text', text: 'Listen. Reply in one line: estimated age of the speaker in years; sex; does it sound like a real child or an adult imitating one; naturalness 1-10; any glitches or noise; accent. Then: how well does it suit ' + suits + ', 1-10.' },
        { type: 'input_audio', input_audio: { data: wav(pcm).toString('base64'), format: 'wav' } },
      ] }],
    }),
  });
  const j = await res.json();
  console.log(id || '(theirs now)', `${(pcm.length / 48000).toFixed(1)}s`, `${ms}ms`, '|', (j.choices?.[0]?.message?.content ?? JSON.stringify(j).slice(0, 200)).replace(/\n/g, ' '));
}
