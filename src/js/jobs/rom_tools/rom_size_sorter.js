registerJobs({
  romSort: {
    title: 'ROM Size Sorter',
    severity: 'safe',
    label: 'Read-only scan',
    body: `Lists every ROM file sorted by size (largest first). Useful for identifying which games take up the most space.<br><br><strong>Nothing is deleted</strong> - this only reports what it finds.<br><div class="confirm-form"><label style="min-width:0;color:var(--text);font-size:13px;">ROM directories to scan:</label><div class="path-list" id="romSortPaths"></div><button class="path-add" onclick="addRomSortPath()">+ Add path</button></div>`,
    action: () => runRomSizeSorter(),
    onOpen: () => {
      const list = document.getElementById('romSortPaths');
      list.innerHTML = '';
      ['/run/media/deck/EmuDeck/Emulation/roms', '/home/deck/Emulation/roms'].forEach(p => addRomSortPathValue(p));
    }
  }
});

async function runRomSizeSorter() {
  const paths = getPathsFromList('romSortPaths');
  disableBtn('btnRomSort');
  openTerminal('ROM Size Sorter');
  appendTerminal('Scanning ROMs...\n');
  try {
    const result = await invoke('rom_size_sorter', { paths });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnRomSort');
}
