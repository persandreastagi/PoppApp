/*
 * Configurazione della sincronizzazione fra telefoni.
 *
 * Scritta da tools/write-config.sh. Non sono credenziali segrete: la
 * configurazione web di Firebase è pubblica per progetto. A proteggere i dati
 * sono il codice famiglia e le regole in firestore.rules.
 */
export const firebaseConfig = {
  apiKey: 'AIzaSyAD5JCeogSffBXWwmp7owC0w7abgJcH2kA',
  authDomain: 'poppapp-fada9.firebaseapp.com',
  projectId: 'poppapp-fada9',
  appId: '1:942475128930:web:63dde4a3bd4aef1a17613b',
};

export const isConfigured = () =>
  Boolean(firebaseConfig.apiKey && firebaseConfig.projectId && firebaseConfig.appId);
