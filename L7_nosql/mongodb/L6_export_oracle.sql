-- =====================================================================
-- L6_export_oracle.sql : export des inscriptions valides pour MongoDB
-- Livrable : L6 · Distribution (collection MongoDB shardée)
-- Responsable : Baptiste (avec Claude Code)
--
-- À lancer en langues, dans le conteneur Oracle, APRÈS run_all.sql (voir README.md
-- de ce dossier) : on part des données nettoyées par le L2 (doublons d'étudiants fusionnés,
-- opérations non valides écartées), pour que MongoDB contienne exactement les 354 458
-- opérations valides et redonne les mêmes valeurs de contrôle qu'Oracle.
--
-- Un document = une inscription, avec ce qu'il faut de la session pour répondre sans
-- jointure (site, ville, langue, début) : en MongoDB, on stocke ensemble ce qu'on lit
-- ensemble.
--
-- Fichier produit : /tmp/inscriptions_mongo.csv (dans le conteneur oracle-bdd).
-- La 1re ligne donne le nom ET le type de chaque champ (option --columnsHaveTypes de
-- mongoimport) : entiers, nombres décimaux, dates.
-- =====================================================================
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 400
SET TRIMSPOOL ON
SET TERMOUT OFF
SET MARKUP CSV ON QUOTE ON

-- point décimal, quel que soit le réglage du poste
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

SPOOL /tmp/inscriptions_mongo.csv

PROMPT _id.int64(),id_etudiant.int32(),id_session.int32(),id_site.int32(),ville.string(),langue.string(),debut.date_go(2006-01-02T15:04:05),date_operation.date_go(2006-01-02T15:04:05),nb_places.int32(),montant.double(),statut.string(),id_groupe.string()

SELECT i.id_inscription,
       i.id_etudiant,
       i.id_session,
       i.id_site,
       c.ville,
       cat.libelle,
       TO_CHAR(s.debut,          'YYYY-MM-DD"T"HH24:MI:SS'),
       TO_CHAR(i.date_operation, 'YYYY-MM-DD"T"HH24:MI:SS'),
       i.nb_places,
       TO_CHAR(i.montant, 'FM9999990.00'),
       i.statut,
       i.id_groupe
FROM   inscription   i
JOIN   session_cours s   ON s.id_session    = i.id_session
JOIN   categorie     cat ON cat.id_categorie = s.id_categorie
JOIN   campus        c   ON c.id_campus     = i.id_site
ORDER BY i.id_inscription;

SPOOL OFF
SET TERMOUT ON
EXIT
