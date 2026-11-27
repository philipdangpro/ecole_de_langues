-- =====================================================================
-- run_all.sql : reconstruit toute la base de zéro, dans l'ordre.
-- Connexion : langues / langues, service FREEPDB1 (après installation_system.sql en system).
-- Lancement (depuis le dossier prerequis/, les chemins sont relatifs à ce fichier) :
--   sqlplus langues/langues@//localhost:1521/FREEPDB1 @run_all.sql
--   ou dans SQL Developer : ouvrir ce fichier puis « Exécuter le script » (F5)
-- Règle : toute modification de la base passe par un de ces scripts.
-- =====================================================================
WHENEVER SQLERROR CONTINUE
SET ECHO ON
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 100
SPOOL run_all.log

-- L1 : nettoyage puis création des tables
@@00_nettoyage.sql
@@../L1_modele/01_creation_tables.sql
-- L2 : chargement des CSV, valeurs de contrôle C1 à C9, 10 requêtes métier
@@../L2_chargement_requetes/02_chargement.sql
@@../L2_chargement_requetes/03_valeurs_controle.sql
@@../L2_chargement_requetes/04_requetes_metier.sql
-- L3 : table à plat, dépendances fonctionnelles, décomposition, dénormalisation
@@../L3_normalisation/05_normalisation.sql
-- L4 : triggers (dont audit) et package du parcours multi-sites
@@../L4_fiabilite/06_triggers.sql
@@../L4_fiabilite/07_package_parcours.sql
-- L5 : performance (index, vue matérialisée) et sécurité (rôles, vues, VPD)
@@../L5_perf_et_securite/08_performance.sql
@@../L5_perf_et_securite/09_securite.sql
-- L6 : fragmentation par site, liens, vues globales
@@../L6_distribution/10_distribution.sql
-- Bonus : type objet avec héritage et méthode
@@../bonus_objet/11_bonus_objet.sql

-- Recompile ce qui a été invalidé en route (V_SESSION_OCCUPATION, après l'ajout
-- de INSCRIPTION.id_site au L3), puis vérifie qu'aucun objet ne reste invalide.
EXEC DBMS_UTILITY.COMPILE_SCHEMA(schema => USER, compile_all => FALSE)
SELECT object_type, object_name FROM user_objects WHERE status <> 'VALID';

SPOOL OFF
