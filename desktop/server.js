// The local server the dashboard talks to (127.0.0.1 only), same API as Questrig.ps1 on Windows.
const http = require('http');
const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const crypto = require('crypto');
const P = require('./platform');

const CLAUDE_MODEL = 'claude-opus-5-5';
const OLLAMA = 'http://127.0.0.1:11434';
const LOCAL_MODEL = 'gemma3:4b', LOCAL_NAME = 'Gemma 3';
const PING_HOSTS = { Cloudflare: '1.1.1.1', Google: '8.8.8.8', Quad9: '9.9.9.9' };
const osName = P.isMac ? 'Mac' : 'Linux PC';

// uiDir: folder with dashboard.html and logo.svg. dataDir: where data.json and the Claude key live.
// secret: { encrypt(string) -> Buffer, decrypt(Buffer) -> string } (Electron safeStorage) or null.
function start({ uiDir, dataDir, secret, openUrl, notify = () => {} }) {
  const token = crypto.randomBytes(16).toString('hex');
  const dataFile = path.join(dataDir, 'data.json');
  const keyFile = path.join(dataDir, 'claude.key');
  fs.mkdirSync(dataDir, { recursive: true });
  const jobs = new Map();
  const apps = P.scanApps();
  const steam = P.steamGames();
  const tools = P.availableTools();

  // Anti-freeze: warn when memory is almost full (the usual reason a Mac or Linux PC grinds to a halt).
  const af = { memSince: null, noticed: false, log: [], pct: 0 };
  const afLog = text => { af.log.unshift({ at: new Date().toTimeString().slice(0, 5), text }); af.log.length = Math.min(af.log.length, 8); };
  const afAlert = () => af.memSince && Date.now() - af.memSince >= 10000;
  const afTimer = setInterval(async () => {
    af.pct = await P.memoryPct();
    if (af.pct < 92) { af.memSince = null; af.noticed = false; return; }
    if (!af.memSince) af.memSince = Date.now();
    else if (afAlert() && !af.noticed) {
      af.noticed = true; afLog(`Memory almost full (${af.pct} %)`);
      notify('Questrig Anti-Freeze', `Memory is almost full (${af.pct} %). Your computer may freeze. Open Questrig to close a big app.`);
    }
  }, 3000);
  let stopOllama = null, ollamaStarting = false;   // stopOllama: set when Questrig started Ollama itself
  // The on/off switch in the AI panel (saved by the dashboard in data.json). Off: Questrig doesn't start Ollama.
  let ollamaOff = false;
  try { ollamaOff = !!JSON.parse(fs.readFileSync(dataFile, 'utf8')).localAiOff; } catch {}

  const getKey = () => {
    try {
      const raw = fs.readFileSync(keyFile);
      return secret ? secret.decrypt(raw) : raw.toString('utf8').trim();
    } catch { return null; }
  };
  const newJob = () => { const id = crypto.randomBytes(12).toString('hex'); const job = { text: '', done: false, error: null, status: null, stop: null, progress: null }; jobs.set(id, job); return [id, job]; };

  async function readLines(res, onLine) {
    const dec = new TextDecoder(); let buf = '';
    for await (const chunk of res.body) {
      buf += dec.decode(chunk, { stream: true });
      let i; while ((i = buf.indexOf('\n')) >= 0) { const line = buf.slice(0, i); buf = buf.slice(i + 1); if (line.trim()) onLine(line); }
    }
    if (buf.trim()) onLine(buf);
  }

  async function claudeJob(job, messages) {
    try {
      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-api-key': getKey(), 'anthropic-version': '2023-06-01', 'anthropic-beta': 'server-side-fallback-2026-07-01' },
        body: JSON.stringify({
          model: CLAUDE_MODEL, max_tokens: 16000, stream: true, fallbacks: 'default', output_config: { effort: 'low' },
          system: `You are Claude, answering inside Questrig, a small widget dashboard on the user's ${osName}. Keep answers short and easy to scan: lead with the answer, then brief details. Use simple Markdown (bold, lists, code blocks) only when it helps.`,
          messages,
        }),
      });
      if (!res.ok) { const raw = await res.text(); job.status = res.status; try { job.error = JSON.parse(raw).error.message; } catch { job.error = raw; } return; }
      await readLines(res, line => {
        if (!line.startsWith('data:')) return;
        const ev = JSON.parse(line.slice(5));
        if (ev.type === 'content_block_delta' && ev.delta.type === 'text_delta') job.text += ev.delta.text;
        else if (ev.type === 'message_delta' && ev.delta.stop_reason) job.stop = ev.delta.stop_reason;
        else if (ev.type === 'error') { job.status = 0; job.error = ev.error.message; }
      });
    } catch (e) { job.status = 0; job.error = e.message; } finally { job.done = true; }
  }

  async function localJob(job, messages) {
    const today = new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
    const system = `You are Questrig AI, a helpful assistant built into Questrig, a widget dashboard on the user's ${osName}. ` +
      `You run locally on their computer (model: ${LOCAL_NAME}), so you work offline and cannot browse the web. Today is ${today}. ` +
      'Keep answers short and easy to scan: lead with the answer, then brief details. Use simple Markdown only when it helps. If you are not sure about a fact, say so instead of guessing.';
    try {
      const res = await fetch(OLLAMA + '/api/chat', { method: 'POST', body: JSON.stringify({ model: LOCAL_MODEL, messages: [{ role: 'system', content: system }, ...messages], stream: true, keep_alive: '5m' }) });
      if (!res.ok) { const raw = await res.text(); job.status = res.status; try { job.error = JSON.parse(raw).error; } catch { job.error = raw; } return; }
      await readLines(res, line => {
        const ev = JSON.parse(line);
        if (ev.error) { job.status = 500; job.error = ev.error; return; }
        if (ev.message?.content) job.text += ev.message.content;
        if (ev.done) job.stop = ev.done_reason === 'length' ? 'max_tokens' : 'end_turn';
      });
    } catch { job.status = 0; job.error = 'The local AI is not running.'; } finally { job.done = true; }
  }

  async function pullJob(job) {
    try {
      const res = await fetch(OLLAMA + '/api/pull', { method: 'POST', body: JSON.stringify({ model: LOCAL_MODEL, stream: true }) });
      await readLines(res, line => {
        const ev = JSON.parse(line);
        if (ev.error) { job.error = ev.error; return; }
        if (ev.total && ev.completed) job.progress = Math.floor(100 * ev.completed / ev.total);
        job.text = String(ev.status);
      });
    } catch (e) { job.status = 0; job.error = e.message; } finally { job.done = true; }
  }

  const ollamaUp = () => fetch(OLLAMA + '/api/tags', { signal: AbortSignal.timeout(1200) }).then(() => true, () => false);
  // Ollama only runs while Questrig is open: start it unless it's already running (then it isn't ours to stop).
  async function ensureOllama() {
    if (ollamaOff || stopOllama || ollamaStarting || !P.ollamaInstalled()) return;
    ollamaStarting = true;
    try { if (!(await ollamaUp())) stopOllama = P.startOllama(); } finally { ollamaStarting = false; }
  }

  async function localStatus() {
    const installed = P.ollamaInstalled();
    let running = false, hasModel = false;
    try {
      const r = await fetch(OLLAMA + '/api/tags', { signal: AbortSignal.timeout(1200) });
      const tags = await r.json(); running = true;
      hasModel = (tags.models || []).some(m => m.name === LOCAL_MODEL || m.model === LOCAL_MODEL);
    } catch {}
    if (installed && !running) ensureOllama();   // e.g. Ollama was installed while Questrig was open
    return { installed, running, hasModel, off: ollamaOff, model: LOCAL_MODEL, name: LOCAL_NAME };
  }

  async function testKey(key) {
    try {
      const r = await fetch('https://api.anthropic.com/v1/models?limit=1', { headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01' }, signal: AbortSignal.timeout(15000) });
      return r.status === 401 || r.status === 403 ? 'That key was not accepted. Check that you copied all of it.' : null;
    } catch { return 'Could not reach Claude. Are you online?'; }
  }

  // Time to open a TCP connection (works without admin rights, unlike ICMP ping).
  const pingOne = host => new Promise(resolve => {
    const t0 = process.hrtime.bigint();
    const s = net.connect({ host, port: 443, timeout: 900 });
    const end = ms => { s.destroy(); resolve(ms); };
    s.on('connect', () => end(Number((process.hrtime.bigint() - t0) / 1000000n)));
    s.on('timeout', () => end(null)); s.on('error', () => end(null));
  });

  const body = req => new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', c => { size += c.length; if (size > 1024 * 1024) { reject(new Error('too big')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8'))); req.on('error', reject);
  });

  let port = 47821;
  const server = http.createServer(async (req, res) => {
    const send = (code, data, type = 'application/json; charset=utf-8') => { res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' }); res.end(data); };
    const json = obj => send(200, JSON.stringify(obj));
    try {
      const url = new URL(req.url, 'http://127.0.0.1');
      const q = url.searchParams, p = url.pathname;
      if (req.headers.host !== `127.0.0.1:${port}`) return send(403, 'forbidden', 'text/plain');
      if (p === '/') return send(200, fs.readFileSync(path.join(uiDir, 'dashboard.html')), 'text/html; charset=utf-8');
      if (p === '/logo.svg') return send(200, fs.readFileSync(path.join(uiDir, 'logo.svg')), 'image/svg+xml');
      const qm = /^\/quiz\/((?:quizzes\/)?[a-z0-9][a-z0-9.-]*\.(js|css|json|html))$/.exec(p);
      if (qm) {   // QuizDesk files (quiz/ next to the dashboard)
        const file = path.join(uiDir, 'quiz', qm[1]);
        if (!fs.existsSync(file)) return send(404, 'not found', 'text/plain');
        const type = { js: 'text/javascript', css: 'text/css', json: 'application/json', html: 'text/html' }[qm[2]];
        return send(200, fs.readFileSync(file), type + '; charset=utf-8');
      }
      if (p === '/api/spotify/art' && q.get('t') === token) {
        if (!P.art.bytes) return send(404, '', 'text/plain');
        res.writeHead(200, { 'Content-Type': P.art.type, 'Cache-Control': 'max-age=3600' }); return res.end(P.art.bytes);
      }
      if (req.headers['x-token'] !== token) return send(403, '{"error":"bad token"}');

      if (req.method === 'GET') switch (p) {
        case '/api/stats': return json({ ...(await P.stats()), spotify: await P.spotifyStats() });
        case '/api/freeze': return json({
          hungSupported: false, auto: false, autoSeconds: 30, hung: [], log: af.log,
          memory: { pct: af.pct || await P.memoryPct(), alert: !!afAlert(), top: afAlert() ? await P.topMemory() : [] },
        });
        case '/api/ping': return json(await Promise.all(Object.entries(PING_HOSTS).map(async ([name, host]) => ({ name, host, ms: await pingOne(host) }))));
        case '/api/apps': return json({ apps, steam, ...tools, platform: process.platform });
        case '/api/store': return send(200, fs.existsSync(dataFile) ? fs.readFileSync(dataFile) : '{}');
        case '/api/claude/status': return json({ hasKey: !!getKey(), model: CLAUDE_MODEL, local: await localStatus() });
        case '/api/claude/poll': {
          const id = q.get('id'), job = jobs.get(id);
          if (!job) return send(404, '{"error":"unknown chat"}');
          if (job.done) jobs.delete(id);
          return json(job);
        }
      }
      if (req.method !== 'POST') return send(405, '{"error":"use POST"}');
      switch (p) {
        case '/api/store': {
          const b = await body(req); JSON.parse(b);   // refuse anything that isn't valid JSON
          fs.writeFileSync(dataFile, b); return json({ ok: true });
        }
        case '/api/claude/key': {
          const key = String(JSON.parse(await body(req)).key || '').trim();
          if (!key) { fs.rmSync(keyFile, { force: true }); return json({ ok: true }); }
          if (!/^sk-ant-[A-Za-z0-9_-]{20,}$/.test(key)) return json({ ok: false, error: 'That doesn\'t look like a Claude API key (they start with sk-ant-).' });
          const problem = await testKey(key);
          if (problem) return json({ ok: false, error: problem });
          fs.writeFileSync(keyFile, secret ? secret.encrypt(key) : key, { mode: 0o600 });
          return json({ ok: true });
        }
        case '/api/ai/power': {   // the on/off switch in the AI panel
          ollamaOff = q.get('on') !== '1';
          if (ollamaOff) { if (stopOllama) stopOllama(); stopOllama = null; P.stopAllOllama(); } else await ensureOllama();
          return json({ ok: true });
        }
        case '/api/ai/pull': {
          if (jobs.size >= 3) return send(429, '{"error":"busy"}');
          const [id, job] = newJob(); pullJob(job); return json({ id });
        }
        case '/api/claude/ask': {
          const ask = JSON.parse(await body(req));
          const local = ask.engine === 'local';
          if (!local && !getKey()) return send(400, '{"error":"no key"}');
          if (jobs.size >= 3) return send(429, '{"error":"busy"}');
          const msgs = Array.isArray(ask.messages) ? ask.messages : [];
          const ok = msgs.length >= 1 && msgs.length <= 60 && msgs.every((m, i) => m.role === (i % 2 ? 'assistant' : 'user') && typeof m.content === 'string' && m.content.trim());
          if (!ok || msgs.at(-1).role !== 'user') return send(400, '{"error":"bad chat"}');
          const clean = msgs.map(m => ({ role: m.role, content: m.content }));
          const [id, job] = newJob();
          (local ? localJob : claudeJob)(job, clean);
          return json({ id });
        }
        case '/api/media': {
          const k = q.get('k');
          if (!['playpause', 'next', 'prev', 'volup', 'voldown', 'mute'].includes(k)) return send(400, '{"error":"unknown key"}');
          if (['volup', 'voldown', 'mute'].includes(k)) { await P.volume(k); return json({ ok: true }); }
          if (await P.spotifyControl(k)) return json({ ok: true });
          if (k === 'playpause' && apps.includes('Spotify') && !(await P.spotifyStats()).running) {
            const [id, job] = newJob(); P.spotifyStart(job); return json({ ok: true, starting: id });
          }
          return json({ ok: false });
        }
        case '/api/launch': return P.launchApp(q.get('id')) ? json({ ok: true }) : send(404, '{"error":"unknown app"}');
        case '/api/tool': {
          const id = q.get('id');
          if (!tools.tools.includes(id)) return send(404, '{"error":"unknown tool"}');
          await P.runTool(id); return json({ ok: true });
        }
        case '/api/freeze/kill': {
          // Only one of the biggest apps, and only while memory is almost full.
          const pid = Number(q.get('pid'));
          const top = afAlert() ? await P.topMemory() : [];
          const t = top.find(x => x.pid === pid);
          if (!t) return send(403, '{"error":"not allowed"}');
          try { process.kill(pid, 'SIGTERM'); setTimeout(() => { try { process.kill(pid, 'SIGKILL'); } catch {} }, 3000); } catch {}
          afLog('Ended ' + t.name); return json({ ok: true });
        }
        case '/api/steam': {
          const id = q.get('id');
          if (!/^\d{1,10}$/.test(id)) return send(400, '{"error":"bad id"}');
          openUrl('steam://rungameid/' + id); return json({ ok: true });
        }
        case '/api/open': {
          const u = q.get('u');   // only https web pages
          if (!/^https:\/\/[^\s"]+$/.test(u || '')) return send(400, '{"error":"https only"}');
          openUrl(u); return json({ ok: true });
        }
      }
      send(404, '{"error":"not found"}');
    } catch (e) { try { send(500, JSON.stringify({ error: String(e.message || e) })); } catch {} }
  });

  ensureOllama();
  const close = () => { server.close(); clearInterval(afTimer); if (stopOllama) { stopOllama(); stopOllama = null; } };

  return new Promise((resolve, reject) => {
    const tryListen = () => {
      server.once('error', err => { if (['EADDRINUSE', 'EACCES'].includes(err.code) && port < 47841) { port++; tryListen(); } else reject(err); });
      server.listen(port, '127.0.0.1', () => resolve({ url: `http://127.0.0.1:${port}/?t=${token}`, close }));
    };
    tryListen();
  });
}

module.exports = { start };
