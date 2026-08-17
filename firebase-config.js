/*
 * Configurazione della sincronizzazione fra telefoni.
 *
 * Finché i campi qui sotto restano vuoti, PoppApp funziona esattamente come prima:
 * i dati restano solo su questo telefono e non esce nulla in rete.
 *
 * Per attivare la sincronizzazione segui il capitolo "Sincronizzare due telefoni"
 * del README e incolla qui i valori del TUO progetto Firebase.
 *
 * Nota: questi valori non sono password. La configurazione web di Firebase è
 * pubblica per progetto: a proteggere i dati sono il codice famiglia e le regole
 * di sicurezza in firestore.rules.
 */
export const firebaseConfig = {
  apiKey: '',
  authDomain: '',
  projectId: '',
  appId: '',
};

export const isConfigured = () =>
  Boolean(firebaseConfig.apiKey && firebaseConfig.projectId && firebaseConfig.appId);
