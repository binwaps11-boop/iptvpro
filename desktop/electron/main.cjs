/*
 * غلاف Electron — يحوّل التطبيق إلى برنامج قابل للتثبيت على ويندوز/ماك/لينكس.
 * يشغّل خادم Node الداخلي ثم يفتح نافذة سطح مكتب تعرض الواجهة.
 *
 * البناء (على جهاز المستخدم، يتطلب إنترنت لتثبيت الحزم):
 *   cd desktop/electron
 *   npm install
 *   npm run dist      # ينتج مثبِّتاً في مجلد electron/out أو dist
 */
const { app, BrowserWindow, shell } = require('electron');
const path = require('node:path');
const { fork } = require('node:child_process');

const PORT = process.env.PORT || 2222;
let serverProc = null;

function startServer() {
  // يشغّل ../server.js كعملية فرعية
  serverProc = fork(path.join(__dirname, '..', 'server.js'), [], {
    env: { ...process.env, PORT: String(PORT) },
    stdio: 'inherit',
  });
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    backgroundColor: '#0b1020',
    title: 'IPTV Pro',
    autoHideMenuBar: true,
    webPreferences: { contextIsolation: true },
  });
  // افتح الروابط الخارجية في المتصفح لا داخل النافذة
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
  const load = () => win.loadURL(`http://localhost:${PORT}`).catch(() => setTimeout(load, 500));
  setTimeout(load, 800);
}

app.whenReady().then(() => {
  startServer();
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (serverProc) serverProc.kill();
  if (process.platform !== 'darwin') app.quit();
});
