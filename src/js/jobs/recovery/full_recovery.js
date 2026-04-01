registerJobs({
  recovery: {
    title: 'Full Recovery',
    severity: 'destructive',
    label: 'Destructive action',
    body: `Use when your Deck is stuck in a <strong>boot loop</strong>.<br><br>This will:<br><br>1. Rename Steam directory to <code>Steam_backup</code> (with timestamp)<br>2. Delete all Gamescope state and config<br><br>You will need to <strong>reboot</strong> and <strong>sign in to Steam</strong> again.<br><br><strong>Warning:</strong> Steam games installed on the <strong>internal drive</strong> are stored inside the Steam directory. After the reset, Steam will need to redownload them. If you choose to delete the backup folder afterward, those games will be permanently removed. Games on SD card are safe.`,
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
