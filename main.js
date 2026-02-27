const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 740,
    minWidth: 600,
    minHeight: 500,
    backgroundColor: '#0a0a0f',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  mainWindow.loadFile('index.html');
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => app.quit());

// ── Helpers ──

function scriptsDir() {
  // Works both in dev and packaged
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'app', 'scripts');
  }
  return path.join(__dirname, 'scripts');
}

function runScript(scriptName, args = []) {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(scriptsDir(), scriptName);

    // Make sure script is executable
    try { fs.chmodSync(scriptPath, 0o755); } catch {}

    const proc = spawn('bash', [scriptPath, ...args], {
      env: { ...process.env, HOME: os.homedir() },
      cwd: os.homedir()
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', d => { stdout += d.toString(); });
    proc.stderr.on('data', d => { stderr += d.toString(); });

    proc.on('close', code => {
      resolve({ code, stdout, stderr });
    });

    proc.on('error', err => {
      reject(err);
    });
  });
}

// ── IPC Handlers ──

// Button 1: Generate .cue from .bin — user picks a .bin file
ipcMain.handle('generate-cue', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Select .bin file(s)',
    filters: [{ name: 'BIN files', extensions: ['bin'] }],
    properties: ['openFile', 'multiSelections']
  });

  if (result.canceled || result.filePaths.length === 0) {
    return { canceled: true };
  }

  const results = [];

  for (const binPath of result.filePaths) {
    const cuePath = binPath.replace(/\.bin$/i, '.cue');
    const binFilename = path.basename(binPath);

    if (fs.existsSync(cuePath)) {
      results.push({ file: binFilename, status: 'skipped', msg: '.cue already exists' });
      continue;
    }

    const cueContent = `FILE "${binFilename}" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n`;

    try {
      fs.writeFileSync(cuePath, cueContent, 'utf8');
      results.push({ file: binFilename, status: 'ok', msg: `Created ${path.basename(cuePath)}` });
    } catch (err) {
      results.push({ file: binFilename, status: 'error', msg: err.message });
    }
  }

  return { canceled: false, results };
});

// Button 2: Run weekly maintenance
ipcMain.handle('run-maintenance', async () => {
  return runScript('maintenance.sh');
});

// Button 3: Steam reset (rename dir)
ipcMain.handle('steam-reset', async () => {
  return runScript('steam-reset.sh');
});

// Button 4: Gamescope reset
ipcMain.handle('gamescope-reset', async () => {
  return runScript('gamescope-reset.sh');
});

// Button 5: Full recovery (steam + gamescope)
ipcMain.handle('full-recovery', async () => {
  return runScript('full-recovery.sh');
});
