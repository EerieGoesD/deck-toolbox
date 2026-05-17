registerJobs({
  romFinder: {
    title: 'ROM Finder',
    severity: 'safe',
    label: 'Read-only search',
    body: `Search your ROM library across internal storage and the SD card for a specific game or filename. Reports the location and type (real file vs symlink) of each match.<br><br><div class="confirm-form"><label class="confirm-form-label">Search term:</label><input type="text" id="romFinderSearch" class="confirm-input" placeholder="e.g. Mario, snes/, .chd" autocomplete="off"><label class="confirm-form-label">Search paths:</label><div class="path-list" id="romFinderPaths"></div><button class="path-add" data-action="addRomFinderPath">+ Add path</button></div>`,
    action: () => runRomFinder(),
    onOpen: () => {
      const list = document.getElementById('romFinderPaths');
      if (list) {
        list.innerHTML = '';
        ['/home/deck/Emulation/roms', '/run/media/deck/EmuDeck/Emulation/roms'].forEach(p => addRomFinderPathValue(p));
      }
      const search = document.getElementById('romFinderSearch');
      if (search) { search.value = ''; setTimeout(() => search.focus(), 50); }
    }
  }
});

async function runRomFinder() {
  const searchEl = document.getElementById('romFinderSearch');
  const search = (searchEl?.value || '').trim();
  if (!search) {
    alert('Enter a search term first.');
    return;
  }
  const paths = getPathsFromList('romFinderPaths');
  disableBtn('btnRomFinder');
  openTerminal('ROM Finder');
  appendTerminal(`Searching for "${search}"...\n`);
  if (paths.length > 0) appendTerminal('Paths: ' + paths.join(', ') + '\n\n');
  try {
    const result = await invoke('rom_finder', { search, paths });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnRomFinder');
}
