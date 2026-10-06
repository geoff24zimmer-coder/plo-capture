// Craig's case: start a cash game, end it immediately with +$492.
import { launch, sleep } from './cdp.mjs';
const S = new URL('.', import.meta.url).pathname;
const b = await launch({ url: 'http://127.0.0.1:8765/' });
try {
  await sleep(9000);
  await b.enableSemantics(); await sleep(800);
  await b.tap('Log played hands'); await sleep(1000);
  await b.tap('Cash game'); await sleep(1200);
  await b.click(250, 576); await b.send('Input.insertText', { text: '1000' }); await sleep(300);
  await b.tap('Start cash game'); await sleep(2500);
  await b.tap('Skip', { exact: true }); await sleep(800);
  await b.click(28, 27); await sleep(1500);           // back from capture
  await b.tap('RESUME SESSION'); await sleep(1800);
  await b.tap('End', { exact: true }); await sleep(1000);
  await b.send('Input.insertText', { text: '1492' }); await sleep(400);
  await b.shot(S + 'q1_end_dialog.png');
  await b.tap('End session', { exact: true, nth: 0 }); await sleep(1500);
  await b.tap('Session tracker'); await sleep(2000);
  await b.tap('Stats', { exact: true }); await sleep(1500);
  await b.shot(S + 'q2_stats.png');
} catch (e) { console.log('ERR', e.message); await b.shot(S + 'err.png'); }
finally { b.close(); }
