const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('toolbox', {
  generateCue: () => ipcRenderer.invoke('generate-cue'),
  runMaintenance: () => ipcRenderer.invoke('run-maintenance'),
  steamReset: () => ipcRenderer.invoke('steam-reset'),
  gamescopeReset: () => ipcRenderer.invoke('gamescope-reset'),
  fullRecovery: () => ipcRenderer.invoke('full-recovery')
});
