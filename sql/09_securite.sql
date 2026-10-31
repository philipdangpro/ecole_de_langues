-- =====================================================================
-- 09_securite.sql
-- Livrable : L5 · Sécurité
-- Responsable : Baptiste (avec Claude Code)
-- Attendu  : rôle, vue de restriction sans données perso inutiles, VPD/masquage/audit unifié + preuve par compte
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Qui voit quoi :
--   compte          rôle              vue                 lignes vues              données personnelles
--   agent_bordeaux  role_agent_site   v_inscrits_site     site de Bordeaux (2)     nom, prénom, téléphone
--   agent_tours     role_agent_site   v_inscrits_site     site de Tours (3)        nom, prénom, téléphone
--   direction       role_direction    v_activite_site     les 3 sites              aucune
--   langues         (propriétaire)    tout                tout                     tout
--   Personne d'autre que langues ne lit les tables : ni e-mail, ni ville, ni date de
--   création du compte, ni parrain ne sortent du schéma.
--
-- Mécanisme : sécurité par ligne (VPD, package DBMS_RLS). Oracle ajoute tout seul une
-- condition « id_site = ... » à chaque requête qui touche INSCRIPTION ou SESSION_COURS,
-- selon le compte connecté. La même vue v_inscrits_site montre donc des lignes différentes
-- à agent_bordeaux et à agent_tours.
--
-- Prérequis (installation_system.sql, en system) : CREATE ROLE, DB_DEVELOPER_ROLE
-- (pour DBMS_RLS), et les comptes agent_bordeaux, agent_tours, direction.
-- Preuve de ce que voit chaque compte : preuves/L5_securite.sql et .txt
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Quel compte travaille pour quel site
--    id_site vide = tous les sites (la direction). Un compte absent de la table ne voit rien.
-- ---------------------------------------------------------------------
CREATE TABLE compte_site (
    nom_compte  VARCHAR2(128 CHAR) CONSTRAINT nn_compte_site_nom NOT NULL,
    id_site     NUMBER(4),
    CONSTRAINT pk_compte_site      PRIMARY KEY (nom_compte),
    CONSTRAINT fk_compte_site_site FOREIGN KEY (id_site) REFERENCES site (id_campus),
    CONSTRAINT ck_compte_site_nom  CHECK (nom_compte = UPPER(nom_compte))
);

COMMENT ON TABLE compte_site IS 'L5 : site de rattachement de chaque compte Oracle, lu par la politique VPD. id_site vide = tous les sites.';

INSERT INTO compte_site (nom_compte, id_site) VALUES ('AGENT_BORDEAUX', 2);
INSERT INTO compte_site (nom_compte, id_site) VALUES ('AGENT_TOURS',    3);
INSERT INTO compte_site (nom_compte, id_site) VALUES ('DIRECTION',      NULL);
COMMIT;


-- ---------------------------------------------------------------------
-- 2. Les vues de restriction
-- ---------------------------------------------------------------------

-- Agent d'accueil : la liste des inscrits aux sessions de son site. Il a besoin du nom
-- pour accueillir l'étudiant et du téléphone pour le prévenir d'un changement. Il n'a
-- pas besoin de l'e-mail, de la ville, de la date de création du compte, du parrain ni
-- du montant payé : ils ne sont pas dans la vue (minimisation, RGPD).
CREATE OR REPLACE VIEW v_inscrits_site AS
SELECT s.id_campus     AS id_site,
       s.id_session,
       s.libelle       AS session_libelle,
       s.debut,
       i.id_inscription,
       e.nom,
       e.prenom,
       e.telephone,
       i.nb_places,
       i.statut
FROM   inscription   i
JOIN   session_cours s ON s.id_session  = i.id_session
JOIN   etudiant      e ON e.id_etudiant = i.id_etudiant;

-- Direction : l'activité de tous les sites, sans aucune donnée personnelle. Pas même
-- l'id de l'étudiant : un identifiant qui permet de suivre une personne reste une donnée
-- personnelle, et la direction n'en a pas besoin pour ses chiffres.
CREATE OR REPLACE VIEW v_activite_site AS
SELECT i.id_site,
       c.ville                 AS ville_site,
       cat.libelle             AS langue,
       i.id_session,
       TRUNC(s.debut, 'MM')    AS mois_session,
       TRUNC(i.date_operation) AS jour_operation,
       i.nb_places,
       i.montant,
       i.statut,
       CASE WHEN i.id_groupe IS NULL THEN 'N' ELSE 'O' END AS dans_un_parcours
FROM   inscription   i
JOIN   session_cours s   ON s.id_session    = i.id_session
JOIN   categorie     cat ON cat.id_categorie = s.id_categorie
JOIN   campus        c   ON c.id_campus     = i.id_site;

COMMENT ON TABLE v_inscrits_site IS 'L5 : vue des agents d''accueil (role_agent_site), filtrée par site par la politique VPD.';
COMMENT ON TABLE v_activite_site IS 'L5 : vue de la direction (role_direction), sans donnée personnelle.';


