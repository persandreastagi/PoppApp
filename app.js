/*
 * PoppApp — diario delle poppate.
 *
 * Due modalità, stessa interfaccia:
 *  - locale:  le poppate stanno in localStorage, non esce nulla dal telefono;
 *  - famiglia: le poppate stanno su Firestore sotto un codice famiglia condiviso,
 *              e localStorage resta come copia locale (primo disegno immediato,
 *              e rete di sicurezza se si scollega il telefono).
 */

import { isConfigured } from './firebase-config.js';

const KEY = 'poppapp.entries.v1';
const PREFS = 'poppapp.prefs.v1';
const $ = (sel) => document.querySelector(sel);

/* ─────────────────────── preferenze ───────────────────────── */

const prefs = (() => {
  try { return JSON.parse(localStorage.getItem(PREFS) || '{}'); } catch { return {}; }
})();
function savePrefs() { localStorage.setItem(PREFS, JSON.stringify(prefs)); }

/* ─────────────────────── archivio ─────────────────────────── */

const valid = (e) =>
  e && typeof e.ts === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(e.ts) && Number.isFinite(e.ml);

function loadLocal() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) || '[]');
    return Array.isArray(raw) ? raw.filter(valid) : [];
  } catch { return []; }
}
const saveLocal = (list) => localStorage.setItem(KEY, JSON.stringify(list));

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);

let entries = loadLocal();
let cloud = null;            // handle restituito da connectFamily(), null in modalità locale
let syncState = 'off';       // off | connecting | online | offline | error
let syncDetail = '';

/** Unico punto da cui l'elenco viene rimpiazzato: ordina, specchia in locale, ridisegna. */
function setEntries(list) {
  entries = list.filter(valid).sort((a, b) => b.ts.localeCompare(a.ts));
  saveLocal(entries);
  render();
}

const store = {
  add(entry) {
    if (cloud) { cloud.add(entry).catch(cloudError); setEntries([...entries, entry]); }
    else setEntries([...entries, entry]);
  },
  update(entry) {
    if (cloud) cloud.update(entry).catch(cloudError);
    setEntries([...entries.filter((e) => e.id !== entry.id), entry]);
  },
  remove(id) {
    if (cloud) cloud.remove(id).catch(cloudError);
    setEntries(entries.filter((e) => e.id !== id));
  },
  clear() {
    if (cloud) for (const e of entries) cloud.remove(e.id).catch(cloudError);
    setEntries([]);
  },
};

function cloudError(err) {
  syncState = 'error';
  syncDetail = err?.code || err?.message || String(err);
  renderSync();
  toast('Sincronizzazione non riuscita');
}

/* ─────────────────────── date e ora ───────────────────────── */

const pad = (n) => String(n).padStart(2, '0');
const dateStr = (d = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const timeStr = (d = new Date()) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const dayOf = (ts) => ts.slice(0, 10);
const hourOf = (ts) => ts.slice(11, 16);

const fmtLong = new Intl.DateTimeFormat('it-IT', { weekday: 'long', day: 'numeric', month: 'long' });
const fmtShort = new Intl.DateTimeFormat('it-IT', { weekday: 'short', day: 'numeric', month: 'short' });
const fmtFull = new Intl.DateTimeFormat('it-IT', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });

function labelDay(day, long = false) {
  if (day === dateStr()) return 'Oggi';
  if (day === dateStr(new Date(Date.now() - 864e5))) return 'Ieri';
  const [y, m, d] = day.split('-').map(Number);
  return (long ? fmtLong : fmtShort).format(new Date(y, m - 1, d));
}
function sinceLabel(ts) {
  const [d, t] = ts.split('T'), [y, mo, da] = d.split('-').map(Number), [h, mi] = t.split(':').map(Number);
  const mins = Math.round((Date.now() - new Date(y, mo - 1, da, h, mi).getTime()) / 60000);
  if (mins < 0) return 'programmata';
  if (mins < 60) return `${mins} min fa`;
  const hh = Math.floor(mins / 60), mm = mins % 60;
  return mm ? `${hh}h ${mm}min fa` : `${hh}h fa`;
}

/* ───────────────────────── toast ──────────────────────────── */

