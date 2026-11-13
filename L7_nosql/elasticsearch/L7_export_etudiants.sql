-- =====================================================================
-- L7_export_etudiants.sql : export des étudiants pour Elasticsearch
-- Livrable : L7 · NoSQL (moteur 1 : Elasticsearch, besoin « recherche »)
-- Responsable : Baptiste (avec Claude Code)
--
-- À lancer en langues, dans le conteneur Oracle, APRÈS run_all.sql (voir README.md
-- de ce dossier) : on part des étudiants nettoyés par le L2 (doublons fusionnés).
--
-- Fichier produit : /tmp/etudiants_es.ndjson (dans le conteneur oracle-bdd), au format
-- de l'API _bulk : pour chaque étudiant, une ligne d'action puis une ligne de document.
-- Les documents sont écrits par JSON_OBJECT : Oracle échappe lui-même les guillemets et
-- les accents (l'atelier M4-6 a perdu 150 films sur des guillemets mal échappés).
--
-- Minimisation (RGPD) : seulement ce que l'accueil tape ou lit pour reconnaître la
-- personne : nom, prénom, ville, site. Ni e-mail, ni téléphone, ni date d'inscription :
-- une fois l'étudiant trouvé, sa fiche complète se lit dans Oracle par son identifiant.
-- =====================================================================
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 1000
SET TRIMSPOOL ON
SET TERMOUT OFF
-- pas de ligne vide entre deux étudiants (SQL*Plus en ajoute après une valeur sur 2 lignes)
SET RECSEP OFF

SPOOL /tmp/etudiants_es.ndjson

SELECT JSON_OBJECT('index' VALUE JSON_OBJECT('_id' VALUE e.id_etudiant))
       || CHR(10) ||
       JSON_OBJECT('id_etudiant' VALUE e.id_etudiant,
                   'nom'         VALUE e.nom,
                   'prenom'      VALUE e.prenom,
                   'ville'       VALUE e.ville,
                   'id_site'     VALUE e.id_campus,
                   'site'        VALUE c.ville
                   ABSENT ON NULL)
FROM   etudiant e
JOIN   campus   c ON c.id_campus = e.id_campus
ORDER BY e.id_etudiant;

SPOOL OFF
SET TERMOUT ON
EXIT
