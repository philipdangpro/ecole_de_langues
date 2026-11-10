-- =====================================================================
-- L7_export_graphe.sql : export du graphe « étudiant -> session » pour Neo4j
-- Livrable : L7 · NoSQL (moteur 2 : Neo4j, besoin « recommandation »)
-- Responsable : Baptiste (avec Claude Code)
--
-- À lancer en langues, dans le conteneur Oracle, APRÈS run_all.sql (voir README.md).
-- Fichier produit : /tmp/graphe_neo4j.cypher, des ordres Cypher prêts pour cypher-shell.
--
-- Pourquoi des ordres Cypher et pas un CSV lu par LOAD CSV : dans le kit, le dossier
-- d'import de Neo4j est monté en lecture seule sur les données du cours. On génère donc
-- des ordres UNWIND [...] par lots de 5 000 lignes (une transaction par lot, mémoire
-- bornée, comme le IN TRANSACTIONS OF de l'atelier M4-7).
--
-- Le graphe :
--   (:Etudiant {id, id_site})  21 471 nœuds, sans nom ni coordonnées : la recommandation
--                              n'en a pas besoin (minimisation, RGPD)
--   (:Session {id, id_site, langue, debut})  47 619 nœuds
--   (:Etudiant)-[:INSCRIT]->(:Session)       une relation par inscription CONFIRMÉE
--                                            (les annulées ne disent pas ce qui plaît)
-- =====================================================================
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 300
SET TRIMSPOOL ON
SET TERMOUT OFF
SET RECSEP OFF

SPOOL /tmp/graphe_neo4j.cypher

-- Relançable : on vide le graphe, puis on pose les contraintes d'unicité, qui créent
-- aussi l'index utilisé par chaque MATCH de l'import (atelier M4-7, question 2).
-- Les relations d'abord, puis les nœuds, par lots : un DETACH DELETE de tout le graphe
-- d'un coup a dépassé le tas de 1 Go du kit (« Java heap space »).
PROMPT MATCH ()-[r:INSCRIT]->() CALL (r) { DELETE r } IN TRANSACTIONS OF 5000 ROWS;;
PROMPT MATCH (n) CALL (n) { DELETE n } IN TRANSACTIONS OF 5000 ROWS;;
PROMPT CREATE CONSTRAINT etudiant_id IF NOT EXISTS FOR (e:Etudiant) REQUIRE e.id IS UNIQUE;;
PROMPT CREATE CONSTRAINT session_id IF NOT EXISTS FOR (s:Session) REQUIRE s.id IS UNIQUE;;

-- Un lot commence par « UNWIND [ » et finit par « ] AS r ... ; » : la 1re ligne de chaque
-- tranche de 5 000 ouvre la liste, la dernière la ferme avec l'ordre de création.
WITH d AS (
    SELECT '[' || id_etudiant || ',' || id_campus || ']' AS v,
           ROW_NUMBER() OVER (ORDER BY id_etudiant) AS rn,
           COUNT(*) OVER () AS n
    FROM   etudiant)
SELECT CASE WHEN MOD(rn - 1, 5000) = 0 THEN 'UNWIND [' END || v ||
       CASE WHEN MOD(rn, 5000) = 0 OR rn = n
            THEN '] AS r CREATE (:Etudiant {id: r[0], id_site: r[1]});' ELSE ',' END
FROM   d ORDER BY rn;

WITH d AS (
    SELECT '[' || s.id_session || ',' || s.id_campus || ',"' || c.libelle || '","'
           || TO_CHAR(s.debut, 'YYYY-MM-DD"T"HH24:MI:SS') || '"]' AS v,
           ROW_NUMBER() OVER (ORDER BY s.id_session) AS rn,
           COUNT(*) OVER () AS n
    FROM   session_cours s
    JOIN   categorie c ON c.id_categorie = s.id_categorie)
SELECT CASE WHEN MOD(rn - 1, 5000) = 0 THEN 'UNWIND [' END || v ||
       CASE WHEN MOD(rn, 5000) = 0 OR rn = n
            THEN '] AS r CREATE (:Session {id: r[0], id_site: r[1], langue: r[2], debut: localdatetime(r[3])});'
            ELSE ',' END
FROM   d ORDER BY rn;

WITH d AS (
    SELECT '[' || id_etudiant || ',' || id_session || ']' AS v,
           ROW_NUMBER() OVER (ORDER BY id_inscription) AS rn,
           COUNT(*) OVER () AS n
    FROM   inscription
    WHERE  statut = 'CONFIRMEE')
SELECT CASE WHEN MOD(rn - 1, 5000) = 0 THEN 'UNWIND [' END || v ||
       CASE WHEN MOD(rn, 5000) = 0 OR rn = n
            THEN '] AS r MATCH (e:Etudiant {id: r[0]}) MATCH (s:Session {id: r[1]}) CREATE (e)-[:INSCRIT]->(s);'
            ELSE ',' END
FROM   d ORDER BY rn;

SPOOL OFF
SET TERMOUT ON
EXIT
