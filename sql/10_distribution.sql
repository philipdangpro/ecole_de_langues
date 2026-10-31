-- =====================================================================
-- 10_distribution.sql
-- Livrable : L6 · Distribution
-- Responsable : Baptiste (avec Claude Code)
-- Attendu  : fragmentation par site (schémas, db links, vues globales)
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Prérequis : installation_system.sql relancé en system (comptes site_bordeaux,
-- site_tours, site_angers, créés pour le L6).
--
-- Architecture (explications : docs/L6_distribution/L6_distribution.md) :
--   - langues = le SIÈGE. Il garde le catalogue de répartition, les liens vers les
--     sites, les vues globales et les procédures réparties.
--   - site_bordeaux, site_tours, site_angers = la base locale de chaque SITE. Dans la
--     réalité, trois serveurs ; ici trois schémas de la même base (le kit n'a qu'une
--     instance Oracle). Seule la chaîne USING des liens changerait sur trois serveurs.
--
-- Schéma de répartition :
--   SESSION_COURS  fragmentation horizontale primaire : id_campus = site
--   INSCRIPTION    fragmentation horizontale DÉRIVÉE de SESSION_COURS (une inscription
--                  suit sa session), écrite simplement grâce à id_site, la colonne
--                  dénormalisée du L3 : la clé étrangère inscription -> session reste
--                  locale au site
--   ETUDIANT       fragmentation horizontale sur id_campus (site de rattachement) :
--                  une seule copie des données personnelles, dans le site qui suit l'étudiant
--   CATEGORIE      répliquée dans chaque site (6 lignes, ne change pas) : la clé
--                  étrangère session -> catégorie reste locale
--   CAMPUS, SIEGE, SITE : restent au siège (référentiel de l'organisation)
--   SESSION_REPLIQUE : copie redondante, au siège, des sessions d'Angers (partie 4 bis).
--                  Elle sert de secours quand Angers est en panne (bascule), et les
--                  conflits entre la copie et le site sont réglés par « le dernier
--                  écrivain gagne » (colonne derniere_maj), comme au Lab 5.
--
-- Les tables centrales de langues (L1 à L5) sont gardées : elles servent de référence
-- pour prouver que la fragmentation est complète, disjointe et reconstructible, et les
-- scripts des livrables précédents en ont besoin. Les nouvelles opérations réparties
-- (pkg_reparti) n'écrivent que dans les fragments.
--
-- Codes d'erreur pris par le L6 : -20020 à -20026.
-- Panne et reprise d'un site : sql/L6_panne_reprise.sql (à lancer à la main).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Catalogue de répartition (au siège)
--    Le siège sait où est chaque fragment : c'est ce que lisent les procédures réparties,
--    qui choisissent leur lien à l'exécution. Ajouter un site = une ligne de plus ici.
-- ---------------------------------------------------------------------
CREATE TABLE catalogue_site (
    id_site    NUMBER(4)          CONSTRAINT nn_catsite_id     NOT NULL,
    ville      VARCHAR2(60 CHAR)  CONSTRAINT nn_catsite_ville  NOT NULL,
    compte     VARCHAR2(30 CHAR)  CONSTRAINT nn_catsite_compte NOT NULL,
    nom_lien   VARCHAR2(30 CHAR)  CONSTRAINT nn_catsite_lien   NOT NULL,
    CONSTRAINT pk_catalogue_site  PRIMARY KEY (id_site),
    CONSTRAINT fk_catsite_site    FOREIGN KEY (id_site) REFERENCES site (id_campus),
    CONSTRAINT uq_catsite_lien    UNIQUE (nom_lien)
);

INSERT INTO catalogue_site VALUES (2, 'Bordeaux', 'SITE_BORDEAUX', 'LIEN_BORDEAUX');
INSERT INTO catalogue_site VALUES (3, 'Tours',    'SITE_TOURS',    'LIEN_TOURS');
INSERT INTO catalogue_site VALUES (4, 'Angers',   'SITE_ANGERS',   'LIEN_ANGERS');
COMMIT;


-- ---------------------------------------------------------------------
-- 2. Liens de base de données, du siège vers chaque site
--    Sur trois serveurs, seule la chaîne USING changerait (hôte du site).
--    00_nettoyage.sql supprime les liens (type DATABASE LINK) au début de run_all.
-- ---------------------------------------------------------------------
CREATE DATABASE LINK lien_bordeaux CONNECT TO site_bordeaux IDENTIFIED BY "site_bordeaux"
    USING '//localhost:1521/FREEPDB1';
CREATE DATABASE LINK lien_tours    CONNECT TO site_tours    IDENTIFIED BY "site_tours"
    USING '//localhost:1521/FREEPDB1';
CREATE DATABASE LINK lien_angers   CONNECT TO site_angers   IDENTIFIED BY "site_angers"
    USING '//localhost:1521/FREEPDB1';


-- ---------------------------------------------------------------------
-- 3. Création des fragments, à distance
--    Le siège ne peut pas écrire « CREATE TABLE …@lien » : il appelle, à travers le
--    lien, la procédure DBMS_UTILITY.EXEC_DDL_STATEMENT du site, qui exécute l'ordre
--    avec les droits du compte du site. Les sites n'ont donc besoin que de CREATE TABLE.
--
--    Chaque fragment porte son prédicat en contrainte CHECK (ck_..._fragment) : une ligne
--    d'un autre site est refusée par le site lui-même, la disjonction est garantie.
--
--    Contraintes qui ne peuvent PAS être posées dans un fragment (une contrainte Oracle
--    ne traverse pas un lien) :
--      - inscription.id_etudiant -> etudiant : 22 955 inscriptions (6,5 %) concernent un
--        étudiant rattaché à un autre site ;
--      - unicité de l'e-mail entre sites ; parrain d'un autre site.
--    Elles sont vérifiées par les requêtes de contrôle de la partie 7.
-- ---------------------------------------------------------------------
DECLARE
    PROCEDURE ddl (p_lien VARCHAR2, p_ordre VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'BEGIN DBMS_UTILITY.EXEC_DDL_STATEMENT@' || p_lien || '(:o); END;'
            USING p_ordre;
    END;
BEGIN
    FOR s IN (SELECT id_site, nom_lien FROM catalogue_site ORDER BY id_site) LOOP

        -- Relançable : on repart de fragments vides (ordre inverse des clés étrangères)
        ddl(s.nom_lien, 'DROP TABLE IF EXISTS inscription   CASCADE CONSTRAINTS PURGE');
        ddl(s.nom_lien, 'DROP TABLE IF EXISTS session_cours CASCADE CONSTRAINTS PURGE');
        ddl(s.nom_lien, 'DROP TABLE IF EXISTS etudiant      CASCADE CONSTRAINTS PURGE');
        ddl(s.nom_lien, 'DROP TABLE IF EXISTS categorie     CASCADE CONSTRAINTS PURGE');

        ddl(s.nom_lien, '
            CREATE TABLE categorie (
                id_categorie  NUMBER(4)          CONSTRAINT nn_categorie_id      NOT NULL,
                libelle       VARCHAR2(40 CHAR)  CONSTRAINT nn_categorie_libelle NOT NULL,
                CONSTRAINT pk_categorie         PRIMARY KEY (id_categorie),
                CONSTRAINT uq_categorie_libelle UNIQUE (libelle))');

        ddl(s.nom_lien, '
            CREATE TABLE etudiant (
                id_etudiant       NUMBER(8)          CONSTRAINT nn_etudiant_id     NOT NULL,
                nom               VARCHAR2(80 CHAR)  CONSTRAINT nn_etudiant_nom    NOT NULL,
                prenom            VARCHAR2(80 CHAR)  CONSTRAINT nn_etudiant_prenom NOT NULL,
                email             VARCHAR2(254 CHAR),
                telephone         VARCHAR2(10 CHAR),
                ville             VARCHAR2(60 CHAR),
                id_campus         NUMBER(4)          CONSTRAINT nn_etudiant_campus NOT NULL,
                date_inscription  DATE               CONSTRAINT nn_etudiant_date   NOT NULL,
                id_parrain        NUMBER(8),
                CONSTRAINT pk_etudiant          PRIMARY KEY (id_etudiant),
                CONSTRAINT uq_etudiant_email    UNIQUE (email),
                CONSTRAINT ck_etudiant_fragment CHECK (id_campus = ' || s.id_site || '))');

        ddl(s.nom_lien, '
            CREATE TABLE session_cours (
                id_session     NUMBER(8)          CONSTRAINT nn_session_id        NOT NULL,
                libelle        VARCHAR2(80 CHAR)  CONSTRAINT nn_session_libelle   NOT NULL,
                id_categorie   NUMBER(4)          CONSTRAINT nn_session_categorie NOT NULL,
                id_campus      NUMBER(4)          CONSTRAINT nn_session_campus    NOT NULL,
                debut          DATE               CONSTRAINT nn_session_debut     NOT NULL,
                duree_minutes  NUMBER(3)          CONSTRAINT nn_session_duree     NOT NULL,
                capacite       NUMBER(3)          CONSTRAINT nn_session_capacite  NOT NULL,
                prix_unitaire  NUMBER(7,2)        CONSTRAINT nn_session_prix      NOT NULL,
                derniere_maj   TIMESTAMP DEFAULT SYSTIMESTAMP
                                                  CONSTRAINT nn_session_maj       NOT NULL,
                CONSTRAINT pk_session           PRIMARY KEY (id_session),
                CONSTRAINT fk_session_categorie FOREIGN KEY (id_categorie)
                                                REFERENCES categorie (id_categorie),
                CONSTRAINT ck_session_capacite  CHECK (capacite > 0),
                CONSTRAINT ck_session_prix      CHECK (prix_unitaire >= 0),
                CONSTRAINT ck_session_fragment  CHECK (id_campus = ' || s.id_site || '))');

        ddl(s.nom_lien, '
            CREATE TABLE inscription (
                id_inscription  NUMBER(10)         CONSTRAINT nn_inscription_id       NOT NULL,
                id_etudiant     NUMBER(8)          CONSTRAINT nn_inscription_etudiant NOT NULL,
                id_session      NUMBER(8)          CONSTRAINT nn_inscription_session  NOT NULL,
                id_groupe       VARCHAR2(10 CHAR),
                date_operation  DATE               CONSTRAINT nn_inscription_date     NOT NULL,
                nb_places       NUMBER(3)          CONSTRAINT nn_inscription_places   NOT NULL,
                montant         NUMBER(9,2)        CONSTRAINT nn_inscription_montant  NOT NULL,
                statut          VARCHAR2(10 CHAR)  CONSTRAINT nn_inscription_statut   NOT NULL,
                id_site         NUMBER(4)          CONSTRAINT nn_inscription_site     NOT NULL,
                CONSTRAINT pk_inscription          PRIMARY KEY (id_inscription),
                CONSTRAINT fk_inscription_session  FOREIGN KEY (id_session)
                                                   REFERENCES session_cours (id_session),
                CONSTRAINT ck_inscription_places   CHECK (nb_places >= 1),
                CONSTRAINT ck_inscription_statut   CHECK (statut IN (''CONFIRMEE'', ''ANNULEE'')),
                CONSTRAINT ck_inscription_montant  CHECK (montant >= 0),
                CONSTRAINT ck_inscription_fragment CHECK (id_site = ' || s.id_site || '))');

        -- Index du L5 (historique d''un étudiant, places d''une session), utiles aussi
        -- au contrôle de capacité de pkg_reparti
        ddl(s.nom_lien, 'CREATE INDEX ix_inscription_etudiant ON inscription (id_etudiant, id_session, statut)');
        ddl(s.nom_lien, 'CREATE INDEX ix_inscription_session  ON inscription (id_session, statut, nb_places)');
    END LOOP;
END;
/


-- ---------------------------------------------------------------------
-- 4. Remplissage des fragments depuis les tables centrales
--    INSERT …@lien SELECT … : le siège pousse vers chaque site les lignes de son
--    prédicat. Un COMMIT par site.
-- ---------------------------------------------------------------------
DECLARE
    v_lien catalogue_site.nom_lien%TYPE;
BEGIN
    FOR s IN (SELECT id_site, nom_lien FROM catalogue_site ORDER BY id_site) LOOP
        v_lien := s.nom_lien;

        EXECUTE IMMEDIATE 'INSERT INTO categorie@' || v_lien
            || ' (id_categorie, libelle) SELECT id_categorie, libelle FROM categorie';

        EXECUTE IMMEDIATE 'INSERT INTO etudiant@' || v_lien
            || ' (id_etudiant, nom, prenom, email, telephone, ville, id_campus, date_inscription, id_parrain)'
            || ' SELECT id_etudiant, nom, prenom, email, telephone, ville, id_campus, date_inscription, id_parrain'
            || ' FROM etudiant WHERE id_campus = :s' USING s.id_site;

        EXECUTE IMMEDIATE 'INSERT INTO session_cours@' || v_lien
            || ' (id_session, libelle, id_categorie, id_campus, debut, duree_minutes, capacite, prix_unitaire)'
            || ' SELECT id_session, libelle, id_categorie, id_campus, debut, duree_minutes, capacite, prix_unitaire'
            || ' FROM session_cours WHERE id_campus = :s' USING s.id_site;

        EXECUTE IMMEDIATE 'INSERT INTO inscription@' || v_lien
            || ' (id_inscription, id_etudiant, id_session, id_groupe, date_operation, nb_places, montant, statut, id_site)'
            || ' SELECT id_inscription, id_etudiant, id_session, id_groupe, date_operation, nb_places, montant, statut, id_site'
            || ' FROM inscription WHERE id_site = :s' USING s.id_site;

        COMMIT;
    END LOOP;
END;
/


-- ---------------------------------------------------------------------
-- 4 bis. Redondance : une copie des sessions d'Angers au siège
--    Démarche du Lab 5 (partie 5, VOYAGE_NORD_REPLIQUE), appliquée à notre école.
--    Pourquoi SESSION_COURS : c'est le catalogue, lu à chaque consultation et à chaque
--    inscription, mais rarement modifié (création d'une session, changement de prix
--    ou de salle). Une copie coûte donc peu à tenir à jour. Les inscriptions, elles,
--    changent sans arrêt : on ne les recopie pas (la file d'attente s'en charge).
--    Pourquoi Angers seulement : c'est le site dont on simule la panne ; pour les autres
--    sites, ce serait la même table avec leurs lignes (colonne id_campus).
--
--    Mise à jour de la copie : différée, par pkg_reparti.synchroniser_replique (à la
--    reprise après une panne, et en temps normal à intervalle régulier, par exemple
--    chaque nuit). Chaque ligne porte la date de sa dernière modification
--    (derniere_maj, aussi dans les fragments) : quand la même session a été modifiée
--    des deux côtés, la modification la plus récente l'emporte (« le dernier écrivain
--    gagne »). Cela suppose des horloges synchronisées : ici, c'est la même instance.
-- ---------------------------------------------------------------------
CREATE TABLE session_replique (
    id_session     NUMBER(8)          CONSTRAINT nn_repl_id        NOT NULL,
    libelle        VARCHAR2(80 CHAR)  CONSTRAINT nn_repl_libelle   NOT NULL,
    id_categorie   NUMBER(4)          CONSTRAINT nn_repl_categorie NOT NULL,
    id_campus      NUMBER(4)          CONSTRAINT nn_repl_campus    NOT NULL,
    debut          DATE               CONSTRAINT nn_repl_debut     NOT NULL,
    duree_minutes  NUMBER(3)          CONSTRAINT nn_repl_duree     NOT NULL,
    capacite       NUMBER(3)          CONSTRAINT nn_repl_capacite  NOT NULL,
    prix_unitaire  NUMBER(7,2)        CONSTRAINT nn_repl_prix      NOT NULL,
    derniere_maj   TIMESTAMP          CONSTRAINT nn_repl_maj       NOT NULL,
    CONSTRAINT pk_session_replique PRIMARY KEY (id_session),
    CONSTRAINT fk_repl_site        FOREIGN KEY (id_campus) REFERENCES catalogue_site (id_site),
    CONSTRAINT ck_repl_capacite    CHECK (capacite > 0),
    CONSTRAINT ck_repl_prix        CHECK (prix_unitaire >= 0)
);

COMMENT ON TABLE session_replique IS 'L6 : copie redondante des sessions d''Angers, lue pendant une panne du site (pkg_reparti.consulter_sessions), resynchronisée par pkg_reparti.synchroniser_replique (le dernier écrivain gagne).';

-- Remplie depuis le fragment d'Angers lui-même, à travers le lien : la copie part avec
-- les mêmes dates derniere_maj que le site
INSERT INTO session_replique (id_session, libelle, id_categorie, id_campus, debut,
                              duree_minutes, capacite, prix_unitaire, derniere_maj)
SELECT id_session, libelle, id_categorie, id_campus, debut,
       duree_minutes, capacite, prix_unitaire, derniere_maj
FROM   session_cours@lien_angers;
COMMIT;


-- ---------------------------------------------------------------------
-- 5. Vues globales (au siège) : la reconstruction des tables par UNION ALL
--    Chaque branche répète le prédicat de son fragment (WHERE id_site = 2…). Il est
--    déjà vrai pour toutes les lignes du fragment, mais l'optimiseur du siège ne voit
--    pas les contraintes CHECK des sites : c'est ce prédicat qui lui dit quel site
--    contient quoi (étape de « localisation » d'une requête répartie). Une requête
--    « WHERE id_site = 3 » n'interroge alors que Tours, les deux autres branches sont
--    éliminées sans être lancées (FILTER NULL IS NOT NULL, preuve partie 7.6).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_g_etudiant AS
SELECT id_etudiant, nom, prenom, email, telephone, ville, id_campus, date_inscription, id_parrain
FROM   etudiant@lien_bordeaux WHERE id_campus = 2
UNION ALL
SELECT id_etudiant, nom, prenom, email, telephone, ville, id_campus, date_inscription, id_parrain
FROM   etudiant@lien_tours    WHERE id_campus = 3
UNION ALL
SELECT id_etudiant, nom, prenom, email, telephone, ville, id_campus, date_inscription, id_parrain
FROM   etudiant@lien_angers   WHERE id_campus = 4;

CREATE OR REPLACE VIEW v_g_session AS
SELECT id_session, libelle, id_categorie, id_campus, debut, duree_minutes, capacite, prix_unitaire
FROM   session_cours@lien_bordeaux WHERE id_campus = 2
UNION ALL
SELECT id_session, libelle, id_categorie, id_campus, debut, duree_minutes, capacite, prix_unitaire
FROM   session_cours@lien_tours    WHERE id_campus = 3
UNION ALL
SELECT id_session, libelle, id_categorie, id_campus, debut, duree_minutes, capacite, prix_unitaire
FROM   session_cours@lien_angers   WHERE id_campus = 4;

CREATE OR REPLACE VIEW v_g_inscription AS
SELECT id_inscription, id_etudiant, id_session, id_groupe, date_operation, nb_places, montant, statut, id_site
FROM   inscription@lien_bordeaux WHERE id_site = 2
UNION ALL
SELECT id_inscription, id_etudiant, id_session, id_groupe, date_operation, nb_places, montant, statut, id_site
FROM   inscription@lien_tours    WHERE id_site = 3
UNION ALL
SELECT id_inscription, id_etudiant, id_session, id_groupe, date_operation, nb_places, montant, statut, id_site
FROM   inscription@lien_angers   WHERE id_site = 4;

-- Annuaires du siège : où se trouve chaque session et chaque étudiant (id -> site),
-- sans aucune donnée personnelle. pkg_reparti s'en sert pour choisir le bon lien sans
-- interroger les trois sites, et donc même quand l'un d'eux est en panne.
CREATE OR REPLACE VIEW v_annuaire_session AS
SELECT id_session, id_campus AS id_site FROM session_cours;

CREATE OR REPLACE VIEW v_annuaire_etudiant AS
SELECT id_etudiant, id_campus AS id_site FROM etudiant;


-- ---------------------------------------------------------------------
-- 6. Package des opérations réparties
--    - inscrire_parcours : le parcours multi-sites (RG16) sur les fragments, tout ou rien.
--      Il écrit dans plusieurs sites en une seule transaction : au COMMIT de l'appelant,
--      Oracle fait tout seul une validation à deux phases (2PC) entre les sites. Si un
--      site est injoignable, le parcours est refusé en entier (cohérence avant
--      disponibilité, voir le classement CAP).
--    - inscrire : une inscription simple. Si le site est en panne, elle est mise en
--      attente au siège (OPERATION_EN_ATTENTE) et rejouée à la reprise.
--    - rejouer_attente : la reprise, qui revérifie la capacité au moment du rejeu.
--    - consulter_sessions : lit le catalogue d'un site ; s'il est en panne, bascule sur
--      la copie du siège (SESSION_REPLIQUE), comme CONSULTER_VOYAGES_NORD au Lab 5.
--    - synchroniser_replique : remet la copie et le site d'accord, dans les deux sens ;
--      en cas de conflit, la modification la plus récente gagne.
--    Les liens sont choisis à l'exécution (SQL dynamique) : le package reste valide même
--    quand un site est en panne.
-- ---------------------------------------------------------------------
CREATE TABLE operation_en_attente (
    id_attente      NUMBER(10) GENERATED ALWAYS AS IDENTITY,
    id_site         NUMBER(4)          CONSTRAINT nn_attente_site     NOT NULL,
    id_inscription  NUMBER(10)         CONSTRAINT nn_attente_insc     NOT NULL,
    id_etudiant     NUMBER(8)          CONSTRAINT nn_attente_etudiant NOT NULL,
    id_session      NUMBER(8)          CONSTRAINT nn_attente_session  NOT NULL,
    nb_places       NUMBER(3)          CONSTRAINT nn_attente_places   NOT NULL,
    date_operation  DATE               CONSTRAINT nn_attente_date     NOT NULL,
    mise_en_attente DATE DEFAULT SYSDATE CONSTRAINT nn_attente_quand  NOT NULL,
    etat            VARCHAR2(10 CHAR) DEFAULT 'EN_ATTENTE' CONSTRAINT nn_attente_etat NOT NULL,
    motif           VARCHAR2(200 CHAR),
    CONSTRAINT pk_operation_en_attente PRIMARY KEY (id_attente),
    CONSTRAINT fk_attente_site  FOREIGN KEY (id_site) REFERENCES catalogue_site (id_site),
    CONSTRAINT ck_attente_etat  CHECK (etat IN ('EN_ATTENTE', 'REJOUEE', 'REFUSEE'))
);

COMMENT ON TABLE operation_en_attente IS 'L6 : inscriptions reçues au siège pendant la panne de leur site, rejouées à la reprise (pkg_reparti.rejouer_attente).';

CREATE OR REPLACE PACKAGE pkg_reparti AS

    -- Nom du lien vers un site (lu dans catalogue_site)
    FUNCTION lien (p_id_site IN NUMBER) RETURN VARCHAR2;

    -- Vrai si l'erreur courante signifie « site injoignable » (compte bloqué, service
    -- arrêté, connexion coupée…)
    FUNCTION erreur_de_lien (p_code IN NUMBER) RETURN BOOLEAN;

    -- Parcours multi-sites sur les fragments : tout ou rien, refuse la sur-réservation
    -- et refuse tout le parcours si un des sites est injoignable. COMMIT par l'appelant.
    PROCEDURE inscrire_parcours (
        p_id_etudiant     IN  NUMBER,
        p_sessions        IN  t_liste_sessions,
        p_nb_places       IN  NUMBER DEFAULT 1,
        p_date_operation  IN  DATE DEFAULT SYSDATE,
        p_id_groupe       OUT VARCHAR2);

    -- Inscription simple. p_etat = 'INSCRITE' (posée dans le site) ou 'EN_ATTENTE'
    -- (site en panne : gardée au siège). COMMIT par l'appelant.
    PROCEDURE inscrire (
        p_id_etudiant     IN  NUMBER,
        p_id_session      IN  NUMBER,
        p_nb_places       IN  NUMBER DEFAULT 1,
        p_date_operation  IN  DATE DEFAULT SYSDATE,
        p_id_inscription  OUT NUMBER,
        p_etat            OUT VARCHAR2);

    -- Reprise d'un site : rejoue ses opérations en attente, dans l'ordre d'arrivée.
    -- Une opération qui n'a plus de place est REFUSEE (avec son motif), pas forcée.
    PROCEDURE rejouer_attente (p_id_site IN NUMBER);

    -- Catalogue d'un site : les p_nb_max prochaines sessions à partir de p_a_partir_de,
    -- affichées par DBMS_OUTPUT. p_source = 'SITE' (lu dans le site) ou 'REPLIQUE'
    -- (site en panne : lu dans la copie du siège). -20026 si le site est en panne et
    -- n'a pas de copie.
    PROCEDURE consulter_sessions (
        p_id_site      IN  NUMBER,
        p_a_partir_de  IN  DATE,
        p_nb_max       IN  NUMBER DEFAULT 5,
        p_source       OUT VARCHAR2);

    -- Resynchronise la copie d'un site avec son fragment (le dernier écrivain gagne).
    -- p_vers_site : lignes recopiées de la copie vers le site (plus récentes au siège) ;
    -- p_vers_replique : lignes recopiées du site vers la copie. COMMIT par l'appelant
    -- (validation à deux phases : le siège et le site sont modifiés ensemble).
    PROCEDURE synchroniser_replique (
        p_id_site        IN  NUMBER,
        p_vers_site      OUT NUMBER,
        p_vers_replique  OUT NUMBER);

END pkg_reparti;
/

CREATE OR REPLACE PACKAGE BODY pkg_reparti AS

    FUNCTION lien (p_id_site IN NUMBER) RETURN VARCHAR2 IS
        v_lien catalogue_site.nom_lien%TYPE;
    BEGIN
        SELECT nom_lien INTO v_lien FROM catalogue_site WHERE id_site = p_id_site;
        RETURN v_lien;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20020, 'Site ' || p_id_site || ' absent du catalogue de répartition');
    END lien;


    FUNCTION erreur_de_lien (p_code IN NUMBER) RETURN BOOLEAN IS
    BEGIN
        -- 28000 compte bloqué, 1017 mot de passe refusé, 2063/2068 erreur venue du lien,
        -- 3113/3114/3135/3150 connexion coupée, 12514/12541/12170 service ou réseau
        -- absent, 2019 lien inconnu
        RETURN p_code IN (-28000, -1017, -2063, -2068, -3113, -3114, -3135, -3150,
                          -12514, -12541, -12170, -2019);
    END erreur_de_lien;


    -- Ferme le lien après une erreur, pour que l'appel suivant retente une connexion
    -- au lieu de réutiliser une session morte
    PROCEDURE fermer_lien (p_lien IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION CLOSE DATABASE LINK ' || p_lien;
    EXCEPTION
        WHEN OTHERS THEN NULL;   -- lien déjà fermé, ou transaction en cours
    END fermer_lien;


    -- Site d'une session, lu dans l'annuaire du siège (pas besoin que le site réponde)
    FUNCTION site_de_session (p_id_session IN NUMBER) RETURN NUMBER IS
        v_site NUMBER;
    BEGIN
        SELECT id_site INTO v_site FROM v_annuaire_session WHERE id_session = p_id_session;
        RETURN v_site;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20022, 'Session ' || p_id_session || ' inexistante (RG11)');
    END site_de_session;


    PROCEDURE verifier_etudiant (p_id_etudiant IN NUMBER) IS
        v_nb NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_nb FROM v_annuaire_etudiant WHERE id_etudiant = p_id_etudiant;
        IF v_nb = 0 THEN
            RAISE_APPLICATION_ERROR(-20023, 'Étudiant ' || p_id_etudiant || ' inexistant');
        END IF;
    END verifier_etudiant;


    -- Verrouille la session dans son site, vérifie la place et pose l'inscription.
    -- Même contrôle que pkg_parcours (L4), mais à travers le lien du site.
    PROCEDURE poser_inscription (
        p_id_inscription IN NUMBER, p_id_etudiant IN NUMBER, p_id_session IN NUMBER,
        p_id_site IN NUMBER, p_id_groupe IN VARCHAR2, p_nb_places IN NUMBER,
        p_date_operation IN DATE)
    IS
        v_lien      catalogue_site.nom_lien%TYPE := lien(p_id_site);
        v_capacite  NUMBER;
        v_prix      NUMBER;
        v_debut     DATE;
        v_occupees  NUMBER;
    BEGIN
        -- Verrou de la ligne de la session dans le site (correction de concurrence du L4)
        EXECUTE IMMEDIATE 'SELECT capacite, prix_unitaire, debut FROM session_cours@' || v_lien
            || ' WHERE id_session = :s FOR UPDATE'
            INTO v_capacite, v_prix, v_debut USING p_id_session;

        IF p_date_operation > v_debut THEN
            RAISE_APPLICATION_ERROR(-20024, 'Session ' || p_id_session
                || ' déjà commencée le ' || TO_CHAR(v_debut, 'DD/MM/YYYY') || ' (RG11)');
        END IF;

        EXECUTE IMMEDIATE 'SELECT NVL(SUM(nb_places), 0) FROM inscription@' || v_lien
            || ' WHERE id_session = :s AND statut = ''CONFIRMEE'''
            INTO v_occupees USING p_id_session;

        IF v_capacite - v_occupees < p_nb_places THEN
            RAISE_APPLICATION_ERROR(-20021, 'Session ' || p_id_session || ' : '
                || GREATEST(v_capacite - v_occupees, 0) || ' place(s) libre(s) sur '
                || v_capacite || ', ' || p_nb_places || ' demandée(s) (RG15)');
        END IF;

        EXECUTE IMMEDIATE 'INSERT INTO inscription@' || v_lien
            || ' (id_inscription, id_etudiant, id_session, id_groupe, date_operation,'
            || '  nb_places, montant, statut, id_site)'
            || ' VALUES (:i, :e, :s, :g, :d, :n, :m, ''CONFIRMEE'', :site)'
            USING p_id_inscription, p_id_etudiant, p_id_session, p_id_groupe,
                  p_date_operation, p_nb_places, p_nb_places * v_prix, p_id_site;
    END poser_inscription;


    PROCEDURE inscrire_parcours (
        p_id_etudiant     IN  NUMBER,
        p_sessions        IN  t_liste_sessions,
        p_nb_places       IN  NUMBER DEFAULT 1,
        p_date_operation  IN  DATE DEFAULT SYSDATE,
        p_id_groupe       OUT VARCHAR2)
    IS
        v_nb       NUMBER;
        v_distinct NUMBER;
        v_site     NUMBER;
        v_code     NUMBER;
        v_message  VARCHAR2(512);
    BEGIN
        SELECT COUNT(*), COUNT(DISTINCT column_value) INTO v_nb, v_distinct FROM TABLE(p_sessions);
        IF v_nb < 2 OR v_distinct < v_nb THEN
            RAISE_APPLICATION_ERROR(-20025,
                'Un parcours compte au moins 2 sessions différentes');
        END IF;
        verifier_etudiant(p_id_etudiant);

        SAVEPOINT avant_parcours_reparti;
        BEGIN
            p_id_groupe := 'G' || TO_CHAR(seq_groupe.NEXTVAL, 'FM00000');

            -- Ordre croissant des sessions : même ordre de verrouillage pour tous
            FOR s IN (SELECT column_value AS id_session FROM TABLE(p_sessions) ORDER BY 1) LOOP
                v_site := site_de_session(s.id_session);
                poser_inscription(seq_inscription.NEXTVAL, p_id_etudiant, s.id_session,
                                  v_site, p_id_groupe, p_nb_places, p_date_operation);
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN
                v_code    := SQLCODE;
                v_message := SQLERRM;
                -- Tout ou rien, sur tous les sites à la fois : le retour au point de
                -- sauvegarde défait aussi les lignes déjà posées dans les autres sites
                ROLLBACK TO SAVEPOINT avant_parcours_reparti;
                p_id_groupe := NULL;
                IF erreur_de_lien(v_code) THEN
                    fermer_lien(lien(v_site));
                    RAISE_APPLICATION_ERROR(-20020, 'Site ' || v_site
                        || ' injoignable : parcours refusé en entier, aucun site modifié ('
                        || v_message || ')');
                END IF;
                RAISE;
        END;
    END inscrire_parcours;


    PROCEDURE inscrire (
        p_id_etudiant     IN  NUMBER,
        p_id_session      IN  NUMBER,
        p_nb_places       IN  NUMBER DEFAULT 1,
        p_date_operation  IN  DATE DEFAULT SYSDATE,
        p_id_inscription  OUT NUMBER,
        p_etat            OUT VARCHAR2)
    IS
        v_site    NUMBER := site_de_session(p_id_session);
        v_message VARCHAR2(512);
    BEGIN
        verifier_etudiant(p_id_etudiant);
        p_id_inscription := seq_inscription.NEXTVAL;

        SAVEPOINT avant_inscription;
        BEGIN
            poser_inscription(p_id_inscription, p_id_etudiant, p_id_session, v_site,
                              NULL, p_nb_places, p_date_operation);
            p_etat := 'INSCRITE';
        EXCEPTION
            WHEN OTHERS THEN
                IF NOT erreur_de_lien(SQLCODE) THEN RAISE; END IF;
                v_message := SUBSTR(SQLERRM, 1, 200);
                -- Site en panne : on garde la demande au siège, avec le même numéro
                -- d'inscription, pour la rejouer à la reprise
                ROLLBACK TO SAVEPOINT avant_inscription;
                fermer_lien(lien(v_site));
                INSERT INTO operation_en_attente (id_site, id_inscription, id_etudiant,
                            id_session, nb_places, date_operation, motif)
                VALUES (v_site, p_id_inscription, p_id_etudiant, p_id_session,
                        p_nb_places, p_date_operation, v_message);
                p_etat := 'EN_ATTENTE';
        END;
    END inscrire;


    PROCEDURE rejouer_attente (p_id_site IN NUMBER) IS
        v_code    NUMBER;
        v_message VARCHAR2(200);
    BEGIN
        FOR a IN (SELECT * FROM operation_en_attente
                  WHERE  id_site = p_id_site AND etat = 'EN_ATTENTE'
                  ORDER BY id_attente) LOOP
            SAVEPOINT avant_rejeu;
            BEGIN
                poser_inscription(a.id_inscription, a.id_etudiant, a.id_session, a.id_site,
                                  NULL, a.nb_places, a.date_operation);
                UPDATE operation_en_attente SET etat = 'REJOUEE', motif = NULL
                WHERE  id_attente = a.id_attente;
            EXCEPTION
                WHEN OTHERS THEN
                    v_code    := SQLCODE;
                    v_message := SUBSTR(SQLERRM, 1, 200);
                    ROLLBACK TO SAVEPOINT avant_rejeu;
                    -- Site toujours en panne : on arrête, tout reste en attente
                    IF erreur_de_lien(v_code) THEN RAISE; END IF;
                    -- Sinon (session pleine entre-temps…) : refus tracé, pas de forçage
                    UPDATE operation_en_attente
                    SET    etat = 'REFUSEE', motif = v_message
                    WHERE  id_attente = a.id_attente;
            END;
        END LOOP;
    END rejouer_attente;


    PROCEDURE consulter_sessions (
        p_id_site      IN  NUMBER,
        p_a_partir_de  IN  DATE,
        p_nb_max       IN  NUMBER DEFAULT 5,
        p_source       OUT VARCHAR2)
    IS
        TYPE t_ligne IS RECORD (id_session NUMBER, libelle VARCHAR2(80 CHAR), debut DATE,
                                capacite NUMBER, prix_unitaire NUMBER);
        TYPE t_lignes IS TABLE OF t_ligne;
        v_lignes  t_lignes;
        v_lien    catalogue_site.nom_lien%TYPE := lien(p_id_site);
        v_code    NUMBER;
        v_message VARCHAR2(512);
    BEGIN
        -- 1. Le site principal. Toutes les lignes sont lues dans ce bloc (BULK COLLECT) :
        --    une coupure pendant la lecture fait aussi basculer. Le lien est écrit en SQL
        --    dynamique : la procédure reste valide pendant la panne (piège PLS-00905
        --    signalé au Lab 5).
        BEGIN
            EXECUTE IMMEDIATE 'SELECT id_session, libelle, debut, capacite, prix_unitaire'
                || ' FROM session_cours@' || v_lien
                || ' WHERE debut >= :d ORDER BY debut, id_session FETCH FIRST :n ROWS ONLY'
                BULK COLLECT INTO v_lignes USING p_a_partir_de, p_nb_max;
            p_source := 'SITE';
        EXCEPTION
            WHEN OTHERS THEN
                v_code    := SQLCODE;
                v_message := SQLERRM;
                IF NOT erreur_de_lien(v_code) THEN RAISE; END IF;
                fermer_lien(v_lien);
                DBMS_OUTPUT.PUT_LINE('Site ' || p_id_site || ' injoignable : '
                    || REPLACE(v_message, CHR(10), ' '));

                -- 2. Bascule sur la copie du siège
                SELECT id_session, libelle, debut, capacite, prix_unitaire
                BULK COLLECT INTO v_lignes
                FROM   session_replique
                WHERE  id_campus = p_id_site AND debut >= p_a_partir_de
                ORDER BY debut, id_session
                FETCH FIRST p_nb_max ROWS ONLY;

                IF v_lignes.COUNT = 0 THEN
                    RAISE_APPLICATION_ERROR(-20026, 'Site ' || p_id_site
                        || ' injoignable et sans copie au siège');
                END IF;
                DBMS_OUTPUT.PUT_LINE('Bascule sur la copie du siège (SESSION_REPLIQUE)');
                p_source := 'REPLIQUE';
        END;

        DBMS_OUTPUT.PUT_LINE('Sessions du site ' || p_id_site || ' lues dans : ' || p_source);
        FOR i IN 1 .. v_lignes.COUNT LOOP
            DBMS_OUTPUT.PUT_LINE('  session ' || v_lignes(i).id_session || ', '
                || TO_CHAR(v_lignes(i).debut, 'DD/MM/YYYY HH24:MI') || ', '
                || v_lignes(i).libelle || ', ' || v_lignes(i).capacite || ' places, '
                || TO_CHAR(v_lignes(i).prix_unitaire, 'FM99990.00') || ' EUR');
        END LOOP;
    END consulter_sessions;


    PROCEDURE synchroniser_replique (
        p_id_site        IN  NUMBER,
        p_vers_site      OUT NUMBER,
        p_vers_replique  OUT NUMBER)
    IS
        TYPE t_sessions IS TABLE OF session_replique%ROWTYPE;
        v_plus_recentes t_sessions;
        v_lien          catalogue_site.nom_lien%TYPE := lien(p_id_site);
        v_code          NUMBER;
        v_message       VARCHAR2(512);
    BEGIN
        -- 1. Sessions plus récentes dans la copie (modifiées au siège, par exemple pendant
        --    une panne) : on les recopie dans le site
        EXECUTE IMMEDIATE 'SELECT r.id_session, r.libelle, r.id_categorie, r.id_campus, r.debut,'
            || ' r.duree_minutes, r.capacite, r.prix_unitaire, r.derniere_maj'
            || ' FROM session_replique r JOIN session_cours@' || v_lien || ' s'
            || ' ON s.id_session = r.id_session'
            || ' WHERE r.id_campus = :site AND r.derniere_maj > s.derniere_maj'
            BULK COLLECT INTO v_plus_recentes USING p_id_site;

        FOR i IN 1 .. v_plus_recentes.COUNT LOOP
            EXECUTE IMMEDIATE 'UPDATE session_cours@' || v_lien
                || ' SET libelle = :l, id_categorie = :c, debut = :d, duree_minutes = :du,'
                || ' capacite = :ca, prix_unitaire = :p, derniere_maj = :m'
                || ' WHERE id_session = :id'
                USING v_plus_recentes(i).libelle, v_plus_recentes(i).id_categorie,
                      v_plus_recentes(i).debut, v_plus_recentes(i).duree_minutes,
                      v_plus_recentes(i).capacite, v_plus_recentes(i).prix_unitaire,
                      v_plus_recentes(i).derniere_maj, v_plus_recentes(i).id_session;
        END LOOP;
        p_vers_site := v_plus_recentes.COUNT;

        -- 2. Sessions plus récentes dans le site, ou nouvelles : on les recopie au siège.
        --    Les lignes recopiées à l'étape 1 ont maintenant la même date des deux côtés :
        --    elles ne bougent plus.
        EXECUTE IMMEDIATE 'MERGE INTO session_replique r'
            || ' USING (SELECT id_session, libelle, id_categorie, id_campus, debut,'
            || '               duree_minutes, capacite, prix_unitaire, derniere_maj'
            || '        FROM session_cours@' || v_lien || ') s'
            || ' ON (r.id_session = s.id_session)'
            || ' WHEN MATCHED THEN UPDATE SET r.libelle = s.libelle, r.id_categorie = s.id_categorie,'
            || '      r.debut = s.debut, r.duree_minutes = s.duree_minutes, r.capacite = s.capacite,'
            || '      r.prix_unitaire = s.prix_unitaire, r.derniere_maj = s.derniere_maj'
            || '      WHERE s.derniere_maj > r.derniere_maj'
            || ' WHEN NOT MATCHED THEN INSERT (id_session, libelle, id_categorie, id_campus, debut,'
            || '      duree_minutes, capacite, prix_unitaire, derniere_maj)'
            || '      VALUES (s.id_session, s.libelle, s.id_categorie, s.id_campus, s.debut,'
            || '      s.duree_minutes, s.capacite, s.prix_unitaire, s.derniere_maj)';
        p_vers_replique := SQL%ROWCOUNT;
    EXCEPTION
        WHEN OTHERS THEN
            v_code    := SQLCODE;
            v_message := SQLERRM;
            IF erreur_de_lien(v_code) THEN
                fermer_lien(v_lien);
                RAISE_APPLICATION_ERROR(-20020, 'Site ' || p_id_site
                    || ' injoignable : synchronisation impossible (' || v_message || ')');
            END IF;
            RAISE;
    END synchroniser_replique;

END pkg_reparti;
/


-- ---------------------------------------------------------------------
-- 7. Vérifications (résultats dans run_all.log et preuves/L6_distribution.txt)
-- ---------------------------------------------------------------------
SET LINESIZE 200
SET PAGESIZE 100
COLUMN ville FORMAT A10

-- 7.1 Taille de chaque fragment, lue directement dans chaque site
COLUMN table_globale FORMAT A18
SELECT 'ETUDIANT' AS table_globale,
       (SELECT COUNT(*) FROM etudiant@lien_bordeaux) AS bordeaux,
       (SELECT COUNT(*) FROM etudiant@lien_tours)    AS tours,
       (SELECT COUNT(*) FROM etudiant@lien_angers)   AS angers,
       (SELECT COUNT(*) FROM v_g_etudiant)           AS vue_globale,
       (SELECT COUNT(*) FROM etudiant)               AS centrale
FROM dual
UNION ALL
SELECT 'SESSION_COURS',
       (SELECT COUNT(*) FROM session_cours@lien_bordeaux),
       (SELECT COUNT(*) FROM session_cours@lien_tours),
       (SELECT COUNT(*) FROM session_cours@lien_angers),
       (SELECT COUNT(*) FROM v_g_session),
       (SELECT COUNT(*) FROM session_cours)
FROM dual
UNION ALL
SELECT 'INSCRIPTION',
       (SELECT COUNT(*) FROM inscription@lien_bordeaux),
       (SELECT COUNT(*) FROM inscription@lien_tours),
       (SELECT COUNT(*) FROM inscription@lien_angers),
       (SELECT COUNT(*) FROM v_g_inscription),
       (SELECT COUNT(*) FROM inscription)
FROM dual
UNION ALL
SELECT 'CATEGORIE (copie)',
       (SELECT COUNT(*) FROM categorie@lien_bordeaux),
       (SELECT COUNT(*) FROM categorie@lien_tours),
       (SELECT COUNT(*) FROM categorie@lien_angers),
       NULL,
       (SELECT COUNT(*) FROM categorie)
FROM dual;
-- Résultat attendu : ETUDIANT 4 646 / 9 820 / 7 005 = 21 471 ; SESSION_COURS 10 486 /
-- 21 963 / 15 170 = 47 619 ; INSCRIPTION 78 676 / 162 669 / 113 113 = 354 458 ;
-- CATEGORIE 6 dans chaque site

-- 7.2 Complétude et reconstruction : la vue globale redonne exactement la table
-- centrale, ligne pour ligne et colonne pour colonne (0 partout)
SELECT 'ETUDIANT' AS table_globale,
       (SELECT COUNT(*) FROM (SELECT * FROM etudiant MINUS SELECT * FROM v_g_etudiant)) AS manquantes,
       (SELECT COUNT(*) FROM (SELECT * FROM v_g_etudiant MINUS SELECT * FROM etudiant)) AS en_trop
FROM dual
UNION ALL
SELECT 'SESSION_COURS',
       (SELECT COUNT(*) FROM (SELECT id_session, libelle, id_categorie, id_campus, debut,
                                     duree_minutes, capacite, prix_unitaire FROM session_cours
                              MINUS SELECT * FROM v_g_session)),
       (SELECT COUNT(*) FROM (SELECT * FROM v_g_session
                              MINUS SELECT id_session, libelle, id_categorie, id_campus, debut,
                                           duree_minutes, capacite, prix_unitaire FROM session_cours))
FROM dual
UNION ALL
SELECT 'INSCRIPTION',
       (SELECT COUNT(*) FROM (SELECT id_inscription, id_etudiant, id_session, id_groupe,
                                     date_operation, nb_places, montant, statut, id_site
                              FROM inscription MINUS SELECT * FROM v_g_inscription)),
       (SELECT COUNT(*) FROM (SELECT * FROM v_g_inscription
                              MINUS SELECT id_inscription, id_etudiant, id_session, id_groupe,
                                           date_operation, nb_places, montant, statut, id_site
                                    FROM inscription))
FROM dual;
-- Résultat attendu : 0 et 0 pour les trois tables

-- 7.3 Disjonction : aucune ligne dans deux fragments (garantie aussi par les CHECK)
SELECT (SELECT COUNT(*) FROM (SELECT id_etudiant FROM v_g_etudiant
                              GROUP BY id_etudiant HAVING COUNT(*) > 1))    AS etudiants_doubles,
       (SELECT COUNT(*) FROM (SELECT id_session FROM v_g_session
                              GROUP BY id_session HAVING COUNT(*) > 1))     AS sessions_doubles,
       (SELECT COUNT(*) FROM (SELECT id_inscription FROM v_g_inscription
                              GROUP BY id_inscription HAVING COUNT(*) > 1)) AS inscriptions_doubles
FROM dual;
-- Résultat attendu : 0, 0, 0

-- 7.4 Contraintes qu'aucun site ne peut garantir seul, vérifiées à travers les liens.
-- Piège mesuré : écrite avec NOT EXISTS, la requête a pris 4 min 27 s, car Oracle
-- interrogeait le site distant une fois par inscription (boucle imbriquée à travers le
-- lien). Le hint USE_HASH fait venir chaque côté une seule fois, puis joint au siège :
-- 0,3 s pour le même résultat.
SELECT /*+ USE_HASH(i e) NO_MERGE(i) NO_MERGE(e) */
       COUNT(*)                                               AS inscriptions,
       SUM(CASE WHEN e.id_etudiant IS NULL THEN 1 ELSE 0 END) AS inscriptions_orphelines,
       SUM(CASE WHEN e.id_campus <> i.id_site THEN 1 ELSE 0 END) AS inscriptions_etudiant_distant
FROM      (SELECT id_etudiant, id_site   FROM v_g_inscription) i
LEFT JOIN (SELECT id_etudiant, id_campus FROM v_g_etudiant)    e ON e.id_etudiant = i.id_etudiant;
-- Résultat attendu : 354 458 inscriptions, 0 orpheline, 22 955 (6,5 %) dont l'étudiant
-- est stocké dans un autre site (le coût de la fragmentation d'ETUDIANT)

SELECT COUNT(*) AS emails_dans_2_sites
FROM  (SELECT email FROM v_g_etudiant WHERE email IS NOT NULL
       GROUP BY email HAVING COUNT(*) > 1);
-- Résultat attendu : 0 (RG4 tenue entre les sites)

-- 7.5 Valeurs de contrôle recalculées sur les fragments : mêmes valeurs qu'en central
-- C5 : chiffre d'affaires par site
SELECT i.id_site, SUM(i.montant) AS c5_chiffre_affaires
FROM   v_g_inscription i
WHERE  i.statut = 'CONFIRMEE'
GROUP BY i.id_site
ORDER BY i.id_site;
-- Résultat attendu : 2 -> 27 333 192 ; 3 -> 56 080 982 ; 4 -> 39 082 945

-- C6 : personnes ayant des opérations sur au moins deux sites (requête multi-sites)
SELECT COUNT(*) AS c6_personnes_multi_sites
FROM  (SELECT id_etudiant FROM v_g_inscription
       GROUP BY id_etudiant HAVING COUNT(DISTINCT id_site) >= 2);
-- Résultat attendu : 12 356

-- 7.6 Élimination des fragments inutiles : une requête sur Tours n'interroge que Tours.
-- Colonne Starts du plan : 1 pour la branche REMOTE de Tours, 0 pour les deux autres.
-- Le plan est retrouvé dans V$SQL par un marqueur (L6_LOCALISATION), comme au L5 : un
-- run_all précédent laisse d'anciennes versions de la requête, on prend la plus récente.
SELECT /*+ GATHER_PLAN_STATISTICS L6_LOCALISATION */ COUNT(*), SUM(montant)
FROM   v_g_inscription
WHERE  id_site = 3 AND statut = 'CONFIRMEE';

SELECT p.plan_table_output
FROM  (SELECT sql_id, child_number FROM v$sql
       WHERE  sql_text LIKE '%L6_LOCALISATION%' AND sql_text NOT LIKE '%v$sql%'
       ORDER BY last_active_time DESC FETCH FIRST 1 ROW ONLY) q,
       TABLE(DBMS_XPLAN.DISPLAY_CURSOR(q.sql_id, q.child_number, 'ALLSTATS LAST +REMOTE')) p;
-- Résultat attendu : les branches de Bordeaux et d'Angers passent sous un FILTER
-- « NULL IS NOT NULL » et ne sont jamais lancées (Starts = 0)

-- 7.7 Redondance : la copie du siège est identique au fragment d'Angers (dates comprises)
SELECT (SELECT COUNT(*) FROM session_replique) AS lignes_copie,
       (SELECT COUNT(*) FROM session_cours@lien_angers) AS lignes_angers,
       (SELECT COUNT(*) FROM (SELECT id_session, libelle, id_categorie, id_campus, debut,
                                     duree_minutes, capacite, prix_unitaire, derniere_maj
                              FROM session_cours@lien_angers
                              MINUS SELECT * FROM session_replique)) AS ecarts
FROM dual;
-- Résultat attendu : 15 170, 15 170, 0 écart

-- En temps normal, la consultation du catalogue lit le site lui-même (source SITE)
SET SERVEROUTPUT ON
DECLARE
    v_source VARCHAR2(10);
BEGIN
    pkg_reparti.consulter_sessions(4, DATE '2026-12-01', 3, v_source);
END;
/
