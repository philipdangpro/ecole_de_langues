# Neo4j — L7 (besoin : recommandation)

Responsable : Baptiste (avec Claude Code). Sortie de référence : `preuves/L7_neo4j.txt`.

**Besoin.** Proposer à un étudiant des sessions à venir de son site, choisies par les étudiants qui étaient dans les mêmes sessions que lui (« ils ont aussi choisi… »). On recommande des sessions et pas des langues : 60 % des étudiants ont déjà suivi les 6 langues. C'est le motif à deux sauts de l'atelier M4-7 : `moi -> session passée <- camarade -> session à venir`.

| Fichier | Rôle |
|---|---|
| `L7_export_graphe.sql` | génère depuis Oracle les ordres Cypher d'import : 21 471 étudiants (sans nom), 47 619 sessions, 326 469 inscriptions confirmées |
| `L7_recommandation.cypher` | contrôle de l'import, recommandation pour l'étudiant 2141, mesure (`PROFILE`) |
| `L7_oracle_comparaison.sql` | la même recommandation en SQL : mêmes 5 sessions, blocs lus et temps |

Le kit monte le dossier d'import de Neo4j en lecture seule (données du cours) : `LOAD CSV` ne peut pas lire nos fichiers. Oracle génère donc des ordres `UNWIND [...]` par lots de 5 000 lignes, exécutés par `cypher-shell`.

## Lancer (PowerShell, depuis la racine du dépôt)

Prérequis : Oracle chargé (`run_all.sql`) et Neo4j du kit démarré
(`cd C:\bdd-kit\3-nosql`, `docker compose --profile neo4j up -d`).

```powershell
# 1. Export depuis Oracle (fichier /tmp/graphe_neo4j.cypher dans le conteneur Oracle)
docker cp nosql/neo4j/L7_export_graphe.sql oracle-bdd:/tmp/L7_export_graphe.sql
docker exec oracle-bdd sqlplus -s langues/langues@//localhost:1521/FREEPDB1 "@/tmp/L7_export_graphe.sql"

# 2. Copie vers Neo4j (en passant par la machine)
docker cp oracle-bdd:/tmp/graphe_neo4j.cypher $env:TEMP/graphe_neo4j.cypher
docker cp $env:TEMP/graphe_neo4j.cypher neo4j:/tmp/graphe_neo4j.cypher
docker cp nosql/neo4j/L7_recommandation.cypher neo4j:/tmp/L7_recommandation.cypher

# 3. Import (de 30 s à 2 min 30), puis recommandation et mesure
docker exec neo4j cypher-shell -f /tmp/graphe_neo4j.cypher
docker exec neo4j cypher-shell --format verbose -f /tmp/L7_recommandation.cypher

# 4. La même recommandation dans Oracle, pour comparer
docker cp nosql/neo4j/L7_oracle_comparaison.sql oracle-bdd:/tmp/L7_oracle_comparaison.sql
docker exec oracle-bdd sqlplus -s langues/langues@//localhost:1521/FREEPDB1 "@/tmp/L7_oracle_comparaison.sql"
```

L'import est relançable : il vide le graphe avant de le recréer.
Sous Git Bash, préfixer les commandes `docker` qui contiennent un chemin `/tmp/...` par
`MSYS_NO_PATHCONV=1`.
