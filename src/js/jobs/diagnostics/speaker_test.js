registerJobs({
  speakerTest: {
    title: 'Speaker Test',
    severity: 'safe',
    label: 'You listen',
    body: `Plays a short tone on the <strong>left</strong> speaker, then the <strong>right</strong>, and asks whether you heard each one.<br><br>Unplug headphones and turn the volume up first.`,
    action: () => runSpeakerTest()
  }
});

async function runSpeakerTest() {
  disableBtn('btnSpeakerTest');
  openTerminal('Speaker Test');
  const results = [];

  for (const side of ['left', 'right']) {
    const name = side === 'left' ? 'Left' : 'Right';
    appendTerminal(`Playing a tone on the ${side} speaker...\n`);
    let played = false;
    try {
      const result = await invoke('speaker_test', { side });
      played = result.code === 0;
      if (!played && result.stderr) appendTerminal(result.stderr);
    } catch (err) {
      appendTerminal('Error: ' + (err.message || err) + '\n');
    }

    if (!played) {
      results.push(`  [FAIL]  ${name} speaker: the tone could not be played`);
      continue;
    }

    const heard = await askYesNo('Speaker Test', `Did you hear the tone from the <strong>${side}</strong> speaker?`);
    if (heard === null) {
      appendTerminal('Speaker test stopped.\n');
      setTermStatus('idle');
      enableBtn('btnSpeakerTest');
      return;
    }
    results.push(heard ? `  [OK]    ${name} speaker: heard` : `  [FAIL]  ${name} speaker: not heard`);
  }

  appendTerminal('\n' + results.join('\n') + '\n');
  setTermStatus(results.some(r => r.includes('[FAIL]')) ? 'error' : 'done');
  enableBtn('btnSpeakerTest');
}