let toastTimer;
function toast(msg) {
  const el = $('#toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 2400);
}
function haptic() { if (navigator.vibrate) navigator.vibrate(8); }

/* ─────────────────────────  tab  ──────────────────────────── */

const TITLES = {
  oggi: ['Oggi', () => fmtFull.format(new Date())],
  storico: ['Storico', () => `${entries.length} poppate registrate`],
  esporta: ['Esporta', () => 'CSV per intervallo di date'],
  famiglia: ['Famiglia', () => (cloud ? 'Archivio condiviso' : 'Archivio su questo telefono')],
};
const currentTab = () => document.querySelector('nav button[aria-selected="true"]').dataset.tab;

function showTab(name) {
  for (const s of document.querySelectorAll('main section')) s.hidden = (s.id !== 'tab-' + name);
  for (const b of document.querySelectorAll('nav button')) b.setAttribute('aria-selected', String(b.dataset.tab === name));
  $('#tabTitle').textContent = TITLES[name][0];
  $('#tabSubtitle').textContent = TITLES[name][1]();
  window.scrollTo(0, 0);
  render();
}
document.querySelectorAll('nav button').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));
$('#syncPill').addEventListener('click', () => showTab('famiglia'));

/* ────────────────────── inserimento ───────────────────────── */

const QUICK_ML = [30, 60, 90, 120, 150, 180];
$('#mlChips').innerHTML = QUICK_ML.map((v) => `<button type="button" class="chip" data-ml="${v}">${v} ml</button>`).join('');
$('#mlChips').addEventListener('click', (e) => {
  const b = e.target.closest('[data-ml]');
  if (b) { $('#fMl').value = b.dataset.ml; haptic(); }
});
document.querySelectorAll('.step').forEach((b) => b.addEventListener('click', () => {
  const inp = $('#fMl');
  inp.value = Math.max(0, (parseInt(inp.value, 10) || 0) + Number(b.dataset.delta));
  haptic();
}));

function resetForm() {
  $('#fDate').value = dateStr();
  $('#fTime').value = timeStr();
  $('#fMl').value = prefs.lastMl || 90;
  $('#fNote').value = '';
}

$('#addForm').addEventListener('submit', (e) => {
  e.preventDefault();
  const ml = parseInt($('#fMl').value, 10);
  if (!Number.isFinite(ml) || ml < 0) return toast('Quantità non valida');
  store.add({ id: uid(), ts: `${$('#fDate').value}T${$('#fTime').value}`, ml, note: $('#fNote').value.trim() });
  prefs.lastMl = ml; savePrefs();
  resetForm();
  haptic();
  toast(`Salvata: ${ml} ml`);
});

/* ──────────────────────── modifica ────────────────────────── */

let editingId = null;
const dlg = $('#editDlg');

function openEdit(id) {
  const e = entries.find((x) => x.id === id);
  if (!e) return;
  editingId = id;
  $('#eDate').value = dayOf(e.ts);
  $('#eTime').value = hourOf(e.ts);
  $('#eMl').value = e.ml;
  $('#eNote').value = e.note || '';
  dlg.showModal();
}

$('#editForm').addEventListener('submit', (ev) => {
  ev.preventDefault();
  const old = entries.find((x) => x.id === editingId);
  if (old) {
    store.update({
      id: old.id,
      ts: `${$('#eDate').value}T${$('#eTime').value}`,
      ml: parseInt($('#eMl').value, 10) || 0,
      note: $('#eNote').value.trim(),
    });
    toast('Modifica salvata');
  }
  dlg.close();
});
$('#eCancel').addEventListener('click', () => dlg.close());
$('#eDelete').addEventListener('click', () => {
  if (!confirm('Eliminare questa poppata?')) return;
  store.remove(editingId);
  dlg.close();
  toast('Poppata eliminata');
});

document.addEventListener('click', (ev) => {
  const li = ev.target.closest('ul.list li[data-id]');
  if (li) openEdit(li.dataset.id);
});

/* ─────────────────────── rendering ────────────────────────── */

function byDay() {
  const map = new Map();
  for (const e of entries) {
    if (!map.has(dayOf(e.ts))) map.set(dayOf(e.ts), []);
    map.get(dayOf(e.ts)).push(e);
  }
  return map;
}
const sum = (arr) => arr.reduce((t, e) => t + e.ml, 0);
const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function itemHTML(e) {
  const recent = dayOf(e.ts) >= dateStr(new Date(Date.now() - 864e5));
  const sub = e.note ? esc(e.note) : (recent ? sinceLabel(e.ts) : '');
  return `<li data-id="${e.id}">
      <span class="time">${hourOf(e.ts)}</span>
      <div style="min-width:0"><div class="note">${sub}</div></div>
      <span class="qty">${e.ml} ml</span>
    </li>`;
}

