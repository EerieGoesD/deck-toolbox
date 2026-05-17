registerJobs({
  fixRomPaths: {
    title: 'Fix ROM Paths',
    severity: 'destructive',
    label: 'Moves files within each disk (with dry-run option)',
    body: `Finds ROMs sitting in the wrong system folder using majority-rule extension detection (eg a .sms file in gamegear/ that should be in mastersystem/). With "Apply", flagged files are moved to the suggested folder on the SAME disk via mv (instant, no copy).<br><br><div class="confirm-form"><label class="confirm-form-label">ROM roots:</label><div class="path-list" id="fixPathsRoots"></div><button class="path-add" data-action="addFixPathsRoot">+ Add path</button><label class="confirm-checkbox"><input type="checkbox" id="fixPathsApply"> Apply (uncheck = dry-run scan only)</label></div>`,
    action: () => runFixRomPaths(),
    onOpen: () => {
      const list = document.getElementById('fixPathsRoots');
      if (list) {
        list.innerHTML = '';
        ['/home/deck/Emulation/roms', '/run/media/deck/EmuDeck/Emulation/roms'].forEach(p => addFixPathsRootValue(p));
      }
      const apply = document.getElementById('fixPathsApply');
      if (apply) apply.checked = false;
    }
  }
});

async function runFixRomPaths() {
  const paths = getPathsFromList('fixPathsRoots');
  const apply = document.getElementById('fixPathsApply')?.checked === true;
  const mode = apply ? 'apply' : 'scan';
  disableBtn('btnFixRomPaths');
  openTerminal('Fix ROM Paths');
  appendTerminal(`Mode: ${mode}\nPaths: ${paths.join(', ')}\n\n`);
  try {
    const result = await invoke('fix_rom_paths', { mode, paths });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnFixRomPaths');
}
