registerJobs({
  gamescope: {
    title: 'Reset Gamescope',
    severity: 'destructive',
    label: 'Destructive action',
    body: `This can fix <strong>boot loops, display glitches, resolution issues, and visual rendering problems</strong>.<br><br>This will delete:<br><br>&#8226; <code>~/.local/state/gamescope</code><br>&#8226; <code>~/.config/gamescope</code><br><br>No games or user data are affected. Only Gamescope's display compositor config is removed. <strong>Reboot recommended</strong> after.`,
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
