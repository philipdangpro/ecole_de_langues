# Elasticsearch — L7 (besoin : recherche)

Responsable : Baptiste (avec Claude Code). Sortie de référence : `preuves/L7_elasticsearch.txt`.

**Besoin.** À l'accueil ou au téléphone, l'agent retrouve un étudiant à partir de ce qu'il entend : un nom mal orthographié, un prénom sans accent. Oracle compare des caractères : « Betrand Leo » donne 0 résultat. Elasticsearch tolère les fautes (`fuzziness`), ignore les accents (analyseur `asciifolding`) et classe les réponses : les 15 Léo Bertrand arrivent en tête.

| Fichier | Rôle |
|---|---|
| `L7_export_etudiants.sql` | exporte d'Oracle les 21 471 étudiants au format `_bulk` (nom, prénom, ville, site ; ni e-mail ni téléphone) |
| `L7_recherche.sh` | crée l'index, importe, vérifie (`errors`, nombre de documents), puis les 3 recherches de l'accueil |
| `L7_oracle_comparaison.sql` | la même recherche dans Oracle (0 résultat) et le nombre de bonnes réponses attendu |

## Lancer (PowerShell, depuis la racine du dépôt)

Prérequis : Oracle chargé (`run_all.sql`) et Elasticsearch du kit démarré
(`cd C:\bdd-kit\3-nosql`, `docker compose --profile elasticsearch up -d`).

```powershell
# 1. Export depuis Oracle (fichier /tmp/etudiants_es.ndjson dans le conteneur Oracle)
docker cp nosql/elasticsearch/L7_export_etudiants.sql oracle-bdd:/tmp/L7_export_etudiants.sql
docker exec oracle-bdd sqlplus -s langues/langues@//localhost:1521/FREEPDB1 "@/tmp/L7_export_etudiants.sql"

# 2. Copie vers Elasticsearch (en passant par la machine)
docker cp oracle-bdd:/tmp/etudiants_es.ndjson $env:TEMP/etudiants_es.ndjson
docker cp $env:TEMP/etudiants_es.ndjson elasticsearch:/tmp/etudiants_es.ndjson
docker cp nosql/elasticsearch/L7_recherche.sh elasticsearch:/tmp/L7_recherche.sh

# 3. Index, import et recherches
docker exec elasticsearch bash /tmp/L7_recherche.sh

# 4. La même recherche dans Oracle, pour comparer
docker cp nosql/elasticsearch/L7_oracle_comparaison.sql oracle-bdd:/tmp/L7_oracle_comparaison.sql
docker exec oracle-bdd sqlplus -s langues/langues@//localhost:1521/FREEPDB1 "@/tmp/L7_oracle_comparaison.sql"
```

Sous Git Bash, préfixer les commandes `docker` qui contiennent un chemin `/tmp/...` par
`MSYS_NO_PATHCONV=1`.