function render() {
  const days = byDay();
  const today = dateStr();
  const shown = $('#fDate').value || today;
  const list = days.get(shown) || [];
  const todayList = days.get(today) || [];

  $('#sToday').textContent = sum(todayList);
  $('#sCount').textContent = todayList.length;
  $('#sLast').textContent = todayList.length ? hourOf(todayList[0].ts) : '–';
  $('#dayLabel').textContent = shown === today ? '' : `— ${labelDay(shown)}`;
  $('#todayList').innerHTML = list.length
    ? list.map(itemHTML).join('')
    : '<li class="empty" style="display:block">Nessuna poppata registrata per questo giorno.</li>';

  $('#hDays').textContent = days.size;
  $('#hTotal').textContent = entries.length;
  const last7 = [...Array(7)].map((_, i) => dateStr(new Date(Date.now() - i * 864e5)));
  const withData = last7.filter((d) => days.has(d));
  $('#hAvg').textContent = withData.length
    ? Math.round(withData.reduce((t, d) => t + sum(days.get(d)), 0) / withData.length)
    : 0;

  $('#historyBox').innerHTML = days.size
    ? [...days.entries()].map(([day, items]) => `
        <div class="card">
          <div class="day">
            <b>${labelDay(day, true)}</b>
            <span>${items.length} poppate · ${sum(items)} ml</span>
          </div>
          <ul class="list">${items.map(itemHTML).join('')}</ul>
        </div>`).join('')
    : '<div class="card"><p class="empty">Nessun dato ancora. Aggiungi la prima poppata dalla scheda “Oggi”.</p></div>';

  updateExportCount();
  renderSync();
  $('#tabSubtitle').textContent = TITLES[currentTab()][1]();
}

$('#fDate').addEventListener('change', render);

/* ──────────────────────── esporta ─────────────────────────── */

function initRange() {
  $('#xTo').value = dateStr();
  $('#xFrom').value = dateStr(new Date(Date.now() - 6 * 864e5));
}

document.querySelectorAll('[data-range]').forEach((b) => b.addEventListener('click', () => {
  const r = b.dataset.range, now = new Date();
  if (r === 'all') {
    const days = [...byDay().keys()];
    $('#xFrom').value = days.length ? days[days.length - 1] : dateStr();
    $('#xTo').value = days.length ? days[0] : dateStr();
  } else if (r === 'month') {
    $('#xFrom').value = dateStr(new Date(now.getFullYear(), now.getMonth(), 1));
    $('#xTo').value = dateStr(now);
  } else {
    $('#xFrom').value = dateStr(new Date(Date.now() - (Number(r) - 1) * 864e5));
    $('#xTo').value = dateStr(now);
  }
  updateExportCount();
}));

function selection() {
  let from = $('#xFrom').value, to = $('#xTo').value;
  if (from && to && from > to) [from, to] = [to, from];
  return entries
    .filter((e) => (!from || dayOf(e.ts) >= from) && (!to || dayOf(e.ts) <= to))
    .slice()
    .sort((a, b) => a.ts.localeCompare(b.ts));
}

function updateExportCount() {
  const sel = selection();
  $('#xCount').textContent = sel.length
    ? `${sel.length} poppate nell'intervallo · ${sum(sel)} ml totali`
    : 'Nessuna poppata nell’intervallo selezionato.';
}
$('#xFrom').addEventListener('change', updateExportCount);
$('#xTo').addEventListener('change', updateExportCount);
$('#xSep').addEventListener('change', () => { prefs.sep = $('#xSep').value; savePrefs(); });

function csv(rows, sep) {
  const cell = (v) => {
    const s = String(v ?? '');
    return /["\n\r]/.test(s) || s.includes(sep) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  return '﻿' + rows.map((r) => r.map(cell).join(sep)).join('\r\n') + '\r\n';
}
const fileTag = () => `${$('#xFrom').value || 'inizio'}_${$('#xTo').value || 'oggi'}`;

$('#xDetail').addEventListener('click', () => {
  const sel = selection();
  if (!sel.length) return toast('Nessun dato da esportare');
  const rows = [['Data', 'Ora', 'Quantita_ml', 'Note']];
  for (const e of sel) rows.push([dayOf(e.ts), hourOf(e.ts), e.ml, e.note || '']);
  rows.push([]);
  rows.push(['Totale poppate', sel.length, 'Totale ml', sum(sel)]);
  saveFile(`poppate_${fileTag()}.csv`, csv(rows, $('#xSep').value), 'text/csv');
});

$('#xDaily').addEventListener('click', () => {
  const sel = selection();
  if (!sel.length) return toast('Nessun dato da esportare');
  const map = new Map();
  for (const e of sel) {
    if (!map.has(dayOf(e.ts))) map.set(dayOf(e.ts), []);
    map.get(dayOf(e.ts)).push(e);
  }
  const rows = [['Data', 'Numero_poppate', 'Totale_ml', 'Media_ml_per_poppata', 'Prima', 'Ultima']];
  for (const [day, items] of map) {
    const tot = sum(items);
    rows.push([day, items.length, tot, Math.round(tot / items.length), hourOf(items[0].ts), hourOf(items[items.length - 1].ts)]);
  }
  saveFile(`riepilogo_giornaliero_${fileTag()}.csv`, csv(rows, $('#xSep').value), 'text/csv');
});

async function saveFile(name, text, mime) {
  const blob = new Blob([text], { type: mime + ';charset=utf-8' });
  try {
    const file = new File([blob], name, { type: mime });
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      await navigator.share({ files: [file], title: name });
      return;
    }
  } catch (err) {
    if (err && err.name === 'AbortError') return;
  }
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = name;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 3000);
  toast('File generato');
}

