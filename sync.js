/*
 * Sincronizzazione fra telefoni via Firebase Firestore.
 *
 * Il modello è volutamente minimo: tutte le poppate di una famiglia stanno in
 *     families/{codiceFamiglia}/poppate/{id}
 * Il codice famiglia è un segreto casuale abbastanza lungo da non essere
 * indovinabile: chi non ce l'ha non sa nemmeno quale documento chiedere, e le
 * regole in firestore.rules impediscono tutto il resto.
 *
 * La cache offline di Firestore fa il lavoro sporco: le poppate segnate senza
 * campo restano in coda su questo telefono e partono da sole appena torna la rete.
 */

import {
  initializeApp,
  getAuth,
  signInAnonymously,
  initializeFirestore,
  persistentLocalCache,
  persistentMultipleTabManager,
  collection,
  doc,
  setDoc,
  deleteDoc,
  onSnapshot,
  getDocs,
  writeBatch,
} from './vendor/firebase.js';

import { firebaseConfig } from './firebase-config.js';

const ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789'; // niente l/o/0/1: si confondono
const GROUPS = 5;
const GROUP_LEN = 4;

/** Genera un codice famiglia del tipo "p7k2-9fpq-m3wz-x4rt-b8de" (~100 bit). */
export function generateFamilyCode() {
  const bytes = new Uint8Array(GROUPS * GROUP_LEN);
  crypto.getRandomValues(bytes);
  const chars = [...bytes].map((b) => ALPHABET[b % ALPHABET.length]);
  return Array.from({ length: GROUPS }, (_, i) =>
    chars.slice(i * GROUP_LEN, (i + 1) * GROUP_LEN).join('')
  ).join('-');
}

/** Ripulisce un codice digitato a mano (spazi, maiuscole, trattini mancanti). */
export function normalizeFamilyCode(raw) {
  const clean = String(raw || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  if (clean.length !== GROUPS * GROUP_LEN) return null;
  if ([...clean].some((c) => !ALPHABET.includes(c))) return null;
  return Array.from({ length: GROUPS }, (_, i) =>
    clean.slice(i * GROUP_LEN, (i + 1) * GROUP_LEN)
  ).join('-');
}

let app = null;
let db = null;
let authReady = null;

function ensureApp() {
  if (app) return;
  app = initializeApp(firebaseConfig);
  db = initializeFirestore(app, {
    localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }),
  });
  authReady = signInAnonymously(getAuth(app));
}

const toEntry = (d) => {
  const v = d.data();
  return { id: d.id, ts: v.ts, ml: Number(v.ml), note: v.note || '' };
};
const toDoc = (e) => ({ ts: e.ts, ml: Number(e.ml), note: e.note || '' });

/**
 * Apre la connessione per un codice famiglia.
 *
 * @param {string} code       codice famiglia normalizzato
 * @param {(entries: object[]) => void} onEntries  chiamata a ogni cambiamento
 * @param {(status: string, detail?: string) => void} onStatus
 *        'connecting' | 'online' | 'offline' | 'error'
 * @returns {{stop: Function, add: Function, update: Function, remove: Function, mergeLocal: Function}}
 */
export function connectFamily(code, onEntries, onStatus) {
  ensureApp();
  const col = collection(db, 'families', code, 'poppate');
  onStatus('connecting');

  let unsubscribe = () => {};
  authReady
    .then(() => {
      unsubscribe = onSnapshot(
        col,
        { includeMetadataChanges: true },
        (snap) => {
          onEntries(snap.docs.map(toEntry));
          // fromCache dopo il primo giro significa: rete assente, stiamo servendo la cache
          onStatus(snap.metadata.fromCache ? 'offline' : 'online');
        },
        (err) => onStatus('error', err.code || err.message)
      );
    })
    .catch((err) => onStatus('error', err.code || err.message));

  return {
    stop: () => unsubscribe(),
    add: (e) => setDoc(doc(col, e.id), toDoc(e)),
    update: (e) => setDoc(doc(col, e.id), toDoc(e)),
    remove: (id) => deleteDoc(doc(col, id)),

    /**
     * Porta in cloud le poppate registrate su questo telefono prima
     * dell'attivazione, saltando quelle già presenti.
     * @returns {Promise<number>} quante ne ha caricate
     */
    async mergeLocal(localEntries) {
      if (!localEntries.length) return 0;
      await authReady;
      const existing = await getDocs(col);
      const seen = new Set(existing.docs.map((d) => { const e = toEntry(d); return `${e.ts}|${e.ml}`; }));
      const nuove = localEntries.filter((e) => !seen.has(`${e.ts}|${e.ml}`));
      for (let i = 0; i < nuove.length; i += 400) {
        const batch = writeBatch(db);
        for (const e of nuove.slice(i, i + 400)) batch.set(doc(col, e.id), toDoc(e));
        await batch.commit();
      }
      return nuove.length;
    },
  };
}
