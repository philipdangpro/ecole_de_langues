-- =====================================================================
-- installation_system.sql
-- À lancer UNE SEULE FOIS, avec le compte administrateur du kit (system / oracle),
-- AVANT run_all.sql. N'est PAS lancé par run_all.sql.
--
-- Pourquoi : le kit du cours ne crée que le compte « club ». Notre projet travaille
-- dans son propre schéma « langues », et le chargement lit les CSV par des tables
-- externes, qui ont besoin d'un objet DIRECTORY que seul un administrateur peut créer.
--
-- Étapes complètes sur un kit neuf (depuis la racine du dépôt) :
--   1. copier les CSV dans le conteneur (PowerShell ou cmd) :
--      docker exec oracle-bdd mkdir -p /opt/oracle/donnees_langues
--      docker cp data/. oracle-bdd:/opt/oracle/donnees_langues/
--      (sous Git Bash, préfixer par MSYS_NO_PATHCONV=1, sinon le chemin /opt/... est
--       réécrit en chemin Windows et la copie échoue sans message)
--   2. ce script, connecté en system à FREEPDB1 :
--      SQL Developer : connexion system/oracle, service FREEPDB1, F5
--      ou (PowerShell) :
--        docker cp sql/installation_system.sql oracle-bdd:/tmp/installation_system.sql
--        docker exec oracle-bdd sqlplus -s system/oracle@//localhost:1521/FREEPDB1 "@/tmp/installation_system.sql"
--   3. run_all.sql, connecté en langues/langues (voir README).
--
-- Relançable : ne recrée pas l'utilisateur s'il existe déjà (Oracle 23ai et plus).
-- =====================================================================

CREATE USER IF NOT EXISTS langues IDENTIFIED BY "langues"
    DEFAULT TABLESPACE USERS
    QUOTA UNLIMITED ON USERS;

-- Mêmes droits que le compte « club » du kit
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE,
      CREATE TRIGGER, CREATE TYPE, CREATE SYNONYM, CREATE MATERIALIZED VIEW,
      CREATE DATABASE LINK TO langues;

-- Lecture du dictionnaire (plans d'exécution, statistiques : L5)
GRANT SELECT_CATALOG_ROLE TO langues;

-- Dossier du conteneur où sont copiés les CSV (étape 1 ci-dessus)
CREATE OR REPLACE DIRECTORY dir_donnees_langues AS '/opt/oracle/donnees_langues';
GRANT READ ON DIRECTORY dir_donnees_langues TO langues;
