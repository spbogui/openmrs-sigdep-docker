#!/bin/sh
# ============================================================================
#  Point d'entrée de l'image spbogui/sigdep
#   1. attend que MySQL réponde (test TCP, sans mysql-client)
#   2. génère openmrs-runtime.properties à partir des variables d'env
#   3. synchronise les modules de l'image dans le dossier de données
#   4. lance Tomcat avec l'utilisateur non-root "openmrs"
# ============================================================================
set -eu

log() { echo "[sigdep-entrypoint] $*"; }

# --- Variables (les anciens noms de cluster-sigdep restent acceptés) -------
DATA_DIR="${OPENMRS_DATA_DIR:-/openmrs/data}"
DB_HOST="${DB_HOST:-${OPENMRS_MYSQL_HOST:-db}}"
DB_PORT="${DB_PORT:-${OPENMRS_MYSQL_PORT:-3306}}"
DB_NAME="${DB_NAME:-openmrs}"
DB_USER="${DB_USER:-${OPENMRS_DB_USER:-openmrs_user}}"
DB_PASSWORD="${DB_PASSWORD:-${OPENMRS_DB_PASS:-}}"
DB_WAIT_TIMEOUT="${DB_WAIT_TIMEOUT:-1800}"
SYNC_MODULES="${SYNC_MODULES:-true}"
AUTO_UPDATE_DATABASE="${AUTO_UPDATE_DATABASE:-false}"
MODULE_WEB_ADMIN="${MODULE_WEB_ADMIN:-true}"
JAVA_XMS="${JAVA_XMS:-1G}"
JAVA_XMX="${JAVA_XMX:-2G}"

if [ -z "$DB_PASSWORD" ]; then
  log "ERREUR : la variable DB_PASSWORD est obligatoire."
  exit 1
fi

mkdir -p "$DATA_DIR/modules"

# --- 1. Attente de la base ------------------------------------------------
log "Attente de MySQL sur $DB_HOST:$DB_PORT (max ${DB_WAIT_TIMEOUT}s)..."
waited=0
until nc -z -w 2 "$DB_HOST" "$DB_PORT" 2>/dev/null; do
  if [ "$waited" -ge "$DB_WAIT_TIMEOUT" ]; then
    log "ERREUR : MySQL injoignable après ${DB_WAIT_TIMEOUT}s."
    exit 1
  fi
  sleep 5; waited=$((waited + 5))
done
log "MySQL joignable."

# --- 2. openmrs-runtime.properties ----------------------------------------
RUNTIME="$DATA_DIR/openmrs-runtime.properties"
{
  echo "### Généré automatiquement au démarrage - ne pas modifier"
  echo "### (ajoutez vos propriétés dans openmrs-runtime.extra.properties)"
  echo "connection.url=jdbc\\:mysql\\://${DB_HOST}\\:${DB_PORT}/${DB_NAME}?autoReconnect\\=true&sessionVariables\\=default_storage_engine\\=InnoDB&useUnicode\\=true&characterEncoding\\=UTF-8&useSSL\\=false"
  echo "connection.username=${DB_USER}"
  echo "connection.password=${DB_PASSWORD}"
  echo "module.allow_web_admin=${MODULE_WEB_ADMIN}"
  echo "auto_update_database=${AUTO_UPDATE_DATABASE}"
  echo "application_data_directory=${DATA_DIR}"
  if [ -f "$DATA_DIR/openmrs-runtime.extra.properties" ]; then
    echo "### --- openmrs-runtime.extra.properties ---"
    cat "$DATA_DIR/openmrs-runtime.extra.properties"
  fi
} > "$RUNTIME"
chmod 600 "$RUNTIME"
log "openmrs-runtime.properties généré."

# --- 3. Synchronisation des modules ---------------------------------------
# Pour chaque .omod de l'image : supprime les autres versions du même module
# dans le dossier de données puis copie la version de l'image.
# Les modules ajoutés à la main (absents de l'image) sont conservés.
if [ "$SYNC_MODULES" = "true" ]; then
  log "Synchronisation des modules SIGDEP..."
  for src in /opt/sigdep/modules/*.omod; do
    [ -e "$src" ] || continue
    name="$(basename "$src")"
    id="$(echo "$name" | sed -E 's/-[0-9][^/]*\.omod$//')"
    for old in "$DATA_DIR/modules/$id"-[0-9]*.omod; do
      [ -e "$old" ] || continue
      if [ "$(basename "$old")" != "$name" ]; then
        log "  - retrait de $(basename "$old")"
        rm -f "$old"
      fi
    done
    if ! cmp -s "$src" "$DATA_DIR/modules/$name"; then
      log "  + installation de $name"
      cp -f "$src" "$DATA_DIR/modules/$name"
    fi
  done
fi

# --- 4. Droits + lancement ------------------------------------------------
export OPENMRS_RUNTIME_PROPERTIES_FILE="$RUNTIME"
export JAVA_OPTS="-server -Dfile.encoding=UTF-8 -Djava.awt.headless=true \
 -Xms${JAVA_XMS} -Xmx${JAVA_XMX} -XX:+UseG1GC \
 -Duser.timezone=${TZ:-Africa/Abidjan} \
 -DOPENMRS_APPLICATION_DATA_DIRECTORY=${DATA_DIR}/ \
 -DOPENMRS_RUNTIME_PROPERTIES_FILE=${RUNTIME} \
 ${JAVA_EXTRA_OPTS:-}"

log "SIGDEP ${SIGDEP_VERSION:-?} - Xms=${JAVA_XMS} Xmx=${JAVA_XMX} - données: ${DATA_DIR}"

if [ "$(id -u)" = "0" ]; then
  # corrige la propriété du dossier de données (ex. ancien volume root)
  find "$DATA_DIR" \! -user openmrs -exec chown openmrs:openmrs {} + 2>/dev/null || true
  exec su-exec openmrs "$@"
fi
exec "$@"
