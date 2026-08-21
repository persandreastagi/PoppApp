#!/usr/bin/env bash
#
# Prepara il backend di PoppApp. Si lancia UNA VOLTA SOLA, da chi pubblica
# l'app: chi poi la usa non deve configurare niente.
#
#   bash tools/setup-firebase.sh
#
# Unico prerequisito: Node.js 18+ (https://nodejs.org). La CLI Firebase viene
# scaricata al volo da npx.
#
# Lo script crea il progetto, il database, pubblica le regole, registra l'app
# web, scrive la configurazione dentro l'app e infine VERIFICA sul serio che
# la sincronizzazione funzioni: accesso, scrittura, lettura, cancellazione e
# rifiuto dei dati malformati.
#
# È rilanciabile: ciò che risulta già fatto viene saltato.

set -euo pipefail

REGION="${REGION:-eur3}"          # eur3 = multiregione europea; Stati Uniti: nam5
PROJECT_ID="${PROJECT_ID:-}"      # se vuoto ne viene creato uno nuovo

titolo() { printf '\n\033[1;35m▸ %s\033[0m\n' "$*"; }
ok()     { printf '  \033[32m✓\033[0m %s\n' "$*"; }
avviso() { printf '  \033[33m!\033[0m %s\n' "$*"; }
errore() { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

FIREBASE=(npx --yes firebase-tools@15)

[ -f firestore.rules ] && [ -f firebase-config.js ] \
  || errore "Lancia lo script dalla cartella del progetto PoppApp."

# ── 0. strumenti ────────────────────────────────────────────────────────────
titolo "Controllo degli strumenti"
command -v node >/dev/null || errore "Node.js non trovato: installalo da https://nodejs.org e rilancia."
ok "Node.js $(node --version)"
command -v curl >/dev/null || errore "curl non trovato."
ok "curl presente"

# ── 1. CLI Firebase ─────────────────────────────────────────────────────────
# Va scaricata alla prima esecuzione: sono decine di megabyte. Il comando resta
# volutamente rumoroso, altrimenti sembra che lo script si sia piantato.
titolo "Preparazione della CLI Firebase"
echo "  Alla prima esecuzione viene scaricata: può richiedere un minuto o due."
echo "  Se sembra ferma, aspetta: sta scaricando."
echo ""
"${FIREBASE[@]}" --version
ok "CLI Firebase pronta"

# ── 2. accesso ──────────────────────────────────────────────────────────────
titolo "Accesso al tuo account Google"
if "${FIREBASE[@]}" login:list 2>/dev/null | grep -q "@"; then
  ok "già autenticato"
elif [ "${LOGIN_MANUALE:-0}" = "1" ]; then
  echo "  Login manuale: comparirà un indirizzo da aprire nel browser, poi un"
  echo "  codice da riportare qui."
  "${FIREBASE[@]}" login --no-localhost
else
  echo "  Dovrebbe aprirsi il browser da solo."
  echo ""
  echo "  Se NON si apre: qui sotto compare un indirizzo lungo che comincia con"
  echo "  https://accounts.google.com/... — copialo e aprilo tu nel browser."
  echo ""
  echo "  Se non compare nessun indirizzo: interrompi con CTRL-C e rilancia con"
  echo "    LOGIN_MANUALE=1 bash tools/setup-firebase.sh"
  echo ""
  "${FIREBASE[@]}" login
fi

# ── 3. progetto ─────────────────────────────────────────────────────────────
titolo "Progetto Firebase"
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="poppapp-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
  echo "  Creo il progetto: $PROJECT_ID"
  echo "  (per riusarne uno tuo: PROJECT_ID=... bash tools/setup-firebase.sh)"
  "${FIREBASE[@]}" projects:create "$PROJECT_ID" -n "PoppApp"
  ok "progetto creato"
else
  # Attenzione: l'ID del progetto NON è il nome che si legge nella console.
  # È tutto minuscolo, tipo "poppapp-a1b2c3". Lo si ricava da projects:list.
  if ! [[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
    errore "\"$PROJECT_ID\" non è un ID di progetto valido.
   L'ID è tutto minuscolo (lettere, cifre e trattini) e non è il nome
   visualizzato nella console: \"PoppApp\" è un nome, \"poppapp-a1b2c3\" è un ID.
   Trova il tuo con:
     npx --yes firebase-tools@15 projects:list
   e usa la colonna \"Project ID\"."
  fi
  if ! "${FIREBASE[@]}" projects:list 2>/dev/null | grep -q "$PROJECT_ID"; then
    errore "Il progetto \"$PROJECT_ID\" non risulta fra i tuoi.
   Elenca quelli disponibili con:
     npx --yes firebase-tools@15 projects:list
   Oppure lascia che lo script ne crei uno nuovo:
     bash tools/setup-firebase.sh"
  fi
  ok "uso il progetto indicato: $PROJECT_ID"
fi

# ── 4. database ─────────────────────────────────────────────────────────────
titolo "Database Firestore (regione $REGION)"

database_presente() {
  "${FIREBASE[@]}" firestore:databases:get "(default)" --project "$PROJECT_ID" >/dev/null 2>&1
}
crea_database() {
  "${FIREBASE[@]}" firestore:databases:create "(default)" --location="$REGION" --project "$PROJECT_ID"
}

if database_presente; then
  avviso "database già presente, lo lascio com'è"
elif crea_database; then
  ok "database creato"
else
  # "An unexpected error has occurred" quasi sempre significa API Firestore
  # ancora spenta sul progetto. Sono due interruttori, poi si riprova da qui.
  echo ""
  avviso "Creazione non riuscita. Quasi sempre è l'API Firestore ancora spenta."
  echo ""
  echo "  1) Attiva l'API (pulsante ABILITA, poi aspetta che finisca):"
  printf '     \033[1;36mhttps://console.cloud.google.com/apis/library/firestore.googleapis.com?project=%s\033[0m\n' "$PROJECT_ID"
  echo ""
  echo "  2) Oppure, più diretto, crea il database a mano — è una pagina sola:"
  printf '     \033[1;36mhttps://console.firebase.google.com/project/%s/firestore\033[0m\n' "$PROJECT_ID"
  echo "     → Crea database → modalità produzione → posizione $REGION"
  echo ""
  for tentativo in $(seq 1 10); do
    read -r -p "  Premi INVIO quando l'hai fatto (o CTRL-C per uscire)... " _ </dev/tty || true
    if database_presente; then ok "database presente"; break; fi
    if crea_database; then ok "database creato"; break; fi
    avviso "ancora non risulta: se hai appena attivato l'API, dalle qualche secondo"
    if [ "$tentativo" -eq 10 ]; then
      errore "Database non creato. Per vedere l'errore vero, senza filtri:
   npx --yes firebase-tools@15 firestore:databases:create \"(default)\" --location=$REGION --project $PROJECT_ID --debug"
    fi
  done
fi

# ── 5. regole di sicurezza ──────────────────────────────────────────────────
titolo "Regole di sicurezza"
"${FIREBASE[@]}" deploy --only firestore:rules --project "$PROJECT_ID" --non-interactive
ok "regole pubblicate"

# ── 6. app web e configurazione ─────────────────────────────────────────────
titolo "App web"
trova_app() {
  "${FIREBASE[@]}" apps:list WEB --project "$PROJECT_ID" 2>/dev/null \
    | grep -oE '1:[0-9]+:web:[a-z0-9]+' | head -1 || true
}
APP_ID="$(trova_app)"
if [ -z "$APP_ID" ]; then
  "${FIREBASE[@]}" apps:create WEB "PoppApp" --project "$PROJECT_ID" >/dev/null
  APP_ID="$(trova_app)"
  ok "app web creata"
else
  avviso "app web già presente"
fi
[ -n "$APP_ID" ] || errore "non sono riuscito a ricavare l'ID dell'app web."

"${FIREBASE[@]}" apps:sdkconfig WEB "$APP_ID" --project "$PROJECT_ID" > /tmp/poppapp-sdkconfig.txt
bash tools/write-config.sh /tmp/poppapp-sdkconfig.txt --no-commit
API_KEY="$(grep -oE "apiKey: '[^']+'" firebase-config.js | cut -d"'" -f2 || true)"
[ -n "$API_KEY" ] || errore "configurazione non scritta correttamente in firebase-config.js"
ok "configurazione scritta in firebase-config.js"

# ── 7. accesso anonimo ──────────────────────────────────────────────────────
# È l'unico passaggio che la CLI Firebase non copre. Con gcloud si fa da qui;
# senza, è un singolo interruttore nella console.
titolo "Accesso anonimo"

anonimo_attivo() {
  local r
  r="$(curl -sS -X POST -H 'Content-Type: application/json' -d '{"returnSecureToken":true}' \
       "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$API_KEY" || true)"
  grep -q '"idToken"' <<<"$r"
}

if anonimo_attivo; then
  ok "già attivo"
elif command -v gcloud >/dev/null && gcloud auth print-access-token >/dev/null 2>&1; then
  curl -sS -X PATCH \
    "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT_ID/config?updateMask=signIn.anonymous.enabled" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -d '{"signIn":{"anonymous":{"enabled":true}}}' >/dev/null
  if anonimo_attivo; then ok "attivato con gcloud"; else errore "attivazione con gcloud non riuscita."; fi
else
  echo "  Un solo interruttore da girare, poi lo script prosegue da solo:"
  echo ""
  printf '    \033[1;36mhttps://console.firebase.google.com/project/%s/authentication/providers\033[0m\n' "$PROJECT_ID"
  echo ""
  echo "    → \"Inizia\" se te lo chiede → voce \"Anonimo\" → attiva → Salva"
  echo ""
  for tentativo in $(seq 1 30); do
    read -r -p "  Premi INVIO quando l'hai fatto (o CTRL-C per uscire)... " _ </dev/tty || true
    if anonimo_attivo; then ok "accesso anonimo attivo"; break; fi
    avviso "non risulta ancora attivo, riprovo a controllare"
    if [ "$tentativo" -eq 30 ]; then errore "accesso anonimo non attivato."; fi
  done
fi

# ── 8. verifica vera ────────────────────────────────────────────────────────
titolo "Verifica della sincronizzazione"

TOKEN="$(curl -sS -X POST -H 'Content-Type: application/json' -d '{"returnSecureToken":true}' \
  "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$API_KEY" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("idToken",""))')"
[ -n "$TOKEN" ] || errore "accesso anonimo non riuscito."
ok "accesso anonimo riuscito"

PROVA="verifica-setup-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 12)"
DOC="https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/families/$PROVA/poppate/prova"

codice_http() {  # metodo, corpo (facoltativo)
  if [ -n "${2:-}" ]; then
    curl -sS -o /tmp/poppapp-verifica.json -w '%{http_code}' -X "$1" "$DOC" \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$2"
  else
    curl -sS -o /tmp/poppapp-verifica.json -w '%{http_code}' -X "$1" "$DOC" \
      -H "Authorization: Bearer $TOKEN"
  fi
}

BUONA='{"fields":{"ts":{"stringValue":"2026-01-01T08:00"},"ml":{"integerValue":"90"},"note":{"stringValue":"verifica"}}}'
[ "$(codice_http PATCH "$BUONA")" = "200" ] || { cat /tmp/poppapp-verifica.json; errore "scrittura di prova rifiutata."; }
ok "scrittura consentita"

[ "$(codice_http GET)" = "200" ] || errore "lettura di prova non riuscita."
ok "lettura consentita"

# le regole devono rifiutare una quantità assurda: se passa, non sono attive
CATTIVA='{"fields":{"ts":{"stringValue":"2026-01-01T08:00"},"ml":{"integerValue":"99999"},"note":{"stringValue":"x"}}}'
if [ "$(codice_http PATCH "$CATTIVA")" = "200" ]; then
  errore "le regole di sicurezza non sono attive: un valore fuori scala è stato accettato.
   Rilancia: npx firebase-tools deploy --only firestore:rules --project $PROJECT_ID"
fi
ok "regole attive: dati malformati rifiutati"

[ "$(codice_http DELETE)" = "200" ] || avviso "documento di prova non cancellato (ininfluente)"
ok "pulizia della prova"

# ── 8. fine ─────────────────────────────────────────────────────────────────
titolo "Tutto pronto"
cat <<EOF
  Progetto:  $PROJECT_ID
  App web:   $APP_ID
  Regione:   $REGION

  La configurazione è dentro firebase-config.js. Per metterla in circolo, una
  delle due:

  A) pubblicarla per tutti i telefoni (consigliata)
       git add firebase-config.js && git commit -m "Backend di PoppApp" && git push

  B) senza git, un telefono alla volta: apri PoppApp -> scheda Famiglia e
     incolla il blocco qui sotto (e' anche in /tmp/poppapp-config.txt)

EOF

# stampa la configurazione anche a schermo: serve a chi sceglie la via B
python3 - <<'PY2'
import pathlib, re
testo = pathlib.Path('firebase-config.js').read_text()
campi = dict(re.findall(r"(\w+): '([^']+)'", testo))
blocco = 'const firebaseConfig = {\n' + ''.join(
    f'  {k}: "{campi[k]}",\n' for k in ('apiKey', 'authDomain', 'projectId', 'appId') if k in campi
) + '};'
pathlib.Path('/tmp/poppapp-config.txt').write_text(blocco + '\n')
print(blocco)
PY2

echo ""
echo "  Poi, dal telefono: Famiglia -> Crea un nuovo codice famiglia ->"
echo "  Invia link e codice. Sull'altro telefono basta aprire il link."
