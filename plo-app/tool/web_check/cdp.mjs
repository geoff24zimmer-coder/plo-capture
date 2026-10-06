// Minimal CDP driver for the Flutter web PWA (headless Chrome, 500x717 @1x).
import { spawn } from 'node:child_process';
import { writeFileSync, readFileSync, mkdtempSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function launch({ url, profile }) {
  // Port 0: Chrome picks a free port and writes it to DevToolsActivePort in
  // OUR profile dir — so we can only ever attach to the browser we spawned
  // (never another session's Chrome on a fixed port).
  // `profile`: reuse a browser profile (keeps IndexedDB across runs, e.g. to
  // test a database upgrade from an older build). Default: a fresh one.
  const dir = profile ?? mkdtempSync(join(tmpdir(), 'cdp-'));
  try { unlinkSync(join(dir, 'DevToolsActivePort')); } catch {}
  const chrome = spawn('google-chrome-stable', [
    '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${dir}`,
    '--window-size=500,717', '--autoplay-policy=no-user-gesture-required',
    '--no-first-run', '--no-default-browser-check', 'about:blank',
  ], { stdio: 'ignore' });
  let port;
  for (let i = 0; i < 100 && !port; i++) {
    try { port = Number(readFileSync(join(dir, 'DevToolsActivePort'), 'utf8').split('\n')[0]); }
    catch { await sleep(100); }
  }
  if (!port) { chrome.kill('SIGKILL'); throw new Error('chrome did not start'); }
  let targets;
  for (let i = 0; i < 50; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); break; }
    catch { await sleep(200); }
  }
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  let id = 0; const pending = new Map(); const logs = []; const handlers = {};
  ws.addEventListener('message', (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
    if (m.method && handlers[m.method]) handlers[m.method](m.params);
    if (m.method === 'Runtime.consoleAPICalled') logs.push(m.params.args.map((a) => a.value).join(' '));
    if (m.method === 'Runtime.exceptionThrown') logs.push('EXC ' + JSON.stringify(m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text));
  });
  const send = (method, params = {}) => new Promise((res, rej) => {
    const i = ++id; pending.set(i, (m) => (m.error ? rej(new Error(method + ': ' + m.error.message)) : res(m.result)));
    ws.send(JSON.stringify({ id: i, method, params }));
  });
  await send('Runtime.enable'); await send('Page.enable'); await send('DOM.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 500, height: 717, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url });

  const evaluate = async (expr) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result.value;
  const click = async (x, y) => {
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
      await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1, pointerType: 'mouse' });
    }
    await sleep(350);
  };
  // Press-and-hold, for Flutter long-press gestures (default 500ms timeout).
  const longPress = async (x, y, ms = 900) => {
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, pointerType: 'mouse' });
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1, pointerType: 'mouse' });
    await sleep(ms);
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1, pointerType: 'mouse' });
    await sleep(350);
  };
  // Clear the focused text field (Backspace × n).
  const clearField = async (n = 12) => {
    for (let i = 0; i < n; i++) {
      for (const type of ['keyDown', 'keyUp']) {
        await send('Input.dispatchKeyEvent', { type, key: 'Backspace', code: 'Backspace', windowsVirtualKeyCode: 8 });
      }
    }
  };
  const shot = async (path) => {
    const { data } = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(path, Buffer.from(data, 'base64'));
  };
  // Flutter's semantics tree gives every widget a DOM node with its label.
  const enableSemantics = () => evaluate(`(() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); return !!p; })()`);
  // Center of the first semantics node whose label/text contains `text` (exact if exact).
  const find = (text, { exact = false, nth = 0 } = {}) => evaluate(`(() => {
      const want = ${JSON.stringify(text)};
      const nodes = [...document.querySelectorAll('flt-semantics, [role]')].filter(n => {
        const l = (n.getAttribute('aria-label') || n.textContent || '').trim();
        const r = n.getBoundingClientRect();
        return r.width > 0 && r.height > 0 && (${exact} ? l === want : l.includes(want));
      });
      // Prefer the smallest matching box (most specific node).
      nodes.sort((a, b) => { const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect(); return ra.width*ra.height - rb.width*rb.height; });
      const n = nodes[${nth}]; if (!n) return null;
      const r = n.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height };
    })()`);
  const tap = async (text, opts = {}) => {
    for (let i = 0; i < 20; i++) {
      const p = await find(text, opts);
      if (p) { await click(p.x, p.y); return p; }
      await sleep(300);
    }
    throw new Error('not found: ' + text);
  };
  const close = () => { try { ws.close(); } catch {} chrome.kill('SIGKILL'); };
  // Let Chrome flush storage (IndexedDB) before exiting — for profile reuse.
  const quit = async () => {
    try { await Promise.race([send('Browser.close'), sleep(3000)]); } catch {}
    await sleep(1500); close();
  };
  const on = (method, cb) => { handlers[method] = cb; };
  return { on, send, evaluate, click, longPress, clearField, shot, enableSemantics, find, tap, sleep, logs, close, quit };
}
