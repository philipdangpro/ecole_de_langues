# MongoDB shardé — L6

Responsable : Baptiste (avec Claude Code). Explications et choix : `docs/L6_distribution/L6_distribution.md`.
Sortie de référence de toutes les étapes : `preuves/L6_mongodb.txt`.

## Ce qu'il y a ici

| Fichier | Rôle |
|---|---|
| `L6_export_oracle.sql` | exporte d'Oracle les 354 458 inscriptions valides (une ligne = un document, avec site, ville, langue et début de la session) |
| `L6_mesures.js` | mesure la répartition selon chaque clé candidate (site, date, étudiant), avant de choisir |
| `L6_sharding.js` | crée `langues.inscriptions` shardée sur `{ id_etudiant: "hashed" }`, et une collection de comparaison shardée par site ; prouve la répartition, le ciblage des requêtes et redonne C5, C6, C8 |

## Lancer (PowerShell, depuis la racine du dépôt)

Prérequis : Oracle chargé (`run_all.sql`) et le cluster du kit démarré et initialisé
(`C:\bdd-kit\2-mongodb-cluster`, `docker compose up -d`, Lab 6 partie 1 ou
`docker compose run --rm init`).

```powershell
# 1. Export depuis Oracle (fichier /tmp/inscriptions_mongo.csv dans le conteneur Oracle)
docker cp nosql/mongodb/L6_export_oracle.sql oracle-bdd:/tmp/L6_export_oracle.sql
docker exec oracle-bdd sqlplus -s langues/langues@//localhost:1521/FREEPDB1 "@/tmp/L6_export_oracle.sql"

# 2. Copie vers le routeur MongoDB (en passant par la machine)
docker cp oracle-bdd:/tmp/inscriptions_mongo.csv $env:TEMP/inscriptions_mongo.csv
docker cp $env:TEMP/inscriptions_mongo.csv mongos:/tmp/inscriptions_mongo.csv
docker cp nosql/mongodb/. mongos:/tmp/

# 3. Import dans une collection non shardée (la 1re ligne du CSV donne les types)
docker exec mongos mongoimport --db langues --collection inscriptions_import --drop --type csv --headerline --columnsHaveTypes --ignoreBlanks --file /tmp/inscriptions_mongo.csv

# 4. Mesures, puis sharding (environ 25 s)
docker exec mongos mongosh langues --quiet --file /tmp/L6_mesures.js
docker exec mongos mongosh langues --quiet --file /tmp/L6_sharding.js
```

Sous Git Bash, préfixer les commandes `docker` qui contiennent un chemin `/tmp/...` par
`MSYS_NO_PATHCONV=1` (sinon le chemin est réécrit en chemin Windows).

Le CSV exporté (36 Mo) n'est pas versionné : il se régénère avec l'étape 1.

## Le document

```json
{ "_id": 346742, "id_etudiant": 15656, "id_session": 26414, "id_site": 2,
  "ville": "Bordeaux", "langue": "allemand",
  "debut": ISODate("2025-02-24T18:15:00Z"), "date_operation": ISODate("2025-01-30T15:09:50Z"),
  "nb_places": 1, "montant": 466, "statut": "CONFIRMEE", "id_groupe": "G00003" }
```

Une inscription par document, avec les champs de la session qu'on affiche avec elle
(site, ville, langue, début) : l'historique d'un étudiant se lit sans jointure. Pas de
nom ni d'e-mail : seul l'identifiant de l'étudiant est copié (minimisation RGPD).
`id_groupe` n'existe que pour les inscriptions d'un parcours (`--ignoreBlanks`).
