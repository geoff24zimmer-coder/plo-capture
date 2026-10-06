// PLO5 hand logging: pick PLO5 → claim a seat → pick five cards → table.
//   node check_plo5.mjs            — screenshots up to the open card picker
//   node check_plo5.mjs x,y x,y …   — then taps those five picker cells
import { launch, sleep } from './cdp.mjs';
const S = new URL('.', import.meta.url).pathname;
const picks = process.argv.slice(2).map((p) => p.split(',').map(Number));
const b = await launch({ url: 'http://127.0.0.1:8765/' });
try {
  await sleep(9000);
  await b.enableSemantics(); await sleep(800);
  await b.tap('Log played hands'); await sleep(1000);
  await b.tap('Cash game'); await sleep(1200);
  await b.tap('PLO5', { exact: true }); await sleep(500);
  await b.shot(S + 'p1_sheet.png');
  await b.tap('Start cash game'); await sleep(2500);
  await b.tap('Skip', { exact: true }); await sleep(800);
  await b.tap('Start hand'); await sleep(1500);
  await b.tap('This is me'); await sleep(1200);
  await b.shot(S + 'p2_picker.png');
  for (const [x, y] of picks) { await b.click(x, y); await sleep(250); }
  if (picks.length) {
    await sleep(1000);
    await b.shot(S + 'p3_table.png');
  }
  console.log('errors:', b.logs.filter((l) => /EXC|rror/.test(l)).join('\n') || 'none');
} catch (e) { console.log('ERR', e.message); await b.shot(S + 'err.png'); }
finally { b.close(); }
