registerJobs({
  uninstallDecky: {
    title: 'Uninstall Decky Loader',
    severity: 'destructive',
    label: 'Destructive action',
    requiresSudo: true,
    body: `This will:<br><br>1. Download and run the <strong>official SteamDeckHomebrew uninstall script</strong><br>2. Remove leftover services, logs, loader config, and template plugins<br><br>Your personal plugins and their data are <strong>kept</strong>. Requires an <strong>internet connection</strong>.`,
    action: () => runUninstallDecky()
  }
});

async function runUninstallDecky() {
  disableBtn('btnUninstallDecky');
  openTerminal('Uninstall Decky Loader');
  appendTerminal('Running Decky uninstall script...\n');
  try {
    const result = await invoke('uninstall_decky');
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnUninstallDecky');
}
