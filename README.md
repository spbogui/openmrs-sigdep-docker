# docker-sigdep-3.x

Image Docker **`spbogui/sigdep:<version>`** (SIGDEP 3.x sur OpenMRS 2.x) et kit `docker compose` de déploiement pour les sites.

Version simplifiée et allégée de l'ancien projet `cluster-sigdep` :

| | cluster-sigdep (ancien) | docker-sigdep-3.x |
|---|---|---|
| Base | `tomcat:7.0-jre8-alpine` (plus maintenue) | Tomcat 9 + `eclipse-temurin:8-jre-alpine` |
| Dump SQL dans l'image | oui (+ `mysql-client`) | **non** : importé par le conteneur MySQL |
| Polices | msttcorefonts (lourd) | `ttf-dejavu` |
| WAR | décompressé au 1er démarrage | pré-décompressé au build |
| Utilisateur | root | `openmrs` (uid 1000) |
| Création base / utilisateur | script `run.sh` (≈150 lignes) | variables natives de l'image MySQL |
| Mise à jour des modules | manuelle | automatique au démarrage |
| Services | OpenMRS, MySQL, nginx-proxy, phpMyAdmin | OpenMRS, MySQL, nginx, sauvegarde quotidienne |

---

## 1. Structure

```
docker-sigdep-3.x/
├── Dockerfile              # image multi-étapes
├── VERSION                 # version courante de l'image (ex. 3.0.0)
├── docker/
│   ├── entrypoint.sh       # attente BD, runtime.properties, sync modules, lancement
│   └── ROOT/index.jsp      # redirection / -> /openmrs
├── wars/openmrs.war        # WAR OpenMRS (non versionné)
├── modules/*.omod          # modules SIGDEP embarqués (non versionnés)
├── db/init/                # dump importé au 1er démarrage de MySQL (non versionné)
├── nginx/default.conf      # reverse proxy
├── scripts/
│   ├── build.sh            # construction / publication de l'image
│   ├── prepare-db.sh       # conversion d'un dump .zip -> db/init/01-openmrs.sql.gz
│   └── backup.sh           # sauvegarde quotidienne (service "backup")
├── docker-compose.yml      # déploiement site
└── .env.example            # configuration site (à copier en .env)
```

Les fichiers lourds (`.war`, `.omod`, dumps, données, sauvegardes) et le `.env` sont exclus de git.

---

## 2. Compiler l'image

### Prérequis

- Docker 20.10+ avec **buildx** (inclus dans Docker Desktop).
- `wars/openmrs.war` : le WAR OpenMRS utilisé par SIGDEP.
- `modules/*.omod` : les modules à embarquer.

> Les serveurs des sites sont en `linux/amd64`. Sur un Mac Apple Silicon, `build.sh` construit par défaut pour `linux/amd64` (émulation, plus lent mais correct).

### Construire

```bash
# version lue dans le fichier VERSION
./scripts/build.sh

# ou une version explicite
./scripts/build.sh 3.0.1
```

### Publier sur Docker Hub

```bash
docker login
PUSH=1 ./scripts/build.sh 3.0.1           # pousse spbogui/sigdep:3.0.1
PUSH=1 LATEST=1 ./scripts/build.sh 3.0.1  # + tag :latest
```

### Sortir une nouvelle version

1. Remplacer le WAR et/ou les `.omod` concernés.
2. Mettre à jour `VERSION` (ex. `3.0.1`).
3. `git commit -am "SIGDEP 3.0.1"` puis `git tag v3.0.1`.
4. `PUSH=1 ./scripts/build.sh`.

### Vérifier la taille

```bash
docker image ls spbogui/sigdep
docker history spbogui/sigdep:3.0.0
```

---

## 3. Déployer sur un site

### Fichiers à copier sur le serveur

```
docker-compose.yml
.env.example
nginx/default.conf
scripts/backup.sh
db/init/01-openmrs.sql.gz      # nouvelle installation uniquement
```

(ou cloner le dépôt puis ajouter le dump dans `db/init/`).

### Installation

```bash
# 1. Configuration
cp .env.example .env
nano .env                     # CHANGER les mots de passe, ajuster SIGDEP_VERSION et la mémoire

# 2. Dump de la base (nouvelle installation)
./scripts/prepare-db.sh /chemin/backup.openmrs.sql.zip

# 3. Démarrage
docker compose up -d
docker compose logs -f db openmrs
```

Au premier démarrage :

1. MySQL crée la base `openmrs` et l'utilisateur `OPENMRS_DB_USER`, puis importe `db/init/*.sql.gz` (plusieurs minutes).
2. OpenMRS attend que MySQL soit prêt, génère `openmrs-runtime.properties`, installe les modules et démarre (compter 5 à 15 min).

Accès : **http://&lt;ip-du-serveur&gt;/** (redirigé vers `/openmrs/`).

### Commandes courantes

```bash
docker compose ps                     # état (colonne STATUS : healthy)
docker compose logs -f openmrs        # journaux OpenMRS
docker compose restart openmrs        # redémarrer OpenMRS
docker compose stop / start           # arrêter / relancer
docker compose down                   # supprimer les conteneurs (données conservées)
```

