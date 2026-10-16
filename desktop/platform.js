// Everything that differs between macOS and Linux: stats, Spotify, installed apps, tools.
// The Windows version of GameDesk is GameDesk/GameDesk.ps1; this file is for the Mac/Linux app.
const os = require('os');
const fs = require('fs');
const path = require('path');
const { execFile, spawn } = require('child_process');

const isMac = process.platform === 'darwin';
const home = os.homedir();

function run(cmd, args, timeout = 3000) {
  return new Promise(resolve => {
    execFile(cmd, args, { timeout, windowsHide: true }, (err, stdout) => resolve(err ? null : String(stdout)));
  });
}
function detach(cmd, args = []) {
  try { spawn(cmd, args, { detached: true, stdio: 'ignore' }).unref(); return true; } catch { return false; }
}
const pathDirs = (process.env.PATH || '').split(path.delimiter).concat(['/usr/bin', '/usr/local/bin', '/bin', '/snap/bin', '/opt/homebrew/bin']);
const which = bin => pathDirs.some(d => { try { fs.accessSync(path.join(d, bin), fs.constants.X_OK); return true; } catch { return false; } });
const osa = script => run('osascript', ['-e', script]);

// ---------- system stats ----------
let prevCpu = null;
function cpuPct() {
  const t = os.cpus().reduce((a, c) => { const tot = Object.values(c.times).reduce((x, y) => x + y, 0); a.idle += c.times.idle; a.total += tot; return a; }, { idle: 0, total: 0 });
  const p = prevCpu; prevCpu = t;
  if (!p || t.total === p.total) return 0;
  return Math.round(1000 * (1 - (t.idle - p.idle) / (t.total - p.total))) / 10;
}
async function memAvailable() {
  if (isMac) {
    const out = await run('vm_stat', []);
    if (out) {
      const size = +(out.match(/page size of (\d+)/) || [0, 4096])[1];
      const pages = k => +((out.match(new RegExp(k + ':\\s+(\\d+)')) || [0, 0])[1]);
      return (pages('Pages free') + pages('Pages inactive') + pages('Pages speculative') + pages('Pages purgeable')) * size;
    }
  } else {
    try { return +fs.readFileSync('/proc/meminfo', 'utf8').match(/MemAvailable:\s+(\d+)/)[1] * 1024; } catch {}
  }
  return os.freemem();
}
async function battery() {
  const none = { hasBattery: false, pct: 0, plugged: true, charging: false, minutesLeft: null, saver: false };
  if (isMac) {
    const out = await run('pmset', ['-g', 'batt']);
    const m = out && out.match(/(\d+)%;\s*([^;]+);\s*(\d+:\d+)?/);
    if (!m) return none;
    const state = m[2].trim();
    const [h, mi] = (m[3] || '').split(':').map(Number);
    return { hasBattery: true, pct: +m[1], plugged: /AC Power/.test(out), charging: state === 'charging', minutesLeft: m[3] && !isNaN(h) && (h || mi) ? h * 60 + mi : null, saver: false };
  }
  try {
    const base = '/sys/class/power_supply';
    const devs = fs.readdirSync(base).map(d => path.join(base, d));
    const read = (d, f) => { try { return fs.readFileSync(path.join(d, f), 'utf8').trim(); } catch { return ''; } };
    const bat = devs.find(d => read(d, 'type') === 'Battery' && read(d, 'present') !== '0');
    if (!bat) return none;
    const ac = devs.find(d => read(d, 'type') === 'Mains');
    const status = read(bat, 'status');
    const now = +read(bat, 'energy_now') || +read(bat, 'charge_now'), rate = +read(bat, 'power_now') || +read(bat, 'current_now');
    return {
      hasBattery: true, pct: +read(bat, 'capacity'), plugged: ac ? read(ac, 'online') === '1' : status !== 'Discharging',
      charging: status === 'Charging', minutesLeft: status === 'Discharging' && now && rate ? Math.round(60 * now / rate) : null, saver: false,
    };
  } catch { return none; }
}
async function stats() {
  const total = os.totalmem(), avail = await memAvailable();
  let diskFree = 0, diskTotal = 0;
  try { const s = fs.statfsSync(isMac && fs.existsSync('/System/Volumes/Data') ? '/System/Volumes/Data' : '/'); diskFree = s.bavail * s.bsize; diskTotal = s.blocks * s.bsize; } catch {}
  const GB = 1024 ** 3;
  return {
    cpu: cpuPct(),
    ramUsed: Math.round((total - avail) / GB * 10) / 10, ramTotal: Math.round(total / GB * 10) / 10, ramPct: Math.round(100 * (total - avail) / total),
    diskFree: Math.round(diskFree / GB), diskTotal: Math.round(diskTotal / GB) || 1,
    uptimeMin: Math.floor(os.uptime() / 60),
    battery: await battery(),
  };
}

