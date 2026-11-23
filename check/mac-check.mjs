// Does Widescreen really run on a Mac? This starts the app on the Mac it is run on (one of GitHub's, for the build
// recipe in .github/workflows/mac.yml) and looks, through the app's own debugging port, whether it comes up, finds
// its ffmpeg, plays a video with a real picture, makes its copies, and opens outputs in a window and fullscreen.
//
//   node check/mac-check.mjs <path to Widescreen.app> <folder for the report and the pictures> [--quick]
//
// Prints PASS / FAIL lines, writes report.json, pictures of the window and of the whole screen, and the app's log.
// Exit code 1 when one of the checks marked "must" failed.
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [, , appArg, outArg, ...flags] = process.argv;
const quick = flags.includes('--quick');
const app = path.resolve(appArg), out = path.resolve(outArg || 'check-out');
// (WS_EXE, WS_EXE_ARGS (a JSON list) and WS_FFMPEG let the script itself be tried on another system: there the
// questions to macOS simply get no answer)
const exe = process.env.WS_EXE || path.join(app, 'Contents', 'MacOS', 'Electron');
const exeArgs = process.env.WS_EXE_ARGS ? JSON.parse(process.env.WS_EXE_ARGS) : [];
const ffmpeg = process.env.WS_FFMPEG || path.join(app, 'Contents', 'Resources', 'ffmpeg', 'ffmpeg');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ws-check-'));
const data = path.join(tmp, 'data'), media = path.join(tmp, 'media');
const PORT = 9470;
fs.mkdirSync(out, { recursive: true }); fs.mkdirSync(media, { recursive: true });
const wait = ms => new Promise(r => setTimeout(r, ms));
const sh = (cmd, args, opt) => { try { return execFileSync(cmd, args, Object.assign({ encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 180000 }, opt || {})).trim(); } catch (e) { return 'ERROR ' + String(e.stderr || e.message || e).trim().split('\n').slice(-3).join(' | '); } };
const report = { app, quick, when: new Date().toISOString(), checks: [], facts: {} };
let failedMust = 0;
function note(name, ok, detail, must) {
  report.checks.push({ name, ok: !!ok, must: !!must, detail: detail === undefined ? null : detail });
  if (!ok && must) failedMust++;
  console.log((ok ? 'PASS ' : (must ? 'FAIL ' : 'NOTE ')) + name + (ok && detail === undefined ? '' : '  ' + JSON.stringify(detail)));
}
const fact = (k, v) => { report.facts[k] = v; console.log('  ' + k + ': ' + (typeof v === 'string' ? v : JSON.stringify(v))); };
const screen = name => { sh('screencapture', ['-x', path.join(out, name)]); };

// ---- the Mac this runs on
fact('macOS', sh('sw_vers', ['-productVersion']));
fact('chip', sh('uname', ['-m']));
fact('displays', sh('system_profiler', ['SPDisplaysDataType']).split('\n').filter(l => /Resolution|Chipset|Display Type|Main Display/.test(l)).map(l => l.trim()).join(' ; '));
fact('programs in the app are for', sh('lipo', ['-archs', exe]));
fact('ffmpeg in the app is for', sh('lipo', ['-archs', ffmpeg]));
fact('signature of the app', sh('codesign', ['-dv', app]).split('\n').filter(l => /Signature|Identifier=|TeamIdentifier|flags/.test(l)).join(' ; ') || sh('codesign', ['-dv', app]).slice(0, 200));

