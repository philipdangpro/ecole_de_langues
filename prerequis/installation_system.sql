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

-- L5 (sécurité, 09_securite.sql) :
--   - CREATE ROLE : langues crée les rôles du L5 et les donne aux comptes ci-dessous
--     (le créateur d'un rôle peut le donner) ;
--   - DBMS_RLS : sécurité par ligne (Virtual Private Database). system ne peut pas
--     donner directement EXECUTE ON SYS.DBMS_RLS (ORA-01031) : seuls des rôles l'ont.
--     On prend DB_DEVELOPER_ROLE, le rôle « développeur » d'Oracle 23ai, qui le contient.
-- On ne donne PAS CREATE USER à langues : créer des comptes reste le travail de
-- l'administrateur, d'où les comptes créés ici.
GRANT CREATE ROLE TO langues;
GRANT DB_DEVELOPER_ROLE TO langues;

-- Comptes de démonstration du L5 (mot de passe = nom du compte) :
--   agent_bordeaux, agent_tours : agents d'accueil d'un site, ne voient que leur site
--   direction                   : siège, voit tous les sites mais aucune donnée personnelle
-- Ils n'ont que le droit de se connecter : leurs droits de lecture viennent des rôles
-- donnés par 09_securite.sql.
CREATE USER IF NOT EXISTS agent_bordeaux IDENTIFIED BY "agent_bordeaux";
CREATE USER IF NOT EXISTS agent_tours    IDENTIFIED BY "agent_tours";
CREATE USER IF NOT EXISTS direction      IDENTIFIED BY "direction";
GRANT CREATE SESSION TO agent_bordeaux, agent_tours, direction;

-- L6 (distribution, 10_distribution.sql) : un compte par site, qui joue le rôle de la
-- base locale du site (mot de passe = nom du compte). Dans la réalité, ce seraient trois
-- serveurs ; ici, trois schémas de la même base, reliés à langues (le siège) par des
-- liens de base de données. Le siège y crée et remplit les fragments à distance : ces
-- comptes n'ont besoin que de se connecter et de créer leurs propres tables.
CREATE USER IF NOT EXISTS site_bordeaux IDENTIFIED BY "site_bordeaux" QUOTA UNLIMITED ON USERS;
CREATE USER IF NOT EXISTS site_tours    IDENTIFIED BY "site_tours"    QUOTA UNLIMITED ON USERS;
CREATE USER IF NOT EXISTS site_angers   IDENTIFIED BY "site_angers"   QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION, CREATE TABLE TO site_bordeaux, site_tours, site_angers;

-- Dossier du conteneur où sont copiés les CSV (étape 1 ci-dessus)
CREATE OR REPLACE DIRECTORY dir_donnees_langues AS '/opt/oracle/donnees_langues';
GRANT READ ON DIRECTORY dir_donnees_langues TO langues;
