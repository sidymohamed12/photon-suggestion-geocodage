# syntax=docker/dockerfile:1
#
# Photon (géocodeur OpenStreetMap avec autocomplétion), index limité à un ou
# plusieurs pays — Sénégal par défaut (PHOTON_PAYS).
#
# Étape « index » : sur l'architecture de la machine de build (natif, donc
# rapide), téléchargement du dump GraphHopper et import des pays demandés.
# Étape finale : JRE de chaque plateforme cible + jar + index. L'index
# OpenSearch/Lucene est indépendant de l'architecture.
#
# L'image est autonome : pas de volume, pas de téléchargement au démarrage,
# démarrage en quelques secondes, plusieurs répliques possibles.
#
# Compatible OpenShift : UID arbitraire du groupe 0, aucun privilège.

ARG JAVA_IMAGE=eclipse-temurin:21-jre-noble

# ── Index (plateforme du build) ──────────────────────────────────────────
FROM --platform=$BUILDPLATFORM ${JAVA_IMAGE} AS index

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl zstd ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ARG PHOTON_VERSION=1.3.0
ARG PHOTON_SHA256=a89707c0045e4807b2a1180e132e68e108d998709f48b6c94b98a6e281f571a5
ARG PHOTON_DUMP_VERSION=1.0
ARG PHOTON_DUMP_URL=
ARG PHOTON_PAYS=sn
ARG PHOTON_LIEU_CONTROLE=Dakar
ARG PHOTON_LANGUES=fr,en
# Une valeur nouvelle (la date du jour en CI) force la reconstruction de
# l'index avec le dump le plus récent ; inchangée, le cache est réutilisé.
ARG DONNEES_DU=local

COPY --chmod=0755 scripts/construire-index.sh /usr/local/bin/construire-index.sh
RUN echo "Données OSM du ${DONNEES_DU}" \
 && construire-index.sh /index

# ── Image finale (plateforme cible) ──────────────────────────────────────
FROM ${JAVA_IMAGE}

ENV HOME=/photon \
    JAVA_OPTS="-XX:MaxRAMPercentage=50 -XX:+ExitOnOutOfMemoryError" \
    PHOTON_LANGUE_DEFAUT=fr \
    PHOTON_MAX_RESULTATS=20

# Pas de RUN ici : rien ne s'exécute sous émulation, quelle que soit la plateforme cible.
COPY --from=index --chown=1001:0 /index /photon
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /photon
USER 1001
EXPOSE 2322

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
