// Per-seat stack editing: long-press a seat → set stack; an edit that would
// change what already happened is refused.
import { launch, sleep } from './cdp.mjs';
const S = new URL('.', import.meta.url).pathname;
const b = await launch({ url: 'http://127.0.0.1:8765/' });
const seat = async (label) => {
  const p = await b.find(label, { exact: false });
  if (!p) throw new Error('seat not found: ' + label);
  return p;
};
try {
  await sleep(9000);
  await b.enableSemantics(); await sleep(800);
  await b.tap('Log played hands'); await sleep(1000);
  await b.tap('Cash game'); await sleep(1200);
  await b.click(250, 576); await b.send('Input.insertText', { text: '1000' }); await sleep(300);
  await b.tap('Start cash game'); await sleep(2500);
  await b.tap('Skip', { exact: true }); await sleep(800);
  await b.tap('Start hand'); await sleep(1500);
  await b.shot(S + 's1_table.png');

  // 1) Before any action: set the BTN to $1,234.
  let p = await seat('BTN');
  console.log('BTN at', JSON.stringify(p));
  await b.longPress(p.x, p.y); await sleep(800);
  await b.shot(S + 's2_dialog.png');
  await b.clearField(); await b.send('Input.insertText', { text: '1234' }); await sleep(300);
  await b.tap('Set stack', { exact: true }); await sleep(800);
  await b.shot(S + 's3_btn_edited.png');

  // 2) UTG raises pot; then try to make UTG shorter than that raise → refused.
  const UTG = { x: 115, y: 172 }; // seat coords at 500x717 (find('UTG') hits UTG1)
  await b.click(230, 640); await sleep(800); // the POT raise button
  await b.shot(S + 's3b_utg_raised.png');
  p = UTG;
  await b.longPress(p.x, p.y); await sleep(800);
  await b.clearField(); await b.send('Input.insertText', { text: '10' }); await sleep(300);
  await b.tap('Set stack', { exact: true }); await sleep(600);
  await b.shot(S + 's4_refused.png');

  // 3) Undo the raise; now the same edit is allowed and caps UTG's options.
  await sleep(2500); // let the snackbar clear
  await b.click(440, 27); await sleep(800); // undo
  p = UTG;
  await b.longPress(p.x, p.y); await sleep(800);
  await b.clearField(); await b.send('Input.insertText', { text: '10' }); await sleep(300);
  await b.tap('Set stack', { exact: true }); await sleep(800);
  await b.shot(S + 's5_utg_short.png');
  console.log('logs:', b.logs.filter((l) => /EXC|rror/.test(l)).join('\n') || 'none');
} catch (e) { console.log('ERR', e.message); await b.shot(S + 'err.png'); }
finally { b.close(); }
