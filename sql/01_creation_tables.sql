-- =====================================================================
-- 01_creation_tables.sql
-- Livrable : L1 · Modèle
-- Rôle     : crée les 7 tables du modèle et 2 vues, avec toutes les contraintes nommées.
--            Modèle et règles de gestion (RG1 à RG16) : docs/L1_modele/L1_modele.md
--            Description colonne par colonne : docs/L1_modele/L1_schema_relationnel.md
-- Lancé par : sql/run_all.sql (après 00_nettoyage.sql)
--
-- Convention de nommage des contraintes :
--   pk_<table>             clé primaire
--   fk_<table>_<cible>     clé étrangère
--   uq_<table>_<colonnes>  unicité
--   ck_<table>_<règle>     vérification
--   nn_<table>_<colonne>   NOT NULL (nommée pour que le message d'erreur soit lisible)
--
-- Choix de types communs :
--   - VARCHAR2(n CHAR) : la longueur compte des caractères, pas des octets (« Siège »,
--     « Léo », « Zoé » prennent plus d'octets que de lettres en UTF-8).
--   - DATE pour toutes les dates : une DATE Oracle garde l'heure à la seconde près, ce qui
--     suffit (les CSV n'ont pas de fractions de seconde) et simplifie les calculs.
--   - Les index sur les clés étrangères ne sont pas créés ici : ils sont mesurés en L5.
-- =====================================================================


-- ---------------------------------------------------------------------
-- CAMPUS et son héritage SIEGE / SITE (RG1, RG2)
-- Une table par type. Le type est recopié dans chaque sous-table et la clé étrangère
-- composite (id_campus, type_campus) empêche de mettre un campus de type SIEGE dans SITE.
-- ---------------------------------------------------------------------
CREATE TABLE campus (
    id_campus    NUMBER(4)          CONSTRAINT nn_campus_id    NOT NULL,
    nom          VARCHAR2(60 CHAR)  CONSTRAINT nn_campus_nom   NOT NULL,
    ville        VARCHAR2(60 CHAR)  CONSTRAINT nn_campus_ville NOT NULL,
    type_campus  VARCHAR2(5 CHAR)   CONSTRAINT nn_campus_type  NOT NULL,
    CONSTRAINT pk_campus         PRIMARY KEY (id_campus),
    CONSTRAINT ck_campus_type    CHECK (type_campus IN ('SIEGE', 'SITE')),
    -- cible des clés étrangères composites des sous-tables
    CONSTRAINT uq_campus_id_type UNIQUE (id_campus, type_campus)
);

CREATE TABLE siege (
    id_campus    NUMBER(4)                        CONSTRAINT nn_siege_id   NOT NULL,
    type_campus  VARCHAR2(5 CHAR) DEFAULT 'SIEGE' CONSTRAINT nn_siege_type NOT NULL,
    CONSTRAINT pk_siege        PRIMARY KEY (id_campus),
    CONSTRAINT ck_siege_type   CHECK (type_campus = 'SIEGE'),
    -- RG2 : type_campus vaut toujours 'SIEGE', donc l'unicité interdit un deuxième siège
    CONSTRAINT uq_siege_unique UNIQUE (type_campus),
    CONSTRAINT fk_siege_campus FOREIGN KEY (id_campus, type_campus)
                               REFERENCES campus (id_campus, type_campus)
);

CREATE TABLE site (
    id_campus    NUMBER(4)                       CONSTRAINT nn_site_id    NOT NULL,
    type_campus  VARCHAR2(5 CHAR) DEFAULT 'SITE' CONSTRAINT nn_site_type  NOT NULL,
    id_siege     NUMBER(4)                       CONSTRAINT nn_site_siege NOT NULL,
    CONSTRAINT pk_site        PRIMARY KEY (id_campus),
    CONSTRAINT ck_site_type   CHECK (type_campus = 'SITE'),
    CONSTRAINT fk_site_campus FOREIGN KEY (id_campus, type_campus)
                              REFERENCES campus (id_campus, type_campus),
    -- RG2 : chaque site dépend du siège
    CONSTRAINT fk_site_siege  FOREIGN KEY (id_siege) REFERENCES siege (id_campus)
);


-- ---------------------------------------------------------------------
-- ETUDIANT (l'usager) et le parrainage réflexif (RG3 à RG7)
-- ---------------------------------------------------------------------
CREATE TABLE etudiant (
    id_etudiant       NUMBER(8)           CONSTRAINT nn_etudiant_id     NOT NULL,
    nom               VARCHAR2(80 CHAR)   CONSTRAINT nn_etudiant_nom    NOT NULL,
    prenom            VARCHAR2(80 CHAR)   CONSTRAINT nn_etudiant_prenom NOT NULL,
    email             VARCHAR2(254 CHAR),                   -- RG5 : facultatif
    telephone         VARCHAR2(10 CHAR),                    -- texte : garde le 0 initial
    ville             VARCHAR2(60 CHAR),
    id_campus         NUMBER(4)           CONSTRAINT nn_etudiant_campus NOT NULL,
    date_inscription  DATE                CONSTRAINT nn_etudiant_date   NOT NULL,  -- création du compte
    id_parrain        NUMBER(8),                            -- RG7 : au plus un parrain
    CONSTRAINT pk_etudiant          PRIMARY KEY (id_etudiant),
    -- RG4 : une personne = un e-mail normalisé. Oracle n'indexe pas les NULL, donc
    -- plusieurs étudiants sans e-mail restent possibles (RG5).
    CONSTRAINT uq_etudiant_email    UNIQUE (email),
    CONSTRAINT ck_etudiant_email_norm CHECK (
        email IS NULL
        OR (email = LOWER(REPLACE(email, ' ', '')) AND INSTR(email, '@') > 1)),
    -- RG6
    CONSTRAINT ck_etudiant_telephone CHECK (
        telephone IS NULL OR REGEXP_LIKE(telephone, '^0[0-9]{9}$')),
    -- RG3 : la clé pointe vers SITE, pas vers CAMPUS : le siège ne peut pas avoir d'étudiants
    CONSTRAINT fk_etudiant_site     FOREIGN KEY (id_campus) REFERENCES site (id_campus),
    -- RG7 : association réflexive
    CONSTRAINT fk_etudiant_parrain  FOREIGN KEY (id_parrain) REFERENCES etudiant (id_etudiant),
    CONSTRAINT ck_etudiant_pas_son_parrain CHECK (id_parrain IS NULL OR id_parrain <> id_etudiant)
);


-- ---------------------------------------------------------------------
-- CATEGORIE (la langue enseignée) et SESSION_COURS (la ressource datée) (RG8)
-- SESSION est un mot réservé d'Oracle, d'où le nom SESSION_COURS.
-- ---------------------------------------------------------------------
CREATE TABLE categorie (
    id_categorie  NUMBER(4) GENERATED BY DEFAULT AS IDENTITY CONSTRAINT nn_categorie_id NOT NULL,
    libelle       VARCHAR2(40 CHAR)  CONSTRAINT nn_categorie_libelle NOT NULL,
    CONSTRAINT pk_categorie          PRIMARY KEY (id_categorie),
    CONSTRAINT uq_categorie_libelle  UNIQUE (libelle),
    CONSTRAINT ck_categorie_libelle_net CHECK (libelle = TRIM(libelle))
);

CREATE TABLE session_cours (
    id_session     NUMBER(8)          CONSTRAINT nn_session_id        NOT NULL,
    libelle        VARCHAR2(80 CHAR)  CONSTRAINT nn_session_libelle   NOT NULL,
    id_categorie   NUMBER(4)          CONSTRAINT nn_session_categorie NOT NULL,
    id_campus      NUMBER(4)          CONSTRAINT nn_session_campus    NOT NULL,
    debut          DATE               CONSTRAINT nn_session_debut     NOT NULL,
    duree_minutes  NUMBER(3)          CONSTRAINT nn_session_duree     NOT NULL,
    capacite       NUMBER(3)          CONSTRAINT nn_session_capacite  NOT NULL,
    prix_unitaire  NUMBER(7,2)        CONSTRAINT nn_session_prix      NOT NULL,
    CONSTRAINT pk_session            PRIMARY KEY (id_session),
    CONSTRAINT fk_session_categorie  FOREIGN KEY (id_categorie) REFERENCES categorie (id_categorie),
    -- RG3 : une session se tient dans un site, jamais au siège
    CONSTRAINT fk_session_site       FOREIGN KEY (id_campus) REFERENCES site (id_campus),
    CONSTRAINT ck_session_duree      CHECK (duree_minutes IN (45, 60, 90, 120)),
    CONSTRAINT ck_session_capacite   CHECK (capacite > 0),
    CONSTRAINT ck_session_prix       CHECK (prix_unitaire >= 0)
);


-- ---------------------------------------------------------------------
-- INSCRIPTION : association porteuse entre ETUDIANT et SESSION_COURS (RG9, RG11, RG16)
-- Identifiant propre (id_inscription) : un étudiant peut avoir plusieurs inscriptions
-- à la même session (annulation puis réinscription) et l'audit (L4) vise une ligne précise.
-- Les règles qui portent sur plusieurs lignes ou plusieurs tables (RG7 date du parrain,
-- RG12 montant, RG13 doublon confirmé, RG14 date du compte, RG15 capacité, RG16 tout ou
-- rien) ne s'écrivent pas en CHECK : elles sont traitées par les triggers et le package (L4).
-- ---------------------------------------------------------------------
CREATE TABLE inscription (
    id_inscription  NUMBER(10)        CONSTRAINT nn_inscription_id       NOT NULL,
    id_etudiant     NUMBER(8)         CONSTRAINT nn_inscription_etudiant NOT NULL,
    id_session      NUMBER(8)         CONSTRAINT nn_inscription_session  NOT NULL,
    id_groupe       VARCHAR2(10 CHAR),                      -- opération groupée, sinon NULL
    date_operation  DATE              CONSTRAINT nn_inscription_date     NOT NULL,
    nb_places       NUMBER(3)         CONSTRAINT nn_inscription_places   NOT NULL,
    montant         NUMBER(9,2)       CONSTRAINT nn_inscription_montant  NOT NULL,
    statut          VARCHAR2(10 CHAR) CONSTRAINT nn_inscription_statut   NOT NULL,
    CONSTRAINT pk_inscription          PRIMARY KEY (id_inscription),
    CONSTRAINT fk_inscription_etudiant FOREIGN KEY (id_etudiant) REFERENCES etudiant (id_etudiant),
    -- RG11 : la session doit exister
    CONSTRAINT fk_inscription_session  FOREIGN KEY (id_session) REFERENCES session_cours (id_session),
    -- RG9
    CONSTRAINT ck_inscription_places   CHECK (nb_places >= 1),
    CONSTRAINT ck_inscription_statut   CHECK (statut IN ('CONFIRMEE', 'ANNULEE')),
    -- RG9 et RG11 : un montant négatif est refusé
    CONSTRAINT ck_inscription_montant  CHECK (montant >= 0),
    -- RG16 : format G + 5 chiffres (ex. G00042)
    CONSTRAINT ck_inscription_groupe   CHECK (id_groupe IS NULL OR REGEXP_LIKE(id_groupe, '^G[0-9]{5}$'))
);


-- ---------------------------------------------------------------------
-- Vues de règles de gestion
-- ---------------------------------------------------------------------

-- RG10 : le site d'une opération est celui de sa session (on ne le stocke pas en double
-- dans INSCRIPTION, il se déduit par jointure).
CREATE OR REPLACE VIEW v_inscription_site AS
SELECT i.id_inscription, i.id_etudiant, i.id_session, i.id_groupe, i.date_operation,
       i.nb_places, i.montant, i.statut,
       s.id_campus AS id_site
FROM   inscription i
JOIN   session_cours s ON s.id_session = i.id_session;

-- RG15 : places confirmées par session, comparées à la capacité
CREATE OR REPLACE VIEW v_session_occupation AS
SELECT s.id_session, s.libelle, s.id_campus AS id_site, s.capacite,
       NVL(SUM(CASE WHEN i.statut = 'CONFIRMEE' THEN i.nb_places END), 0) AS places_confirmees,
       CASE WHEN NVL(SUM(CASE WHEN i.statut = 'CONFIRMEE' THEN i.nb_places END), 0) > s.capacite
            THEN 'O' ELSE 'N' END AS sur_reservee
FROM   session_cours s
LEFT JOIN inscription i ON i.id_session = s.id_session
GROUP BY s.id_session, s.libelle, s.id_campus, s.capacite;


-- ---------------------------------------------------------------------
-- Commentaires stockés dans le dictionnaire (visibles dans SQL Developer, onglet Détails)
-- ---------------------------------------------------------------------
COMMENT ON TABLE campus        IS 'Siège ou site de l''école (RG1). Le type est détaillé dans SIEGE ou SITE.';
COMMENT ON TABLE siege         IS 'Sous-type de CAMPUS : un seul siège (RG2).';
COMMENT ON TABLE site          IS 'Sous-type de CAMPUS : Bordeaux, Tours, Angers. Porte les étudiants et les sessions (RG3).';
COMMENT ON TABLE etudiant      IS 'Usager. Une personne = un e-mail normalisé (RG4, RG5).';
COMMENT ON TABLE categorie     IS 'Langue enseignée (FLE, anglais, espagnol, allemand, italien, chinois).';
COMMENT ON TABLE session_cours IS 'Ressource datée : une session de cours dans un site (RG8).';
COMMENT ON TABLE inscription   IS 'Opération : un étudiant réserve des places à une session (association porteuse, RG9).';

COMMENT ON COLUMN etudiant.date_inscription  IS 'Date de création du compte (RG14), à ne pas confondre avec INSCRIPTION.date_operation.';
COMMENT ON COLUMN etudiant.id_parrain        IS 'Parrain (association réflexive, RG7). Absent des CSV : colonne ajoutée, vide au départ.';
COMMENT ON COLUMN inscription.date_operation IS 'Date de l''inscription (colonne date_inscription de inscriptions.csv).';
COMMENT ON COLUMN inscription.montant        IS 'nb_places x prix_unitaire, même pour une annulation (RG12).';
COMMENT ON COLUMN inscription.id_groupe      IS 'Opération groupée (parcours) passée en une fois, tout ou rien (RG16).';
