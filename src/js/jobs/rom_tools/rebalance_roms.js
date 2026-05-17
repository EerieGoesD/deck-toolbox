registerJobs({
  rebalanceRoms: {
    title: 'Rebalance ROMs',
    severity: 'destructive',
    label: 'Moves files across disks (with dry-run option)',
    body: `Balances disk usage between internal storage and the SD card using a bidirectional, symlink-aware planner. Pick the move strategy: largest-first finishes faster (fewer moves), smallest-first balances more precisely but runs longer. A variety pass moves files back the other way (round-robin across systems) so both disks end up with ROMs from many systems.<br><br><div class="confirm-form"><label class="confirm-form-label">Internal root:</label><input type="text" id="rebalanceInternal" class="confirm-input"><label class="confirm-form-label">SD card root:</label><input type="text" id="rebalanceSd" class="confirm-input"><label class="confirm-form-label">Move strategy:</label><label class="confirm-checkbox"><input type="radio" name="rebalanceStrategy" value="largest" id="rebalanceStrategyLargest"> Largest files first (faster, fewer moves)</label><label class="confirm-checkbox"><input type="radio" name="rebalanceStrategy" value="smallest" id="rebalanceStrategySmallest"> Smallest files first (slower, finer balance)</label><label class="confirm-form-label">Balance threshold (% gap to skip planning):</label><input type="number" id="rebalanceThreshold" class="confirm-input" min="0" step="0.1" style="width:100px;align-self:flex-start;"><label class="confirm-checkbox"><input type="checkbox" id="rebalanceApply"> Apply (uncheck = dry-run scan only). Cross-disk moves can take minutes per GB on the SD card.</label></div>`,
    action: () => runRebalanceRoms(),
    onOpen: () => {
      const i = document.getElementById('rebalanceInternal');
      const s = document.getElementById('rebalanceSd');
      if (i) i.value = '/home/deck/Emulation/roms';
      if (s) s.value = '/run/media/deck/EmuDeck/Emulation/roms';
      const apply = document.getElementById('rebalanceApply');
      if (apply) apply.checked = false;
      const lg = document.getElementById('rebalanceStrategyLargest');
      if (lg) lg.checked = true;
      const th = document.getElementById('rebalanceThreshold');
      if (th) th.value = '2';
    }
  }
});

async function runRebalanceRoms() {
  const internalRoot = document.getElementById('rebalanceInternal')?.value.trim() || '/home/deck/Emulation/roms';
  const sdRoot = document.getElementById('rebalanceSd')?.value.trim() || '/run/media/deck/EmuDeck/Emulation/roms';
  const apply = document.getElementById('rebalanceApply')?.checked === true;
  const mode = apply ? 'apply' : 'scan';
  const smallestChecked = document.getElementById('rebalanceStrategySmallest')?.checked === true;
  const strategy = smallestChecked ? 'smallest' : 'largest';
  const thRaw = document.getElementById('rebalanceThreshold')?.value;
  const thNum = Number(thRaw);
  const threshold = (Number.isFinite(thNum) && thNum >= 0) ? String(thNum) : '2';
  disableBtn('btnRebalanceRoms');
  openTerminal('Rebalance ROMs');
  appendTerminal(`Mode: ${mode}\nStrategy: ${strategy} first\nBalance threshold: ${threshold}%\nInternal: ${internalRoot}\nSD: ${sdRoot}\n\n`);
  try {
    const result = await invoke('rebalance_roms', { mode, internalRoot, sdRoot, strategy, threshold });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnRebalanceRoms');
}
