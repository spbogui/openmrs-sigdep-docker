# db/init/

Scripts importés **automatiquement par le conteneur MySQL au tout premier démarrage** (volume `db-data` vide). Formats acceptés : `.sql`, `.sql.gz`, `.sh`, exécutés par ordre alphabétique.

Générer le script depuis un dump SIGDEP :

```bash
./scripts/prepare-db.sh /chemin/vers/backup.openmrs.sql.zip   # -> db/init/01-openmrs.sql.gz
```

Le dump doit cibler la base `openmrs`. Les fichiers de dump ne sont pas versionnés dans git.
