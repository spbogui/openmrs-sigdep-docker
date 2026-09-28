# docker-sigdep-3.x

Image Docker **`spbogui/sigdep:<version>`** (SIGDEP 3.x sur OpenMRS 2.x) et kit `docker compose` de déploiement pour les sites **Linux et Windows**.

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
│   ├── make-site-kit.sh    # génère dist/sigdep-site-<version>.zip (kit site)
│   ├── prepare-db.sh       # conversion d'un dump .zip -> db/init/01-openmrs.sql.gz
│   └── backup.sh           # sauvegarde / restauration (service "backup")
├── windows/                # outils pour les sites sous Windows
│   ├── sigdep.ps1          # script PowerShell (install, start, backup, restore...)
│   ├── *.bat               # raccourcis double-clic (installer, demarrer, sauvegarder...)
│   └── wslconfig.example   # limite mémoire WSL2 / Docker Desktop
├── .gitattributes          # fins de ligne LF/CRLF garanties (clonage sous Windows)
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
5. `./scripts/make-site-kit.sh` : produit `dist/sigdep-site-3.0.1.zip`, le kit à envoyer aux sites (Linux et Windows). `NO_DB=1` pour un kit de mise à jour sans le dump.

### Construire depuis un poste Windows

Utiliser **Git Bash** (fourni avec Git for Windows) et Docker Desktop : `./scripts/build.sh` fonctionne à l'identique. Le fichier `.gitattributes` garantit que les scripts restent en fin de ligne Unix même avec `core.autocrlf=true`, et le Dockerfile nettoie de toute façon `entrypoint.sh`.

### Vérifier la taille

```bash
docker image ls spbogui/sigdep
docker history spbogui/sigdep:3.0.0
```

---

## 3. Déployer sur un site

> Sites sous Windows : voir la section 4.

### Fichiers à copier sur le serveur

Le plus simple : décompresser le kit `sigdep-site-<version>.zip` (voir `make-site-kit.sh`). Il contient :

```
docker-compose.yml
.env.example
nginx/default.conf
scripts/backup.sh, scripts/prepare-db.sh
windows/                       # utile seulement sous Windows
db/init/01-openmrs.sql.gz      # nouvelle installation uniquement
```

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

## 4. Déployer sur un site Windows

