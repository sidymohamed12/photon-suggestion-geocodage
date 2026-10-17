#!/usr/bin/env bash
#
# Construit un index Photon limité à un ou plusieurs pays dans
# <dossier>/photon_data (Sénégal par défaut).
#
#   1. télécharge le jar Photon (empreinte SHA-256 vérifiée) ;
#   2. choisit le dump JSON GraphHopper : PHOTON_DUMP_URL, ou, pour le
#      Sénégal, le plus petit dump publié qui le couvre ;
#   3. l'importe en flux (téléchargement → décompression → import), en ne
#      gardant que les pays demandés (-country-codes) ;
#   4. vérifie que l'index trouve un lieu connu avant de valider.
#
# Exécuté pendant le build Docker, sur l'architecture de la machine de
# build : l'index produit est portable et servi tel quel quelle que soit
# l'architecture de l'image finale (amd64, arm64, s390x…).
#
# Usage : construire-index.sh <dossier-sortie>
#
# Variables :
#   PHOTON_PAYS            codes pays ISO séparés par des virgules (sn)
#   PHOTON_LIEU_CONTROLE   lieu qui doit être trouvé dans le 1ᵉʳ pays (Dakar)
#   PHOTON_DUMP_URL        dump JSON précis (obligatoire hors Sénégal)
#   PHOTON_LANGUES         langues des noms importés (fr,en)
#   PHOTON_VERSION, PHOTON_SHA256, PHOTON_DUMP_VERSION, IMPORT_THREADS

set -Eeuo pipefail

SORTIE=${1:?usage: construire-index.sh <dossier-sortie>}
PHOTON_VERSION=${PHOTON_VERSION:-1.3.0}
PHOTON_SHA256=${PHOTON_SHA256:-a89707c0045e4807b2a1180e132e68e108d998709f48b6c94b98a6e281f571a5}
PHOTON_DUMP_VERSION=${PHOTON_DUMP_VERSION:-1.0}
PHOTON_PAYS=$(printf '%s' "${PHOTON_PAYS:-sn}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
PHOTON_LIEU_CONTROLE=${PHOTON_LIEU_CONTROLE:-Dakar}
PHOTON_LANGUES=${PHOTON_LANGUES:-fr,en}
IMPORT_THREADS=${IMPORT_THREADS:-$(nproc)}
BASE=https://download1.graphhopper.com/public

PREMIER_PAYS=$(printf '%s' "${PHOTON_PAYS%%,*}" | tr '[:lower:]' '[:upper:]')

log() { printf '[index] %s\n' "$*"; }

mkdir -p "$SORTIE"
JAR="${SORTIE}/photon.jar"

# ── 1. Jar Photon ────────────────────────────────────────────────────────
log "Photon ${PHOTON_VERSION}, pays : ${PHOTON_PAYS}"
curl -fsSL --retry 3 -o "$JAR" \
    "https://github.com/komoot/photon/releases/download/${PHOTON_VERSION}/photon-${PHOTON_VERSION}.jar"
echo "${PHOTON_SHA256}  ${JAR}" | sha256sum -c --quiet - \
    || { log "ERREUR : empreinte du jar inattendue (PHOTON_SHA256 à mettre à jour avec PHOTON_VERSION ?)"; exit 1; }

# ── 2. Choix du dump ─────────────────────────────────────────────────────
if [ -n "${PHOTON_DUMP_URL:-}" ]; then
    url=$PHOTON_DUMP_URL
elif [ "$PHOTON_PAYS" = "sn" ]; then
    # Du plus petit au plus gros : seule la couverture du Sénégal compte, le
    # filtre -country-codes écarte le reste à l'import.
    candidats=(
        "africa/senegal/photon-dump-senegal-${PHOTON_DUMP_VERSION}-latest.jsonl.zst"
        "africa/senegal-and-gambia/photon-dump-senegal-and-gambia-${PHOTON_DUMP_VERSION}-latest.jsonl.zst"
        "africa/west-africa/photon-dump-west-africa-${PHOTON_DUMP_VERSION}-latest.jsonl.zst"
        "africa/photon-dump-africa-${PHOTON_DUMP_VERSION}-latest.jsonl.zst"
    )
    url=
    for chemin in "${candidats[@]}"; do
        if curl -fsIL --retry 2 -o /dev/null "${BASE}/${chemin}"; then
            url="${BASE}/${chemin}"
            break
        fi
    done
    [ -n "$url" ] || { log "ERREUR : aucun dump trouvé sous ${BASE}/africa — définir PHOTON_DUMP_URL"; exit 1; }
else
    log "ERREUR : PHOTON_DUMP_URL obligatoire pour les pays « ${PHOTON_PAYS} » (dump couvrant ces pays, cf. ${BASE})"
    exit 1
fi
taille=$(curl -fsIL "$url" | tr -d '\r' | awk 'tolower($1)=="content-length:" {t=$2} END {print t+0}')
log "Dump : ${url} ($(( taille / 1024 / 1024 )) Mio)"

# ── 3. Import en flux, pays demandés uniquement ──────────────────────────
debut=$(date +%s)
curl -fsSL --retry 3 "$url" \
    | zstd -dc \
    | java -Xmx2g --enable-native-access=ALL-UNNAMED -jar "$JAR" import \
        -import-file - \
        -data-dir "$SORTIE" \
        -country-codes "$PHOTON_PAYS" \
        -languages "$PHOTON_LANGUES" \
        -j "$IMPORT_THREADS"

[ -d "${SORTIE}/photon_data" ] || { log "ERREUR : photon_data absent après l'import"; exit 1; }

# ── 4. Contrôle : l'index doit trouver le lieu de contrôle ───────────────
# Évite de publier une image vide (dump sans les pays demandés, import tronqué…).
java -Xmx1g --enable-native-access=ALL-UNNAMED -jar "$JAR" serve \
    -data-dir "$SORTIE" -listen-ip 127.0.0.1 -listen-port 2399 >/dev/null 2>&1 &
serveur=$!
trap 'kill "$serveur" 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do
    curl -fs -o /dev/null http://127.0.0.1:2399/status && break
    sleep 2
done
reponse=$(curl -fsS -G 'http://127.0.0.1:2399/api' --data-urlencode "q=${PHOTON_LIEU_CONTROLE}" \
    -d limit=1 -d "countrycode=${PREMIER_PAYS}") \
    || { log "ERREUR : le serveur de contrôle ne répond pas"; exit 1; }
case "$reponse" in
    *"\"countrycode\":\"${PREMIER_PAYS}\""*) log "Contrôle OK : « ${PHOTON_LIEU_CONTROLE} » trouvé" ;;
    *) log "ERREUR : « ${PHOTON_LIEU_CONTROLE} » introuvable dans l'index — réponse : ${reponse}"; exit 1 ;;
esac
kill "$serveur"
wait "$serveur" 2>/dev/null || true
trap - EXIT

date -u +%Y-%m-%dT%H:%M:%SZ > "${SORTIE}/index-construit-le"
echo "$url" > "${SORTIE}/index-source"
echo "$PHOTON_PAYS" > "${SORTIE}/index-pays"
log "Index construit en $(( ($(date +%s) - debut) / 60 )) min : $(du -sh "${SORTIE}/photon_data" | cut -f1)"

# Images OpenShift : l'UID arbitraire appartient au groupe 0, qui reçoit
# donc les mêmes droits que le propriétaire.
chmod -R g=u "$SORTIE"
