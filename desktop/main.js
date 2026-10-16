// GameDesk for macOS and Linux: an Electron window around the same dashboard the Windows version uses.
const { app, BrowserWindow, shell, safeStorage, nativeTheme, Menu } = require('electron');
const path = require('path');
const server = require('./server');

if (!app.requestSingleInstanceLock()) { app.quit(); return; }

let win, srv;
app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });

app.whenReady().then(async () => {
  nativeTheme.themeSource = 'dark';   // dark (black) title bar and menus
  const uiDir = app.isPackaged ? path.join(process.resourcesPath, 'ui') : path.join(__dirname, '..', 'GameDesk');
  const secret = safeStorage.isEncryptionAvailable() ? { encrypt: s => safeStorage.encryptString(s), decrypt: b => safeStorage.decryptString(b) } : null;
  srv = await server.start({ uiDir, dataDir: app.getPath('userData'), secret, openUrl: u => shell.openExternal(u) });

  if (process.platform !== 'darwin') Menu.setApplicationMenu(null);
  win = new BrowserWindow({
    width: 1500, height: 960, minWidth: 900, minHeight: 600,
    title: 'GameDesk', backgroundColor: '#000000', autoHideMenuBar: true,
    icon: path.join(uiDir, 'logo.png'),
    webPreferences: { contextIsolation: true, sandbox: true, nodeIntegration: false },
  });
  win.webContents.setWindowOpenHandler(({ url }) => { if (url.startsWith('https://')) shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('http://127.0.0.1:')) e.preventDefault(); });
  win.loadURL(srv.url);
});

app.on('window-all-closed', () => app.quit());
app.on('will-quit', () => { if (srv) srv.close(); });   // also stops Ollama if GameDesk started it
