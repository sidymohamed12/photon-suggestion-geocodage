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

set -eu

echo "[photon] index ($(cat /photon/index-pays 2>/dev/null || echo "?")) construit le $(cat /photon/index-construit-le 2>/dev/null || echo "?") depuis $(cat /photon/index-source 2>/dev/null || echo "?")"

# shellcheck disable=SC2086  # JAVA_OPTS et PHOTON_OPTIONS : listes d'options à découper
exec java ${JAVA_OPTS} --enable-native-access=ALL-UNNAMED \
    -jar /photon/photon.jar serve \
    -data-dir /photon \
    -listen-ip 0.0.0.0 \
    -listen-port "${PORT:-2322}" \
    -default-language "${PHOTON_LANGUE_DEFAUT}" \
    -max-results "${PHOTON_MAX_RESULTATS}" \
    -max-reverse-results 5 \
    ${PHOTON_OPTIONS:-}
