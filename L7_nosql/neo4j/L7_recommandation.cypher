// =====================================================================
// L7_recommandation.cypher : « les étudiants de vos sessions se sont aussi inscrits à… »
// Livrable : L7 · NoSQL (moteur 2 : Neo4j, besoin « recommandation »)
// Responsable : Baptiste (avec Claude Code)
//
// Besoin réel : quand un étudiant passe à l'accueil (ou à la fin d'une session), lui
// proposer des sessions à venir de son site, choisies par les étudiants qui étaient dans
// les mêmes sessions que lui. On recommande des SESSIONS et pas des langues : 12 985
// étudiants (60 %) ont déjà suivi les 6 langues (mesuré dans Oracle).
// C'est le motif à deux sauts de l'atelier M4-7 (question 17) :
//   moi -> session passée <- camarade -> session à venir
//
// Lancement (voir README.md) : docker exec neo4j cypher-shell -f /tmp/L7_recommandation.cypher
// Date de référence fixe (31/10/2026) : le résultat ne dépend pas du jour où on le relance.
// Sortie de référence : preuves/L7_neo4j.txt
// =====================================================================

// Contrôle de l'import : mêmes nombres qu'Oracle (21 471 étudiants, 47 619 sessions,
// 326 469 inscriptions confirmées)
MATCH (e:Etudiant) WITH count(e) AS etudiants
MATCH (s:Session)  WITH etudiants, count(s) AS sessions
MATCH ()-[r:INSCRIT]->()
RETURN etudiants, sessions, count(r) AS inscriptions_confirmees;

// Q1. Recommandations pour l'étudiant 2141 (celui des L5 et L6 : 13 inscriptions
//     confirmées, dont 11 dans des sessions passées)
//   - camarades : étudiants inscrits à au moins une de ses sessions passées ;
//   - sessions recommandées : à venir, dans son site, où il n'est pas déjà inscrit ;
//   - classées par nombre de camarades qui les ont choisies.
MATCH (moi:Etudiant {id: 2141})-[:INSCRIT]->(passee:Session)<-[:INSCRIT]-(camarade:Etudiant)
      -[:INSCRIT]->(reco:Session)
WHERE passee.debut < localdatetime('2026-10-31T00:00:00')
  AND reco.debut  >= localdatetime('2026-10-31T00:00:00')
  AND reco.id_site = moi.id_site
  AND camarade <> moi
  AND NOT (moi)-[:INSCRIT]->(reco)
RETURN reco.id AS session, reco.langue AS langue, reco.debut AS debut,
       count(DISTINCT camarade) AS camarades
ORDER BY camarades DESC, debut, session
LIMIT 5;

// Q2. Mesure : la même requête avec PROFILE (colonnes Time en ms et DbHits, accès au
// graphe). Chaque saut suit les relations des seuls nœuds atteints : 13 inscriptions,
// 84 places de camarades dans ses sessions passées, 1 430 inscriptions de ces camarades
// (colonne Rows).
// Comparaison avec la même requête en SQL : L7_oracle_comparaison.sql. Mesuré : mêmes
// 5 sessions ; Oracle 633 blocs lus en 0,02 s, Neo4j 5 193 accès en 0,1 à 0,25 s.
// Sur notre volume, Oracle (avec les index du L5) n'est pas plus lent : Neo4j est choisi
// pour la forme de la requête, pas pour la vitesse (voir le compte rendu L7).
PROFILE
MATCH (moi:Etudiant {id: 2141})-[:INSCRIT]->(passee:Session)<-[:INSCRIT]-(camarade:Etudiant)
      -[:INSCRIT]->(reco:Session)
WHERE passee.debut < localdatetime('2026-10-31T00:00:00')
  AND reco.debut  >= localdatetime('2026-10-31T00:00:00')
  AND reco.id_site = moi.id_site
  AND camarade <> moi
  AND NOT (moi)-[:INSCRIT]->(reco)
RETURN reco.id AS session, reco.langue AS langue, reco.debut AS debut,
       count(DISTINCT camarade) AS camarades
ORDER BY camarades DESC, debut, session
LIMIT 5;
