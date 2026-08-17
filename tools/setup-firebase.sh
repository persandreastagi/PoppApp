#!/usr/bin/env bash
#
# Prepara da riga di comando tutto ciò che serve alla sincronizzazione di PoppApp:
# progetto Firebase, database Firestore, accesso anonimo, regole di sicurezza e
# app web. Alla fine stampa la configurazione da incollare nell'app.
#
#   bash tools/setup-firebase.sh
#
# Prerequisiti (una volta sola sulla tua macchina):
#   - Node.js 18+            https://nodejs.org
#   - Google Cloud CLI       https://cloud.google.com/sdk/docs/install
#                            (macOS con Homebrew: brew install --cask google-cloud-sdk)
#
# Lo script è pensato per essere rilanciabile: se un passaggio risulta già fatto,
# lo salta invece di fallire.

set -euo pipefail

REGION="${REGION:-eur3}"          # eur3 = multiregione europea; per gli USA: nam5
PROJECT_ID="${PROJECT_ID:-}"      # se vuoto ne viene proposto uno nuovo

titolo() { printf '\n\033[1;35m▸ %s\033[0m\n' "$*"; }
ok()     { printf '  \033[32m✓\033[0m %s\n' "$*"; }
avviso() { printf '  \033[33m!\033[0m %s\n' "$*"; }
errore() { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 0. strumenti ────────────────────────────────────────────────────────────
titolo "Controllo degli strumenti"

command -v node >/dev/null || errore "Node.js non trovato. Installalo da https://nodejs.org e rilancia."
ok "Node.js $(node --version)"

command -v gcloud >/dev/null || errore \
"Google Cloud CLI non trovata.
   macOS:  brew install --cask google-cloud-sdk
   altro:  https://cloud.google.com/sdk/docs/install
   Serve solo per attivare l'accesso anonimo: è l'unica cosa che la CLI Firebase non sa fare."
ok "gcloud $(gcloud --version 2>/dev/null | head -1 | awk '{print $NF}')"

# npx scarica firebase-tools al volo: nessuna installazione globale da gestire
FIREBASE=(npx --yes firebase-tools@15)
ok "firebase-tools via npx"

# ── 1. accessi ──────────────────────────────────────────────────────────────
titolo "Accesso ai tuoi account Google"
avviso "Si aprirà il browser due volte: una per Firebase, una per Google Cloud."
avviso "Su una macchina senza browser aggiungi --no-localhost a entrambi i comandi."

"${FIREBASE[@]}" login
gcloud auth login

# ── 2. progetto ─────────────────────────────────────────────────────────────
titolo "Progetto Firebase"

if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="poppapp-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
  echo "  Verrà creato il progetto: $PROJECT_ID"
  echo "  (per usarne uno esistente: PROJECT_ID=... bash tools/setup-firebase.sh)"
  "${FIREBASE[@]}" projects:create "$PROJECT_ID" -n "PoppApp"
  ok "progetto creato"
else
  ok "uso il progetto indicato: $PROJECT_ID"
fi

gcloud config set project "$PROJECT_ID" >/dev/null
ok "gcloud puntato su $PROJECT_ID"

# ── 3. API ──────────────────────────────────────────────────────────────────
titolo "Attivazione delle API necessarie"
gcloud services enable firestore.googleapis.com identitytoolkit.googleapis.com \
  --project "$PROJECT_ID"
ok "Firestore e Identity Toolkit attive"

# ── 4. database ─────────────────────────────────────────────────────────────
titolo "Database Firestore (regione $REGION)"
if gcloud firestore databases describe --database='(default)' --project "$PROJECT_ID" >/dev/null 2>&1; then
  avviso "database già presente, lo lascio com'è"
else
  gcloud firestore databases create --location="$REGION" --type=firestore-native --project "$PROJECT_ID"
  ok "database creato"
fi

# ── 5. accesso anonimo ──────────────────────────────────────────────────────
# È il passaggio che nella console si fa da Authentication → Sign-in method.
titolo "Accesso anonimo"
RISPOSTA=$(curl -sS -X PATCH \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT_ID/config?updateMask=signIn.anonymous.enabled" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{"signIn":{"anonymous":{"enabled":true}}}')

if grep -q '"enabled": *true' <<<"$RISPOSTA"; then
  ok "accesso anonimo attivo"
else
  echo "$RISPOSTA"
  errore "attivazione dell'accesso anonimo non riuscita: leggi il messaggio qui sopra."
fi

# ── 6. regole di sicurezza ──────────────────────────────────────────────────
titolo "Regole di sicurezza"
[ -f firestore.rules ] || errore "firestore.rules non trovato: lancia lo script dalla cartella del progetto."
"${FIREBASE[@]}" deploy --only firestore:rules --project "$PROJECT_ID" --non-interactive
ok "regole pubblicate"

# ── 7. app web e configurazione ─────────────────────────────────────────────
titolo "App web"
APP_ID=$("${FIREBASE[@]}" apps:list WEB --project "$PROJECT_ID" 2>/dev/null \
  | grep -oE '1:[0-9]+:web:[a-z0-9]+' | head -1 || true)

if [ -z "$APP_ID" ]; then
  "${FIREBASE[@]}" apps:create WEB "PoppApp" --project "$PROJECT_ID" >/dev/null
  APP_ID=$("${FIREBASE[@]}" apps:list WEB --project "$PROJECT_ID" 2>/dev/null \
    | grep -oE '1:[0-9]+:web:[a-z0-9]+' | head -1)
  ok "app web creata"
else
  avviso "app web già presente"
fi
[ -n "$APP_ID" ] || errore "non sono riuscito a ricavare l'ID dell'app web."

"${FIREBASE[@]}" apps:sdkconfig WEB "$APP_ID" --project "$PROJECT_ID" > /tmp/poppapp-sdkconfig.txt

python3 - <<'PY'
import json, re, pathlib
testo = pathlib.Path('/tmp/poppapp-sdkconfig.txt').read_text()
m = re.search(r'\{.*\}', testo, re.S)
if not m:
    raise SystemExit('configurazione non riconosciuta in /tmp/poppapp-sdkconfig.txt')
cfg = json.loads(m.group(0))
# a seconda della versione la CLI incarta la configurazione in "sdkConfig"
if 'sdkConfig' in cfg:
    cfg = cfg['sdkConfig']
chiavi = ['apiKey', 'authDomain', 'projectId', 'appId']
mancanti = [k for k in chiavi if not cfg.get(k)]
if mancanti:
    raise SystemExit('mancano dalla configurazione: ' + ', '.join(mancanti))

blocco = 'const firebaseConfig = {\n' + ''.join(f'  {k}: "{cfg[k]}",\n' for k in chiavi) + '};'
pathlib.Path('/tmp/poppapp-config.txt').write_text(blocco + '\n')

print('\n\033[1;32m════ Configurazione da incollare nell\'app ════\033[0m\n')
print(blocco)
print('\n\033[1;32m══════════════════════════════════════════════\033[0m')
PY

titolo "Fatto"
cat <<EOF
  Progetto:  $PROJECT_ID
  App web:   $APP_ID
  Regione:   $REGION

  Ultimo passo, dal telefono:
    apri PoppApp → scheda Famiglia → incolla il blocco qui sopra
    → "Attiva la sincronizzazione" → "Crea un nuovo codice famiglia"
    → "Invia link e codice" e mandalo all'altro telefono.

  Il blocco è anche in /tmp/poppapp-config.txt

  In alternativa, per scriverlo nel repository (vale per chiunque apra l'app,
  e non va incollato su nessun telefono):
    bash tools/write-config.sh /tmp/poppapp-config.txt && git push
EOF
