# PoppApp 🍼

Diario delle poppate: registri giorno per giorno **orario** e **quantità in ml** di ogni poppata,
e quando serve esporti in **CSV** i dati di un intervallo di date.

È una *web app installabile* (PWA): si aggiunge alla schermata Home dell'iPhone e da lì si comporta
come un'app normale — icona, schermo intero, nessuna barra di Safari, **funziona anche senza rete**.
Non serve l'App Store e non serve un Mac.

Due telefoni possono condividere lo stesso diario tramite un **codice famiglia**: chi segna una
poppata la fa comparire sull'altro telefono in pochi secondi (capitolo 5).

---

## 1. Metterla online (una volta sola, 1 minuto)

Il codice è già pronto per GitHub Pages, e il branch `claude/app-tracciamento-allattamento-j7bxmf`
è il branch predefinito del repository: non serve nessun merge.

1. Apri **https://github.com/persandreastagi/PoppApp/settings/pages**
2. In *Build and deployment → Source* scegli **GitHub Actions**.
3. Vai su **Actions → Deploy su GitHub Pages → Run workflow** (oppure aspetta il push successivo:
   il workflow `.github/workflows/pages.yml` gira da solo a ogni push su questo branch).
4. Dopo un paio di minuti l'app è online a:

   ```
   https://persandreastagi.github.io/PoppApp/
   ```

> Alternativa senza Actions: in *Source* scegli **Deploy from a branch**, branch
> `claude/app-tracciamento-allattamento-j7bxmf`, cartella `/ (root)`, e salva. Stesso indirizzo finale.

## 2. Installarla sull'iPhone

1. Apri quell'indirizzo **con Safari** (non Chrome: solo Safari sa installare le app sulla Home).
2. Tocca il pulsante **Condividi** (il quadrato con la freccia in su).
3. Scegli **Aggiungi a Home**, poi **Aggiungi**.
4. Trovi l'icona del biberon tra le app. Da lì in poi funziona anche in aereo o senza campo.

## 3. Come si usa

**Oggi** — in alto il totale di ml della giornata, il numero di poppate e l'ora dell'ultima.
Sotto il modulo di inserimento: giorno e orario sono già compilati con *adesso*, la quantità si imposta
con i pulsanti rapidi (30 / 60 / 90 / 120 / 150 / 180 ml) o con **−** e **+** a passi di 10.
Il campo note è facoltativo. Un tocco su **Salva poppata** e sei a posto.

**Storico** — tutte le giornate, dalla più recente, ognuna con numero di poppate e totale ml.
**Tocca una riga qualsiasi per correggerla o eliminarla** (vale anche nella scheda Oggi).

**Famiglia** — collega il telefono di chi segue le poppate con te, o mostra il codice famiglia da
passargli. Se la sincronizzazione non è configurata, la scheda lo dice e spiega come attivarla.

**Esporta** — scegli l'intervallo `Dal` / `Al` (o usa le scorciatoie *Ultimi 7 giorni*, *Ultimi 30 giorni*,
*Questo mese*, *Tutto*) e poi:

| Pulsante | Contenuto del CSV |
|---|---|
| **Esporta dettaglio poppate** | una riga per poppata: `Data`, `Ora`, `Quantita_ml`, `Note` + riga finale coi totali |
| **Riepilogo giornaliero** | una riga per giorno: `Data`, `Numero_poppate`, `Totale_ml`, `Media_ml_per_poppata`, `Prima`, `Ultima` |

Si apre il menu di condivisione di iOS: puoi salvare il file in **File**, mandarlo via mail
(comodo per il pediatra) o su WhatsApp.

Il separatore predefinito è il **punto e virgola**, quello che l'Excel italiano si aspetta: il file si apre
già diviso in colonne con un doppio tocco. Se usi Fogli Google, scegli la virgola dal menu a tendina.

## 4. Dove finiscono i dati

Di base restano **solo sul tuo iPhone** (archivio locale di Safari): nessun server, nessun account.
Il rovescio della medaglia è doppio: se cancelli l'app o cambi telefono spariscono, e **ogni telefono
vede solo le proprie poppate**. Per condividerle con un secondo telefono vedi il capitolo 5.

In ogni caso, nella scheda Esporta c'è **Backup**: *Esporta backup* salva un file `.json` con tutto lo
storico, *Importa backup* lo rimette dentro (anche su un altro telefono, e senza creare doppioni).
Fanne uno ogni tanto, magari su iCloud Drive.

## 5. Sincronizzare due telefoni

Con la sincronizzazione attiva, chi segna una poppata la fa comparire sull'altro telefono in pochi
secondi. Si può continuare a segnare anche senza campo: le poppate restano in coda e partono da sole
appena torna la rete.

Serve un progetto Firebase gratuito (piano Spark: per due telefoni i consumi sono trascurabili).
**Da fare una volta sola, su un telefono solo.** Sono tutti clic nella console Firebase: non c'è
niente da modificare nel codice.

