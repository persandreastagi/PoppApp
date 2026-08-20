#!/usr/bin/env bash
#
# Scrive la configurazione Firebase dentro firebase-config.js e prepara il commit,
# per chi preferisce tenerla nel repository invece di incollarla nell'app.
#
#   bash tools/write-config.sh /tmp/poppapp-config.txt
#   bash tools/write-config.sh                    # legge da standard input
#   bash tools/write-config.sh file --no-commit   # scrive senza fare commit
#
# Accetta il blocco così come lo mostra la console Firebase, con o senza
# "const firebaseConfig =" e punto e virgola finale.

set -euo pipefail

SORGENTE="${1:-/dev/stdin}"
COMMIT=1
if [ "${2:-}" = "--no-commit" ]; then COMMIT=0; fi
[ -f firebase-config.js ] || { echo "Lancialo dalla cartella del progetto." >&2; exit 1; }

python3 - "$SORGENTE" <<'PY'
import pathlib, re, sys

testo = pathlib.Path(sys.argv[1]).read_text()
cfg = dict(re.findall(r'["\']?([A-Za-z]+)["\']?\s*:\s*["\']([^"\']+)["\']', testo))

if not cfg.get('projectId'):
    raise SystemExit('projectId non trovato: il testo non sembra una configurazione Firebase.')
cfg.setdefault('authDomain', f"{cfg['projectId']}.firebaseapp.com")

mancanti = [k for k in ('apiKey', 'projectId', 'appId') if not cfg.get(k)]
if mancanti:
    raise SystemExit('mancano dalla configurazione: ' + ', '.join(mancanti))

campi = ''.join(f"  {k}: '{cfg[k]}',\n" for k in ('apiKey', 'authDomain', 'projectId', 'appId'))
pathlib.Path('firebase-config.js').write_text(f"""/*
 * Configurazione della sincronizzazione fra telefoni.
 *
 * Scritta da tools/write-config.sh. Non sono credenziali segrete: la
 * configurazione web di Firebase è pubblica per progetto. A proteggere i dati
 * sono il codice famiglia e le regole in firestore.rules.
 */
export const firebaseConfig = {{
{campi}}};

export const isConfigured = () =>
  Boolean(firebaseConfig.apiKey && firebaseConfig.projectId && firebaseConfig.appId);
""")
print(f"firebase-config.js aggiornato con il progetto “{cfg['projectId']}”")
PY

if [ "$COMMIT" = "1" ]; then
  git add firebase-config.js
  git commit -m "Configurazione Firebase del progetto" >/dev/null
  echo "Commit creato. Ora: git push"
fi
