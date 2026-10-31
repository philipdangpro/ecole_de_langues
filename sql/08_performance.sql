-- =====================================================================
-- 08_performance.sql
-- Livrable : L5 · Performance
-- Responsable : Baptiste (avec Claude Code)
-- Attendu  : 3 requêtes lentes : plan + blocs lus avant/après ; vue matérialisée ou partitionnement
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Trois requêtes que l'école lance souvent, toutes lentes sur nos 354 458 inscriptions,
-- car elles parcourent toute la table INSCRIPTION (2 304 blocs) :
--   Q1  l'historique d'un étudiant (accueil, à chaque visite)       -> index
--   Q2  les places libres d'une session (à chaque inscription : c'est
--       le contrôle du package du L4, au pic de la rentrée)        -> index couvrant
--   Q3  le tableau de bord : places et CA par site et par langue    -> vue matérialisée
--
-- Méthode de mesure (la même pour les 6 exécutions) :
--   - chaque requête porte le hint GATHER_PLAN_STATISTICS : Oracle compte, pour chaque
--     étape du plan, les lignes réellement produites et les blocs lus (colonne Buffers) ;
--   - un repère dans le hint (L5_Q1_AVANT, ...) permet de retrouver la requête dans V$SQL ;
--   - DBMS_XPLAN.DISPLAY_CURSOR(..., 'ALLSTATS LAST') affiche le plan réellement suivi ;
--   - le tableau L5_MESURE résume les blocs lus avant / après.
--   Lecture de V$SQL : SELECT_CATALOG_ROLE, donné par installation_system.sql.
--   « Blocs lus » = lectures logiques (Buffers). C'est la mesure stable : elle ne dépend
--   pas de ce qui est déjà en mémoire, contrairement au temps.
-- =====================================================================
SET LINESIZE 200
SET PAGESIZE 200
COLUMN plan_table_output FORMAT A160
COLUMN libelle FORMAT A25
COLUMN langue  FORMAT A10
COLUMN statut  FORMAT A9


-- ---------------------------------------------------------------------
-- 0. Statistiques à jour : l'optimiseur choisit ses plans à partir d'elles
-- ---------------------------------------------------------------------
BEGIN
    FOR t IN (SELECT table_name FROM user_tables
              WHERE table_name IN ('INSCRIPTION', 'SESSION_COURS', 'ETUDIANT', 'CATEGORIE')) LOOP
        DBMS_STATS.GATHER_TABLE_STATS(USER, t.table_name);
    END LOOP;
END;
/

CREATE TABLE l5_mesure (
    requete     VARCHAR2(4 CHAR)   CONSTRAINT nn_l5_mesure_requete NOT NULL,
    version     VARCHAR2(5 CHAR)   CONSTRAINT nn_l5_mesure_version NOT NULL,
    optimisation VARCHAR2(60 CHAR),
    blocs_lus   NUMBER,
    lignes      NUMBER,
    CONSTRAINT pk_l5_mesure PRIMARY KEY (requete, version),
    CONSTRAINT ck_l5_mesure_version CHECK (version IN ('AVANT', 'APRES'))
);
COMMENT ON TABLE l5_mesure IS 'L5 : blocs lus par les 3 requêtes lentes, avant et après optimisation (rempli par 08_performance.sql).';


-- =====================================================================
-- Q1. Historique d'un étudiant (ici l'étudiant 2141 : 17 inscriptions, la moyenne)
-- =====================================================================
SELECT /*+ GATHER_PLAN_STATISTICS L5_Q1_AVANT */
       i.id_inscription, i.date_operation, s.libelle, s.debut, i.nb_places, i.montant, i.statut
FROM   inscription i
JOIN   session_cours s ON s.id_session = i.id_session
WHERE  i.id_etudiant = 2141
ORDER BY i.date_operation;

SELECT p.plan_table_output
FROM  (SELECT sql_id, child_number FROM v$sql
       WHERE  sql_text LIKE '%L5_Q1_AVANT%' AND sql_text NOT LIKE '%v$sql%'
       ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST')) p;
-- Plan avant : TABLE ACCESS FULL sur INSCRIPTION, environ 2 300 blocs lus pour 17 lignes.

-- Optimisation : index sur l'étudiant. La clé étrangère fk_inscription_etudiant n'avait
-- pas d'index (choix du L1 : mesurer d'abord). id_session et statut sont ajoutés derrière :
-- le même index sert au contrôle RG13 du L4 (étudiant + session + statut) sans lire la table.
CREATE INDEX ix_inscription_etudiant ON inscription (id_etudiant, id_session, statut);

