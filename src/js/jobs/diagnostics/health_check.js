registerJobs({
  healthCheck: {
    title: 'Health Check',
    severity: 'safe',
    label: 'Read-only check',
    body: `Checks the Deck's hardware and flags anything that looks wrong:<br>&#8226; <strong>Battery</strong> - health, charge, temperature<br>&#8226; <strong>Storage</strong> - SSD health report, wear, errors, free space, SD card<br>&#8226; <strong>CPU, GPU, memory, fan</strong> - working, temperatures, fan speed<br>&#8226; <strong>Screen, audio, controls</strong> - detected and working<br>&#8226; <strong>Wi-Fi and Bluetooth</strong> - detected and turned on<br><br><strong>Nothing is changed.</strong> The SSD health report needs the sudo password (Unlock at the top).`,
    action: () => runHealthCheck()
  }
});

async function runHealthCheck() {
  disableBtn('btnHealth');
  openTerminal('Health Check');
  try {
    const result = await invoke('health_check');
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnHealth');
}
