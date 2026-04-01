registerJobs({
  maintenance: {
    title: 'Weekly Maintenance',
    severity: 'caution',
    label: 'System maintenance',
    requiresSudo: true,
    body: `This will run the following tasks:<br><br>&#8226; <strong>Flatpak</strong> - update apps/runtimes, remove unused (user + system)<br>&#8226; <strong>Journals</strong> - rotate and vacuum system/user logs<br>&#8226; <strong>TRIM</strong> - run filesystem TRIM on all mounted drives<br>&#8226; <strong>Cleanup</strong> - delete old temp files and thumbnail cache<br>&#8226; <strong>Health</strong> - disk usage warnings and SMART checks<br><br>Logs are saved to <code>~/.local/state/steamdeck-maintenance/logs/</code>.<div class="confirm-form"><div class="confirm-field"><label style="min-width:0;flex:1;"><input type="checkbox" id="maintForceHeavy" style="margin-right:8px;cursor:pointer;vertical-align:middle;" /><span style="color:var(--text);">Run heavy tasks even on battery</span><br><span style="font-size:11px;color:var(--muted);margin-left:26px;">Flatpak updates and TRIM are skipped on battery by default. Check this to force them.</span></label></div></div>`,
    action: () => runMaintenance()
  }
});

async function runMaintenance() {
  const forceHeavy = document.getElementById('maintForceHeavy')?.checked ? '1' : '0';
  disableBtn('btnMaint');
  openTerminal('Weekly Maintenance');
  appendTerminal('Starting maintenance - this may take several minutes...\n');
  try {
    const result = await invoke('run_maintenance', { forceHeavy });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnMaint');
}
