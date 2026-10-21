// QuizDesk inside Questrig: a quiz library that works offline, the shared quiz collection from
// github.com/CillX1/QuizDesk, and duels (live with a room code, or challenge codes).
// Uses the same duel protocol and challenge codes as the standalone QuizDesk app, so both can play together.
(() => {
  const REPO = 'CillX1/QuizDesk';
  const RAW = `https://raw.githubusercontent.com/${REPO}/main/quizzes/`;
  const TONES = { mathe: 'Math', netz: 'Networking', sql: 'Databases', web: 'Web', sprache: 'Languages', other: 'Other' };
  const FORM_TONES = { mathe: 'Mathe', netz: 'Netzwerk / Telematik', sql: 'Datenbanken / SQL', web: 'Web / Programmieren', sprache: 'Sprachen', other: 'Anderes' };
  const MAX_BYTES = 5 * 1024 * 1024;
  const $q = id => document.getElementById(id);

  function mk(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function button(label, cls, onClick) { const b = mk('button', 'qd-btn ' + (cls || ''), label); b.type = 'button'; b.onclick = onClick; return b; }
  const note = (msg, bad) => { if (typeof toast === 'function') toast(msg); else console[bad ? 'error' : 'log'](msg); };
  const errText = e => String((e && e.message) || e);

  async function sha256(buf) {
    const h = await crypto.subtle.digest('SHA-256', buf);
    return [...new Uint8Array(h)].map(b => b.toString(16).padStart(2, '0')).join('');
  }
  const looksLikeQuiz = text => text.length > 0 && text.length <= MAX_BYTES && /<(!doctype html|html|body|script)/i.test(text.slice(0, 20000));
  const titleOf = html => ((/<title>([^<]{1,120})<\/title>/i.exec(html) || [])[1] || '').trim();
  function clean(m) {
    const s = (v, max) => String(v || '').replace(/\s+/g, ' ').trim().slice(0, max);
    return { title: s(m.title, 80) || 'Quiz', tone: TONES[m.tone] ? m.tone : 'other', tag: s(m.tag, 24), desc: s(m.desc, 200), author: s(m.author, 40) };
  }
  function readPool(text) {
    const s = (v, max) => typeof v === 'string' ? v.slice(0, max) : '';
    const questions = (JSON.parse(text).questions || []).map(x => ({
      t: s(x.t, 60), q: s(x.q, 400), code: s(x.code, 600), a: s(x.a, 200),
      w: Array.isArray(x.w) ? x.w.map(y => s(y, 200)).filter(Boolean).slice(0, 6) : [],
    })).filter(x => x.q && x.a && x.w.length >= 3);
    if (questions.length < 5) throw new Error('Not enough duel questions.');
    return questions;
  }

  // ---------- storage: IndexedDB in Questrig's own browser profile ----------
  let dbp;
  function db() {
    return dbp || (dbp = new Promise((resolve, reject) => {
      const r = indexedDB.open('quizdesk', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('quizzes', { keyPath: 'id' });
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
    }));
  }
  async function tx(mode, fn) {
    const d = await db();
    return new Promise((resolve, reject) => {
      const t = d.transaction('quizzes', mode), store = t.objectStore('quizzes');
      const r = fn(store);
      t.oncomplete = () => resolve(r && r.result);
      t.onerror = () => reject(t.error);
    });
  }
  const getAll = () => tx('readonly', s => s.getAll());
  const getOne = id => tx('readonly', s => s.get(id));
  const put = item => tx('readwrite', s => s.put(item));
  const del = id => tx('readwrite', s => s.delete(id));

  let library = [];        // metadata only (no html)
  let catalog = null;      // null = not loaded, false = offline
  const meta = x => { const { html, duel, ...m } = x; return m; };
  async function refreshLibrary() { library = (await getAll()).map(meta).sort((a, b) => (a.order || 0) - (b.order || 0) || a.title.localeCompare(b.title)); }

  // Quizzes that ship with Questrig go into the library once each, so removing one keeps it removed.
  async function seedBundled() {
    let seeded = [];
    try { seeded = JSON.parse(localStorage.getItem('qd-seeded') || '[]'); } catch {}
    const bundled = (await (await fetch('/quiz/quizzes/catalog.json', { cache: 'no-store' })).json()).quizzes;
    let order = 0;
    for (const q of bundled) {
      if (seeded.includes(q.id) || await getOne(q.id)) continue;
      const html = await (await fetch('/quiz/quizzes/' + q.file)).text();
      const item = { id: q.id, ...clean(q), source: 'catalog', sha256: await sha256(new TextEncoder().encode(html)), html, order: order++ };
      if (q.duel) { item.duel = await (await fetch('/quiz/quizzes/' + q.duel)).text(); item.duelSha = await sha256(new TextEncoder().encode(item.duel)); }
      await put(item);
      seeded.push(q.id);
    }
    try { localStorage.setItem('qd-seeded', JSON.stringify(seeded)); } catch {}
  }

  async function fetchCatalog() {
    try {
      const res = await fetch(RAW + 'catalog.json?t=' + Date.now(), { cache: 'no-store', signal: AbortSignal.timeout(8000) });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      catalog = ((await res.json()).quizzes || []).filter(q => /^[a-z0-9-]{1,48}$/.test(q.id) && /^[a-z0-9-]+\.html$/.test(q.file))
        .map(q => ({ id: q.id, file: q.file, sha256: q.sha256, ...clean(q),
          duel: /^[a-z0-9-]+\.duel\.json$/.test(q.duel || '') ? q.duel : null, duelSha256: q.duelSha256 || null }));
    } catch { catalog = false; }
  }

  async function download(id) {
    const e = (catalog || []).find(q => q.id === id);
    if (!e) throw new Error('This quiz is not in the collection.');
    const buf = await (await fetch(RAW + e.file, { cache: 'no-store' })).arrayBuffer();
    const html = new TextDecoder().decode(buf);
    if (!looksLikeQuiz(html)) throw new Error('That file is not a valid quiz.');
    const sha = await sha256(buf);
    if (e.sha256 && sha !== e.sha256) throw new Error('The download arrived damaged. Try again.');
    const item = { id, ...clean(e), source: 'catalog', sha256: sha, html, order: (await getOne(id))?.order ?? library.length };
    if (e.duel) {
      const dbuf = await (await fetch(RAW + e.duel, { cache: 'no-store' })).arrayBuffer();
      if (e.duelSha256 && await sha256(dbuf) !== e.duelSha256) throw new Error('The duel questions arrived damaged. Try again.');
      item.duel = new TextDecoder().decode(dbuf); readPool(item.duel); item.duelSha = e.duelSha256 || await sha256(dbuf);
    }
    await put(item);
    await refreshLibrary();
  }
  const outdated = (mine, remote) => remote && ((remote.sha256 && remote.sha256 !== mine.sha256) || (remote.duelSha256 && remote.duelSha256 !== mine.duelSha));

  function slug(text) {
    const base = String(text).toLowerCase().replace(/ä/g, 'ae').replace(/ö/g, 'oe').replace(/ü/g, 'ue').replace(/ß/g, 'ss')
      .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40) || 'quiz';
    let id = base, n = 2;
    while (library.some(q => q.id === id)) id = `${base}-${n++}`;
    return id;
  }

  function saveFile(name, text) {
    const a = mk('a');
    a.href = URL.createObjectURL(new Blob([text], { type: 'text/plain' }));
    a.download = name;
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 10000);
  }

  // ---------- UI ----------
  const root = mk('div', 'qd-root hidden');
  root.innerHTML = `
    <div class="qd-wrap">
      <header class="qd-top">
        <h1>Quizzes</h1>
        <nav class="qd-tabs" role="tablist">
          <button role="tab" data-tab="mine">My quizzes <span id="qd-n"></span></button>
          <button role="tab" data-tab="find">Browse</button>
          <button role="tab" data-tab="duel">Duel</button>
        </nav>
        <button class="qd-btn" id="qd-import" type="button">+ Add quiz file</button>
        <button class="qd-btn qd-close" id="qd-close" type="button" title="Back to Questrig">✕</button>
      </header>
      <section data-view="mine">
        <div class="qd-bar"><input class="qd-input qd-search" id="qd-search" type="search" placeholder="Search quizzes…"><div class="qd-chips" id="qd-chips"></div></div>
        <p class="qd-note">Saved on this PC, so they also work offline.</p>
        <div class="qd-grid" id="qd-grid-mine"></div>
      </section>
      <section data-view="find" hidden>
        <div class="qd-bar"><p class="qd-net" id="qd-net"></p><button class="qd-btn" id="qd-refresh" type="button">Refresh</button></div>
        <div class="qd-grid" id="qd-grid-find"></div>
        <p class="qd-note qd-share-note">Share your own quiz: add it with <b>+ Add quiz file</b>, then click <b>Submit</b> on its card. Questrig saves a copy to your Downloads and opens the GitHub form; drag the file in and send it. Once approved, everyone sees it here.</p>
      </section>
      <section data-view="duel" hidden>
        <div class="qd-setup">
          <label>Your name<input class="qd-input" id="qd-name" maxlength="20" placeholder="e.g. Marco" autocomplete="off"></label>
          <label>Quiz<select class="qd-input" id="qd-dquiz"></select></label>
          <label>Questions<select class="qd-input" id="qd-dn"><option>5</option><option selected>10</option><option>15</option><option>20</option></select></label>
          <label>Time per question<select class="qd-input" id="qd-dtime"><option value="15">15 s</option><option value="20" selected>20 s</option><option value="30">30 s</option><option value="45">45 s</option></select></label>
        </div>
        <div class="qd-duels">
          <article class="qd-panel">
            <h2>Live duel</h2>
            <p>Play at the same time over the internet: same questions, same clock. Right and fast scores the most.</p>
            <div id="qd-live-idle" class="qd-stack">
              <button class="qd-btn solid" id="qd-host" type="button">Create duel</button>
              <div class="qd-or">or join a duel</div>
              <div class="qd-row"><input class="qd-input qd-code" id="qd-code" maxlength="5" placeholder="CODE" autocomplete="off"><button class="qd-btn" id="qd-join" type="button">Join</button></div>
            </div>
            <div id="qd-lobby" class="qd-stack" hidden>
              <p class="qd-muted">Your duel code</p>
              <p class="qd-bigcode" id="qd-lobby-code"></p>
              <p class="qd-lobby-status" id="qd-lobby-status"></p>
              <div class="qd-row">
                <button class="qd-btn" id="qd-copy-code" type="button">Copy code</button>
                <button class="qd-btn solid" id="qd-start" type="button" hidden>Start duel</button>
                <button class="qd-btn" id="qd-leave" type="button">Cancel</button>
              </div>
            </div>
            <p class="qd-err" id="qd-live-err"></p>
          </article>
          <article class="qd-panel">
            <h2>Challenge</h2>
            <p>Play a round on your own, then send the code. They get exactly the same questions and try to beat your points.</p>
            <div class="qd-stack">
              <button class="qd-btn solid" id="qd-solo" type="button">Play a round</button>
              <div class="qd-or">or accept a challenge</div>
              <div class="qd-row"><input class="qd-input" id="qd-chal" placeholder="QD-…" autocomplete="off"><button class="qd-btn" id="qd-accept" type="button">Accept</button></div>
            </div>
            <p class="qd-err" id="qd-chal-err"></p>
          </article>
        </div>
      </section>
    </div>
    <div class="qd-player hidden" id="qd-player">
      <div class="qd-player-bar"><b id="qd-player-title"></b><button class="qd-btn" id="qd-player-close" type="button">✕ Close quiz</button></div>
      <iframe id="qd-frame" sandbox="allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox" title="Quiz"></iframe>
    </div>
    <div class="qd-game hidden" id="qd-game">
      <div class="qd-game-inner">
        <div class="qd-players">
          <div class="qd-player-card me"><span id="qd-me-name"></span><b id="qd-me-score">0</b></div>
          <div class="qd-progress" id="qd-progress"></div>
          <div class="qd-player-card opp" id="qd-opp-card"><span id="qd-opp-name"></span><b id="qd-opp-score">0</b></div>
        </div>
        <div class="qd-timer"><i id="qd-timer"></i></div>
        <div id="qd-play">
          <p class="qd-topic" id="qd-topic"></p>
          <h2 class="qd-question" id="qd-q"></h2>
          <pre class="qd-codeblock" id="qd-codeblock" hidden></pre>
          <div class="qd-answers" id="qd-answers"></div>
          <p class="qd-status" id="qd-status"></p>
        </div>
        <div class="qd-end" id="qd-end" hidden>
          <p class="qd-end-title" id="qd-end-title"></p>
          <p class="qd-end-score" id="qd-end-score"></p>
          <div id="qd-share" hidden><p class="qd-muted">Your challenge code:</p><code class="qd-chalcode" id="qd-chalcode"></code></div>
          <div class="qd-row center" id="qd-end-actions"></div>
        </div>
        <button class="qd-btn qd-quit" id="qd-quit" type="button">Leave</button>
      </div>
    </div>
    <dialog class="qd-dialog" id="qd-meta">
      <form method="dialog" id="qd-meta-form">
        <h2 id="qd-meta-head">Add quiz</h2>
        <label>Title<input class="qd-input" id="qd-m-title" required maxlength="80"></label>
        <label>Subject<select class="qd-input" id="qd-m-tone">${Object.entries(TONES).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}</select></label>
        <label>Tab label <small>e.g. module number</small><input class="qd-input" id="qd-m-tag" maxlength="24" placeholder="M162"></label>
        <label>Short description<input class="qd-input" id="qd-m-desc" maxlength="200"></label>
        <div class="qd-row right"><button class="qd-btn" type="button" id="qd-m-cancel">Cancel</button><button class="qd-btn solid" type="submit">Save</button></div>
      </form>
    </dialog>
    <input type="file" id="qd-file" accept=".html,.htm,.txt" hidden>`;
  document.body.append(root);

  let filter = 'all', query = '', metaMode = null;

  function showTab(t) {
    root.querySelectorAll('[data-tab]').forEach(b => b.setAttribute('aria-selected', String(b.dataset.tab === t)));
    root.querySelectorAll('[data-view]').forEach(v => v.hidden = v.dataset.view !== t);
    if (t === 'duel') fillDuelQuizzes();
    if (t === 'find' && catalog === false) loadCatalog();
  }
  root.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => showTab(b.dataset.tab));

  function open(tab) {
    root.classList.remove('hidden');
    document.documentElement.classList.add('qd-open');
    showTab(tab || 'mine');
  }
  function close() {
    root.classList.add('hidden');
    document.documentElement.classList.remove('qd-open');
  }
  $q('qd-close').onclick = close;

  function card(q) {
    const c = mk('article', 'qd-card');
    c.style.setProperty('--tc', `var(--qd-${TONES[q.tone] ? q.tone : 'other'})`);
    c.append(mk('span', 'qd-tab', q.tag || TONES[q.tone] || 'Quiz'), mk('h3', null, q.title));
    if (q.duelSha || q.duel) c.append(mk('span', 'qd-meta', '⚔ Duel ready'));
    c.append(mk('p', 'qd-desc', q.desc || ''));
    if (q.author) c.append(mk('span', 'qd-meta', 'by ' + q.author));
    return c;
  }

  async function busy(btn, label, fn) {
    const old = btn.textContent; btn.disabled = true; btn.textContent = label;
    try { await fn(); } catch (e) { note(errText(e), true); } finally { btn.disabled = false; btn.textContent = old; }
  }

  async function play(id) {
    const q = await getOne(id);
    if (!q) return;
    $q('qd-player-title').textContent = q.title;
    $q('qd-frame').srcdoc = q.html;
    $q('qd-player').classList.remove('hidden');
    if (root.classList.contains('hidden')) open('mine');
  }
  $q('qd-player-close').onclick = () => { $q('qd-player').classList.add('hidden'); $q('qd-frame').srcdoc = ''; };

  function renderMine() {
    $q('qd-n').textContent = library.length;
    const used = new Set(library.map(q => q.tone));
    if (filter !== 'all' && !used.has(filter)) filter = 'all';
    const chips = $q('qd-chips'); chips.textContent = '';
    [['all', 'All'], ...Object.keys(TONES).filter(k => used.has(k)).map(k => [k, TONES[k]])].forEach(([k, label]) => {
      const b = button(label, 'chip' + (filter === k ? ' on' : ''), () => { filter = k; renderMine(); });
      chips.append(b);
    });
    const shown = library.filter(q => (filter === 'all' || q.tone === filter) && (!query || `${q.title} ${q.desc} ${q.tag}`.toLowerCase().includes(query)));
    const grid = $q('qd-grid-mine'); grid.textContent = '';
    if (!shown.length) grid.append(mk('div', 'qd-empty', library.length ? 'No quiz matches your search.' : 'No quizzes yet. Download some under Browse or add a file.'));
    for (const q of shown) {
      const c = card(q), act = mk('div', 'qd-actions');
      const remote = catalog && catalog.find(x => x.id === q.id);
      act.append(button('Play', 'solid', () => play(q.id)));
      if (q.source === 'catalog' && outdated(q, remote)) {
        const up = button('Update', '', () => busy(up, 'Loading…', async () => { await download(q.id); renderAll(); note('Updated'); }));
        act.append(up);
      }
      if (q.source === 'import') {
        act.append(button('Submit', '', () => submit(q.id)));
        act.append(button('Edit', '', () => openMeta({ kind: 'edit', id: q.id }, q)));
      }
      act.append(button('Export', '', async () => { const x = await getOne(q.id); saveFile(q.title.replace(/[\\/:*?"<>|]/g, '') + '.html', x.html); }));
      const d = button('Remove', 'danger', async () => {
        if (!d.classList.contains('armed')) { d.classList.add('armed'); d.textContent = 'Sure?'; return; }
        await del(q.id); await refreshLibrary(); renderAll(); note('Removed');
      });
      act.append(d);
      c.append(act); grid.append(c);
    }
  }

  function renderFind() {
    const net = $q('qd-net'), grid = $q('qd-grid-find'); grid.textContent = '';
    if (catalog === null) { net.className = 'qd-net'; net.textContent = 'Connecting…'; return; }
    if (catalog === false) { net.className = 'qd-net off'; net.textContent = 'Offline. Your quizzes under My quizzes still work.'; grid.append(mk('div', 'qd-empty', 'Connect to the internet to see new quizzes.')); return; }
    net.className = 'qd-net on'; net.textContent = `Online · ${catalog.length} quizzes in the collection`;
    for (const q of catalog) {
      const c = card(q), act = mk('div', 'qd-actions'), mine = library.find(x => x.id === q.id);
      if (mine && !outdated(mine, q)) act.append(mk('span', 'qd-done', '✓ Downloaded'), button('Play', '', () => play(q.id)));
      else { const b = button(mine ? 'Update' : 'Download', 'solid', () => busy(b, 'Loading…', async () => { await download(q.id); renderAll(); note(`"${q.title}" is now available offline`); })); act.append(b); }
      c.append(act); grid.append(c);
    }
  }

  function renderWidget() {
    const list = $q('qdWidgetList');
    if (!list) return;
    list.textContent = '';
    if (!library.length) { list.append(mk('div', 'muted small', 'No quizzes yet.')); return; }
    for (const q of library.slice(0, 5)) {
      const row = mk('div', 'qd-wrow');
      row.style.setProperty('--tc', `var(--qd-${TONES[q.tone] ? q.tone : 'other'})`);
      row.append(mk('span', 'qd-wdot'), mk('span', 'qd-wtitle', q.title), button('Play', '', () => play(q.id)));
      list.append(row);
    }
    const more = library.length - 5;
    if (more > 0) list.append(button(`+ ${more} more`, 'linkish', () => open('mine')));
  }

  function renderAll() { renderMine(); renderFind(); renderWidget(); }
  async function loadCatalog() { catalog = null; renderFind(); await fetchCatalog(); renderAll(); }
  $q('qd-refresh').onclick = loadCatalog;
  $q('qd-search').addEventListener('input', e => { query = e.target.value.trim().toLowerCase(); renderMine(); });

  // ---------- import / edit / submit ----------
  let pending = null;
  $q('qd-import').onclick = () => $q('qd-file').click();
  $q('qd-file').onchange = async e => {
    const f = e.target.files[0]; e.target.value = '';
    if (!f) return;
    const html = await f.text();
    if (!looksLikeQuiz(html)) { note('That file is not a quiz. Pick an .html file (5 MB max).', true); return; }
    pending = html;
    openMeta({ kind: 'import' }, { title: titleOf(html) || f.name.replace(/\.(quiz\.)?(html?|txt)$/i, ''), tone: 'other' });
  };
  function openMeta(mode, q) {
    metaMode = mode;
    $q('qd-meta-head').textContent = mode.kind === 'edit' ? 'Edit quiz' : 'Add quiz';
    $q('qd-m-title').value = q.title || ''; $q('qd-m-tone').value = TONES[q.tone] ? q.tone : 'other';
    $q('qd-m-tag').value = q.tag || ''; $q('qd-m-desc').value = q.desc || '';
    $q('qd-meta').showModal();
  }
  $q('qd-m-cancel').onclick = () => $q('qd-meta').close();
  $q('qd-meta-form').addEventListener('submit', async ev => {
    ev.preventDefault();
    const m = clean({ title: $q('qd-m-title').value, tone: $q('qd-m-tone').value, tag: $q('qd-m-tag').value, desc: $q('qd-m-desc').value });
    if (metaMode.kind === 'import') {
      await put({ id: slug(m.title), ...m, source: 'import', sha256: await sha256(new TextEncoder().encode(pending)), html: pending, order: library.length });
      pending = null;
    } else {
      const x = await getOne(metaMode.id); await put({ ...x, ...m });
    }
    $q('qd-meta').close();
    await refreshLibrary(); showTab('mine'); renderAll();
    note(metaMode.kind === 'import' ? 'Added' : 'Saved');
  });
  // GitHub only accepts certain attachment types, so the quiz goes along as a .txt copy of its HTML.
  async function submit(id) {
    const q = await getOne(id);
    saveFile(q.id + '.quiz.txt', q.html);
    const p = new URLSearchParams({ template: 'quiz.yml', title: 'Quiz: ' + q.title, titel: q.title, fach: FORM_TONES[q.tone] || 'Anderes', reiter: q.tag, beschreibung: q.desc });
    const url = `https://github.com/${REPO}/issues/new?${p}`;
    if (typeof openUrl === 'function') openUrl(url).catch(() => window.open(url)); else window.open(url);
    note(`Saved ${q.id}.quiz.txt to Downloads. Drag it into the "Quiz-Datei" field on GitHub.`);
  }

  // ---------- duels ----------
  const ALPHA = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789', PREFIX = 'quizdesk-v1-', REVEAL_MS = 2800;
  let peer = null, conn = null, role = null, settings = null, game = null;
  const myName = () => ($q('qd-name').value.trim() || 'Me').slice(0, 20);
  const str = (v, max) => typeof v === 'string' ? v.slice(0, max) : '';
  const randCode = () => Array.from(crypto.getRandomValues(new Uint32Array(5)), n => ALPHA[n % ALPHA.length]).join('');
  const points = (ok, ms, time) => ok ? Math.round(500 + 500 * Math.max(0, 1 - ms / (time * 1000))) : 0;
  function rng(seed) {
    return () => {
      seed = seed + 0x6D2B79F5 | 0;
      let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }
  function shuffled(arr, r) { const a = arr.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }
  // The same pool and seed always give the same questions in the same order (also in the QuizDesk app).
  function makeRound(pool, n, seed) {
    const r = rng(seed);
    return shuffled(pool.questions.map((_, i) => i), r).slice(0, n).map(i => {
      const x = pool.questions[i];
      const opts = shuffled([x.a, ...shuffled(x.w, r).slice(0, 3)], r);
      return { t: x.t, q: x.q, code: x.code, opts, c: opts.indexOf(x.a) };
    });
  }
  const b64 = s => btoa(String.fromCharCode(...new TextEncoder().encode(s))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const unb64 = s => new TextDecoder().decode(Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)));
  async function copy(text) {
    try { await navigator.clipboard.writeText(text); note('Copied'); }
    catch { const i = mk('textarea'); i.value = text; document.body.append(i); i.select(); document.execCommand('copy'); i.remove(); note('Copied'); }
  }

  function fillDuelQuizzes() {
    const sel = $q('qd-dquiz'), keep = sel.value; sel.textContent = '';
    const usable = library.filter(q => q.duelSha);
    for (const q of usable) { const o = mk('option', null, q.title); o.value = q.id; sel.append(o); }
    if (usable.some(q => q.id === keep)) sel.value = keep;
    $q('qd-host').disabled = $q('qd-solo').disabled = !usable.length;
  }
  async function loadPool(id) {
    const q = await getOne(id || $q('qd-dquiz').value);
    if (!q || !q.duel) throw new Error('This quiz has no duel questions.');
    return { id: q.id, title: q.title, sha: q.duelSha, questions: readPool(q.duel) };
  }

  const liveErr = m => { $q('qd-live-err').textContent = m; };
  const showLobby = on => { $q('qd-live-idle').hidden = on; $q('qd-lobby').hidden = !on; };
  function leave() {
    try { conn && conn.close(); } catch {}
    try { peer && peer.destroy(); } catch {}
    peer = conn = null; role = null; settings = null;
    clearTimers(); showLobby(false); $q('qd-start').hidden = true;
  }
  const send = m => { if (conn && conn.open) conn.send(m); };
  function hook(c) {
    conn = c;
    c.on('open', () => send({ type: 'hello', name: myName(), v: 1 }));
    c.on('data', m => { try { onMessage(m); } catch (e) { console.error(e); } });
    c.on('close', () => { if (conn === c) lost(); });
    c.on('error', () => { if (conn === c) lost(); });
  }
  function lost() {
    const inGame = !$q('qd-game').classList.contains('hidden'), ended = inGame && !$q('qd-end').hidden;
    const opp = game ? game.opp.name : 'Your opponent';
    leave();
    if (ended) showEnd($q('qd-end-title').textContent, `${$q('qd-end-score').textContent} · ${opp} left the duel.`, [['Back', 'solid', closeGame]]);
    else if (inGame) showEnd('Connection lost', '', [['Back', 'solid', closeGame]]);
    else liveErr('The connection dropped.');
  }
  function peerError(e) {
    const t = e && e.type;
    if (role === 'host' && t === 'unavailable-id') { try { peer.destroy(); } catch {} return hostCreate(); }
    const msg = t === 'peer-unavailable' ? 'No open duel with that code. Is the code right?'
      : ['network', 'server-error', 'socket-error', 'socket-closed'].includes(t) ? 'Can\'t reach the duel server. Are you online?'
        : 'The duel could not connect.';
    leave(); liveErr(msg);
  }
  function hostCreate() {
    role = 'host';
    const code = randCode();
    peer = new Peer(PREFIX + code, { debug: 0 });
    peer.on('open', () => { $q('qd-lobby-code').textContent = code; $q('qd-lobby-status').textContent = 'Waiting for your opponent… Send them the code.'; showLobby(true); });
    peer.on('connection', c => { if (conn) { c.on('open', () => { c.send({ type: 'busy' }); setTimeout(() => c.close(), 500); }); return; } hook(c); });
    peer.on('error', peerError);
  }
  function guestJoin(code) {
    role = 'guest';
    peer = new Peer({ debug: 0 });
    peer.on('open', () => {
      hook(peer.connect(PREFIX + code, { reliable: true }));
      $q('qd-lobby-code').textContent = code; $q('qd-lobby-status').textContent = 'Connecting…';
      $q('qd-copy-code').hidden = true; showLobby(true);
    });
    peer.on('error', peerError);
  }
  function onMessage(m) {
    if (!m || typeof m !== 'object') return;
    if (m.type === 'busy') { leave(); liveErr('That duel is already full.'); return; }
    if (m.type === 'hello') {
      const opp = str(m.name, 20) || 'Opponent';
      $q('qd-lobby-status').dataset.opp = opp;
      if (game) game.opp.name = opp;
      if (role === 'host') { $q('qd-lobby-status').textContent = `${opp} is here. Ready?`; $q('qd-start').hidden = false; }
      else $q('qd-lobby-status').textContent = `Connected to ${opp}. Waiting for the duel to start…`;
      return;
    }
    if (role === 'guest') {
      if (m.type === 'start') {
        const qs = Array.isArray(m.questions) ? m.questions.slice(0, 30).map(x => ({ t: str(x.t, 60), q: str(x.q, 400), code: str(x.code, 600),
          opts: Array.isArray(x.opts) ? x.opts.slice(0, 4).map(o => str(o, 200)) : [] })).filter(x => x.q && x.opts.length === 4) : [];
        if (!qs.length) return;
        startGame({ mode: 'guest', title: str(m.title, 80), questions: qs, time: Math.min(90, Math.max(5, +m.time || 20)), oppName: $q('qd-lobby-status').dataset.opp || 'Opponent' });
        $q('qd-status').textContent = 'Starting…';
      } else if (m.type === 'q' && game) { const i = m.i | 0; if (i >= 0 && i < game.questions.length) ask(i); }
      else if (m.type === 'answered' && game && (m.i | 0) === game.i) $q('qd-status').textContent = game.myChoice !== undefined ? `${game.opp.name} answered too.` : `${game.opp.name} already answered!`;
      else if (m.type === 'reveal' && game && (m.i | 0) === game.i) { const me = m.guest || {}, op = m.host || {}; reveal(m.c | 0, { choice: me.choice | 0, pts: me.pts | 0 }, { choice: op.choice | 0, pts: op.pts | 0 }); }
      else if (m.type === 'end' && game) finish();
    } else if (role === 'host' && game && m.type === 'ans') {
      const i = m.i | 0;
      if (i !== game.i || game.oppAns) return;
      game.oppAns = { choice: Math.max(-1, Math.min(3, m.choice | 0)), ms: Math.max(0, Math.min(game.time * 1000, +m.ms || 0)) };
      if (game.myChoice === undefined) $q('qd-status').textContent = `${game.opp.name} already answered!`;
      maybeFinishRound();
    }
  }
  function hostStartDuel() {
    const seed = crypto.getRandomValues(new Uint32Array(1))[0];
    const questions = makeRound(settings.pool, settings.n, seed);
    send({ type: 'start', title: settings.pool.title, time: settings.time, questions: questions.map(({ t, q, code, opts }) => ({ t, q, code, opts })) });
    startGame({ mode: 'host', title: settings.pool.title, questions, time: settings.time, oppName: $q('qd-lobby-status').dataset.opp || 'Opponent' });
    $q('qd-status').textContent = 'Starting…';
    later(() => hostAsk(0), 1500);
  }
  function hostAsk(i) {
    send({ type: 'q', i }); ask(i); game.oppAns = null;
    later(() => { if (!game.oppAns) game.oppAns = { choice: -1, ms: game.time * 1000 }; maybeFinishRound(); }, game.time * 1000 + 1500);
  }
  function maybeFinishRound() {
    if (!game || game.mode !== 'host' || game.revealed || game.myChoice === undefined || !game.oppAns) return;
    const q = game.questions[game.i];
    const mine = { choice: game.myChoice, pts: points(game.myChoice === q.c, game.myMs, game.time) };
    const theirs = { choice: game.oppAns.choice, pts: points(game.oppAns.choice === q.c, game.oppAns.ms, game.time) };
    send({ type: 'reveal', i: game.i, c: q.c, host: mine, guest: theirs });
    reveal(q.c, mine, theirs);
    later(() => { if (game.i + 1 < game.questions.length) hostAsk(game.i + 1); else { send({ type: 'end' }); finish(); } }, REVEAL_MS);
  }

  let timers = [], tick = null;
  const later = (fn, ms) => { const t = setTimeout(fn, ms); timers.push(t); return t; };
  function clearTimers() { timers.forEach(clearTimeout); timers = []; cancelAnimationFrame(tick); }
  function startGame({ mode, title, questions, time, oppName, target }) {
    clearTimers();
    game = { mode, title, questions, time, i: -1, me: { name: myName(), score: 0, pts: [] }, opp: { name: oppName || '', score: 0 }, target };
    $q('qd-me-name').textContent = game.me.name; $q('qd-opp-name').textContent = game.opp.name;
    $q('qd-opp-card').hidden = mode === 'solo';
    $q('qd-me-score').textContent = $q('qd-opp-score').textContent = '0';
    $q('qd-play').hidden = false; $q('qd-end').hidden = true; $q('qd-share').hidden = true;
    $q('qd-q').textContent = title; $q('qd-topic').textContent = mode === 'solo' ? 'Challenge' : 'Duel';
    $q('qd-codeblock').hidden = true; $q('qd-answers').textContent = ''; $q('qd-progress').textContent = '';
    $q('qd-timer').style.transform = 'scaleX(1)';
    $q('qd-game').classList.remove('hidden');
  }
  function ask(i) {
    const q = game.questions[i];
    Object.assign(game, { i, myChoice: undefined, myMs: 0, revealed: false, t0: performance.now() });
    $q('qd-progress').textContent = `Question ${i + 1} / ${game.questions.length}`;
    $q('qd-topic').textContent = q.t || game.title; $q('qd-q').textContent = q.q;
    $q('qd-codeblock').hidden = !q.code; $q('qd-codeblock').textContent = q.code || '';
    $q('qd-status').textContent = '';
    const box = $q('qd-answers'); box.textContent = '';
    q.opts.forEach((o, k) => {
      const b = mk('button', 'qd-ans a' + k); b.type = 'button';
      b.append(mk('span', 'qd-key', String(k + 1)), mk('span', null, o));
      b.onclick = () => answer(k); box.append(b);
    });
    const bar = $q('qd-timer');
    const frame = () => {
      const left = 1 - (performance.now() - game.t0) / (game.time * 1000);
      bar.style.transform = `scaleX(${Math.max(0, left)})`;
      if (left <= 0) { if (game.myChoice === undefined) answer(-1); return; }
      tick = requestAnimationFrame(frame);
    };
    cancelAnimationFrame(tick); tick = requestAnimationFrame(frame);
  }
  function answer(k) {
    if (!game || game.myChoice !== undefined || game.revealed) return;
    game.myChoice = k; game.myMs = Math.min(game.time * 1000, performance.now() - game.t0);
    cancelAnimationFrame(tick);
    [...$q('qd-answers').children].forEach((b, j) => { b.disabled = true; if (j === k) b.classList.add('picked'); });
    if (game.mode === 'guest') { send({ type: 'ans', i: game.i, choice: k, ms: game.myMs }); $q('qd-status').textContent = k < 0 ? 'Time\'s up.' : `Waiting for ${game.opp.name}…`; }
    else if (game.mode === 'host') { send({ type: 'answered', i: game.i }); if (!game.oppAns) $q('qd-status').textContent = k < 0 ? 'Time\'s up.' : `Waiting for ${game.opp.name}…`; maybeFinishRound(); }
    else {
      const q = game.questions[game.i];
      const mine = { choice: k, pts: points(k === q.c, game.myMs, game.time) };
      reveal(q.c, mine, game.target ? { choice: -2, pts: game.target.p[game.i] | 0 } : null);
      later(() => game.i + 1 < game.questions.length ? ask(game.i + 1) : finish(), REVEAL_MS);
    }
  }
  function reveal(c, mine, theirs) {
    game.revealed = true; cancelAnimationFrame(tick);
    game.me.score += mine.pts; game.me.pts[game.i] = mine.pts;
    if (theirs) game.opp.score += theirs.pts;
    $q('qd-me-score').textContent = game.me.score; $q('qd-opp-score').textContent = game.opp.score;
    [...$q('qd-answers').children].forEach((b, j) => {
      b.disabled = true; b.classList.add(j === c ? 'right' : 'dim');
      if (theirs && j === theirs.choice) b.append(mk('span', 'qd-opp-pick', game.opp.name));
    });
    const me = mine.choice === c ? `Correct! +${mine.pts}` : mine.choice < 0 ? 'Time\'s up.' : 'Wrong.';
    const op = !theirs ? '' : theirs.choice === -2 ? ` · ${game.opp.name} got ${theirs.pts} here.`
      : ` · ${game.opp.name}: ${theirs.choice === c ? '+' + theirs.pts : theirs.choice < 0 ? 'no answer' : 'wrong'}`;
    $q('qd-status').textContent = me + op;
  }
  function finish() {
    clearTimers();
    const me = game.me.score, op = game.opp.score;
    if (game.mode === 'solo') {
      const code = 'QD-' + b64(JSON.stringify({ v: 1, q: game.quizId, h: game.sha.slice(0, 10), s: game.seed, t: game.time, m: game.me.name, p: game.me.pts }));
      $q('qd-chalcode').textContent = code; $q('qd-share').hidden = false;
      const msg = `I challenge you in Questrig! "${game.title}", ${game.questions.length} questions, I scored ${me}. Duel → accept a challenge and paste this code:\n${code}`;
      showEnd(`${me} points`, 'Send the code to someone. Can they beat you?', [['Copy code with message', 'solid', () => copy(msg)], ['Copy code only', '', () => copy(code)], ['Done', '', closeGame]]);
      return;
    }
    const title = me > op ? 'You win! 🏆' : me < op ? `${game.opp.name} wins` : 'Draw';
    const actions = game.mode === 'host' ? [['Rematch', 'solid', hostStartDuel], ['Finish', '', () => { leave(); closeGame(); }]]
      : game.mode === 'guest' ? [['Finish', '', () => { leave(); closeGame(); }]] : [['Done', 'solid', closeGame]];
    showEnd(title, `${game.me.name} ${me} : ${op} ${game.opp.name}`, actions);
  }
  function showEnd(title, sub, actions) {
    $q('qd-play').hidden = true; $q('qd-end').hidden = false;
    $q('qd-end-title').textContent = title; $q('qd-end-score').textContent = sub;
    const box = $q('qd-end-actions'); box.textContent = '';
    for (const [label, cls, fn] of actions) box.append(button(label, cls, fn));
  }
  function closeGame() { clearTimers(); game = null; $q('qd-game').classList.add('hidden'); }

  $q('qd-host').onclick = async () => {
    liveErr('');
    if (typeof Peer === 'undefined') { liveErr('Live duels could not load.'); return; }
    try {
      const pool = await loadPool();
      settings = { pool, n: Math.min(+$q('qd-dn').value || 10, pool.questions.length), time: +$q('qd-dtime').value };
      $q('qd-copy-code').hidden = false; hostCreate();
    } catch (e) { liveErr(errText(e)); }
  };
  $q('qd-join').onclick = () => {
    liveErr('');
    const code = $q('qd-code').value.trim().toUpperCase();
    if (!/^[A-Z0-9]{5}$/.test(code)) { liveErr('The code has 5 characters, e.g. K7P2Q.'); return; }
    if (typeof Peer === 'undefined') { liveErr('Live duels could not load.'); return; }
    guestJoin(code);
  };
  $q('qd-code').addEventListener('keydown', e => { if (e.key === 'Enter') $q('qd-join').click(); });
  $q('qd-start').onclick = () => { $q('qd-start').hidden = true; hostStartDuel(); };
  $q('qd-leave').onclick = leave;
  $q('qd-copy-code').onclick = () => copy(`Duel me in Questrig! Duel → join with code: ${$q('qd-lobby-code').textContent}`);
  $q('qd-solo').onclick = async () => {
    $q('qd-chal-err').textContent = '';
    try {
      const pool = await loadPool(), seed = crypto.getRandomValues(new Uint32Array(1))[0];
      const n = Math.min(+$q('qd-dn').value || 10, pool.questions.length);
      role = 'solo';
      startGame({ mode: 'solo', title: pool.title, questions: makeRound(pool, n, seed), time: +$q('qd-dtime').value });
      Object.assign(game, { quizId: pool.id, sha: pool.sha, seed });
      later(() => ask(0), 900);
    } catch (e) { $q('qd-chal-err').textContent = errText(e); }
  };
  $q('qd-accept').onclick = async () => {
    const err = $q('qd-chal-err'); err.textContent = '';
    const m = /QD-([A-Za-z0-9_-]+)/.exec($q('qd-chal').value);
    let c;
    try { c = JSON.parse(unb64(m[1])); } catch { err.textContent = 'That isn\'t a valid challenge code. Copy all of it; it starts with QD-.'; return; }
    const q = library.find(x => x.id === c.q);
    if (!q || !q.duelSha) { err.textContent = 'You need a quiz you don\'t have yet. Download it under Browse.'; return; }
    if (!q.duelSha.startsWith(str(c.h, 10))) { err.textContent = 'You have different versions of this quiz. Both of you: update it under Browse.'; return; }
    try {
      const pool = await loadPool(q.id), p = Array.isArray(c.p) ? c.p.slice(0, 30).map(x => x | 0) : [];
      role = 'challenge';
      startGame({ mode: 'challenge', title: pool.title, questions: makeRound(pool, p.length, c.s >>> 0), time: Math.min(90, Math.max(5, +c.t || 20)), oppName: str(c.m, 20) || 'Challenger', target: { p } });
      later(() => ask(0), 900);
    } catch (e) { err.textContent = errText(e); }
  };
  $q('qd-quit').onclick = () => { if (role === 'host' || role === 'guest') leave(); closeGame(); };
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && !root.classList.contains('hidden') && $q('qd-game').classList.contains('hidden') && !$q('qd-meta').open) {
      if (!$q('qd-player').classList.contains('hidden')) $q('qd-player-close').click(); else close();
      return;
    }
    if ($q('qd-game').classList.contains('hidden') || !game || /INPUT|SELECT|TEXTAREA/.test(e.target.tagName)) return;
    const k = '1234'.indexOf(e.key);
    if (k >= 0) answer(k);
  });
  try { $q('qd-name').value = localStorage.getItem('qd-name') || ''; } catch {}
  $q('qd-name').addEventListener('input', () => { try { localStorage.setItem('qd-name', $q('qd-name').value); } catch {} });

  // ---------- widget on the dashboard ----------
  const w = document.querySelector('[data-w="quiz"]');
  if (w) {
    w.querySelector('#qdOpen').onclick = () => open('mine');
    w.querySelector('#qdDuel').onclick = () => open('duel');
    w.querySelector('#qdBrowse').onclick = () => open('find');
  }

  (async () => {
    try { await seedBundled(); } catch (e) { console.error('QuizDesk: bundled quizzes', e); }
    await refreshLibrary();
    renderAll();
    loadCatalog();
  })();
  window.quizdesk = { open, close };
})();