SELECT /*+ GATHER_PLAN_STATISTICS L5_Q1_APRES */
       i.id_inscription, i.date_operation, s.libelle, s.debut, i.nb_places, i.montant, i.statut
FROM   inscription i
JOIN   session_cours s ON s.id_session = i.id_session
WHERE  i.id_etudiant = 2141
ORDER BY i.date_operation;

SELECT p.plan_table_output
FROM  (SELECT sql_id, child_number FROM v$sql
       WHERE  sql_text LIKE '%L5_Q1_APRES%' AND sql_text NOT LIKE '%v$sql%'
       ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST')) p;
-- Plan après : INDEX RANGE SCAN sur IX_INSCRIPTION_ETUDIANT, puis accès aux 17 lignes.


-- =====================================================================
-- Q2. Places confirmées d'une session (le contrôle de sur-réservation du package L4)
-- =====================================================================
SELECT /*+ GATHER_PLAN_STATISTICS L5_Q2_AVANT */
       NVL(SUM(nb_places), 0) AS places_confirmees
FROM   inscription
WHERE  id_session = 17
AND    statut = 'CONFIRMEE';

SELECT p.plan_table_output
FROM  (SELECT sql_id, child_number FROM v$sql
       WHERE  sql_text LIKE '%L5_Q2_AVANT%' AND sql_text NOT LIKE '%v$sql%'
       ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST')) p;
-- Plan avant : TABLE ACCESS FULL, environ 2 300 blocs lus pour une poignée de lignes.

-- Optimisation : index « couvrant ». Il contient toutes les colonnes dont la requête a
-- besoin (session, statut, places) : Oracle répond avec l'index seul, sans lire la table.
-- Il sert aussi d'index à la clé étrangère fk_inscription_session.
CREATE INDEX ix_inscription_session ON inscription (id_session, statut, nb_places);

SELECT /*+ GATHER_PLAN_STATISTICS L5_Q2_APRES */
       NVL(SUM(nb_places), 0) AS places_confirmees
FROM   inscription
WHERE  id_session = 17
AND    statut = 'CONFIRMEE';

SELECT p.plan_table_output
FROM  (SELECT sql_id, child_number FROM v$sql
       WHERE  sql_text LIKE '%L5_Q2_APRES%' AND sql_text NOT LIKE '%v$sql%'
       ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST')) p;
-- Plan après : INDEX RANGE SCAN sur IX_INSCRIPTION_SESSION, aucun accès à la table.


-- =====================================================================
-- Q3. Tableau de bord de la direction : places et CA confirmés par site et par langue
--     Il lit forcément toutes les inscriptions confirmées : un index n'y peut rien.
--     On calcule le résultat à l'avance dans une vue matérialisée.
-- =====================================================================
SELECT /*+ GATHER_PLAN_STATISTICS L5_Q3_AVANT */
       i.id_site, c.libelle AS langue, SUM(i.nb_places) AS places, SUM(i.montant) AS ca
FROM   inscription i
JOIN   session_cours s ON s.id_session = i.id_session
JOIN   categorie c     ON c.id_categorie = s.id_categorie
WHERE  i.statut = 'CONFIRMEE'
GROUP BY i.id_site, c.libelle
ORDER BY i.id_site, c.libelle;

SELECT p.plan_table_output
FROM  (SELECT sql_id, child_number FROM v$sql
       WHERE  sql_text LIKE '%L5_Q3_AVANT%' AND sql_text NOT LIKE '%v$sql%'
       ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST')) p;
-- Plan avant : 2 jointures par hachage et lecture complète d'INSCRIPTION et SESSION_COURS.

-- Optimisation : vue matérialisée par site, langue et MOIS de la session.
--   - Le mois permet d'autres tableaux (évolution mensuelle, rentrée de septembre) à
--     partir de la même vue : 3 sites x 6 langues x 24 mois, quelques centaines de lignes.
--   - ENABLE QUERY REWRITE : Oracle réécrit tout seul la requête Q3 (inchangée) pour lire
--     la vue au lieu des tables. Les programmes existants n'ont rien à changer.
--   - REFRESH COMPLETE ON DEMAND : recalculée à la demande (par exemple chaque nuit,
--     DBMS_MVIEW.REFRESH('MV_ACTIVITE_MENSUELLE')). Un tableau de bord tolère des chiffres
--     de la veille. Tant qu'elle n'est pas recalculée après une nouvelle inscription, Oracle
--     ne l'utilise plus pour réécrire (query_rewrite_integrity = enforced) : la requête
--     repasse sur les tables, plus lente mais jamais fausse.
CREATE MATERIALIZED VIEW mv_activite_mensuelle
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
ENABLE QUERY REWRITE
AS
SELECT i.id_site,
       c.libelle                AS langue,
       TRUNC(s.debut, 'MM')     AS mois,
       COUNT(*)                 AS nb_inscriptions,
       SUM(i.nb_places)         AS places,
       SUM(i.montant)           AS ca
FROM   inscription i
JOIN   session_cours s ON s.id_session = i.id_session
JOIN   categorie c     ON c.id_categorie = s.id_categorie
WHERE  i.statut = 'CONFIRMEE'
GROUP BY i.id_site, c.libelle, TRUNC(s.debut, 'MM');

COMMENT ON MATERIALIZED VIEW mv_activite_mensuelle IS 'L5 : places et CA confirmés par site, langue et mois. Recalcul : DBMS_MVIEW.REFRESH.';

EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'MV_ACTIVITE_MENSUELLE')

SELECT /*+ GATHER_PLAN_STATISTICS L5_Q3_APRES */
       i.id_site, c.libelle AS langue, SUM(i.nb_places) AS places, SUM(i.montant) AS ca
FROM   inscription i
JOIN   session_cours s ON s.id_session = i.id_session
JOIN   categorie c     ON c.id_categorie = s.id_categorie
WHERE  i.statut = 'CONFIRMEE'
GROUP BY i.id_site, c.libelle
ORDER BY i.id_site, c.libelle;

SELECT p.plan_table_output
FROM  (SELECT sql_id, child_number FROM v$sql
       WHERE  sql_text LIKE '%L5_Q3_APRES%' AND sql_text NOT LIKE '%v$sql%'
       ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST')) p;
-- Plan après : MAT_VIEW REWRITE ACCESS FULL sur MV_ACTIVITE_MENSUELLE : la requête n'a
-- pas changé, Oracle lit la vue matérialisée. Même résultat qu'avant (C5 et C9 par site).


-- =====================================================================
-- Bilan : blocs lus avant / après
-- Pour chaque requête, on lit dans V$SQL_PLAN_STATISTICS_ALL la première étape du plan
-- (id = 1) : ses Buffers comptent les blocs lus par tout le plan.
-- Si la base a été reconstruite plusieurs fois, V$SQL peut garder d'anciennes versions
-- de la requête : on prend la plus récente (last_active_time).
-- =====================================================================
INSERT INTO l5_mesure (requete, version, optimisation, blocs_lus, lignes)
SELECT SUBSTR(m.repere, 4, 2),
       SUBSTR(m.repere, 7),
       CASE SUBSTR(m.repere, 4, 2)
            WHEN 'Q1' THEN 'index ix_inscription_etudiant'
            WHEN 'Q2' THEN 'index couvrant ix_inscription_session'
            WHEN 'Q3' THEN 'vue matérialisée mv_activite_mensuelle'
       END,
       st.last_cr_buffer_gets + st.last_cu_buffer_gets,
       st.last_output_rows
FROM  (SELECT 'L5_Q1_AVANT' AS repere FROM dual UNION ALL SELECT 'L5_Q1_APRES' FROM dual
       UNION ALL SELECT 'L5_Q2_AVANT' FROM dual UNION ALL SELECT 'L5_Q2_APRES' FROM dual
       UNION ALL SELECT 'L5_Q3_AVANT' FROM dual UNION ALL SELECT 'L5_Q3_APRES' FROM dual) m
CROSS APPLY (SELECT sql_id, child_number FROM v$sql
             WHERE  sql_text LIKE '%' || m.repere || '%' AND sql_text NOT LIKE '%v$sql%'
             ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q
JOIN   v$sql_plan_statistics_all st ON st.sql_id = q.sql_id
                                   AND st.child_number = q.child_number
                                   AND st.id = 1;
COMMIT;

COLUMN requete      FORMAT A7
COLUMN optimisation FORMAT A40
SELECT a.requete, a.optimisation,
       a.blocs_lus AS blocs_avant, p.blocs_lus AS blocs_apres,
       ROUND(a.blocs_lus / NULLIF(p.blocs_lus, 0)) AS divise_par
FROM   l5_mesure a
JOIN   l5_mesure p ON p.requete = a.requete AND p.version = 'APRES'
WHERE  a.version = 'AVANT'
ORDER BY a.requete;
-- Résultat : voir preuves/L5_performance.txt et docs/comptes_rendus/05_L5_performance_securite.md