/* ──────────────────────── backup ──────────────────────────── */

$('#bExport').addEventListener('click', () => {
  const data = JSON.stringify({ app: 'PoppApp', version: 1, exportedAt: new Date().toISOString(), entries }, null, 2);
  saveFile(`poppapp_backup_${dateStr()}.json`, data, 'application/json');
});

$('#bImport').addEventListener('click', () => $('#bFile').click());
$('#bFile').addEventListener('change', async (ev) => {
  const file = ev.target.files[0];
  if (!file) return;
  try {
    const data = JSON.parse(await file.text());
    const incoming = (Array.isArray(data) ? data : data.entries || []).filter(valid);
    if (!incoming.length) return toast('Nessuna poppata trovata nel file');
    const seen = new Set(entries.map((e) => `${e.ts}|${e.ml}`));
    const nuove = [];
    for (const e of incoming) {
      const k = `${e.ts}|${e.ml}`;
      if (seen.has(k)) continue;
      seen.add(k);
      nuove.push({ id: e.id || uid(), ts: e.ts, ml: e.ml, note: e.note || '' });
    }
    if (cloud) for (const e of nuove) cloud.add(e).catch(cloudError);
    setEntries([...entries, ...nuove]);
    toast(nuove.length ? `Importate ${nuove.length} poppate` : 'Dati già presenti');
  } catch {
    toast('File non valido');
  } finally {
    ev.target.value = '';
  }
});

$('#bWipe').addEventListener('click', () => {
  const dove = cloud
    ? 'Cancellare TUTTE le poppate? Essendo i telefoni collegati, spariranno anche dall\'altro telefono.'
    : 'Cancellare TUTTE le poppate registrate? L\'operazione non è reversibile.';
  if (!confirm(dove)) return;
  if (!confirm('Confermi definitivamente? Consigliato fare prima un backup.')) return;
  store.clear();
  toast('Dati cancellati');
});

/* ─────────────────────── famiglia ─────────────────────────── */

const SYNC_TEXT = {
  off: ['solo questo telefono', 'Solo questo telefono'],
  connecting: ['collegamento…', 'Collegamento in corso…'],
  online: ['sincronizzato', 'Sincronizzato'],
  offline: ['offline', 'Offline — le modifiche partono appena torna la rete'],
  error: ['errore', 'Sincronizzazione in errore'],
};

const EXPLAIN = {
  off: 'Le poppate sono salvate solo qui. Nessun altro telefono le vede.',
  connecting: 'Sto contattando l’archivio condiviso.',
  online: 'Le poppate che segni compaiono sull’altro telefono in pochi secondi, e viceversa.',
  offline: 'Puoi continuare a segnare le poppate: restano in coda su questo telefono e si allineano da sole appena torna la connessione.',
  error: 'Controlla la configurazione Firebase e le regole di sicurezza. Le poppate restano comunque salvate su questo telefono.',
};

function renderSync() {
  const [short, long] = SYNC_TEXT[syncState];
  const pill = $('#syncPill');
  pill.textContent = short;
  pill.dataset.state = syncState;
  $('#syncDot').dataset.state = syncState;
  $('#syncText').textContent = long;
  $('#syncExplain').textContent = EXPLAIN[syncState] + (syncState === 'error' && syncDetail ? ` (${syncDetail})` : '');

  const configured = isConfigured();
  const joined = Boolean(prefs.familyCode);
  $('#cardNotConfigured').hidden = configured;
  $('#cardJoin').hidden = !configured || joined;
  $('#cardFamily').hidden = !configured || !joined;
  if (joined) $('#fCode').textContent = prefs.familyCode;
}

