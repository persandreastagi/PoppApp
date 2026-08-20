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

# ── 1. accesso ──────────────────────────────────────────────────────────────
titolo "Accesso al tuo account Google"
if "${FIREBASE[@]}" login:list 2>/dev/null | grep -q "@"; then
  ok "già autenticato"
else
  avviso "si aprirà il browser (su macchina senza browser: aggiungi --no-localhost)"
  "${FIREBASE[@]}" login
fi

# ── 2. progetto ─────────────────────────────────────────────────────────────
titolo "Progetto Firebase"
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="poppapp-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
  echo "  Creo il progetto: $PROJECT_ID"
  echo "  (per riusarne uno tuo: PROJECT_ID=... bash tools/setup-firebase.sh)"
  "${FIREBASE[@]}" projects:create "$PROJECT_ID" -n "PoppApp"
  ok "progetto creato"
else
  ok "uso il progetto indicato: $PROJECT_ID"
fi

# ── 3. database ─────────────────────────────────────────────────────────────
titolo "Database Firestore (regione $REGION)"
if "${FIREBASE[@]}" firestore:databases:get "(default)" --project "$PROJECT_ID" >/dev/null 2>&1; then
  avviso "database già presente, lo lascio com'è"
else
  if ! "${FIREBASE[@]}" firestore:databases:create "(default)" --location="$REGION" --project "$PROJECT_ID"; then
    errore "Creazione del database non riuscita.
   Se l'errore parla di API disattivata, aprila una volta qui e rilancia lo script:
   https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=$PROJECT_ID"
  fi
  ok "database creato"
fi

# ── 4. regole di sicurezza ──────────────────────────────────────────────────
titolo "Regole di sicurezza"
"${FIREBASE[@]}" deploy --only firestore:rules --project "$PROJECT_ID" --non-interactive
ok "regole pubblicate"

# ── 5. app web e configurazione ─────────────────────────────────────────────
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

# ── 6. accesso anonimo ──────────────────────────────────────────────────────
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

# ── 7. verifica vera ────────────────────────────────────────────────────────
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

  La configurazione è dentro firebase-config.js: da ora chi apre l'app non
  deve impostare niente. Pubblicala:

    git add firebase-config.js && git commit -m "Backend di PoppApp" && git push

  Poi, dal telefono: Famiglia → Crea un nuovo codice famiglia → Invia link e
  codice. Sull'altro telefono basta aprire il link.
EOF
