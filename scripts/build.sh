#!/usr/bin/env bash
# ============================================================================
#  Construit l'image spbogui/sigdep:<version>
#
#  Usage : ./scripts/build.sh [version]        (défaut : contenu de VERSION)
#  Variables :
#    IMAGE=spbogui/sigdep   nom de l'image
#    PLATFORM=linux/amd64   architecture cible (serveurs des sites)
#    PUSH=1                 pousse l'image sur Docker Hub au lieu de la charger
#    LATEST=1               ajoute aussi le tag :latest
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
IMAGE="${IMAGE:-spbogui/sigdep}"
PLATFORM="${PLATFORM:-linux/amd64}"

[ -f wars/openmrs.war ] || { echo "ERREUR : wars/openmrs.war introuvable."; exit 1; }
ls modules/*.omod >/dev/null 2>&1 || { echo "ERREUR : aucun .omod dans modules/."; exit 1; }

TAGS=(-t "$IMAGE:$VERSION")
[ "${LATEST:-0}" = "1" ] && TAGS+=(-t "$IMAGE:latest")
OUTPUT="--load"; [ "${PUSH:-0}" = "1" ] && OUTPUT="--push"

echo ">> Construction de $IMAGE:$VERSION ($PLATFORM)"
echo ">> Modules embarqués :"; ls -1 modules/*.omod | sed 's#modules/#   - #'

docker buildx build \
  --platform "$PLATFORM" \
  --build-arg VERSION="$VERSION" \
  "${TAGS[@]}" \
  $OUTPUT .

[ "$OUTPUT" = "--load" ] && docker image ls "$IMAGE:$VERSION"
echo ">> Terminé."
