#!/bin/bash
# ============================================================================
#  Sauvegarde quotidienne de la base OpenMRS (service "backup")
#    - lancé en boucle : un dump chaque jour à BACKUP_TIME (défaut 02:00)
#    - "backup.sh now"            : dump immédiat puis arrêt
#    - "backup.sh restore <fic>"  : restaure un dump (nom dans /backups ou chemin)
#    - "backup.sh list"           : liste les sauvegardes
#  Fichiers : /backups/openmrs-AAAA-MM-JJ_HHMM.sql.gz
# ============================================================================
set -euo pipefail

DB_HOST="${DB_HOST:-db}"
DB_NAME="${DB_NAME:-openmrs}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_TIME="${BACKUP_TIME:-02:00}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD manquant}"

log() { echo "[backup $(date '+%F %T')] $*"; }

do_backup() {
  mkdir -p "$BACKUP_DIR"
  local file="$BACKUP_DIR/openmrs-$(date +%F_%H%M).sql.gz"
  log "Dump de '$DB_NAME' -> $file"
  mysqldump -h "$DB_HOST" -u root --single-transaction --quick \
            --routines --triggers --add-drop-database --max_allowed_packet=512M \
            --databases "$DB_NAME" | gzip -6 > "$file.part"
  mv "$file.part" "$file"
  log "OK ($(du -h "$file" | cut -f1))"
  find "$BACKUP_DIR" -name 'openmrs-*.sql.gz' -mtime +"$BACKUP_KEEP_DAYS" -print -delete || true
}

do_restore() {
  local f="$1"
  [ -f "$f" ] || f="$BACKUP_DIR/$1"
  [ -f "$f" ] || { log "ERREUR : fichier introuvable : $1"; exit 1; }
  log "Restauration de $f (la base '$DB_NAME' est remplacée)..."
  case "$f" in
    *.gz) gunzip -c "$f" ;;
    *)    cat "$f" ;;
  esac | mysql -h "$DB_HOST" -u root --max_allowed_packet=512M
  log "Restauration terminée."
}

case "${1:-}" in
  now)     do_backup; exit 0 ;;
  restore) do_restore "${2:?Usage : backup.sh restore <fichier>}"; exit 0 ;;
  list)    ls -lh "$BACKUP_DIR"/openmrs-*.sql.gz 2>/dev/null || echo "Aucune sauvegarde."; exit 0 ;;
esac

log "Planification : tous les jours à $BACKUP_TIME, conservation $BACKUP_KEEP_DAYS jours."
while true; do
  now=$(date +%s)
  next=$(date -d "today $BACKUP_TIME" +%s)
  [ "$next" -le "$now" ] && next=$(date -d "tomorrow $BACKUP_TIME" +%s)
  sleep $((next - now))
  do_backup || log "ERREUR pendant la sauvegarde"
done
