-- =====================================================================
-- run_all.sql : reconstruit toute la base de zéro, dans l'ordre.
-- Lancement (depuis le dossier sql/) :
--   sqlplus utilisateur/motdepasse@//localhost:1521/FREEPDB1 @run_all.sql
--   ou dans SQL Developer : ouvrir ce fichier puis « Exécuter le script » (F5)
-- Règle : toute modification de la base passe par un de ces scripts.
-- =====================================================================
WHENEVER SQLERROR CONTINUE
SET ECHO ON
SET DEFINE OFF
SPOOL run_all.log

@@00_nettoyage.sql
@@01_creation_tables.sql
@@02_chargement.sql
@@03_valeurs_controle.sql
@@04_requetes_metier.sql
@@05_normalisation.sql
@@06_triggers.sql
@@07_package_parcours.sql
@@08_performance.sql
@@09_securite.sql
@@10_distribution.sql
-- @@11_bonus_objet.sql          -- optionnel (bonus +2)

SPOOL OFF