// ---------- Spotify ----------
const art = { key: '', bytes: null, type: 'image/jpeg' };
let spotifyHidden = false;
const mpris = ['--session', '--dest', 'org.mpris.MediaPlayer2.spotify', '--object-path', '/org/mpris/MediaPlayer2'];
async function spotifyRunning() { return !!(await run('pgrep', ['-x', isMac ? 'Spotify' : 'spotify'])) || (!isMac && !!(await run('pgrep', ['-f', 'spotify/spotify']))); }

async function spotifyNow() {
  let now = null, artUrl = '';
  if (isMac) {
    const out = await osa('if application "Spotify" is running then tell application "Spotify" to return (name of current track) & linefeed & (artist of current track) & linefeed & (album of current track) & linefeed & (player state as string) & linefeed & (artwork url of current track)');
    if (out && out.trim()) {
      const [title, artist, album, state, url] = out.replace(/\n$/, '').split('\n');
      now = { title, artist, album, status: state === 'playing' ? 'Playing' : 'Paused' }; artUrl = url || '';
    }
  } else {
    const meta = await run('gdbus', ['call', ...mpris, '--method', 'org.freedesktop.DBus.Properties.Get', 'org.mpris.MediaPlayer2.Player', 'Metadata'], 1500);
    if (meta) {
      const str = k => { const m = meta.match(new RegExp(`'${k}': <\\[?(['"])((?:\\\\.|(?!\\1).)*)\\1`)); return m ? m[2].replace(/\\(.)/g, '$1') : ''; };
      const st = await run('gdbus', ['call', ...mpris, '--method', 'org.freedesktop.DBus.Properties.Get', 'org.mpris.MediaPlayer2.Player', 'PlaybackStatus'], 1500);
      now = { title: str('xesam:title'), artist: str('xesam:artist'), album: str('xesam:album'), status: /Playing/.test(st || '') ? 'Playing' : 'Paused' };
      artUrl = str('mpris:artUrl').replace('open.spotify.com/image', 'i.scdn.co/image');
    }
  }
  if (!now || !now.title) return null;
  const key = now.artist + '|' + now.title;
  if (art.key !== key) {
    art.key = key; art.bytes = null;
    if (/^https:\/\//.test(artUrl)) {
      fetch(artUrl).then(async r => { if (r.ok && art.key === key) { art.bytes = Buffer.from(await r.arrayBuffer()); art.type = r.headers.get('content-type') || 'image/jpeg'; } }).catch(() => {});
    }
  }
  now.art = art.bytes && art.key === key ? String(Math.abs([...key].reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 7))) : null;
  return now;
}
async function spotifyStats() {
  const running = await spotifyRunning();
  if (!running) spotifyHidden = false;
  return { running, title: '', now: running ? await spotifyNow().catch(() => null) : null, hidden: running && spotifyHidden, canHide: isMac };
}
async function spotifyControl(k) {
  if (isMac) {
    const cmd = { playpause: 'playpause', next: 'next track', prev: 'previous track' }[k];
    return !!(await osa(`tell application "Spotify" to ${cmd}`));
  }
  const m = { playpause: 'PlayPause', next: 'Next', prev: 'Previous' }[k];
  return !!(await run('gdbus', ['call', ...mpris, '--method', 'org.mpris.MediaPlayer2.Player.' + m]));
}
const sleep = ms => new Promise(r => setTimeout(r, ms));
// Starts Spotify in the background and begins playback. Reports through a job (polled by the page).
async function spotifyStart(job) {
  try {
    if (isMac) {
      await run('open', ['-g', '-j', '-a', 'Spotify']);
      spotifyHidden = true;
    } else if (!launchApp('Spotify')) throw new Error('Spotify isn\'t installed');
    const deadline = Date.now() + 30000;
    let ready = false;
    while (Date.now() < deadline && !ready) {
      await sleep(700);
      ready = isMac ? (await osa('if application "Spotify" is running then tell application "Spotify" to return player state as string')) !== null && await spotifyRunning()
        : !!(await run('gdbus', ['call', ...mpris, '--method', 'org.freedesktop.DBus.Properties.Get', 'org.mpris.MediaPlayer2.Player', 'PlaybackStatus']));
    }
    if (!ready) { job.text = 'started'; return; }
    for (let i = 0; i < 6; i++) {
      await sleep(800);
      if (isMac) await osa('tell application "Spotify" to play'); else await run('gdbus', ['call', ...mpris, '--method', 'org.mpris.MediaPlayer2.Player.Play']);
      const now = await spotifyNow();
      if (now && now.status === 'Playing') { job.text = 'playing'; break; }
    }
    if (job.text !== 'playing') job.error = 'Spotify started, but there was no song ready to play. Click "Show app" and pick a song once.';
  } catch (e) { job.error = e.message; } finally { job.done = true; }
}
async function spotifyShow() {
  spotifyHidden = false;
  if (isMac) return run('open', ['-a', 'Spotify']);
  launchApp('Spotify');
}
async function spotifyHide() {
  if (!isMac) return;
  await osa('tell application "System Events" to set visible of process "Spotify" to false');
  spotifyHidden = true;
}

