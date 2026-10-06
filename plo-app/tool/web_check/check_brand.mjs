// Rebrand check: the splash (held by blocking Flutter's bootstrap) at the
// wordmark moment and its end, then the real home screen + page metadata.
import { launch, sleep } from './cdp.mjs';
const S = new URL('.', import.meta.url).pathname;

// 1) Splash only: block Flutter so the video stays up.
let b = await launch({ url: 'about:blank' });
try {
  await b.send('Network.enable');
  await b.send('Network.setBlockedURLs', { urls: ['*flutter_bootstrap.js*'] });
  await b.send('Page.navigate', { url: 'http://127.0.0.1:8765/' });
  const t0 = Date.now();
  const at = async (ms, name) => { await sleep(Math.max(0, ms - (Date.now() - t0))); await b.shot(S + name); };
  await at(3700, 'b1_splash_wordmark.png');
  await at(7600, 'b2_splash_end.png');
  const v = await b.evaluate(`(() => { const v = document.querySelector('video'); return v ? {t: v.currentTime, src: v.currentSrc, ended: v.ended} : null; })()`);
  console.log('video', JSON.stringify(v));
} finally { b.close(); }

// 2) Real boot → home screen + metadata.
b = await launch({ url: 'http://127.0.0.1:8765/' });
try {
  await sleep(9000);
  await b.shot(S + 'b3_home.png');
  const meta = await b.evaluate(`(async () => ({
    title: document.title,
    apple: document.querySelector('meta[name=apple-mobile-web-app-title]')?.content,
    manifest: await (await fetch('manifest.json')).json().then(m => [m.name, m.short_name]),
  }))()`);
  console.log('meta', JSON.stringify(meta));
} finally { b.close(); }
