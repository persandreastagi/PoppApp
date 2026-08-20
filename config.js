/*
 * Da dove arriva la configurazione Firebase.
 *
 * Due strade, in ordine di precedenza:
 *  1. quella incollata nell'app (scheda Famiglia), salvata su questo telefono;
 *  2. quella eventualmente scritta in firebase-config.js dentro il repository.
 *
 * La prima esiste per non dover toccare il codice: si copia il blocco che la
 * console Firebase mostra alla creazione dell'app web e lo si incolla nell'app.
 */

import { firebaseConfig as baked } from './firebase-config.js';

const KEY = 'poppapp.fbconfig.v1';

const completa = (c) => Boolean(c && c.apiKey && c.projectId && c.appId);

export function getConfig() {
  try {
    const salvata = JSON.parse(localStorage.getItem(KEY) || 'null');
    if (completa(salvata)) return salvata;
  } catch { /* configurazione salvata illeggibile: si ricade su quella del repository */ }
  return completa(baked) ? baked : null;
}

export const isConfigured = () => Boolean(getConfig());

/**
 * Da dove arriva la configurazione attiva.
 *
 * Serve a distinguere l'app pubblicata (configurazione nel codice: chi la usa
 * non deve toccare niente, e non deve nemmeno vedere i comandi per farlo) da
 * una copia configurata a mano su un singolo telefono.
 *
 * @returns {'codice'|'incollata'|null}
 */
export function configSource() {
  try {
    const salvata = JSON.parse(localStorage.getItem(KEY) || 'null');
    if (completa(salvata)) return 'incollata';
  } catch { /* vedi getConfig() */ }
  return completa(baked) ? 'codice' : null;
}

export function setConfig(cfg) {
  if (!completa(cfg)) throw new Error('configurazione incompleta');
  localStorage.setItem(KEY, JSON.stringify(cfg));
}

export function clearConfig() {
  localStorage.removeItem(KEY);
}

/**
 * Estrae la configurazione da quello che l'utente ha incollato.
 *
 * Accetta sia il blocco JavaScript della console Firebase
 *   const firebaseConfig = { apiKey: "AIza…", authDomain: "x.firebaseapp.com", … };
 * sia il solo oggetto, sia JSON. Ignora tutto ciò che non riconosce.
 *
 * @returns {object|null} la configurazione, o null se manca qualcosa di essenziale
 */
export function parseConfig(text) {
  const cfg = {};
  const re = /["']?([A-Za-z]+)["']?\s*:\s*["']([^"']+)["']/g;
  let m;
  while ((m = re.exec(String(text || '')))) cfg[m[1]] = m[2];

  const out = {
    apiKey: cfg.apiKey,
    projectId: cfg.projectId,
    appId: cfg.appId,
    authDomain: cfg.authDomain || (cfg.projectId ? `${cfg.projectId}.firebaseapp.com` : undefined),
  };
  if (cfg.storageBucket) out.storageBucket = cfg.storageBucket;
  if (cfg.messagingSenderId) out.messagingSenderId = cfg.messagingSenderId;
  return completa(out) ? out : null;
}

/* ── trasporto della configurazione dentro il link di invito ────────────────
 * Non è un segreto (la configurazione web di Firebase è pubblica per progetto),
 * ma sta nel frammento dell'URL, che il browser non manda al server.
 */

export function encodeConfig(cfg) {
  const minima = { apiKey: cfg.apiKey, authDomain: cfg.authDomain, projectId: cfg.projectId, appId: cfg.appId };
  return btoa(JSON.stringify(minima)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function decodeConfig(s) {
  try {
    const b64 = String(s).replace(/-/g, '+').replace(/_/g, '/');
    const cfg = JSON.parse(atob(b64));
    return completa(cfg) ? cfg : null;
  } catch {
    return null;
  }
}
