// ─────────────────────────────────────────────
// Deck Toolbox - Core Infrastructure
// ─────────────────────────────────────────────

const { invoke } = window.__TAURI__.core;

// Global state
let sudoAuthenticated = false;
const CONFIRM_DATA = {};

// Job registration (called by each job file)
function registerJobs(entries) {
  Object.assign(CONFIRM_DATA, entries);
}

// Button helpers
function disableBtn(id) { document.getElementById(id).disabled = true; }
function enableBtn(id) { document.getElementById(id).disabled = false; }

// ─────────────────────────────────────────────
// External links
// ─────────────────────────────────────────────

function openLink(url) {
  if (window.__TAURI__?.shell?.open) {
    window.__TAURI__.shell.open(url);
  } else {
    invoke('open_url', { url }).catch(() => {});
  }
}

// ─────────────────────────────────────────────
// Sudo setup (for users with no password)
// ─────────────────────────────────────────────

async function showSudoSetup() {
  document.getElementById('confirmTitle').textContent = 'Set Up Sudo Password';
  const sub = document.getElementById('confirmSubtitle');
  sub.textContent = 'Checking...';
  sub.className = 'confirm-subtitle none';
  document.getElementById('confirmBody').innerHTML = 'Detecting password status...';
  const yesBtn = document.getElementById('confirmYes');
  yesBtn.style.display = 'none';
  document.getElementById('confirmOverlay').classList.add('open');

  let hasPassword = false;
  try { hasPassword = await invoke('check_has_password'); } catch (e) {}

  if (hasPassword) {
    sub.textContent = 'Password detected';
    sub.className = 'confirm-subtitle safe';
    document.getElementById('confirmBody').innerHTML = `
      Your Steam Deck already has a sudo password configured.<br><br>
      Enter it in the password field above and click <strong>Unlock</strong> to authenticate.<br><br>
      <span style="font-family:var(--mono);font-size:11px;color:var(--muted);">If you forgot your password, open Konsole and run: <code>passwd</code></span>`;
    yesBtn.textContent = 'OK';
    yesBtn.className = 'tool-btn primary';
    yesBtn.style.display = '';
    yesBtn.onclick = () => closeConfirm();
  } else {
    sub.textContent = 'First-time setup';
    sub.className = 'confirm-subtitle caution';
    document.getElementById('confirmBody').innerHTML = `
      No password is set on this Steam Deck. You need one to run scripts that require system access.<br><br>
      <div class="confirm-form">
        <div class="confirm-field"><label>New password:</label><input type="password" id="setupPw1" /></div>
        <div class="confirm-field"><label>Repeat password:</label><input type="password" id="setupPw2" data-enter="confirmYes" /></div>
        <div id="setupError" style="font-family:var(--mono);font-size:12px;color:var(--danger);display:none;"></div>
      </div>`;
    yesBtn.textContent = 'Set Password';
    yesBtn.className = 'tool-btn primary';
    yesBtn.style.display = '';
    yesBtn.onclick = async () => {
      const pw1 = document.getElementById('setupPw1').value;
      const pw2 = document.getElementById('setupPw2').value;
      const errEl = document.getElementById('setupError');
      errEl.style.color = 'var(--danger)';
      if (!pw1) { errEl.textContent = 'Password cannot be empty.'; errEl.style.display = ''; return; }
      if (pw1 !== pw2) { errEl.textContent = 'Passwords do not match.'; errEl.style.display = ''; return; }
      if (pw1.length < 4) { errEl.textContent = 'Password must be at least 4 characters.'; errEl.style.display = ''; return; }
      errEl.textContent = 'Setting password...';
      errEl.style.display = '';
      errEl.style.color = 'var(--muted)';
      try {
        const result = await invoke('set_user_password', { newPassword: pw1 });
        if (result.code === 0) {
          errEl.textContent = 'Password set! You can now use it to authenticate.';
          errEl.style.color = 'var(--success)';
          setTimeout(() => closeConfirm(), 2000);
        } else {
          errEl.textContent = 'Failed. Open Konsole and run: passwd';
          errEl.style.color = 'var(--danger)';
        }
      } catch (err) {
        errEl.textContent = 'Error. Open Konsole and run: passwd';
        errEl.style.color = 'var(--danger)';
      }
    };
    setTimeout(() => document.getElementById('setupPw1')?.focus(), 100);
  }
}

// ─────────────────────────────────────────────
// Sudo authentication
// ─────────────────────────────────────────────

