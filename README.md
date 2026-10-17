# photon-senegal

Image Docker prête à l'emploi de [Photon](https://github.com/komoot/photon), le géocodeur OpenStreetMap avec **autocomplétion**, dont l'index est limité au **Sénégal**. Taper « Sanda » propose « Marché Sandaga ». D'autres pays sont possibles (voir [Autre pays](#autre-pays)).

- **Index embarqué dans l'image.** Pas de volume, pas d'import au démarrage, pas d'accès internet à l'exécution. Le service démarre en quelques secondes et accepte plusieurs répliques.
- **Multi-architecture :** `linux/amd64`, `linux/arm64` et `linux/s390x`.
- **Compatible OpenShift :** UID arbitraire du groupe 0, aucun privilège. Fonctionne aussi tel quel sur Kubernetes, Docker et Podman.
- **Données OSM rafraîchies chaque semaine** à partir des dumps publiés par GraphHopper.

Ce dépôt fournit l'image et des exemples de déploiement. **Le déploiement et l'exploitation restent à votre charge.**

## Démarrage rapide

```bash
docker compose up --build        # 1er build : téléchargement du dump et import
curl 'localhost:2322/api?q=Sanda&limit=5'
curl 'localhost:2322/reverse?lat=14.6735&lon=-17.439&limit=1'
```

