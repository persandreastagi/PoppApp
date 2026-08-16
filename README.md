# PoppApp 🍼

Diario delle poppate: registri giorno per giorno **orario** e **quantità in ml** di ogni poppata,
e quando serve esporti in **CSV** i dati di un intervallo di date.

È una *web app installabile* (PWA): si aggiunge alla schermata Home dell'iPhone e da lì si comporta
come un'app normale — icona, schermo intero, nessuna barra di Safari, **funziona anche senza rete**.
Non serve l'App Store, non serve un Mac, non serve un account.

---

## 1. Metterla online (una volta sola, 2 minuti)

Il codice è già pronto per GitHub Pages.

1. Vai su **Settings → Pages** del repository `persandreastagi/poppapp`.
2. In *Build and deployment → Source* scegli **GitHub Actions** e salva.
3. Fai il merge di questo branch su `main`: il workflow `.github/workflows/pages.yml` pubblica il sito da solo.
4. Dopo un minuto l'app è all'indirizzo:

   ```
   https://persandreastagi.github.io/poppapp/
   ```

> In alternativa, in *Source* puoi scegliere **Deploy from a branch** → branch `main`, cartella `/ (root)`:
> funziona ugualmente, il workflow diventa superfluo.

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

Restano **solo sul tuo iPhone** (archivio locale di Safari). Nessun server, nessun account, nessuno
li vede a parte te. Il rovescio della medaglia: se cancelli l'app o cambi telefono, spariscono.

Per questo nella scheda Esporta c'è **Backup**: *Esporta backup* salva un file `.json` con tutto lo
storico, *Importa backup* lo rimette dentro (anche su un altro telefono, e senza creare doppioni).
Fanne uno ogni tanto, magari su iCloud Drive.

## 5. Struttura del progetto

```
index.html            l'app intera (interfaccia + logica, nessuna dipendenza esterna)
manifest.webmanifest  nome, icona e modalità a schermo intero per l'installazione
sw.js                 service worker: mette in cache l'app per l'uso offline
icons/                icone dell'app
tools/make_icons.py   rigenera le icone PNG (python3 tools/make_icons.py)
.github/workflows/    pubblicazione automatica su GitHub Pages
```

Per provarla al computer basta un server locale nella cartella del progetto
(`python3 -m http.server 8000`, poi apri `http://localhost:8000`): aprendo `index.html` con doppio clic
il service worker non si registra, ma il resto funziona lo stesso.

### Aggiornamenti

Se modifichi `index.html`, alza il numero di versione della cache in `sw.js`
(`const CACHE = 'poppapp-v2'`) così l'iPhone scarica la versione nuova invece di riusare quella salvata.