L'image est une image **Linux** : sous Windows elle tourne dans **WSL2** (sous-système Linux de Windows). Rien ne change dans l'image ni dans `docker-compose.yml` ; le dossier `windows\` fournit des raccourcis pour les opérateurs.

### 4.1 Prérequis

|                | Windows 10 (22H2) / 11                 | Windows Server 2019 / 2022                       |
| -------------- | -------------------------------------- | ------------------------------------------------ |
| Moteur         | **Docker Desktop** (WSL2)              | Docker Engine dans une distribution WSL2 (§ 4.6) |
| Virtualisation | Activée dans le BIOS (VT-x / AMD-V)    | idem ; sur une VM : virtualisation imbriquée     |
| RAM            | 8 Go minimum, 16 Go recommandé         | idem                                             |
| Disque         | 30 Go libres, SSD fortement recommandé | idem                                             |

> **Licence Docker Desktop** : gratuite pour l'usage personnel, l'éducation, l'open source non commercial. L'alternative gratuite est Docker Engine dans WSL2 (§ 4.6).

### 4.2 Installer Docker Desktop (une fois par poste)

1. En PowerShell **administrateur** : `wsl --install`, puis redémarrer.
2. Installer [Docker Desktop](https://www.docker.com/products/docker-desktop/) en gardant l'option « Use WSL 2 ».
3. Docker Desktop > _Settings_ > _General_ : cocher **« Start Docker Desktop when you sign in »**.
4. (Recommandé) Limiter la mémoire : copier `windows\wslconfig.example` dans `C:\Users\<utilisateur>\.wslconfig`, ajuster, puis `wsl --shutdown`.

### 4.3 Installer SIGDEP

1. Décompresser le kit dans un dossier **court, sans espaces ni accents**, par ex. `C:\SIGDEP`.
2. Double-cliquer sur **`windows\installer.bat`** (ou glisser le fichier `backup.openmrs.sql.zip` sur `installer.bat` si le dump n'est pas déjà dans `db\init\`). Le script :
   - vérifie que Docker tourne et lance Docker Desktop si besoin ;
   - crée `.env` avec des **mots de passe générés aléatoirement** et les données OpenMRS dans un **volume Docker** (`OPENMRS_DATA_PATH=openmrs-data`) ;
   - prépare `db\init\01-openmrs.sql.gz` ;
   - télécharge les images et démarre SIGDEP.
3. Accès depuis les autres postes : clic droit sur **`windows\ouvrir-pare-feu.bat`** > _Exécuter en tant qu'administrateur_.
4. Adresse : **http://localhost/openmrs/** sur le serveur, **http://&lt;ip-du-serveur&gt;/openmrs/** ailleurs (`ipconfig` pour l'IP).

> **Sauvegardez le fichier `.env`** (clé USB, coffre) : il contient les mots de passe de la base.

### 4.4 Raccourcis du quotidien (`windows\`)

| Fichier                   | Action                                                          |
| ------------------------- | --------------------------------------------------------------- |
| `demarrer.bat`            | Démarre SIGDEP                                                  |
| `arreter.bat`             | Arrête SIGDEP                                                   |
| `etat.bat`                | État des conteneurs + adresse                                   |
| `journaux.bat`            | Journaux OpenMRS en direct (Ctrl+C pour quitter)                |
| `sauvegarder.bat`         | Sauvegarde immédiate dans `backups\`                            |
| `restaurer.bat`           | Glisser un `.sql.gz` dessus pour restaurer (**écrase la base**) |
| `mettre-a-jour.bat 3.0.1` | Passe à la version 3.0.1 de l'image                             |
| `ouvrir-pare-feu.bat`     | Ouvre le port HTTP dans le pare-feu (administrateur)            |

Ces raccourcis appellent `windows\sigdep.ps1`, utilisable directement :

```powershell
powershell -ExecutionPolicy Bypass -File windows\sigdep.ps1 status
powershell -ExecutionPolicy Bypass -File windows\sigdep.ps1 logs db
powershell -ExecutionPolicy Bypass -File windows\sigdep.ps1 restore openmrs-2026-09-28_0200.sql.gz
```

### 4.5 Spécificités Windows prises en compte

| Point                                             | Solution                                                                         |
| ------------------------------------------------- | -------------------------------------------------------------------------------- |
| Fins de ligne CRLF qui cassent les scripts Linux  | `.gitattributes` ; le Dockerfile et le service `backup` reconvertissent en LF    |
| Dossiers `C:\` montés : lents, droits incohérents | Données OpenMRS et MySQL dans des **volumes Docker** (`openmrs-data`, `db-data`) |
| `/etc/localtime` inexistant                       | Fuseau fixé par la variable `TZ`                                                 |
| Port 80 déjà pris (IIS, Skype...)                 | `HTTP_PORT=8081` dans `.env`                                                     |
| Mémoire WSL2 limitée par défaut                   | `windows\wslconfig.example`                                                      |
| Encodage PowerShell 5.1                           | `.ps1` / `.bat` en ASCII + CRLF                                                  |
| Redémarrage du PC                                 | `restart: unless-stopped` + Docker Desktop lancé à l'ouverture de session        |

> Docker Desktop ne démarre qu'**après ouverture d'une session** Windows. Sur un poste serveur, activer l'ouverture de session automatique du compte dédié, ou utiliser l'option § 4.6.

Consulter les fichiers de données OpenMRS (volume) : `docker run --rm -v sigdep_openmrs-data:/d alpine ls -la /d`.

### 4.6 Alternative sans Docker Desktop (Windows Server, ou sans licence)

1. `wsl --install -d Ubuntu`, puis dans Ubuntu : installer Docker Engine ([procédure officielle](https://docs.docker.com/engine/install/ubuntu/)) et activer systemd (`/etc/wsl.conf` : `[boot]` puis `systemd=true`).
2. Copier le kit **dans le système de fichiers Linux** (`~/sigdep`, pas `/mnt/c/...`, beaucoup plus lent) et suivre la **procédure Linux** (section 3).
3. Accès réseau : `networkingMode=mirrored` dans `.wslconfig` (Windows 11 / Server 2025) ; sinon redirection de port avec `netsh interface portproxy`.
4. Démarrage automatique : tâche planifiée « Au démarrage » lançant `wsl.exe -d Ubuntu -u root -- systemctl start docker`.

À valider sur un site pilote avant généralisation.

---

## 5. Sauvegardes

Le service `backup` fait un `mysqldump` compressé chaque jour à `BACKUP_TIME` dans `./backups/` et supprime ceux de plus de `BACKUP_KEEP_DAYS` jours. Sous Windows : `sauvegarder.bat` / `restaurer.bat`.

```bash
# sauvegarde immédiate
docker compose exec backup sigdep-backup now