1. **Crea il progetto** — vai su [console.firebase.google.com](https://console.firebase.google.com),
   *Crea un progetto*, chiamalo `PoppApp`. Google Analytics: puoi disattivarlo, non serve.
2. **Attiva l'accesso anonimo** — *Authentication* → *Inizia* → scheda *Sign-in method* →
   **Anonimo** → attiva. Serve perché le regole di sicurezza rifiutino le richieste che non
   arrivano dall'app; per voi è invisibile, non c'è nessun login da fare.
3. **Crea il database** — *Firestore Database* → *Crea database* → modalità **produzione** →
   posizione `eur3 (europe-west)`.
4. **Pubblica le regole** — scheda *Regole*, sostituisci tutto con il contenuto di
   [`firestore.rules`](firestore.rules) e premi *Pubblica*. Senza questo passo il database resta
   chiuso e l'app segnala un errore di sincronizzazione.
5. **Aggiungi un'app web** — *Impostazioni progetto* (l'ingranaggio) → sezione *Le tue app* →
   icona `</>`, dai un nome (`PoppApp`), **non** attivare Firebase Hosting. Alla fine ti mostra un
   blocco che comincia con `const firebaseConfig = {`: **copialo tutto**.
6. **Incollalo nell'app** — apri PoppApp, scheda **Famiglia**, incolla nel riquadro e premi
   *Attiva la sincronizzazione*. (Lo stesso blocco resta sempre disponibile in
   *Impostazioni progetto → Le tue app*.)
7. **Collega l'altro telefono** — scheda **Famiglia** → *Crea un nuovo codice famiglia* →
   *Invia link e codice*: parte un messaggio già pronto. Chi lo riceve apre il link con Safari e il
   telefono si collega da solo: **il link porta con sé anche la configurazione**, quindi sul secondo
   telefono non c'è niente da impostare.

La pillola in alto a destra dice sempre a che punto sta: *solo questo telefono*, *sincronizzato*,
*offline*, *errore*.

In alternativa alla scheda Famiglia, la configurazione si può scrivere una volta per tutte in
`firebase-config.js`: vale per chiunque apra l'app, ma richiede un commit e il redeploy.

### Il codice famiglia

È una stringa casuale tipo `p7k2-9fpq-m3wz-x4rt-b8de` (~100 bit): è la chiave dell'archivio
condiviso, e chi ce l'ha vede tutte le poppate. **Trattalo come una password.** Le regole in
`firestore.rules` chiudono tutto il resto: niente scritture fuori dal percorso della famiglia,
niente codici corti, niente documenti di forma diversa da quella prevista.

I valori in `firebase-config.js`, invece, **non sono segreti**: la configurazione web di Firebase è
pubblica per progetto e sta in chiaro in qualsiasi app che la usi. A proteggere i dati sono il codice
famiglia e le regole di sicurezza, non quei valori.

Finché non incolli una configurazione, l'app funziona come prima, tutta in locale: la scheda
Famiglia lo dice esplicitamente e non viene caricato nulla di Firebase.

## 6. Struttura del progetto

```
index.html            struttura e stile dell'interfaccia
app.js                logica dell'app: inserimento, storico, CSV, backup, schede
sync.js               sincronizzazione via Firestore e gestione del codice famiglia
config.js             da dove arriva la configurazione Firebase (incollata o dal repository)
firebase-config.js    configurazione scritta nel repository (facoltativa, vuota = solo locale)
firestore.rules       regole di sicurezza da incollare nella console Firebase
vendor/firebase.js    SDK Firebase impacchettato nel repository (niente CDN esterne)
manifest.webmanifest  nome, icona e modalità a schermo intero per l'installazione
sw.js                 service worker: mette in cache l'app per l'uso offline
icons/                icone dell'app
tools/make_icons.py   rigenera le icone PNG (python3 tools/make_icons.py)
.github/workflows/    pubblicazione automatica su GitHub Pages
```

Per provarla al computer serve un server locale nella cartella del progetto
(`python3 -m http.server 8000`, poi apri `http://localhost:8000`): con il doppio clic su
`index.html` i moduli JavaScript non si caricano.

### Aggiornamenti

Se modifichi i file dell'app, alza il numero di versione della cache in `sw.js`
(`const CACHE = 'poppapp-v3'`) così l'iPhone scarica la versione nuova invece di riusare quella salvata.

### Rigenerare il bundle Firebase

`vendor/firebase.js` è un pacchetto delle sole parti di Firebase che servono (app, auth, firestore),
tenuto nel repository per non dipendere da CDN esterne e restare utilizzabile offline. Per rifarlo:

```sh
npm i firebase esbuild
npx esbuild bundle-entry.js --bundle --format=esm --minify --outfile=vendor/firebase.js
```

dove `bundle-entry.js` riesporta le funzioni elencate in cima a `sync.js`.