// ---- the ffmpeg inside the app
const ffv = sh(ffmpeg, ['-hide_banner', '-version']).split('\n')[0];
note('the ffmpeg inside the app runs on this Mac', /^ffmpeg version/.test(ffv), ffv, true);
const enc = sh(ffmpeg, ['-hide_banner', '-encoders']);
fact('encoders', { libx264: /libx264/.test(enc), h264_videotoolbox: /h264_videotoolbox/.test(enc), libvpx_vp9: /libvpx-vp9/.test(enc) });
// test media, made with that ffmpeg: a video with few full pictures (as downloads have), one that has to be converted, a picture
const ff = args => sh(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-y'].concat(args));
const m = n => path.join(media, n);
ff(['-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=30:duration=20', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=20', '-c:v', 'libx264', '-preset', 'veryfast', '-g', '250', '-keyint_min', '250', '-sc_threshold', '0', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', m('t_long.mp4')]);
ff(['-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25:duration=3', '-f', 'lavfi', '-i', 'sine=frequency=330:duration=3', '-c:v', 'mjpeg', '-q:v', '4', '-c:a', 'pcm_s16le', m('t_conv.avi')]);
ff(['-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=30:duration=1', '-frames:v', '1', m('t_pic.png')]);
if (!quick) ff(['-f', 'lavfi', '-i', 'testsrc2=size=3840x2160:rate=30:duration=5', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', m('t_4k.mp4')]);
note('test media were made with it', fs.existsSync(m('t_long.mp4')) && fs.existsSync(m('t_conv.avi')) && fs.existsSync(m('t_pic.png')), fs.readdirSync(media), true);

// ---- the app
let child = null, ws = null, id = 0; const pending = new Map();
function start(extra) {
  const log = fs.openSync(path.join(out, 'app-output.txt'), 'a');
  child = spawn(exe, exeArgs.concat([`--devtools-port=${PORT}`, `--data-dir=${data}`], extra || []), { stdio: ['ignore', log, log] });
  child.gone = new Promise(r => child.on('exit', code => r(code)));
}
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
        ws.onclose = () => { for (const p of pending.values()) p.rej(new Error('closed')); pending.clear(); };
        return true;
      }
    } catch (e) { }
    if (Date.now() - t0 > ms) return false;
    await wait(250);
  }
}
const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async expression => { const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception && r.exceptionDetails.exception.description || r.exceptionDetails.text); return r.result.value; };
const page = body => ev(`(async () => { const S = WS.state, E = WS.engine, wait = ms => new Promise(r => setTimeout(r, ms)); const until = async (f, ms) => { const t = Date.now(); while (Date.now() - t < ms) { try { if (f()) return true; } catch (e) { } await wait(100); } try { return !!f(); } catch (e) { return false; } }; ${body} })()`);
const shot = async name => { try { const r = await send('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(path.join(out, name), Buffer.from(r.data, 'base64')); } catch (e) { } };
async function ready(ms) {
  if (!(await connect(ms))) return false;
  for (let i = 0; i < ms / 100; i++) { try { if (await ev(`!!(window.WS && WS.state && WS.state.project)`)) return true; } catch (e) { } await wait(100); }
  return false;
}
const safe = async (name, fn, must) => { try { await fn(); } catch (e) { note(name, false, 'the check itself broke: ' + String(e.message || e).slice(0, 300), must); } };

const t0 = Date.now();
start();
const up = await ready(90000);
note('the app starts and its window comes up', up, { seconds: +((Date.now() - t0) / 1000).toFixed(1) }, true);
if (up) {
  await wait(2500);
  await safe('what the app says about itself', async () => {
    const info = await page(`return { version: S.version, ffmpeg: S.ffmpeg, powerpoint: S.powerpoint, displays: S.displays, storage: S.storage, agent: navigator.userAgent, platform: navigator.platform,
      graphics: (() => { try { const c = document.createElement('canvas').getContext('webgl'); const e = c.getExtension('WEBGL_debug_renderer_info'); return e ? c.getParameter(e.UNMASKED_RENDERER_WEBGL) : '?'; } catch (x) { return '?'; } })(),
      s3tc: (() => { try { return !!document.createElement('canvas').getContext('webgl').getExtension('WEBGL_compressed_texture_s3tc'); } catch (x) { return false; } })(),
      window: [innerWidth, innerHeight, devicePixelRatio] };`);
    fact('the app', info);
    note('it finds its ffmpeg', info.ffmpeg === true, info.ffmpeg, true);
    note('it lists the display of this Mac', Array.isArray(info.displays) && info.displays.length >= 1 && info.displays[0].w > 0, info.displays, true);
  }, true);
  await shot('window-1-start.png'); screen('screen-1-start.png');

  await safe('adding media', async () => {
    const files = ['t_long.mp4', 't_pic.png', 't_conv.avi'].concat(quick ? [] : ['t_4k.mp4']).map(n => ({ path: m(n) }));
    const r = await page(`S.project.master.volume = 0; S.settings.optimize = false; S.settings.scrubCopies = false;
      E.addFiles(0, 0, ${JSON.stringify(files)}, false);
      await until(() => S.project.layers[0].clips.slice(0, ${files.length}).every(c => c && (c.status === 'ok' || c.status === 'error' || c.status === 'missing')), 120000);
      return S.project.layers[0].clips.slice(0, ${files.length}).map(c => c ? { name: c.name, kind: c.kind, status: c.status, w: c.w, h: c.h, dur: c.dur, converted: !!c.converted, error: c.error || '' } : null);`);
    note('a video, a picture and a file that must be converted are added and ready', r.every(c => c && c.status === 'ok'), r, true);
    note('the file that must be converted was converted by the ffmpeg in the app', !!(r[2] && r[2].status === 'ok' && r[2].converted), r[2], true);
  }, true);

  // a clip plays, with a real picture
  const plays = async (col, label, must) => safe(label, async () => {
    const r = await page(`E.trigger(0, ${col}); await wait(2500);
      const L = S.project.layers[0], p = E.playing(L), d = S.preview && S.preview.layers.get(L.id), el = d && d.cur && d.cur.el;
      const t1 = el && el.currentTime; await wait(1500); const t2 = el && el.currentTime;
      const g = document.createElement('canvas'); g.width = 64; g.height = 36; const x = g.getContext('2d', { willReadFrequently: true });
      if (S.preview) S.preview.snapshot(x, 64, 36); const px = x.getImageData(0, 0, 64, 36).data; let lit = 0, sum = 0; for (let i = 0; i < px.length; i += 4) { if (px[i] + px[i + 1] + px[i + 2] > 60) lit++; sum += px[i] * 3 + px[i + 1] * 5 + px[i + 2] * 7; }
      const q = el && el.getVideoPlaybackQuality ? el.getVideoPlaybackQuality() : null;
      return { playing: p ? p.clip.name : null, tag: el ? el.tagName : null, t1, t2, lit, sum, frames: q ? q.totalVideoFrames : null, dropped: q ? q.droppedVideoFrames : null, size: el ? [el.videoWidth, el.videoHeight] : null };`);
    note(label, !!r.playing && r.lit > 1500 && (r.tag !== 'VIDEO' || r.t2 !== r.t1), r, must);      // (a short clip may have started again in between)
  }, must);
  await plays(0, 'a video plays in the Composition Monitor, with a real picture that moves', true);
  await shot('window-2-playing.png'); screen('screen-2-playing.png');
  await plays(2, 'the converted file plays', true);
  if (!quick) await plays(3, 'a 4K video plays', false);
  await plays(1, 'a picture shows', true);

  await safe('the sound picture of a clip', async () => {
    const r = await page(`const c = S.project.layers[0].clips[0]; const w = await Promise.race([E.waveform(c), wait(60000).then(() => 'timeout')]); return w === 'timeout' ? 'timeout' : (w ? w.length : 0);`);
    note('the sound picture of a clip is made', typeof r === 'number' && r > 100, r, false);
  });

  if (!quick) await safe('copies', async () => {
    const r = await page(`S.settings.optimize = true; S.settings.scrubCopies = true; const c = S.project.layers[0].clips[0];
      E.clearAll(); await wait(500);
      E.optCopy(c); E.scrubCopy(c, true);
      const t0 = Date.now();
      const over = x => x && x.state !== 'check' && x.state !== 'making';
      await until(() => over(E.optState(c)) && over(E.scrubState(c)), 240000);
      const o = E.optState(c), s = E.scrubState(c); S.settings.optimize = false;
      return { seconds: Math.round((Date.now() - t0) / 1000), instantJumps: o, dragging: s };`);
    note('the copy for instant jumps is made (how: ' + (r.instantJumps && r.instantJumps.how) + ')', !!(r.instantJumps && r.instantJumps.state === 'ready'), r, false);
    note('the small copy for dragging the playhead is made', !!(r.dragging && r.dragging.state === 'ready'), r.dragging, false);
  });

  // outputs
  await safe('an output in a window', async () => {
    const r = await page(`E.trigger(0, 0); await wait(800); E.openWindow();
      const led = await until(() => S.leader && S.leader !== 'preview', 30000); await wait(5000);
      return { led, leader: S.leader, kind: S.previewKind, open: S.outputs.open.map(o => ({ id: o.id, mode: o.mode, w: o.w, h: o.h })), stats: S.stats, mirror: S.frameW || 0 };`);
    screen('screen-3-window-output.png'); await shot('window-3-with-window-output.png');
    note('an output opens in a window, takes over the show and reports its pictures', r.led && r.open.length === 1 && !!r.stats && r.stats.fps > 0, r, true);
    await page(`E.closeAllOutputs(); await until(() => S.leader === 'preview' || !S.outputs.open.length, 10000); return 0;`);
  }, true);
  await safe('a fullscreen output', async () => {
    const r = await page(`const d = S.displays[0]; E.trigger(0, 0); await wait(500); E.openFullscreen(d.id);
      const led = await until(() => S.leader && S.leader !== 'preview', 30000); await wait(4000);
      let shell = null; try { shell = await Promise.race([WS.host.call('shellState', {}), wait(3000).then(() => null)]); } catch (e) { }
      return { led, display: d, open: S.outputs.open.map(o => ({ id: o.id, mode: o.mode, w: o.w, h: o.h, display: o.display })), lost: S.outputs.lost, stats: S.stats, shell };`);
    screen('screen-4-fullscreen-output.png');
    note('a fullscreen output opens on the display, takes over the show and reports its pictures', r.led && r.open.length === 1 && r.open[0].mode === 'fullscreen' && !!r.stats && r.stats.fps > 0, r, true);
    await page(`E.closeAllOutputs(); await until(() => !S.outputs.open.length, 10000); return 0;`);
    await wait(1500); screen('screen-5-after-fullscreen.png');
  }, true);

  // leaving and coming back
  await safe('the session', async () => {
    await page(`S.project.name = 'Mac check'; E.touch(); E.flush(); await wait(1500); return 0;`);
    const errs = await page(`return (window.__errs || []).slice(0, 5);`).catch(() => []);
    await ev(`WS.host.send('quit', {}); 0`).catch(() => { });
    const code = await Promise.race([child.gone, wait(20000).then(() => 'still running')]);
    note('Quit ends the app', code !== 'still running', code, true);
    if (code === 'still running') { try { child.kill('SIGKILL'); } catch (e) { } await wait(1500); }
    const left = sh('pgrep', ['-f', ffmpeg]);
    note('no ffmpeg helper is left behind', !left || /^ERROR/.test(left), left, false);
    try { ws.close(); } catch (e) { }
    start();
    const again = await ready(90000);
    const s = again ? await page(`await wait(1500); return { name: S.project.name, clips: S.project.layers[0].clips.filter(Boolean).length };`) : null;
    note('started again, the composition is as it was left', !!s && s.name === 'Mac check' && s.clips >= 3, s, true);
    await shot('window-4-after-restart.png');
    await ev(`WS.host.send('quit', {}); 0`).catch(() => { });
    await Promise.race([child.gone, wait(15000)]);
  }, true);
}
try { if (child && child.exitCode === null) child.kill('SIGKILL'); } catch (e) { }
for (const f of ['widescreen.log']) { try { fs.copyFileSync(path.join(data, f), path.join(out, f)); } catch (e) { } }
report.failedMust = failedMust;
fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 1));
const passed = report.checks.filter(c => c.ok).length;
console.log(`passed ${passed} of ${report.checks.length}` + (failedMust ? `, ${failedMust} that must pass did not` : ''));
process.exit(failedMust ? 1 : 0);
