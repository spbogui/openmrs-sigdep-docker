#!/usr/bin/env bash
# ============================================================================
#  Prépare le script d'initialisation de la base pour le conteneur MySQL.
#  Convertit un dump (.zip / .sql / .sql.gz) en db/init/01-openmrs.sql.gz
#  (MySQL l'importe automatiquement au 1er démarrage, volume vide seulement).
#
#  Usage : ./scripts/prepare-db.sh chemin/vers/backup.openmrs.sql.zip
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:?Usage : $0 <dump.zip|dump.sql|dump.sql.gz>}"
DEST="db/init/01-openmrs.sql.gz"
mkdir -p db/init

case "$SRC" in
  *.zip)    unzip -p "$SRC" -x '__MACOSX/*' | gzip -6 > "$DEST" ;;
  *.sql.gz) cp "$SRC" "$DEST" ;;
  *.sql)    gzip -6 -c "$SRC" > "$DEST" ;;
  *) echo "Format non supporté : $SRC"; exit 1 ;;
esac

echo ">> $DEST prêt ($(du -h "$DEST" | cut -f1))"
