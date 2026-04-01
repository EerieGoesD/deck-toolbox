registerJobs({
  dupeRom: {
    title: 'Duplicate ROM Finder',
    severity: 'safe',
    label: 'Read-only scan',
    body: `This will scan each console folder for near-duplicate ROM files using normalized filenames (strips punctuation, ignores case).<br><br><strong>Nothing is deleted</strong> - this only reports what it finds.<br><div class="confirm-form"><label style="min-width:0;color:var(--text);font-size:13px;">Search paths:</label><div class="path-list" id="dupeRomPaths"></div><button class="path-add" onclick="addDupeRomPath()">+ Add path</button></div>`,
    action: () => runDuplicateRomFinder(),
    onOpen: () => {
      const list = document.getElementById('dupeRomPaths');
      list.innerHTML = '';
      ['/run/media/EmuDeck/Emulation/roms', '/home/deck/Emulation/roms'].forEach(p => addDupeRomPathValue(p));
    }
  }
});

function parseDuplicateOutput(stdout) {
  const groups = [];
  let current = null;
  for (const line of stdout.split('\n')) {
    const headerMatch = line.match(/^=== \[(.+?)\] Possible duplicates \(normalized: (.+?)\) ===$/);
    if (headerMatch) {
      current = { console: headerMatch[1], normalized: headerMatch[2], files: [] };
      groups.push(current);
    } else if (current && line.trim().startsWith('/')) {
      current.files.push(line.trim());
    }
  }
  return groups;
}

function showDuplicateSelectionDialog(groups) {
  document.getElementById('confirmTitle').textContent = 'Delete Duplicate ROMs';
  const sub = document.getElementById('confirmSubtitle');
  sub.textContent = 'Select files to delete';
  sub.className = 'confirm-subtitle destructive';

  let html = `<div class="dupe-select-bar">
    <button class="dupe-select-btn" onclick="dupeSelectAll()">Select all duplicates</button>
    <button class="dupe-select-btn" onclick="dupeDeselectAll()">Deselect all</button>
    <span class="dupe-count" id="dupeCount">0 files selected</span>
  </div><div class="dupe-scroll">`;

  let fileIdx = 0;
  for (const group of groups) {
    html += `<div class="dupe-group">`;
    html += `<div class="dupe-group-header">[${group.console}] ${group.files.length} files</div>`;
    for (let i = 0; i < group.files.length; i++) {
      const id = `dupe_${fileIdx++}`;
      const filename = group.files[i].split('/').pop();
      html += `<div class="dupe-file">
        <input type="checkbox" id="${id}" data-path="${group.files[i].replace(/"/g, '&quot;')}" onchange="dupeUpdateCount()" />
        <label for="${id}" title="${group.files[i]}">${filename}</label>
      </div>`;
    }
    html += `</div>`;
  }
  html += `</div>`;

  document.getElementById('confirmBody').innerHTML = html;
  const yesBtn = document.getElementById('confirmYes');
  yesBtn.textContent = 'Delete Selected';
  yesBtn.className = 'tool-btn danger';
  yesBtn.onclick = () => dupeDeleteSelected();
  document.getElementById('confirmOverlay').classList.add('open');
}

function dupeSelectAll() {
  // Select second file in each group (keep first, delete rest)
  document.querySelectorAll('.dupe-group').forEach(group => {
    const boxes = group.querySelectorAll('input[type="checkbox"]');
    boxes.forEach((cb, i) => { cb.checked = i > 0; });
  });
  dupeUpdateCount();
}

function dupeDeselectAll() {
  document.querySelectorAll('.dupe-scroll input[type="checkbox"]').forEach(cb => { cb.checked = false; });
  dupeUpdateCount();
}

function dupeUpdateCount() {
  const count = document.querySelectorAll('.dupe-scroll input[type="checkbox"]:checked').length;
  const el = document.getElementById('dupeCount');
  if (el) el.textContent = count + ' file' + (count !== 1 ? 's' : '') + ' selected';
}

async function dupeDeleteSelected() {
  const checked = document.querySelectorAll('.dupe-scroll input[type="checkbox"]:checked');
  const files = Array.from(checked).map(cb => cb.dataset.path);
  if (files.length === 0) {
    closeConfirm();
    return;
  }
  closeConfirm();
  openTerminal('Delete Duplicate ROMs');
  appendTerminal(`Deleting ${files.length} file(s)...\n\n`);
  try {
    const result = await invoke('delete_files', { files });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
}

async function runDuplicateRomFinder() {
  const paths = getPathsFromList('dupeRomPaths');
  disableBtn('btnDupeRom');
  openTerminal('Duplicate ROM Finder');
  appendTerminal('Scanning for duplicate ROMs...\n');
  if (paths.length > 0) appendTerminal('Paths: ' + paths.join(', ') + '\n\n');
  try {
    const result = await invoke('duplicate_rom_finder', { paths });
    appendTerminal(result.stdout);
    if (result.stderr) appendTerminal('\n--- stderr ---\n' + result.stderr);
    setTermStatus(result.code === 0 ? 'done' : 'error');

    // Parse and offer deletion if duplicates found
    const groups = parseDuplicateOutput(result.stdout);
    if (groups.length > 0) {
      showDuplicateSelectionDialog(groups);
    }
  } catch (err) {
    appendTerminal('Error: ' + (err.message || err));
    setTermStatus('error');
  }
  enableBtn('btnDupeRom');
}
