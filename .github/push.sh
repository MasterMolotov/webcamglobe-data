#!/bin/sh
# Lädt die neue Kameraliste hoch, auch wenn während des langen Laufs jemand anderes etwas hochgeladen hat.
# Vorher wurde der Push dann abgelehnt und die stundenlange Prüfung war verloren.
# Aufruf: .github/push.sh "Commit-Nachricht"
set -e
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add webcams.json webcams.sqlite
if git diff --cached --quiet; then
  echo "Nichts Neues hochzuladen"
  exit 0
fi
git commit -q -m "$1"
for attempt in 1 2 3 4; do
  if git push -q origin HEAD:main; then
    echo "Hochgeladen (Versuch $attempt)"
    exit 0
  fi
  echo "Push abgelehnt, hole den neuesten Stand und versuche es erneut"
  git fetch -q origin main
  # Die eigene Liste und Datenbank gewinnen: Sie sind das Ergebnis dieses Laufs. Code-Änderungen von außen bleiben erhalten.
  if ! git rebase -X theirs origin/main; then
    git rebase --abort || true
    echo "Zusammenführen nicht möglich"
    exit 1
  fi
  sleep $((attempt * 5))
done
echo "Hochladen nach 4 Versuchen fehlgeschlagen"
exit 1