// ---------- volume ----------
async function volume(k) {
  if (isMac) {
    const s = { volup: 'set volume output volume ((output volume of (get volume settings)) + 6)', voldown: 'set volume output volume ((output volume of (get volume settings)) - 6)',
      mute: 'set volume output muted (not (output muted of (get volume settings)))' }[k];
    return osa(s);
  }
  if (which('wpctl')) return run('wpctl', k === 'mute' ? ['set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle'] : ['set-volume', '-l', '1.0', '@DEFAULT_AUDIO_SINK@', k === 'volup' ? '5%+' : '5%-']);
  if (which('pactl')) return run('pactl', k === 'mute' ? ['set-sink-mute', '@DEFAULT_SINK@', 'toggle'] : ['set-sink-volume', '@DEFAULT_SINK@', k === 'volup' ? '+5%' : '-5%']);
  if (which('amixer')) return run('amixer', ['-q', 'set', 'Master', k === 'mute' ? 'toggle' : k === 'volup' ? '5%+' : '5%-']);
}

// ---------- installed apps ----------
// Display name -> macOS app bundle names / Linux .desktop ids (Flatpak and Snap included).
const APPS = {
  Steam: [['Steam'], ['steam', 'com.valvesoftware.Steam', 'steam_steam']],
  Spotify: [['Spotify'], ['spotify', 'com.spotify.Client', 'spotify_spotify', 'spotify-client']],
  Discord: [['Discord'], ['discord', 'com.discordapp.Discord', 'discord_discord']],
  'Epic Games Launcher': [['Epic Games Launcher'], []],
  'Battle.net': [['Battle.net'], []],
  'EA app': [['EA app'], []],
  'GOG GALAXY': [['GOG Galaxy'], []],
  'Riot Client': [['Riot Client'], []],
  'OBS Studio': [['OBS'], ['com.obsproject.Studio', 'obs', 'obs-studio_obs-studio']],
  Heroic: [['Heroic'], ['heroic', 'com.heroicgameslauncher.hgl']],
  Lutris: [[], ['net.lutris.Lutris', 'lutris']],
  WhatsApp: [['WhatsApp'], []],
  Claude: [['Claude'], []],
  'Google Chrome': [['Google Chrome'], ['google-chrome', 'com.google.Chrome']],
  'Microsoft Teams': [['Microsoft Teams'], []],
};
const desktopDirs = [
  '/usr/share/applications', '/usr/local/share/applications', path.join(home, '.local/share/applications'),
  '/var/lib/flatpak/exports/share/applications', path.join(home, '.local/share/flatpak/exports/share/applications'), '/var/lib/snapd/desktop/applications',
];
const found = {};
function scanApps() {
  for (const [name, [macApps, linuxIds]] of Object.entries(APPS)) {
    if (isMac) {
      for (const a of macApps) {
        const p = ['/Applications', path.join(home, 'Applications')].map(d => path.join(d, a + '.app')).find(p => fs.existsSync(p));
        if (p) { found[name] = p; break; }
      }
    } else {
      for (const id of linuxIds) {
        const p = desktopDirs.map(d => path.join(d, id + '.desktop')).find(p => fs.existsSync(p));
        if (p) { found[name] = p; break; }
      }
    }
  }
  return Object.keys(found).sort();
}
function launchApp(name) {
  const p = found[name];
  if (!p) return false;
  if (isMac) return detach('open', ['-a', p]);
  if (which('gio')) return detach('gio', ['launch', p]);
  if (which('gtk-launch')) return detach('gtk-launch', [path.basename(p, '.desktop')]);
  const exec = (fs.readFileSync(p, 'utf8').match(/^Exec=(.*)$/m) || [])[1];
  if (!exec) return false;
  const parts = exec.replace(/%[a-zA-Z]/g, '').trim().split(/\s+/);
  return detach(parts[0], parts.slice(1));
}

