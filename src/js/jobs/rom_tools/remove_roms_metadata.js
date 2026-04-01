registerJobs({
  romMetadata: {
    title: 'Remove ROMs Metadata',
    severity: 'destructive',
    label: 'Destructive action',
    body: `This will delete:<br><br>&#8226; All downloaded media from <code>EmuDeck/Emulation/tools/downloaded_media/</code><br>&#8226; All <code>gamelist.xml</code> files from EmuDeck and ES-DE<br><br>Your actual <strong>ROM files are not touched</strong>. Run this before re-scraping artwork.`,
    action: () => runRemoveRomsMetadata()
  }
});

async function runRemoveRomsMetadata() {
  disableBtn('btnRomMeta');
  openTerminal('Remove ROMs Metadata');
  try {
    const result = await invoke('remove_roms_metadata');
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnRomMeta');
}
