registerJobs({
  screenTest: {
    title: 'Screen Test',
    severity: 'safe',
    label: 'You check the screen',
    body: `Fills the whole screen with one colour at a time: black, white, grey, red, green and blue.<br><br>Look for dots, lines or patches that stay a different colour. <strong>Tap the screen</strong> to go to the next colour.`,
    action: () => runScreenTest()
  }
});

const SCREEN_TEST_COLOURS = ['#000000', '#ffffff', '#808080', '#ff0000', '#00ff00', '#0000ff'];

function setAppFullscreen(on) {
  try {
    const win = window.__TAURI__?.window?.getCurrentWindow?.();
    if (win) return win.setFullscreen(on).catch(() => {});
  } catch (e) {}
  return Promise.resolve();
}

async function runScreenTest() {
  disableBtn('btnScreenTest');
  await setAppFullscreen(true);

  const layer = document.createElement('div');
  layer.className = 'screen-test';
  document.body.appendChild(layer);

  const finished = await new Promise(resolve => {
    let i = 0;
    layer.style.background = SCREEN_TEST_COLOURS[0];
    const next = () => {
      i++;
      if (i >= SCREEN_TEST_COLOURS.length) { cleanup(); resolve(true); return; }
      layer.style.background = SCREEN_TEST_COLOURS[i];
    };
    const onKey = e => {
      e.preventDefault();
      if (e.key === 'Escape') { cleanup(); resolve(false); }
      else next();
    };
    const cleanup = () => {
      layer.removeEventListener('pointerdown', next);
      document.removeEventListener('keydown', onKey, true);
      layer.remove();
    };
    layer.addEventListener('pointerdown', next);
    document.addEventListener('keydown', onKey, true);
  });

  await setAppFullscreen(false);
  openTerminal('Screen Test');

  if (!finished) {
    appendTerminal('Screen test stopped.\n');
    setTermStatus('idle');
    enableBtn('btnScreenTest');
    return;
  }

  const ok = await askYesNo('Screen Test', 'Did every colour fill the screen evenly, with no dots, lines or patches that looked different?');
  if (ok === null) {
    appendTerminal('Screen test stopped.\n');
    setTermStatus('idle');
  } else if (ok) {
    appendTerminal('  [OK]    Screen: every colour looked right\n');
    setTermStatus('done');
  } else {
    appendTerminal('  [FAIL]  Screen: problems seen on the colour test\n');
    setTermStatus('error');
  }
  enableBtn('btnScreenTest');
}
