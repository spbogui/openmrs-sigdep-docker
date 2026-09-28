# modules/

Tous les fichiers `*.omod` présents ici sont embarqués dans l'image (`/opt/sigdep/modules`).

Au démarrage, le conteneur les synchronise dans `/openmrs/data/modules` : l'ancienne version d'un module est retirée et la version de l'image est installée. Un module ajouté à la main sur un site (et absent d'ici) est conservé.

Pour mettre à jour un module : remplacez son `.omod` ici, augmentez `VERSION`, reconstruisez l'image.

Les `.omod` ne sont pas versionnés dans git (voir `.gitignore`).
