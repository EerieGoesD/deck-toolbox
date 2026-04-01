registerJobs({
  recovery: {
    title: 'Full Recovery',
    severity: 'destructive',
    label: 'Destructive action',
    body: `This will:<br><br>1. Rename Steam directory to <code>Steam_backup</code> (with timestamp)<br>2. Delete all Gamescope state and config<br><br>Use when your Deck is stuck in a <strong>boot loop</strong>. You will need to <strong>reboot</strong> and <strong>sign in to Steam</strong> again.<br><br>Backup folders can be very large. You will be asked if you want to delete them after.`,
    action: () => runFullRecovery()
  }
});

async function runFullRecovery() {
  disableBtn('btnRecovery');
  openTerminal('Full Recovery');
  try {
    const result = await invoke('full_recovery');
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
    if (result.code === 0) promptDeleteBackups();
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnRecovery');
}
