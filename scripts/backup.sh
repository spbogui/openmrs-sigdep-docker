#!/bin/bash
# ============================================================================
#  Sauvegarde quotidienne de la base OpenMRS (service "backup")
#    - lancé en boucle : un dump chaque jour à BACKUP_TIME (défaut 02:00)
#    - "backup.sh now" : fait un dump immédiat puis s'arrête
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
            --routines --triggers --max_allowed_packet=512M \
            --databases "$DB_NAME" | gzip -6 > "$file.part"
  mv "$file.part" "$file"
  log "OK ($(du -h "$file" | cut -f1))"
  find "$BACKUP_DIR" -name 'openmrs-*.sql.gz' -mtime +"$BACKUP_KEEP_DAYS" -print -delete || true
}

if [ "${1:-}" = "now" ]; then
  do_backup
  exit 0
fi

log "Planification : tous les jours à $BACKUP_TIME, conservation $BACKUP_KEEP_DAYS jours."
while true; do
  now=$(date +%s)
  next=$(date -d "today $BACKUP_TIME" +%s)
  [ "$next" -le "$now" ] && next=$(date -d "tomorrow $BACKUP_TIME" +%s)
  sleep $((next - now))
  do_backup || log "ERREUR pendant la sauvegarde"
done
