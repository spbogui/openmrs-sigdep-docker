#!/usr/bin/env bash
# ============================================================================
#  Génère le kit de déploiement d'un site (Linux ou Windows) :
#     dist/sigdep-site-<version>.zip
#  Contenu : docker-compose.yml, .env.example, nginx/, scripts/, windows/,
#            db/init/01-openmrs.sql.gz (sauf NO_DB=1), README.md
#
#  Usage : ./scripts/make-site-kit.sh [version]      (défaut : VERSION)
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
NAME="sigdep-site-$VERSION"
OUT="dist/$NAME"

rm -rf "$OUT" "dist/$NAME.zip"
mkdir -p "$OUT"/{nginx,scripts,windows,db/init,backups}

cp docker-compose.yml README.md "$OUT/"
sed "s/^SIGDEP_VERSION=.*/SIGDEP_VERSION=$VERSION/" .env.example > "$OUT/.env.example"
cp nginx/default.conf "$OUT/nginx/"
cp scripts/backup.sh scripts/prepare-db.sh "$OUT/scripts/"
cp windows/* "$OUT/windows/"
cp db/README.md "$OUT/db/"
if [ "${NO_DB:-0}" != "1" ] && ls db/init/*.sql.gz >/dev/null 2>&1; then
  cp db/init/*.sql.gz "$OUT/db/init/"
fi

# fins de ligne : LF pour Linux/conteneurs, CRLF pour les scripts Windows
for f in "$OUT"/windows/*.bat "$OUT"/windows/*.ps1 "$OUT"/windows/*.example; do
  perl -pi -e 's/\r?\n/\r\n/' "$f"
done
for f in "$OUT"/scripts/*.sh "$OUT"/nginx/*.conf "$OUT"/docker-compose.yml "$OUT"/.env.example; do
  perl -pi -e 's/\r\n/\n/' "$f"
done
chmod 755 "$OUT"/scripts/*.sh

(cd dist && zip -qr "$NAME.zip" "$NAME")
rm -rf "$OUT"
echo ">> Kit prêt : dist/$NAME.zip ($(du -h "dist/$NAME.zip" | cut -f1))"
