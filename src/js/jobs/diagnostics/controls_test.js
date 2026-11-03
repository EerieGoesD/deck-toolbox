registerJobs({
  controlsTest: {
    title: 'Controls Test',
    severity: 'safe',
    label: 'You press the controls',
    body: `Press every button, push each stick in all four directions and click it, and touch and click both trackpads. Each one ticks off when the Deck sees it.<br><br>The Steam button is left out because it opens Steam.`,
    action: () => runControlsTest()
  }
});

const CONTROL_GROUPS = [
  ['Face buttons', [['A', 'A'], ['B', 'B'], ['X', 'X'], ['Y', 'Y']]],
  ['D-pad', [['DUP', 'Up'], ['DDOWN', 'Down'], ['DLEFT', 'Left'], ['DRIGHT', 'Right']]],
  ['Shoulders', [['L1', 'L1'], ['R1', 'R1'], ['L2', 'L2'], ['R2', 'R2']]],
  ['Back buttons', [['L4', 'L4'], ['L5', 'L5'], ['R4', 'R4'], ['R5', 'R5']]],
  ['Menu buttons', [['VIEW', 'View'], ['MENU', 'Menu'], ['QAM', '...']]],
  ['Left stick', [['LS_UP', 'Up'], ['LS_DOWN', 'Down'], ['LS_LEFT', 'Left'], ['LS_RIGHT', 'Right'], ['L3', 'Click'], ['LS_TOUCH', 'Touch']]],
  ['Right stick', [['RS_UP', 'Up'], ['RS_DOWN', 'Down'], ['RS_LEFT', 'Left'], ['RS_RIGHT', 'Right'], ['R3', 'Click'], ['RS_TOUCH', 'Touch']]],
  ['Left trackpad', [['LPAD_TOUCH', 'Touch'], ['LPAD_CLICK', 'Click']]],
  ['Right trackpad', [['RPAD_TOUCH', 'Touch'], ['RPAD_CLICK', 'Click']]],
];

async function runControlsTest() {
  disableBtn('btnControlsTest');
  const all = CONTROL_GROUPS.flatMap(([group, items]) => items.map(([id, label]) => ({ id, name: `${group} ${label}` })));
  const seen = new Set();

  document.getElementById('confirmTitle').textContent = 'Controls Test';
  const sub = document.getElementById('confirmSubtitle');
  sub.className = 'confirm-subtitle';
  const updateCount = () => { sub.textContent = `${seen.size} of ${all.length} ticked`; };
  updateCount();
  document.getElementById('confirmBody').innerHTML = '<div class="controls-grid">' + CONTROL_GROUPS.map(([group, items]) =>
    `<div class="controls-group"><span class="controls-group-label">${group}</span>` +
    items.map(([id, label]) => `<span class="control-chip" data-control="${id}">${label}</span>`).join('') +
    '</div>').join('') + '</div>';
  document.querySelector('.confirm-box').classList.add('wide');
  const cancel = document.querySelector('.confirm-cancel');
  cancel.style.display = 'none';
  const doneBtn = document.getElementById('confirmYes');
  doneBtn.textContent = 'Done';
  doneBtn.className = 'tool-btn primary';
  doneBtn.style.display = '';

  // The controller also types keys and clicks in Desktop Mode. Swallow those
  // so pressing buttons cannot close the dialog or press Done by accident.
  const block = e => { e.preventDefault(); e.stopPropagation(); };
  document.addEventListener('keydown', block, true);
  document.addEventListener('keyup', block, true);
  document.addEventListener('contextmenu', block, true);
  document.activeElement?.blur?.();
  confirmLocked = true;
  document.getElementById('confirmOverlay').classList.add('open');

  let finished = false;
  let unlisten = null;
  const finish = async (errorMessage) => {
    if (finished) return;
    finished = true;
    if (unlisten) unlisten();
    try { await invoke('stop_controls_test'); } catch (e) {}
    document.removeEventListener('keydown', block, true);
    document.removeEventListener('keyup', block, true);
    document.removeEventListener('contextmenu', block, true);
    confirmLocked = false;
    cancel.style.display = '';
    closeConfirm();

    openTerminal('Controls Test');
    if (errorMessage) {
      appendTerminal('  [FAIL]  ' + errorMessage + '\n');
      setTermStatus('error');
    } else {
      const missing = all.filter(c => !seen.has(c.id));
      appendTerminal(`  [OK]    ${seen.size} of ${all.length} controls responded\n`);
      if (missing.length) appendTerminal('  [FAIL]  No response from: ' + missing.map(c => c.name).join(', ') + '\n');
      setTermStatus(missing.length ? 'error' : 'done');
    }
    enableBtn('btnControlsTest');
  };

  doneBtn.onclick = () => finish();

  try {
    unlisten = await window.__TAURI__.event.listen('controls-test', event => {
      let msg;
      try { msg = JSON.parse(event.payload); } catch (e) { return; }
      if (msg.type === 'press') {
        const chip = document.querySelector(`.control-chip[data-control="${msg.id}"]`);
        if (!chip || seen.has(msg.id)) return;
        seen.add(msg.id);
        chip.classList.add('on');
        updateCount();
        if (seen.size === all.length) setTimeout(() => finish(), 600);
      } else if (msg.type === 'error') {
        finish(msg.message);
      } else if (msg.type === 'end' && !finished) {
        finish('The controls test stopped unexpectedly.');
      }
    });
    await invoke('start_controls_test');
  } catch (err) {
    finish(String(err?.message || err));
  }
}
