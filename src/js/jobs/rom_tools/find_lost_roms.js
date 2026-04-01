registerJobs({
  lostRoms: {
    title: 'Find Lost ROMs',
    severity: 'safe',
    label: 'Read-only scan',
    body: `Searches for ROM files outside of your known ROM directories. Any ROMs found elsewhere are reported as potentially lost.<br><br><strong>Nothing is deleted</strong> - this only reports what it finds.<br><div class="confirm-form"><label style="min-width:0;color:var(--text);font-size:13px;">Known ROM paths (excluded from results):</label><div class="path-list" id="lostRomPaths"></div><button class="path-add" onclick="addLostRomPath()">+ Add path</button></div>`,
    action: () => runFindLostRoms(),
    onOpen: () => {
      const list = document.getElementById('lostRomPaths');
      list.innerHTML = '';
      ['/run/media/deck/EmuDeck/Emulation/roms', '/home/deck/Emulation/roms'].forEach(p => addLostRomPathValue(p));
    }
  }
});

async function runFindLostRoms() {
  const paths = getPathsFromList('lostRomPaths');
  disableBtn('btnLostRoms');
  openTerminal('Find Lost ROMs');
  if (paths.length > 0) appendTerminal('Excluding: ' + paths.join(', ') + '\n');
  appendTerminal('Searching for lost ROMs...\n\n');
  try {
    const result = await invoke('find_lost_roms', { paths });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnLostRoms');
}