// ---------- Steam games ----------
function steamGames() {
  const roots = isMac ? [path.join(home, 'Library/Application Support/Steam')]
    : [path.join(home, '.steam/steam'), path.join(home, '.local/share/Steam'), path.join(home, '.var/app/com.valvesoftware.Steam/.local/share/Steam'), path.join(home, 'snap/steam/common/.local/share/Steam')];
  const libs = new Set(), games = {};
  for (const r of roots) {
    if (!fs.existsSync(r)) continue;
    libs.add(fs.realpathSync(r));
    try {
      const vdf = fs.readFileSync(path.join(r, 'steamapps/libraryfolders.vdf'), 'utf8');
      for (const m of vdf.matchAll(/"path"\s+"([^"]+)"/g)) libs.add(m[1].replace(/\\\\/g, '\\'));
    } catch {}
  }
  for (const lib of libs) {
    let files = [];
    try { files = fs.readdirSync(path.join(lib, 'steamapps')).filter(f => /^appmanifest_\d+\.acf$/.test(f)); } catch { continue; }
    for (const f of files) {
      try {
        const t = fs.readFileSync(path.join(lib, 'steamapps', f), 'utf8');
        const id = (t.match(/"appid"\s+"(\d+)"/) || [])[1], name = (t.match(/"name"\s+"([^"]+)"/) || [])[1];
        if (id && name && !/Redistributable|Steamworks|Proton|Runtime/.test(name)) games[id] = name;
      } catch {}
    }
  }
  return Object.entries(games).map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name));
}