/**
 * Collega questo telefono a un archivio di famiglia.
 *
 * `migrate` va messo a true SOLO quando il collegamento è nuovo (creazione del
 * codice, inserimento manuale, link di invito): in quel caso le poppate segnate
 * finora su questo telefono vengono portate in cloud.
 *
 * Alla riapertura dell'app invece NON si migra nulla: la copia locale è solo uno
 * specchio di quella condivisa, e ricaricarla farebbe tornare indietro le
 * poppate cancellate nel frattempo dall'altro telefono.
 */
async function joinFamily(code, { silent = false, migrate = false } = {}) {
  const { connectFamily } = await import('./sync.js');
  prefs.familyCode = code; savePrefs();

  const locali = entries.slice();
  cloud = connectFamily(
    code,
    (remote) => setEntries(remote),
    (state, detail) => { syncState = state; syncDetail = detail || ''; renderSync(); }
  );
  renderSync();

  if (!migrate) return;
  try {
    const caricate = await cloud.mergeLocal(locali);
    if (!silent) toast(caricate ? `Collegato — caricate ${caricate} poppate` : 'Telefono collegato');
  } catch (err) {
    cloudError(err);
  }
}

$('#fCreate').addEventListener('click', async () => {
  const { generateFamilyCode } = await import('./sync.js');
  await joinFamily(generateFamilyCode(), { migrate: true });
  showTab('famiglia');
});

$('#fJoin').addEventListener('click', async () => {
  const { normalizeFamilyCode } = await import('./sync.js');
  const code = normalizeFamilyCode($('#fJoinCode').value);
  if (!code) return toast('Codice non valido');
  await joinFamily(code, { migrate: true });
  showTab('famiglia');
});

$('#fCopy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(prefs.familyCode);
    toast('Codice copiato');
  } catch {
    toast('Copia non riuscita: tieni premuto sul codice');
  }
});

$('#fShare').addEventListener('click', async () => {
  const url = `${location.origin}${location.pathname}#f=${prefs.familyCode}`;
  const text = `PoppApp — il diario delle poppate.\nApri questo link sul telefono (con Safari) e aggiungilo alla schermata Home:\n${url}\n\nCodice famiglia: ${prefs.familyCode}`;
  try {
    if (navigator.share) { await navigator.share({ title: 'PoppApp', text }); return; }
    await navigator.clipboard.writeText(text);
    toast('Messaggio copiato');
  } catch (err) {
    if (err?.name !== 'AbortError') toast('Condivisione non riuscita');
  }
});

$('#fLeave').addEventListener('click', () => {
  if (!confirm('Scollegare questo telefono dall’archivio condiviso?\n\nLe poppate restano salvate qui, ma da adesso non vedrai più quelle segnate dall’altro telefono.')) return;
  if (cloud) { cloud.stop(); cloud = null; }
  delete prefs.familyCode; savePrefs();
  syncState = 'off';
  toast('Telefono scollegato');
  render();
});

/* ──────────────────────── avvio ───────────────────────────── */

resetForm();
initRange();
if (prefs.sep) $('#xSep').value = prefs.sep;
showTab('oggi');

// link di invito: .../#f=codice-famiglia
async function handleInviteLink() {
  const m = location.hash.match(/[#&]f=([a-z0-9-]+)/i);
  if (!m) return false;
  history.replaceState(null, '', location.pathname + location.search);
  if (!isConfigured()) return false;

  const { normalizeFamilyCode } = await import('./sync.js');
  const code = normalizeFamilyCode(m[1]);
  if (!code) return false;
  if (prefs.familyCode === code) return false;

  if (prefs.familyCode && prefs.familyCode !== code) {
    // già collegato a un'altra famiglia: non decido io, glielo propongo
    $('#fJoinCode').value = code;
    showTab('famiglia');
    toast('Codice ricevuto: controlla e conferma');
    return true;
  }
  await joinFamily(code, { silent: true, migrate: true });
  toast('Telefono collegato alla famiglia');
  showTab('oggi');
  return true;
}

handleInviteLink()
  .then((gestito) => {
    if (!gestito && isConfigured() && prefs.familyCode) return joinFamily(prefs.familyCode, { silent: true });
  })
  .catch((err) => {
    // tipicamente: primo avvio offline con l'SDK non ancora in cache
    syncState = 'error';
    syncDetail = err?.code || 'SDK non disponibile';
    renderSync();
  });

// riallinea data e ora quando l'app torna in primo piano
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') return;
  if ($('#fDate').value === dateStr() || !$('#fDate').value) {
    $('#fDate').value = dateStr();
    $('#fTime').value = timeStr();
  }
  render();
});

if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));
}
