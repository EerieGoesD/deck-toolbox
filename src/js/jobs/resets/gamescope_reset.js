registerJobs({
  gamescope: {
    title: 'Reset Gamescope',
    severity: 'destructive',
    label: 'Destructive action',
    body: `This will delete:<br><br>&#8226; <code>~/.local/state/gamescope</code><br>&#8226; <code>~/.config/gamescope</code><br><br>Fixes display glitches, resolution issues, and rendering problems. No user data is lost. <strong>Reboot recommended</strong> after.`,
    action: () => runGamescopeReset()
  }
});

async function runGamescopeReset() {
  disableBtn('btnGamescope');
  openTerminal('Reset Gamescope');
  try {
    const result = await invoke('gamescope_reset');
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnGamescope');
}
