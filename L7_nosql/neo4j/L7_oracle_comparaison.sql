-- =====================================================================
-- L7_oracle_comparaison.sql : la même recommandation écrite en SQL
-- Livrable : L7 · NoSQL (moteur 2 : Neo4j)
-- Responsable : Baptiste (avec Claude Code)
--
-- À lancer en langues (après run_all.sql). Même question que L7_recommandation.cypher
-- (Q1), pour vérifier que les deux moteurs donnent les mêmes sessions et comparer le
-- travail fait : en SQL, chaque saut du graphe devient une jointure d'INSCRIPTION sur
-- elle-même (3 copies d'INSCRIPTION ici).
-- =====================================================================
SET LINESIZE 200
SET PAGESIZE 200
COLUMN plan_table_output FORMAT A160
COLUMN langue FORMAT A10

SELECT /*+ GATHER_PLAN_STATISTICS L7_RECO */
       reco.id_session AS session_id, c.libelle AS langue, reco.debut,
       COUNT(DISTINCT cam.id_etudiant) AS camarades
FROM   etudiant      moi
JOIN   inscription   i_moi  ON i_moi.id_etudiant = moi.id_etudiant AND i_moi.statut = 'CONFIRMEE'
JOIN   session_cours passee ON passee.id_session  = i_moi.id_session
JOIN   inscription   cam    ON cam.id_session     = passee.id_session AND cam.statut = 'CONFIRMEE'
JOIN   inscription   i_reco ON i_reco.id_etudiant = cam.id_etudiant  AND i_reco.statut = 'CONFIRMEE'
JOIN   session_cours reco   ON reco.id_session    = i_reco.id_session
JOIN   categorie     c      ON c.id_categorie     = reco.id_categorie
WHERE  moi.id_etudiant = 2141
AND    passee.debut <  DATE '2026-10-31'
AND    reco.debut   >= DATE '2026-10-31'
AND    reco.id_campus = moi.id_campus
AND    cam.id_etudiant <> moi.id_etudiant
AND    NOT EXISTS (SELECT 1 FROM inscription x
                   WHERE  x.id_etudiant = moi.id_etudiant AND x.id_session = reco.id_session
                   AND    x.statut = 'CONFIRMEE')
GROUP BY reco.id_session, c.libelle, reco.debut
ORDER BY camarades DESC, reco.debut, reco.id_session
FETCH FIRST 5 ROWS ONLY;
-- Résultat attendu : les 5 mêmes sessions que Neo4j (47540, 4372, 43684, 36019, 18242),
-- 2 camarades chacune

-- Blocs lus (colonne Buffers) et temps (A-Time), avec les index du L5 sur INSCRIPTION.
-- Résultat mesuré : 633 blocs lus, 0,02 s. Chaque jointure passe par un index du L5
-- (ix_inscription_etudiant, ix_inscription_session) : comme dans le graphe, on ne lit
-- que les inscriptions atteintes (13, puis 84, puis 1 430), pas toute la table.
SELECT p.plan_table_output
FROM  (SELECT sql_id, child_number FROM v$sql
       WHERE  sql_text LIKE '%L7_RECO%' AND sql_text NOT LIKE '%v$sql%'
       ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST')) p;
EXIT