// ---------- quick tools ----------
// Each tool: a label (shown instead of the Windows name) and candidate commands; the first one installed is used.
const mac = (label, ...cmd) => ({ label, cmds: [cmd] });
const pane = id => 'x-apple.systempreferences:' + id;
const MAC_TOOLS = {
  taskmgr: mac('Activity Monitor', 'open', '-a', 'Activity Monitor'),
  settings: mac('Settings', 'open', pane('')),
  explorer: mac('Finder', 'open', home),
  downloads: mac('Downloads', 'open', path.join(home, 'Downloads')),
  calc: mac('Calculator', 'open', '-a', 'Calculator'),
  snip: mac('Screenshot', 'open', '-a', 'Screenshot'),
  sound: mac('Sound', 'open', pane('com.apple.Sound-Settings.extension')),
  display: mac('Display', 'open', pane('com.apple.Displays-Settings.extension')),
  power: mac('Power', 'open', pane('com.apple.Battery-Settings.extension')),
  battery: mac('Battery', 'open', pane('com.apple.Battery-Settings.extension')),
  bluetooth: mac('Bluetooth', 'open', pane('com.apple.BluetoothSettings')),
  wifi: mac('Wi-Fi', 'open', pane('com.apple.wifi-settings-extension')),
  update: mac('Update', 'open', pane('com.apple.Software-Update-Settings.extension')),
  lock: mac('Lock', 'pmset', 'displaysleepnow'),
};
const gcc = p => ['gnome-control-center', p];
const kcm = p => ['systemsettings', p];
const LINUX_TOOLS = {
  taskmgr: { label: 'System Monitor', cmds: [['gnome-system-monitor'], ['plasma-systemmonitor'], ['ksysguard'], ['xfce4-taskmanager'], ['mate-system-monitor']] },
  settings: { label: 'Settings', cmds: [['gnome-control-center'], ['systemsettings'], ['xfce4-settings-manager'], ['cinnamon-settings']] },
  explorer: { label: 'Files', cmds: [['xdg-open', home]] },
  downloads: { label: 'Downloads', cmds: [['xdg-open', path.join(home, 'Downloads')]] },
  calc: { label: 'Calculator', cmds: [['gnome-calculator'], ['kcalc'], ['galculator'], ['mate-calc'], ['qalculate-gtk']] },
  snip: { label: 'Screenshot', cmds: [['gnome-screenshot', '-i'], ['spectacle'], ['flameshot', 'gui'], ['xfce4-screenshooter']] },
  sound: { label: 'Sound', cmds: [gcc('sound'), kcm('kcm_pulseaudio'), ['pavucontrol']] },
  display: { label: 'Display', cmds: [gcc('display'), kcm('kcm_kscreen')] },
  power: { label: 'Power', cmds: [gcc('power'), kcm('kcm_powerdevilprofilesconfig'), ['xfce4-power-manager-settings']] },
  battery: { label: 'Battery', cmds: [gcc('power'), kcm('kcm_powerdevilprofilesconfig'), ['xfce4-power-manager-settings']] },
  bluetooth: { label: 'Bluetooth', cmds: [gcc('bluetooth'), kcm('kcm_bluetooth'), ['blueman-manager']] },
  wifi: { label: 'Wi-Fi', cmds: [gcc('wifi'), kcm('kcm_networkmanagement'), ['nm-connection-editor']] },
  update: { label: 'Update', cmds: [['gnome-software', '--mode=updates'], ['plasma-discover', '--mode', 'update'], ['update-manager']] },
  lock: { label: 'Lock', cmds: [['loginctl', 'lock-session']] },
};
const TOOLS = isMac ? MAC_TOOLS : LINUX_TOOLS;
const toolCmd = id => (TOOLS[id]?.cmds || []).find(c => which(c[0]));
function availableTools() {
  const ids = Object.keys(TOOLS).filter(id => toolCmd(id));
  if (isMac) ids.push('spotifyshow', 'spotifyhide'); else ids.push('spotifyshow');
  return { tools: ids, toolNames: Object.fromEntries(ids.filter(id => TOOLS[id]).map(id => [id, TOOLS[id].label])) };
}
async function runTool(id) {
  if (id === 'spotifyshow') return spotifyShow();
  if (id === 'spotifyhide') return spotifyHide();
  const c = toolCmd(id);
  if (!c) return false;
  return detach(c[0], c.slice(1));
}

// ---------- Ollama (local AI) ----------
function ollamaInstalled() { return which('ollama') || (isMac && fs.existsSync('/Applications/Ollama.app')); }
// Starts Ollama in the background and returns a function that stops it again (or null if it couldn't start).
function startOllama() {
  if (isMac && fs.existsSync('/Applications/Ollama.app')) return detach('open', ['-g', '-a', 'Ollama']) ? () => osa('quit app "Ollama"') : null;
  if (!which('ollama')) return null;
  try {
    const c = spawn('ollama', ['serve'], { detached: true, stdio: 'ignore' });
    c.on('error', () => {}); c.unref();
    // detached = its own process group, so this also ends the model runner Ollama started.
    return () => { try { process.kill(-c.pid); } catch {} };
  } catch { return null; }
}
// The AI panel's off switch: also stops an Ollama GameDesk didn't start.
function stopAllOllama() {
  if (isMac) osa('quit app "Ollama"');
  run('pkill', ['-x', 'ollama']);
}

module.exports = { isMac, stats, spotifyStats, spotifyControl, spotifyStart, art, volume, scanApps, launchApp, steamGames, availableTools, runTool, ollamaInstalled, startOllama, stopAllOllama };
