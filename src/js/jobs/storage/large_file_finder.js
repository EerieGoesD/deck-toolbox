registerJobs({
  largeFile: {
    title: 'Large File Finder',
    severity: 'safe',
    label: 'Read-only scan',
    body: `Scans your Deck for the largest items sorted by size.<br><strong>Nothing is deleted</strong> - this only reports what is using your storage.<br><div class="confirm-form"><div class="confirm-field"><label>Show:</label><select id="lfMode"><option value="3" selected>Files and Folders</option><option value="1">Files only</option><option value="2">Folders only</option></select></div><div class="confirm-field"><label>Top:</label><input type="number" id="lfCount" value="50" min="1" max="500" /> <span style="font-family:var(--mono);font-size:12px;color:var(--muted);">results</span></div><div class="confirm-field"><label>ROMs:</label><select id="lfExclude"><option value="n" selected>Include ROMs</option><option value="y">Exclude ROMs</option></select></div></div>`,
    action: () => runLargeFileFinder()
  }
});

async function runLargeFileFinder() {
  const mode = document.getElementById('lfMode')?.value || '3';
  const count = document.getElementById('lfCount')?.value || '50';
  const excludeRoms = document.getElementById('lfExclude')?.value || 'n';
  disableBtn('btnLargeFile');
  openTerminal('Large File Finder');
  appendTerminal('Scanning for large files... (this may take a moment)\n');
  try {
    const result = await invoke('large_file_finder', { excludeRoms, mode, count });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnLargeFile');
}