async function cacheSudo() {
  const input = document.getElementById('sudoPassword');
  const status = document.getElementById('sudoStatus');
  const password = input.value;
  if (!password) return;

  status.className = 'sudo-status none';
  status.textContent = 'Authenticating...';

  try {
    const result = await invoke('cache_sudo', { password });
    if (result.code === 0) {
      status.className = 'sudo-status ok';
      status.textContent = 'Authenticated';
      sudoAuthenticated = true;
      if (document.getElementById('sudoSave').checked) {
        await invoke('save_sudo_password', { password });
      }
      input.value = '';
      input.disabled = true;
      input.placeholder = 'Authenticated';
      document.querySelector('.sudo-btn').disabled = true;
      document.querySelector('.sudo-btn').style.opacity = '0.4';
    } else {
      status.className = 'sudo-status fail';
      status.textContent = 'Wrong password';
      const detail = (result.stderr || result.stdout || '').trim();
      if (detail) {
        openTerminal('Sudo authentication');
        appendTerminal('Sudo rejected the password.\n\n--- sudo stderr ---\n' + detail + '\n');
        setTermStatus('error');
      }
    }
  } catch (err) {
    const msg = err?.message || String(err);
    status.className = 'sudo-status fail';
    status.textContent = 'Error: ' + msg;
    openTerminal('Sudo authentication');
    appendTerminal('cache_sudo failed: ' + msg + '\n');
    setTermStatus('error');
  }
}

// Auto-load saved password on app start
(async function loadSavedSudo() {
  try {
    const saved = await invoke('load_sudo_password');
    if (saved) {
      document.getElementById('sudoStatus').className = 'sudo-status ok';
      document.getElementById('sudoStatus').textContent = 'Authenticated';
      document.getElementById('sudoSave').checked = true;
      sudoAuthenticated = true;
      const inp = document.getElementById('sudoPassword');
      inp.disabled = true;
      inp.placeholder = 'Authenticated';
      document.querySelector('.sudo-btn').disabled = true;
      document.querySelector('.sudo-btn').style.opacity = '0.4';
    }
  } catch (e) {}
})();

// ─────────────────────────────────────────────
// Tabs
// ─────────────────────────────────────────────

function switchTab(name, target) {
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
  document.querySelector(`.tab-content[data-tab="${name}"]`).classList.add('active');
  if (target) target.classList.add('active');
  if (name === 'storage') loadStorageBars();
}

// ─────────────────────────────────────────────
// Event delegation (CSP forbids inline on*= handlers)
// ─────────────────────────────────────────────

