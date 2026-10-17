#!/bin/sh
#
# Démarre le serveur Photon sur l'index embarqué (/photon/photon_data).
#
# Variables :
#   PORT                   port d'écoute (2322)
#   JAVA_OPTS              options JVM (heap = 50 % de la limite mémoire du pod)
#   PHOTON_LANGUE_DEFAUT   langue des résultats sans « lang » (fr)
#   PHOTON_MAX_RESULTATS   plafond du paramètre « limit » (20)
#   PHOTON_OPTIONS         options supplémentaires de « photon serve »
#   PHOTON_REPERTOIRE_TRAVAIL  si renseigné (ex. volume emptyDir), l'index y est
#                          recopié au démarrage et Photon l'utilise : nécessaire
#                          quand OpenSearch ne peut pas écrire dans la couche
#                          overlayfs de l'image (« Underlying file changed by an
#                          external force », vu sur OpenShift/CRI-O)

set -eu

echo "[photon] index ($(cat /photon/index-pays 2>/dev/null || echo "?")) construit le $(cat /photon/index-construit-le 2>/dev/null || echo "?") depuis $(cat /photon/index-source 2>/dev/null || echo "?")"

DONNEES=/photon
if [ -n "${PHOTON_REPERTOIRE_TRAVAIL:-}" ]; then
    DONNEES=${PHOTON_REPERTOIRE_TRAVAIL}
    rm -rf "${DONNEES}/photon_data"
    cp -r /photon/photon_data "${DONNEES}/"
    echo "[photon] index recopié dans ${DONNEES} ($(du -sh "${DONNEES}/photon_data" | cut -f1))"
fi
# Verrou OpenSearch éventuellement laissé dans l'index : OpenSearch en recrée un.
find "${DONNEES}/photon_data" -name node.lock -delete 2>/dev/null || true

# shellcheck disable=SC2086  # JAVA_OPTS et PHOTON_OPTIONS : listes d'options à découper
exec java ${JAVA_OPTS} --enable-native-access=ALL-UNNAMED \
    -jar /photon/photon.jar serve \
    -data-dir "${DONNEES}" \
    -listen-ip 0.0.0.0 \
    -listen-port "${PORT:-2322}" \
    -default-language "${PHOTON_LANGUE_DEFAUT}" \
    -max-results "${PHOTON_MAX_RESULTATS}" \
    -max-reverse-results 5 \
    ${PHOTON_OPTIONS:-}
