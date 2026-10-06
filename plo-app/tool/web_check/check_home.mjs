// New home screen: three equal feature buttons → sub-menu → setup sheet.
import { launch, sleep } from './cdp.mjs';
const S = new URL('.', import.meta.url).pathname;
const b = await launch({ url: 'http://127.0.0.1:8765/' });
try {
  await sleep(9000);
  await b.enableSemantics(); await sleep(800);
  await b.shot(S + 'h1_home.png');
  await b.tap('Log played hands'); await sleep(1200);
  await b.shot(S + 'h2_submenu.png');
  await b.tap('Cash game'); await sleep(1500);
  await b.shot(S + 'h3_setup.png');
} catch (e) {
  console.log('ERR', e.message); await b.shot(S + 'err.png');
} finally { b.close(); }
