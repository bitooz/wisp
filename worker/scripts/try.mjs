// Sends one /think to the deployed Worker and prints each event as it arrives (audio summarised).
//   node scripts/try.mjs <body.json> [--wav=path] [--model=…] [--pcm=out.raw]
import { readFileSync, writeFileSync } from 'node:fs';
const cfg = JSON.parse(readFileSync(new URL('../../brain.json', import.meta.url)));
const args = process.argv.slice(2);
const body = JSON.parse(readFileSync(args[0], 'utf8'));
for (const a of args.slice(1)) {
  if (a.startsWith('--wav=')) body.audio = readFileSync(a.slice(6)).toString('base64');
  if (a.startsWith('--model=')) body.model = a.slice(8);
  if (a.startsWith('--provider=')) body.provider = a.slice(11);
}
const out = args.find((a) => a.startsWith('--pcm='))?.slice(6);
const t0 = Date.now();
const res = await fetch(cfg.url + '/think', { method: 'POST', headers: { 'content-type': 'application/json', 'x-wisp-key': cfg.key }, body: JSON.stringify(body) });
const pcm = [];
let buf = '';
const dec = new TextDecoder();
for await (const chunk of res.body) {
  buf += dec.decode(chunk, { stream: true });
  let nl;
  while ((nl = buf.indexOf('\n')) >= 0) {
    const m = JSON.parse(buf.slice(0, nl));
    buf = buf.slice(nl + 1);
    if (m.type === 'audio') {
      const b = Buffer.from(m.pcm, 'base64');
      if (!pcm.length) console.log(`${Date.now() - t0} ms  first audio (${b.length} bytes)`);
      pcm.push(b);
    } else console.log(`${Date.now() - t0} ms `, JSON.stringify(m));
  }
}
if (out && pcm.length) writeFileSync(out, Buffer.concat(pcm));
