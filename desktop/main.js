// OmniGameDesk for macOS and Linux: an Electron window around the same dashboard the Windows version uses.
const { app, BrowserWindow, shell, safeStorage, nativeTheme, Menu, Notification } = require('electron');
const fs = require('fs');
const path = require('path');
const server = require('./server');

// OmniGameDesk used to be called GameDesk: keep its saved data (widgets, notes, the Claude key).
const oldData = path.join(app.getPath('appData'), 'GameDesk');
if (fs.existsSync(oldData) && !fs.existsSync(app.getPath('userData'))) { try { fs.renameSync(oldData, app.getPath('userData')); } catch {} }

if (!app.requestSingleInstanceLock()) { app.quit(); return; }

let win, srv;
app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });

app.whenReady().then(async () => {
  nativeTheme.themeSource = 'dark';   // dark (black) title bar and menus
  const uiDir = app.isPackaged ? path.join(process.resourcesPath, 'ui') : path.join(__dirname, '..', 'OmniGameDesk');
  const secret = safeStorage.isEncryptionAvailable() ? { encrypt: s => safeStorage.encryptString(s), decrypt: b => safeStorage.decryptString(b) } : null;
  const notify = (title, body) => { if (Notification.isSupported()) { const n = new Notification({ title, body }); n.on('click', () => { if (win) { win.show(); win.focus(); } }); n.show(); } };
  srv = await server.start({ uiDir, dataDir: app.getPath('userData'), secret, openUrl: u => shell.openExternal(u), notify });

  if (process.platform !== 'darwin') Menu.setApplicationMenu(null);
  win = new BrowserWindow({
    width: 1500, height: 960, minWidth: 900, minHeight: 600,
    title: 'OmniGameDesk', backgroundColor: '#000000', autoHideMenuBar: true,
    icon: path.join(uiDir, 'logo.png'),
    webPreferences: { contextIsolation: true, sandbox: true, nodeIntegration: false },
  });
  win.webContents.setWindowOpenHandler(({ url }) => { if (url.startsWith('https://')) shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('http://127.0.0.1:')) e.preventDefault(); });
  win.loadURL(srv.url);
});

app.on('window-all-closed', () => app.quit());
app.on('will-quit', () => { if (srv) srv.close(); });   // also stops Ollama if OmniGameDesk started it
