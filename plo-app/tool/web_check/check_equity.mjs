// Equity calculator on the real web build: pick AAKKds vs KKQQds, time the
// 100k-deal simulation in the browser, then a flop (exact) and screenshots.
import { launch, sleep } from './cdp.mjs';
const S = new URL('.', import.meta.url).pathname;
const b = await launch({ url: 'http://127.0.0.1:8765/' });
const pickFaces = async (faces) => {
  for (const f of faces) { await b.tap(f, { exact: true, nth: 0 }); }
  await sleep(700);
};
const waitFor = async (text, ms = 60000) => {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    if (await b.find(text)) return Date.now() - t0;
    await sleep(50);
  }
  return -1;
};
try {
  await sleep(9000);
  await b.enableSemantics(); await sleep(800);
  await b.shot(S + 'e0_landing.png');
  await b.tap('Equity', { exact: true }); await sleep(2000);
  await b.shot(S + 'e1_empty.png');
  await b.tap('Any'); await sleep(900);
  await b.shot(S + 'e2_picker.png');
  await pickFaces(['A♠', 'A♥', 'K♠', 'K♥']);
  await b.tap('Any'); await sleep(900);
  for (const f of ['K♦', 'K♣', 'Q♦']) await b.tap(f, { exact: true, nth: 0 });
  const t0 = Date.now();
  await b.tap('Q♣', { exact: true, nth: 0 });
  const ms = await waitFor('100,000 deals');
  console.log('MC 100k in browser (incl. 200ms picker close):', ms >= 0 ? Date.now() - t0 : 'timeout', 'ms');
  await b.shot(S + 'e3_preflop.png');
  await b.tap('Flop'); await sleep(900);
  await pickFaces(['2♣', '7♦', 'J♥']);
  await sleep(1500);
  await b.shot(S + 'e4_flop.png');
  await b.tap('PLO5', { exact: true }); await sleep(600);
  await b.tap('Add player'); await sleep(400);
  await b.tap('Add player'); await sleep(2500);
  await b.shot(S + 'e5_plo5_multi.png');
  console.log('LOGS', JSON.stringify(b.logs.slice(-10)));
} catch (e) {
  console.log('ERR', e.message); await b.shot(S + 'err.png');
  console.log('LOGS', JSON.stringify(b.logs.slice(-10)));
} finally { b.close(); }
