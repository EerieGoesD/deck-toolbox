registerJobs({
  cue: {
    title: 'Generate .cue from .bin',
    severity: 'safe',
    label: 'Read-only operation',
    body: `This will:<br><br>&#8226; Open a file picker to select <code>.bin</code> disc image files<br>&#8226; Create a matching <code>.cue</code> sheet for each file (MODE2/2352, single track)<br>&#8226; Skip any files that already have a <code>.cue</code><br><br>Your <code>.bin</code> files will <strong>not</strong> be modified.`,
    action: () => runCue()
  }
});

async function runCue() {
  disableBtn('btnCue');
  try {
    const result = await invoke('generate_cue');
    if (result.canceled) { enableBtn('btnCue'); return; }
    openTerminal('Generate .cue');
    for (const r of result.results) {
      const prefix = r.status === 'ok' ? '>' : r.status === 'skipped' ? '-' : 'x';
      appendTerminal(`${prefix}  ${r.file}: ${r.msg}`);
    }
    setTermStatus(result.results.every(r => r.status !== 'error') ? 'done' : 'error');
  } catch (err) {
    openTerminal('Generate .cue');
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnCue');
}