# liste des sauvegardes
docker compose exec backup sigdep-backup list

# restauration (écrase la base !)
docker compose stop openmrs
docker compose exec backup sigdep-backup restore openmrs-2026-09-28_0200.sql.gz
docker compose start openmrs
```

Pour réinstaller un site à partir d'une sauvegarde : copier le fichier `.sql.gz` dans `db/init/` à la place de `01-openmrs.sql.gz`, puis `docker compose down -v && docker compose up -d` (**`-v` supprime la base existante**).

---

## 6. Variables d'environnement

### `.env` (site)

| Variable                           | Défaut           | Rôle                            |
| ---------------------------------- | ---------------- | ------------------------------- |
| `SIGDEP_VERSION`                   | `3.0.0`          | Tag de l'image `spbogui/sigdep` |
| `MYSQL_ROOT_PASSWORD`              | — (obligatoire)  | Mot de passe root MySQL         |
| `OPENMRS_DB_USER`                  | `openmrs_user`   | Utilisateur MySQL d'OpenMRS     |
| `OPENMRS_DB_PASSWORD`              | — (obligatoire)  | Son mot de passe                |
| `JAVA_XMS` / `JAVA_XMX`            | `2G` / `4G`      | Mémoire Java                    |
| `MYSQL_INNODB_BUFFER`              | `1G`             | Cache InnoDB                    |
| `HTTP_PORT`                        | `80`             | Port nginx                      |
| `OPENMRS_DATA_PATH`                | `./openmrs-data` | Dossier de données OpenMRS      |
| `BACKUP_TIME` / `BACKUP_KEEP_DAYS` | `02:00` / `14`   | Sauvegardes                     |
| `TZ`                               | `Africa/Abidjan` | Fuseau horaire                  |

### Image `spbogui/sigdep`

| Variable                          | Défaut                    | Rôle                                             |
| --------------------------------- | ------------------------- | ------------------------------------------------ |
| `DB_HOST` / `DB_PORT` / `DB_NAME` | `db` / `3306` / `openmrs` | Connexion MySQL                                  |
| `DB_USER` / `DB_PASSWORD`         | `openmrs_user` / —        | Identifiants (mot de passe obligatoire)          |
| `JAVA_XMS` / `JAVA_XMX`           | `1G` / `2G`               | Mémoire Java                                     |
| `JAVA_EXTRA_OPTS`                 | —                         | Options JVM supplémentaires                      |
| `SYNC_MODULES`                    | `true`                    | Synchroniser les modules de l'image au démarrage |
| `AUTO_UPDATE_DATABASE`            | `false`                   | Propriété OpenMRS `auto_update_database`         |
| `MODULE_WEB_ADMIN`                | `true`                    | Autoriser l'ajout de modules depuis l'interface  |
| `DB_WAIT_TIMEOUT`                 | `1800`                    | Attente max de MySQL (secondes)                  |

Propriétés OpenMRS supplémentaires : les écrire dans `openmrs-data/openmrs-runtime.extra.properties`, elles sont ajoutées au fichier généré.

---

## 7. Dépannage

| Symptôme                                            | Piste                                                                                       |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `openmrs` reste en `waiting`                        | MySQL importe encore le dump : `docker compose logs -f db`                                  |
| Page de configuration initiale OpenMRS              | Base vide ou mauvais identifiants : vérifier `db/init/` et `.env`                           |
| Import non relancé après modif de `db/init/`        | Normal : il ne se fait que sur volume vide (`docker compose down -v` pour repartir de zéro) |
| `OutOfMemoryError`                                  | Augmenter `JAVA_XMX` dans `.env`                                                            |
| Erreur de build `wars/openmrs.war introuvable`      | Déposer le WAR dans `wars/`                                                                 |
| Windows : « Docker ne répond pas »                  | Lancer Docker Desktop ; vérifier la virtualisation dans le BIOS et `wsl --status`           |
| Windows : `/bin/bash^M: bad interpreter`            | Script modifié avec un éditeur Windows : reprendre le kit d'origine                         |
| Windows : « l'exécution de scripts est désactivée » | Passer par les `.bat` (ils utilisent `-ExecutionPolicy Bypass`)                             |
| Windows : lenteur importante                        | Données dans des volumes Docker (pas `C:\...`), SSD, `.wslconfig` avec assez de mémoire     |
