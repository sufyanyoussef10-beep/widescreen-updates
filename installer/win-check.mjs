// The installed Widescreen, looked at while it runs (it was started with --devtools-port=9470 by check.ps1):
// does it come up on a clean Windows machine, find its ffmpeg, and play a video with a real picture?
//   node win-check.mjs <folder it is installed in> <version> <folder for the pictures>
// Prints PASS / FAIL lines and "passed n of m". The app is left running.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const [, , dir, version, out] = process.argv;
const PORT = 9470;
const wait = ms => new Promise(r => setTimeout(r, ms));
let ws = null, id = 0, good = 0, all = 0; const pending = new Map();
const note = (name, ok, detail) => { all++; if (ok) good++; console.log((ok ? 'PASS ' : 'FAIL ') + name + (ok ? '' : '  ' + JSON.stringify(detail))); };
async function connect(ms) {
  const t0 = Date.now();
  for (;;) {
    try {
      const ts = (await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()).filter(t => t.type === 'page');
      const t = ts.find(x => x.url.includes('index.html'));
      if (t) {
        ws = new WebSocket(t.webSocketDebuggerUrl);
        await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
        ws.onmessage = e => { const d = JSON.parse(e.data); if (d.id && pending.has(d.id)) { const p = pending.get(d.id); pending.delete(d.id); d.error ? p.rej(new Error(d.error.message)) : p.res(d.result); } };
        return true;
      }
    } catch (e) { }
    if (Date.now() - t0 > ms) return false;
    await wait(300);
  }
}
const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async expression => { const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception && r.exceptionDetails.exception.description || r.exceptionDetails.text); return r.result.value; };
const page = body => ev(`(async () => { const S = WS.state, E = WS.engine, wait = ms => new Promise(r => setTimeout(r, ms)); const until = async (f, ms) => { const t = Date.now(); while (Date.now() - t < ms) { try { if (f()) return true; } catch (e) { } await wait(100); } try { return !!f(); } catch (e) { return false; } }; ${body} })()`);
const safe = async (name, fn) => { try { await fn(); } catch (e) { note(name, false, 'the check itself broke: ' + String(e.message || e).slice(0, 300)); } };

const t0 = Date.now();
let up = await connect(90000);
if (up) { up = false; for (let i = 0; i < 600; i++) { try { if (await ev(`!!(window.WS && WS.state && WS.state.project)`)) { up = true; break; } } catch (e) { } await wait(100); } }
note('installed, Widescreen starts and its window comes up', up, { seconds: +((Date.now() - t0) / 1000).toFixed(1) });
if (up) {
  await wait(2000);
  await safe('what the app says about itself', async () => {
    const info = await page(`return { version: S.version.replace(/\\+.*$/, ''), ffmpeg: S.ffmpeg, displays: S.displays.map(d => 'Display ' + d.number + ' ' + d.w + 'x' + d.h), agent: navigator.userAgent, window: [innerWidth, innerHeight, devicePixelRatio],
      graphics: (() => { try { const c = document.createElement('canvas').getContext('webgl'); const e = c.getExtension('WEBGL_debug_renderer_info'); return e ? c.getParameter(e.UNMASKED_RENDERER_WEBGL) : '?'; } catch (x) { return '?'; } })() };`);
    console.log('  the app: ' + JSON.stringify(info));
    note('it is version ' + version + ' and finds its ffmpeg', info.version === version && info.ffmpeg === true, info);
  });
  await safe('a video', async () => {
    const media = path.join(out, 'media'); fs.mkdirSync(media, { recursive: true });
    const clip = path.join(media, 't_clip.mp4');
    execFileSync(path.join(dir, 'tools', 'ffmpeg.exe'), ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=30:duration=8', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=8', '-c:v', 'libx264', '-preset', 'veryfast', '-g', '30', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', clip]);
    const r = await page(`S.project.master.volume = 0; S.settings.optimize = false; S.settings.scrubCopies = false;
      E.addFiles(0, 0, [{ path: ${JSON.stringify(clip)} }], false);
      await until(() => { const c = S.project.layers[0].clips[0]; return c && (c.status === 'ok' || c.status === 'error' || c.status === 'missing'); }, 60000);
      const c = S.project.layers[0].clips[0]; if (!c || c.status !== 'ok') return { status: c ? c.status : 'none', error: c ? c.error : '' };
      E.trigger(0, 0); await wait(3000);
      const L = S.project.layers[0], d = S.preview && S.preview.layers.get(L.id), el = d && d.cur && d.cur.el;
      const t1 = el && el.currentTime; await wait(1500); const t2 = el && el.currentTime;
      const g = document.createElement('canvas'); g.width = 64; g.height = 36; const x = g.getContext('2d', { willReadFrequently: true });
      if (S.preview) S.preview.snapshot(x, 64, 36); const px = x.getImageData(0, 0, 64, 36).data; let lit = 0; for (let i = 0; i < px.length; i += 4) if (px[i] + px[i + 1] + px[i + 2] > 60) lit++;
      const q = el && el.getVideoPlaybackQuality ? el.getVideoPlaybackQuality() : null;
      return { status: c.status, w: c.w, h: c.h, dur: c.dur, t1, t2, lit, frames: q ? q.totalVideoFrames : null, dropped: q ? q.droppedVideoFrames : null };`);
    note('a video made with its ffmpeg is added and plays, with a real picture that moves', r.status === 'ok' && r.lit > 1500 && r.t2 !== r.t1, r);
  });
  await safe('a picture of the window', async () => {
    const r = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(path.join(out, 'app-window.png'), Buffer.from(r.data, 'base64'));
  });
  await safe('updates', async () => {
    const u = await page(`const u = await Promise.race([E.checkUpdate(), wait(20000).then(() => ({ state: 'no answer' }))]); return { state: u.state, version: u.version || '', error: u.error || '' };`);
    console.log('  updates: ' + JSON.stringify(u));
    note('it can ask the download page for updates', u.state === 'none' || u.state === 'available', u);
  });
}
console.log('passed ' + good + ' of ' + all);
try { ws && ws.close(); } catch (e) { }
process.exit(good === all ? 0 : 1);
