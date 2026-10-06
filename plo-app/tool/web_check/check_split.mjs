// Tracker / hand-log separation, including the real upgrade path.
//   node check_split.mjs seed <profile>    — OLD build on :8765: restore the
//                                            demo backup (combined format)
//   node check_split.mjs verify <profile>  — NEW build on :8765, same profile:
//                                            the data split; live tracker flow
import { launch, sleep } from './cdp.mjs';
const S = new URL('.', import.meta.url).pathname;
const [phase, profile] = process.argv.slice(2);
const b = await launch({ url: 'http://127.0.0.1:8765/', profile });
const wheel = (dy) => b.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 250, y: 400, deltaX: 0, deltaY: dy });
try {
  await sleep(9000);
  await b.enableSemantics(); await sleep(800);
  if (phase === 'seed') {
    await b.tap('Session tracker'); await sleep(2500);
    await b.tap('Backup & export'); await sleep(600);
    await b.send('Page.setInterceptFileChooserDialog', { enabled: true });
    const chosen = new Promise((r) => b.on('Page.fileChooserOpened', r));
    await b.tap('Restore from backup');
    const { backendNodeId } = await chosen;
    await b.send('DOM.setFileInputFiles', { backendNodeId, files: [S + 'demo-backup.json'] });
    await sleep(1500);
    await b.tap('Restore', { exact: true }); await sleep(3000);
    await b.tap('Sessions', { exact: true }); await sleep(1500);
    await b.shot(S + 'x0_old_sessions.png');
  } else {
    await b.shot(S + 'x1_home.png');
    // Hand side: Past sessions lists only the session that had hands.
    await b.tap('Log played hands'); await sleep(1000);
    await b.shot(S + 'x2_sheet.png');
    await b.tap('Past sessions'); await sleep(2500);
    await b.shot(S + 'x3_past.png');
    await b.tap('5 hands'); await sleep(2500);
    await b.shot(S + 'x4_hand_list.png');
    await b.click(28, 27); await sleep(1200);
    await b.click(28, 27); await sleep(1500);
    // Tracker side: every result, no hands.
    await b.tap('Session tracker'); await sleep(2500);
    await b.tap('Sessions', { exact: true }); await sleep(1500);
    await b.shot(S + 'x5_tracker_sessions.png');
    await b.tap('Stats', { exact: true }); await sleep(1200);
    for (let i = 0; i < 6; i++) { await wheel(700); await sleep(300); }
    await sleep(600);
    await b.shot(S + 'x6_stats_bottom.png');
    const allInCard = await b.find('ALL-IN LUCK');
    console.log('ALL-IN LUCK card present:', !!allInCard);
    // Live tracker session: start → add on → end with cash-out.
    await b.tap('Start session'); await sleep(1200);
    await b.shot(S + 'x7_start_form.png');
    await b.click(250, 178); // venue field (coords at 500x717)
    await b.send('Input.insertText', { text: 'Lodge' }); await sleep(300);
    await b.click(250, 400); // buy-in field
    await b.send('Input.insertText', { text: '1000' }); await sleep(300);
    await b.tap('Start', { exact: true }); await sleep(1500);
    await b.shot(S + 'x8_live_bar.png');
    await b.tap('Add on', { exact: true }); await sleep(800);
    await b.send('Input.insertText', { text: '500' }); await sleep(300);
    await b.tap('Add', { exact: true }); await sleep(1200);
    await b.tap('End', { exact: true }); await sleep(1000);
    await b.send('Input.insertText', { text: '2100' }); await sleep(300);
    await b.shot(S + 'x9_end_dialog.png');
    await b.tap('End session', { exact: true, nth: 0 }); await sleep(1500);
    await b.shot(S + 'x10_ended.png');
    // Hand side setup sheet: no buy-in, no game picker.
    await b.click(28, 27); await sleep(1500);
    await b.tap('Log played hands'); await sleep(1000);
    await b.tap('Cash game'); await sleep(1200);
    await b.shot(S + 'x11_hand_setup.png');
  }
  console.log('errors:', b.logs.filter((l) => /EXC|rror/.test(l)).join('\n') || 'none');
} catch (e) { console.log('ERR', e.message); await b.shot(S + 'err.png'); }
finally { await b.quit(); }