document.addEventListener('click', (e) => {
  const target = e.target.closest('[data-action]');
  if (!target) return;
  const action = target.dataset.action;
  const arg = target.dataset.arg;
  switch (action) {
    case 'switchTab':         switchTab(arg, target); break;
    case 'confirmAction':     confirmAction(arg); break;
    case 'openLink':          e.preventDefault(); openLink(arg); break;
    case 'cacheSudo':         cacheSudo(); break;
    case 'showSudoSetup':     showSudoSetup(); break;
    case 'loadStorageBars':   loadStorageBars(); break;
    case 'termExpand':        termExpand(); break;
    case 'termCollapse':      termCollapse(); break;
    case 'copyTerminal':      copyTerminal(); break;
    case 'exportTerminal':    exportTerminal(); break;
    case 'clearTerminal':     clearTerminal(); break;
    case 'closeConfirm':      closeConfirm(); break;
    case 'removePathItem':    target.closest('.path-item')?.remove(); break;
    case 'addDupeRomPath':    addDupeRomPath(); break;
    case 'addLostRomPath':    addLostRomPath(); break;
    case 'addRomSortPath':    addRomSortPath(); break;
    case 'dupeSelectAll':     if (typeof dupeSelectAll === 'function') dupeSelectAll(); break;
    case 'dupeDeselectAll':   if (typeof dupeDeselectAll === 'function') dupeDeselectAll(); break;
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter') return;
  const target = e.target.closest('[data-enter]');
  if (!target) return;
  const action = target.dataset.enter;
  switch (action) {
    case 'cacheSudo':     cacheSudo(); break;
    case 'confirmYes':    document.getElementById('confirmYes').click(); break;
  }
});

document.addEventListener('change', (e) => {
  const target = e.target.closest('[data-change]');
  if (!target) return;
  const action = target.dataset.change;
  switch (action) {
    case 'dupeUpdateCount': if (typeof dupeUpdateCount === 'function') dupeUpdateCount(); break;
  }
});

// ─────────────────────────────────────────────
// Storage size bars
// ─────────────────────────────────────────────

function formatBytes(bytes) {
  if (!bytes && bytes !== 0) return '-';
  if (bytes < 1024) return bytes + ' B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1024;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) { value /= 1024; i++; }
  return (value >= 100 ? value.toFixed(0) : value.toFixed(1)) + ' ' + units[i];
}

async function loadStorageBars() {
  const container = document.getElementById('storageBars');
  if (!container) return;
  container.innerHTML = '<div class="storage-bars-empty">Reading storage info...</div>';
  try {
    const disks = await invoke('get_disk_usage');
    if (!disks || disks.length === 0) {
      container.innerHTML = '<div class="storage-bars-empty">Could not read storage info.</div>';
      return;
    }
    container.innerHTML = disks.map(d => {
      const total = Number(d.total) || 0;
      const used = Number(d.used) || 0;
      const pct = total > 0 ? Math.min(100, (used / total) * 100) : 0;
      const usedFmt = formatBytes(used);
      const totalFmt = formatBytes(total);
      const fillClass = pct >= 90 ? 'danger' : pct >= 75 ? 'warn' : '';
      const labelOutside = pct < 28;
      const usedLabelStyle = labelOutside
        ? `left: ${pct}%; transform: translate(6px, -50%);`
        : `left: ${pct}%; transform: translate(calc(-100% - 6px), -50%);`;
      const usedLabelClass = labelOutside ? 'storage-bar-used outside' : 'storage-bar-used';
      return `
        <div class="storage-bar-row">
          <div class="storage-bar-header">
            <span class="storage-bar-name">${d.label}</span>
            <span class="storage-bar-percent">${pct.toFixed(1)}% used</span>
          </div>
          <div class="storage-bar-track">
            <div class="storage-bar-fill ${fillClass}" style="width: ${pct}%"></div>
            <span class="${usedLabelClass}" style="${usedLabelStyle}">${usedFmt}</span>
            <span class="storage-bar-total">${totalFmt}</span>
          </div>
        </div>`;
    }).join('');
  } catch (err) {
    container.innerHTML = '<div class="storage-bars-empty">Error reading storage info.</div>';
  }
}

document.addEventListener('DOMContentLoaded', () => {
  setTermState('collapsed');
  loadStorageBars();
});

// ─────────────────────────────────────────────
// Terminal (right panel)
// ─────────────────────────────────────────────

function openTerminal(label) {
  document.getElementById('termTitle').textContent = label;
  document.getElementById('termBody').innerHTML = '';
  document.getElementById('termBody').style.display = '';
  document.getElementById('termPlaceholder').style.display = 'none';
  setTermStatus('running');
  if (termState === 'collapsed') setTermState('half');
}

function appendTerminal(text) {
  const body = document.getElementById('termBody');
  const lines = text.split('\n');
  for (const line of lines) {
    const el = document.createElement('div');
    el.textContent = line;
    if (/\bOK\b/i.test(line)) el.className = 'line-ok';
    else if (/\bWARN\b/i.test(line)) el.className = 'line-warn';
    else if (/\bFAIL\b|\bERROR\b/i.test(line)) el.className = 'line-err';
    body.appendChild(el);
  }
  body.scrollTop = body.scrollHeight;
}

function setTermStatus(type) {
  const el = document.getElementById('termStatus');
  el.className = 'terminal-status ' + type;
  const labels = { idle: 'Idle', running: 'Running...', done: 'Done', error: 'Error' };
  el.textContent = labels[type] || type;
}

function clearTerminal() {
  document.getElementById('termBody').innerHTML = '';
  document.getElementById('termBody').style.display = 'none';
  document.getElementById('termPlaceholder').style.display = '';
  document.getElementById('termTitle').textContent = 'Terminal';
  setTermStatus('idle');
}

function copyTerminal() {
  const body = document.getElementById('termBody');
  const text = body.innerText;
  if (!text) return;
  navigator.clipboard.writeText(text);
}

async function exportTerminal() {
  const body = document.getElementById('termBody');
  const text = body.innerText;
  if (!text) return;
  try {
    await invoke('export_log', { content: text });
  } catch (err) {
    console.error('Export failed:', err);
  }
}

let termState = 'collapsed';

function setTermState(state) {
  termState = state;
  const panel = document.querySelector('.panel-right');
  panel.classList.remove('state-collapsed', 'state-half', 'state-full');
  panel.classList.add('state-' + state);
}

function termExpand() {
  if (termState === 'collapsed') setTermState('half');
  else if (termState === 'half') setTermState('full');
}

function termCollapse() {
  if (termState === 'full') setTermState('half');
  else if (termState === 'half') setTermState('collapsed');
}

// ─────────────────────────────────────────────
// Confirm dialog
// ─────────────────────────────────────────────

function confirmAction(key) {
  const data = CONFIRM_DATA[key];
  const needsSudoInput = data.requiresSudo && !sudoAuthenticated;

  document.getElementById('confirmTitle').textContent = data.title;
  const sub = document.getElementById('confirmSubtitle');
  sub.textContent = data.label;
  sub.className = 'confirm-subtitle ' + data.severity;

  let bodyHtml = data.body;
  if (needsSudoInput) {
    bodyHtml += `<div class="confirm-sudo-field"><label>Sudo password:</label><input type="password" id="confirmSudoInput" placeholder="Required for this script" data-enter="confirmYes" /></div>`;
  }
  document.getElementById('confirmBody').innerHTML = bodyHtml;

  const yesBtn = document.getElementById('confirmYes');
  yesBtn.textContent = data.severity === 'safe' ? 'Run' : 'Confirm';
  yesBtn.className = 'tool-btn ' + (data.severity === 'destructive' ? 'danger' : data.severity === 'caution' ? 'warn' : 'primary');

  yesBtn.onclick = async () => {
    if (needsSudoInput) {
      const pw = document.getElementById('confirmSudoInput')?.value;
      if (!pw) {
        document.getElementById('confirmSudoInput').style.borderColor = 'var(--danger)';
        return;
      }
      try {
        const result = await invoke('cache_sudo', { password: pw });
        if (result.code !== 0) {
          document.getElementById('confirmSudoInput').value = '';
          document.getElementById('confirmSudoInput').style.borderColor = 'var(--danger)';
          document.getElementById('confirmSudoInput').placeholder = 'Wrong password - try again';
          const detail = (result.stderr || result.stdout || '').trim();
          if (detail) {
            closeConfirm();
            openTerminal('Sudo authentication');
            appendTerminal('Sudo rejected the password.\n\n--- sudo stderr ---\n' + detail + '\n');
            setTermStatus('error');
          }
          return;
        }
        sudoAuthenticated = true;
        document.getElementById('sudoStatus').className = 'sudo-status ok';
        document.getElementById('sudoStatus').textContent = 'Authenticated';
        if (document.getElementById('sudoSave').checked) {
          await invoke('save_sudo_password', { password: pw });
        }
      } catch (err) {
        const msg = err?.message || String(err);
        closeConfirm();
        openTerminal('Sudo authentication');
        appendTerminal('cache_sudo failed: ' + msg + '\n');
        setTermStatus('error');
        return;
      }
    }
    closeConfirm();
    data.action();
  };

  document.getElementById('confirmOverlay').classList.add('open');
  if (data.onOpen) data.onOpen();
  if (needsSudoInput) {
    setTimeout(() => document.getElementById('confirmSudoInput')?.focus(), 100);
  }
}

function closeConfirm() {
  document.getElementById('confirmOverlay').classList.remove('open');
  document.querySelector('.confirm-box').classList.remove('wide');
}

document.getElementById('confirmOverlay').addEventListener('click', e => {
  if (e.target === e.currentTarget) closeConfirm();
});

// ─────────────────────────────────────────────
// Path list helpers
// ─────────────────────────────────────────────

function addPathToList(listId, value) {
  const list = document.getElementById(listId);
  const item = document.createElement('div');
  item.className = 'path-item';
  item.innerHTML = `<input type="text" value="${value}" placeholder="/path/to/roms" /><button class="path-remove" data-action="removePathItem">x</button>`;
  list.appendChild(item);
}

function getPathsFromList(listId) {
  return Array.from(document.querySelectorAll(`#${listId} .path-item input`)).map(i => i.value.trim()).filter(Boolean);
}

function addDupeRomPath() { addPathToList('dupeRomPaths', ''); }
function addDupeRomPathValue(p) { addPathToList('dupeRomPaths', p); }
function addLostRomPath() { addPathToList('lostRomPaths', ''); }
function addLostRomPathValue(p) { addPathToList('lostRomPaths', p); }
function addRomSortPath() { addPathToList('romSortPaths', ''); }
function addRomSortPathValue(p) { addPathToList('romSortPaths', p); }

// ─────────────────────────────────────────────
// Prompt to delete Steam backups (used by resets + recovery)
// ─────────────────────────────────────────────

function promptDeleteBackups() {
  const data = {
    title: 'Delete backup folders?',
    body: `The backup folders (<code>Steam_backup</code>) may take up a <strong>very large amount of storage</strong>.<br><br>Would you like to delete them to free up space?`,
    action: async () => {
      openTerminal('Delete Backups');
      try {
        const result = await invoke('delete_steam_backups');
        appendTerminal(result.stdout);
        if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
        setTermStatus(result.code === 0 ? 'done' : 'error');
      } catch (err) {
        appendTerminal('Error: ' + (err.message || err));
        setTermStatus('error');
      }
    }
  };
  document.getElementById('confirmTitle').textContent = data.title;
  document.getElementById('confirmBody').innerHTML = data.body;
  document.getElementById('confirmYes').textContent = 'Delete';
  const yesBtn = document.getElementById('confirmYes');
  yesBtn.onclick = () => { closeConfirm(); data.action(); };
  document.getElementById('confirmOverlay').classList.add('open');
}
