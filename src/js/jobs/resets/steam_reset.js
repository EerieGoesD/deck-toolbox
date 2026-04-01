registerJobs({
  steam: {
    title: 'Reset Steam Client',
    severity: 'destructive',
    label: 'Destructive action',
    body: `This can fix <strong>Steam Deck boot loops</strong> and Steam client issues.<br><br>This will:<br>&#8226; Rename <code>~/.local/share/Steam</code> to <code>Steam_backup</code><br>&#8226; If a backup already exists, a timestamp is appended<br>&#8226; Steam will create a fresh directory on next launch<br>&#8226; You will need to <strong>sign in again</strong><br>&#8226; Non-default install locations will need to be re-added<br>&#8226; Games on SD card or other drives are <strong>safe</strong><br><br><strong>Warning:</strong> Steam games installed on the <strong>internal drive</strong> are stored inside the Steam directory. After the reset, Steam will need to redownload them. If you choose to delete the backup folder afterward, those games will be permanently removed.`,
    action: () => runSteamReset()
  }
});

async function runSteamReset() {
  disableBtn('btnSteam');
  openTerminal('Reset Steam Client');
  try {
    const result = await invoke('steam_reset');
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
    if (result.code === 0) promptDeleteBackups();
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnSteam');
}
