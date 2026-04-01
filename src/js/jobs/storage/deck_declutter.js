registerJobs({
  declutter: {
    title: 'Deck Declutter',
    severity: 'destructive',
    label: 'Destructive action',
    requiresSudo: true,
    body: `This will scan for and delete known clutter:<br>&#8226; Old <code>.flatpak</code> installer files<br>&#8226; Stale build caches (<code>.flatpak-builder</code>, <code>go-build</code>)<br>&#8226; Leftover AppImages and launcher archives<br>&#8226; Winetricks caches<br><br>Only <strong>known safe-to-delete</strong> items at specific paths are targeted.`,
    action: () => runDeckDeclutter()
  }
});

async function runDeckDeclutter() {
  disableBtn('btnDeclutter');
  openTerminal('Deck Declutter');
  try {
    const result = await invoke('deck_declutter');
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnDeclutter');
}
