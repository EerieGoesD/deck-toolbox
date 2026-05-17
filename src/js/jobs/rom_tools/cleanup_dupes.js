registerJobs({
  cleanupDupes: {
    title: 'Cleanup Duplicate ROMs',
    severity: 'destructive',
    label: 'Deletes files (with dry-run option)',
    body: `Finds ROMs that exist as REAL files on BOTH internal storage and the SD card (usually a sign that an earlier rebalance was interrupted). With "Apply" the internal-side copy is removed; the SD-side copy is kept because ES-DE typically scans the SD root.<br><br><div class="confirm-form"><label class="confirm-form-label">Internal root:</label><input type="text" id="cleanupInternal" class="confirm-input"><label class="confirm-form-label">SD card root:</label><input type="text" id="cleanupSd" class="confirm-input"><label class="confirm-checkbox"><input type="checkbox" id="cleanupApply"> Apply (uncheck = dry-run scan only)</label></div>`,
    action: () => runCleanupDupes(),
    onOpen: () => {
      const i = document.getElementById('cleanupInternal');
      const s = document.getElementById('cleanupSd');
      if (i) i.value = '/home/deck/Emulation/roms';
      if (s) s.value = '/run/media/deck/EmuDeck/Emulation/roms';
      const apply = document.getElementById('cleanupApply');
      if (apply) apply.checked = false;
    }
  }
});

async function runCleanupDupes() {
  const internalRoot = document.getElementById('cleanupInternal')?.value.trim() || '/home/deck/Emulation/roms';
  const sdRoot = document.getElementById('cleanupSd')?.value.trim() || '/run/media/deck/EmuDeck/Emulation/roms';
  const apply = document.getElementById('cleanupApply')?.checked === true;
  const mode = apply ? 'apply' : 'scan';
  disableBtn('btnCleanupDupes');
  openTerminal('Cleanup Duplicate ROMs');
  appendTerminal(`Mode: ${mode}\nInternal: ${internalRoot}\nSD: ${sdRoot}\n\n`);
  try {
    const result = await invoke('cleanup_dupes', { mode, internalRoot, sdRoot });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnCleanupDupes');
}