### Mettre à jour la version sur un site

```bash
# dans .env : SIGDEP_VERSION=3.0.1
docker compose pull openmrs
docker compose up -d openmrs
```

Les modules de la nouvelle image remplacent automatiquement leurs anciennes versions dans `openmrs-data/modules`.

---

## 4. Sauvegardes

Le service `backup` fait un `mysqldump` compressé chaque jour à `BACKUP_TIME` dans `./backups/` et supprime ceux de plus de `BACKUP_KEEP_DAYS` jours.

```bash
# sauvegarde immédiate
docker compose exec backup /scripts/backup.sh now

# restauration (écrase la base !)
gunzip -c backups/openmrs-2026-09-28_0200.sql.gz | \
  docker compose exec -T db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
docker compose restart openmrs
```

Pour réinstaller un site à partir d'une sauvegarde : copier le fichier `.sql.gz` dans `db/init/` à la place de `01-openmrs.sql.gz`, puis `docker compose down -v && docker compose up -d` (**`-v` supprime la base existante**).

---

## 5. Variables d'environnement

### `.env` (site)

| Variable | Défaut | Rôle |
|---|---|---|
| `SIGDEP_VERSION` | `3.0.0` | Tag de l'image `spbogui/sigdep` |
| `MYSQL_ROOT_PASSWORD` | — (obligatoire) | Mot de passe root MySQL |
| `OPENMRS_DB_USER` | `openmrs_user` | Utilisateur MySQL d'OpenMRS |
| `OPENMRS_DB_PASSWORD` | — (obligatoire) | Son mot de passe |
| `JAVA_XMS` / `JAVA_XMX` | `2G` / `4G` | Mémoire Java |
| `MYSQL_INNODB_BUFFER` | `1G` | Cache InnoDB |
| `HTTP_PORT` | `80` | Port nginx |
| `OPENMRS_DATA_PATH` | `./openmrs-data` | Dossier de données OpenMRS |
| `BACKUP_TIME` / `BACKUP_KEEP_DAYS` | `02:00` / `14` | Sauvegardes |
| `TZ` | `Africa/Abidjan` | Fuseau horaire |

### Image `spbogui/sigdep`

| Variable | Défaut | Rôle |
|---|---|---|
| `DB_HOST` / `DB_PORT` / `DB_NAME` | `db` / `3306` / `openmrs` | Connexion MySQL |
| `DB_USER` / `DB_PASSWORD` | `openmrs_user` / — | Identifiants (mot de passe obligatoire) |
| `JAVA_XMS` / `JAVA_XMX` | `1G` / `2G` | Mémoire Java |
| `JAVA_EXTRA_OPTS` | — | Options JVM supplémentaires |
| `SYNC_MODULES` | `true` | Synchroniser les modules de l'image au démarrage |
| `AUTO_UPDATE_DATABASE` | `false` | Propriété OpenMRS `auto_update_database` |
| `MODULE_WEB_ADMIN` | `true` | Autoriser l'ajout de modules depuis l'interface |
| `DB_WAIT_TIMEOUT` | `1800` | Attente max de MySQL (secondes) |

Les anciens noms (`OPENMRS_MYSQL_HOST`, `OPENMRS_MYSQL_PORT`, `OPENMRS_DB_USER`, `OPENMRS_DB_PASS`) restent acceptés.

Propriétés OpenMRS supplémentaires : les écrire dans `openmrs-data/openmrs-runtime.extra.properties`, elles sont ajoutées au fichier généré.

---

## 6. Migrer un site `cluster-sigdep` existant

Sans réimporter la base :

1. Arrêter l'ancien déploiement : `docker compose down` (dans l'ancien dossier, **sans `-v`**).
2. Repérer le volume MySQL existant : `docker volume ls | grep db-data` (ex. `cluster-sigdep_db-data`).
3. Dans le nouveau `docker-compose.yml`, déclarer ce volume comme externe :
   ```yaml
   volumes:
     db-data:
       external: true
       name: cluster-sigdep_db-data
   ```
4. Dans `.env` : `OPENMRS_DATA_PATH=/chemin/vers/ancien/OpenMRS` et reprendre `MYSQL_ROOT_PASSWORD` et le mot de passe `openmrs_user` existants.
5. `docker compose up -d`. L'entrypoint corrige les droits du dossier et remplace les anciennes versions des modules.

La base existant déjà, `db/init/` n'est pas utilisé.

---

## 7. Dépannage

| Symptôme | Piste |
|---|---|
| `openmrs` reste en `waiting` | MySQL importe encore le dump : `docker compose logs -f db` |
| Page de configuration initiale OpenMRS | Base vide ou mauvais identifiants : vérifier `db/init/` et `.env` |
| Import non relancé après modif de `db/init/` | Normal : il ne se fait que sur volume vide (`docker compose down -v` pour repartir de zéro) |
| `OutOfMemoryError` | Augmenter `JAVA_XMX` dans `.env` |
| Erreur de build `wars/openmrs.war introuvable` | Déposer le WAR dans `wars/` |