L'API est celle de Photon : `/api` (recherche et autocomplétion), `/reverse` (géocodage inverse) et `/status`. Les paramètres sont décrits dans la [documentation de l'API Photon](https://github.com/komoot/photon/blob/master/docs/api-v1.md). Les résultats sont au format GeoJSON et portent les identifiants OSM (`osm_type`, `osm_id`).

## Contenu

```
photon-senegal/
├── Dockerfile                      # étape « index » (native) + image finale multi-architecture
├── compose.yaml                    # essai local : docker compose up --build
├── docker/entrypoint.sh            # photon serve sur l'index embarqué, port 2322
├── scripts/construire-index.sh     # jar vérifié → dump GraphHopper → import des pays → contrôle
├── kubernetes/                     # exemple Kustomize (Kubernetes ou OpenShift)
│   ├── kustomization.yaml
│   ├── deployment.yaml             # 2 répliques, sans volume, mise à jour sans coupure
│   ├── service.yaml                # ClusterIP
│   └── networkpolicy.yaml          # accès limité au namespace
└── .github/workflows/photon-image.yml   # build + publication Docker Hub (v1, v2…)
```

## Fonctionnement

```
Build (natif)                                              Image (amd64, arm64, s390x)
─────────────                                              ───────────────────────────
photon-1.3.0.jar (SHA-256 vérifié)                         JRE 21 + jar + index
dump JSON GraphHopper ─ zstd ─► import -country-codes sn ──►  démarrage en quelques secondes
                                contrôle : « Dakar » trouvé    aucun volume
```

- **Données.** Ce sont les [dumps Photon](https://download1.graphhopper.com/public/) publiés chaque semaine par GraphHopper. Pour le Sénégal, le script prend le plus petit dump publié qui le couvre, en essayant dans l'ordre le pays, la région puis le continent. Seuls les pays demandés sont importés, avec les noms en français et en anglais.
- **Un seul import pour toutes les architectures.** L'import tourne nativement sur la machine de build, et l'index produit est indépendant de l'architecture. Le service a été vérifié sur s390x avec un index construit sur amd64. L'étape finale du Dockerfile ne contient que des `COPY`, donc l'émulation QEMU n'est pas nécessaire.
- **Contrôle avant publication.** Le build échoue si l'index ne trouve pas le lieu de contrôle (« Dakar » par défaut). Cela évite de publier une image vide.

## Construire et publier avec GitHub Actions

Le workflow `.github/workflows/photon-image.yml` publie l'image à chaque push sur `main`, chaque lundi pour reprendre les données de la semaine, et sur lancement manuel. Les versions sont taguées `v1`, `v2`… et `latest`.

Dans *Settings → Secrets and variables → Actions* :

| Type | Nom | Défaut | Rôle |
|---|---|---|---|
| Variable | `DOCKERHUB_USERNAME` | — | Compte ou organisation Docker Hub (obligatoire) |
| Secret | `DOCKERHUB_TOKEN` | — | Jeton Docker Hub « Read & Write » (obligatoire) |
| Variable | `DOCKERHUB_REPOSITORY` | `photon-senegal` | Nom de l'image |
| Variable | `PLATEFORMES` | `linux/amd64,linux/arm64,linux/s390x` | Architectures publiées |
| Variable | `PHOTON_PAYS` | `sn` | Pays importés (codes ISO, séparés par des virgules) |
| Variable | `PHOTON_LIEU_CONTROLE` | `Dakar` | Lieu à trouver pour valider l'index |
| Variable | `PHOTON_LANGUES` | `fr,en` | Langues des noms importés |
| Variable | `PHOTON_DUMP_URL` | recherche automatique (Sénégal) | Dump à importer, obligatoire hors Sénégal |

Pour construire sans GitHub :

```bash
docker buildx build --platform linux/amd64,linux/arm64,linux/s390x \
  --build-arg DONNEES_DU=$(date +%F) -t <registre>/photon-senegal:v1 --push .
```

`DONNEES_DU` force la reconstruction de l'index avec le dump le plus récent. Si sa valeur ne change pas, le cache de build est réutilisé.

## Déployer

### Kubernetes ou OpenShift

1. Remplacer `newName` dans `kubernetes/kustomization.yaml` par votre image.
2. Appliquer :

```bash
kubectl apply -k kubernetes/       # ou : oc apply -k kubernetes/
kubectl rollout status deploy/photon
```

Depuis le même namespace, le service répond sur `http://photon:2322`. Depuis un autre namespace, utiliser `http://photon.<namespace>.svc.cluster.local:2322` et adapter `networkpolicy.yaml`.

Photon n'a ni authentification ni limite de débit. Les exemples le gardent donc interne au cluster (Service `ClusterIP`, pas d'Ingress ni de Route). Si vous l'exposez, placez devant lui une passerelle qui gère l'authentification et la limitation de débit.

### Docker

```bash
docker run -d --name photon -p 2322:2322 <registre>/photon-senegal:v1
```

### Mettre à jour les données

Publier une nouvelle image (le workflow le fait chaque lundi), puis déployer le nouveau tag. Avec deux répliques, la mise à jour progressive se fait sans coupure.

## Configuration à l'exécution

| Variable | Défaut | Rôle |
|---|---|---|
| `JAVA_OPTS` | `-XX:MaxRAMPercentage=50 -XX:+ExitOnOutOfMemoryError` | Options JVM |
| `PHOTON_LANGUE_DEFAUT` | `fr` | Langue des résultats quand la requête ne précise pas `lang` |
| `PHOTON_MAX_RESULTATS` | `20` | Plafond du paramètre `limit` |
| `PHOTON_OPTIONS` | — | Options supplémentaires de `photon serve`, par exemple `-metrics-enable prometheus` ou `-cors-any` |
| `PORT` | `2322` | Port d'écoute |

**Ressources :** pour le Sénégal, 1 Gio demandé et 2 Gio de limite par pod suffisent. La moitié sert de heap Java, le reste de cache disque pour l'index.

## Autre pays

Fixer les arguments de build, ou les variables du workflow :

```bash
docker compose build \
  --build-arg PHOTON_PAYS=ci \
  --build-arg PHOTON_LIEU_CONTROLE=Abidjan \
  --build-arg PHOTON_DUMP_URL=https://download1.graphhopper.com/public/africa/photon-dump-africa-1.0-latest.jsonl.zst
```

- **`PHOTON_DUMP_URL`** est obligatoire hors Sénégal. Choisir sur [download1.graphhopper.com/public](https://download1.graphhopper.com/public/) un dump JSON (`photon-dump-…-1.0-latest.jsonl.zst`) qui couvre le pays : un dump pays s'il existe, sinon la région ou le continent. Le filtre `PHOTON_PAYS` ne garde que le pays demandé.
- Pour plusieurs pays : `PHOTON_PAYS=sn,gm`. Le lieu de contrôle est alors cherché dans le premier.
- Pensez à renommer l'image (`DOCKERHUB_REPOSITORY`).

## Limites

- **Pas de recherche par identifiant OSM.** Photon n'a pas d'équivalent au `/lookup` de Nominatim. Pour retrouver un lieu à partir de son identifiant, conservez ses coordonnées au moment où il est suggéré, ou associez [nominatim-senegal](../nominatim-senegal).
- **Géocodage inverse moins détaillé que Nominatim.** Photon renvoie l'objet le plus proche, sans reconstruire l'adresse complète.
- **Dépendance aux dumps GraphHopper.** Si leur organisation change et qu'aucun dump n'est trouvé, le build échoue avec un message explicite : renseigner alors `PHOTON_DUMP_URL`.

## Licences

- Photon : Apache 2.0.
- Données : © les contributeurs [OpenStreetMap](https://www.openstreetmap.org/copyright), licence ODbL. **L'attribution « © OpenStreetMap contributors » doit être affichée avec les résultats.**
