registerJobs({
  deckyLeftovers: {
    title: 'Find Decky Leftovers',
    severity: 'safe',
    label: 'Read-only scan',
    body: `This will:<br>&#8226; Check known Decky Loader paths (<code>~/homebrew</code>, <code>~/.local/share/decky</code>, <code>~/.config/decky</code>, systemd services)<br>&#8226; Search for any remaining files with "decky" or "plugin_loader" in the name<br>&#8226; Show file sizes and locations<br><br><strong>Nothing is deleted</strong> - this only reports what it finds.`,
    action: () => runFindDeckyLeftovers()
  }
});

async function runFindDeckyLeftovers() {
  disableBtn('btnDeckyLeftovers');
  openTerminal('Find Decky Leftovers');
  try {
    const result = await invoke('find_decky_leftovers');
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnDeckyLeftovers');
}