-- ---------------------------------------------------------------------
-- 3. Les rôles
--    Les rôles ne sont pas supprimés par 00_nettoyage.sql (ce ne sont pas des objets du
--    schéma) : on les supprime ici s'ils existent, pour pouvoir relancer run_all.
--    Les droits vont aux rôles, et les rôles aux comptes : pour un nouvel agent, il suffit
--    de lui donner le rôle et d'ajouter une ligne dans COMPTE_SITE.
-- ---------------------------------------------------------------------
BEGIN
    -- le créateur d'un rôle le reçoit automatiquement : il apparaît dans USER_ROLE_PRIVS
    FOR r IN (SELECT granted_role FROM user_role_privs
              WHERE  granted_role IN ('ROLE_AGENT_SITE', 'ROLE_DIRECTION')) LOOP
        EXECUTE IMMEDIATE 'DROP ROLE ' || r.granted_role;
    END LOOP;
END;
/

CREATE ROLE role_agent_site;
CREATE ROLE role_direction;

GRANT SELECT ON v_inscrits_site TO role_agent_site;
GRANT SELECT ON v_activite_site TO role_direction;

GRANT role_agent_site TO agent_bordeaux, agent_tours;
GRANT role_direction  TO direction;


-- ---------------------------------------------------------------------
-- 4. Sécurité par ligne (VPD)
--    La fonction renvoie la condition qu'Oracle ajoute aux requêtes du compte connecté :
--      - langues (propriétaire) : aucune condition. Indispensable : les triggers et le
--        package du L4, la vue matérialisée du L5 tournent sous ce compte ;
--      - compte rattaché à un site : id_site = ce site ;
--      - compte « tous les sites » (direction) : aucune condition ;
--      - tout autre compte : 1 = 0, il ne voit rien (refus par défaut).
--    La politique est posée sur les TABLES, pas sur les vues : elle s'applique quel que
--    soit le chemin (vue, jointure, sous-requête).
--    Pas de politique sur ETUDIANT : un étudiant de Bordeaux peut suivre un cours à Tours
--    (12 356 personnes ont des opérations sur au moins deux sites, C6). L'agent de Tours
--    doit le voir dans la liste de SA session. Il ne voit les étudiants qu'à travers
--    v_inscrits_site, donc seulement ceux inscrits dans son site.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_vpd_site (p_schema IN VARCHAR2, p_objet IN VARCHAR2)
RETURN VARCHAR2
IS
    v_compte  VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
    v_trouve  NUMBER;
    v_site    compte_site.id_site%TYPE;
    v_colonne VARCHAR2(30);
BEGIN
    IF v_compte = p_schema THEN
        RETURN NULL;
    END IF;

    SELECT COUNT(*), MAX(id_site) INTO v_trouve, v_site
    FROM   compte_site
    WHERE  nom_compte = v_compte;

    IF v_trouve = 0 THEN
        RETURN '1 = 0';
    ELSIF v_site IS NULL THEN
        RETURN NULL;
    END IF;

    -- le site s'appelle id_site dans INSCRIPTION, id_campus dans SESSION_COURS
    v_colonne := CASE p_objet WHEN 'INSCRIPTION' THEN 'id_site' ELSE 'id_campus' END;
    RETURN v_colonne || ' = ' || v_site;
END fn_vpd_site;
/

BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema   => USER,
        object_name     => 'INSCRIPTION',
        policy_name     => 'POL_INSCRIPTION_SITE',
        function_schema => USER,
        policy_function => 'FN_VPD_SITE',
        statement_types => 'SELECT, INSERT, UPDATE, DELETE',
        update_check    => TRUE);          -- interdit aussi d'écrire une ligne d'un autre site

    DBMS_RLS.ADD_POLICY(
        object_schema   => USER,
        object_name     => 'SESSION_COURS',
        policy_name     => 'POL_SESSION_SITE',
        function_schema => USER,
        policy_function => 'FN_VPD_SITE',
        statement_types => 'SELECT, INSERT, UPDATE, DELETE',
        update_check    => TRUE);
END;
/


-- Contrôle : les rôles, leurs droits et les politiques en place
COLUMN grantee      FORMAT A16
COLUMN table_name   FORMAT A16
COLUMN privilege    FORMAT A10
COLUMN object_name  FORMAT A14
COLUMN policy_name  FORMAT A21
COLUMN function     FORMAT A12
SELECT grantee, table_name, privilege
FROM   user_tab_privs_made
WHERE  grantee IN ('ROLE_AGENT_SITE', 'ROLE_DIRECTION')
ORDER BY grantee;

SELECT object_name, policy_name, function, sel, ins, upd, del, enable
FROM   user_policies
ORDER BY object_name;
-- Résultat attendu : 2 droits SELECT (un par rôle), 2 politiques actives
