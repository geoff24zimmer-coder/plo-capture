// Restore the seed backup through the real file input, then screenshot the
// tracker's tabs and a session screen.
import { launch, sleep } from './cdp.mjs';
const S = new URL('.', import.meta.url).pathname;
const b = await launch({ url: 'http://127.0.0.1:8765/' });
try {
  await sleep(9000); // splash + boot
  await b.enableSemantics(); await sleep(800);
  await b.shot(S + 't0_landing.png');
  // Backup & restore lives on the home screen (it covers hands too).
  await b.tap('Backup & restore'); await sleep(800);
  await b.shot(S + 't0b_backup_sheet.png');
  // Headless can't show a native chooser — intercept it and feed the input.
  await b.send('Page.setInterceptFileChooserDialog', { enabled: true });
  const chosen = new Promise((r) => b.on('Page.fileChooserOpened', r));
  await b.tap('Restore from backup');
  const { backendNodeId } = await chosen;
  await b.send('DOM.setFileInputFiles', { backendNodeId, files: [S + 'demo-backup.json'] });
  await sleep(1500);
  await b.shot(S + 't1_restore_confirm.png');
  await b.tap('Restore', { exact: true }); await sleep(2500);
  await b.shot(S + 't1b_restored.png');
  await b.tap('Session tracker'); await sleep(2500);
  await b.shot(S + 't2_calendar.png');
  await b.tap('Previous month'); await sleep(800);
  await b.shot(S + 't3_calendar_sep.png');
  await b.tap('Stats', { exact: true }); await sleep(1200);
  await b.shot(S + 't4_stats.png');
  await b.evaluate(`window.scrollBy(0,0)`);
  // Scroll the stats list with mouse wheel.
  await b.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 250, y: 400, deltaX: 0, deltaY: 520 }); await sleep(900);
  await b.shot(S + 't5_stats_scrolled.png');
  await b.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 250, y: 400, deltaX: 0, deltaY: 700 }); await sleep(900);
  await b.shot(S + 't6_stats_more.png');
  await b.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 250, y: 400, deltaX: 0, deltaY: -3000 }); await sleep(900);
  await b.tap('Tournaments'); await sleep(900);
  await b.shot(S + 't7_mtt.png');
  await b.tap('Sessions', { exact: true }); await sleep(1200);
  await b.shot(S + 't8_sessions.png');
  await b.tap('Champions', { nth: 0 }); await sleep(1800);
  await b.shot(S + 't10_editor.png'); // a tracker row opens its editor
  await b.tap('Close'); await sleep(800);
  await b.tap('Log a past session'); await sleep(1000);
  await b.shot(S + 't11_log.png');
  console.log('LOGS', JSON.stringify(b.logs.slice(-15)));
} catch (e) {
  console.log('ERR', e.message);
  await b.shot(S + 'err.png');
  console.log('LOGS', JSON.stringify(b.logs.slice(-15)));
} finally { b.close(); }
