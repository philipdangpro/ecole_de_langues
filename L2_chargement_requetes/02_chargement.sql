-- =====================================================================
-- 02_chargement.sql
-- Livrable : L2 · Chargement
-- Attendu  : chargement des 4 CSV de data/ avec traitement des défauts (correction, rejet tracé, signalement)
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Prérequis : sql/installation_system.sql a été lancé une fois (DIRECTORY dir_donnees_langues
-- qui pointe vers les CSV copiés dans le conteneur, voir README).
--
-- Méthode : chaque CSV est lu par une TABLE EXTERNE (le fichier reste sur le disque, Oracle le
-- lit comme une table), puis copié dans les tables du L1 par INSERT ... SELECT.
--
-- Défauts traités ici (seulement ceux qui empêcheraient le chargement) :
--   1. 73 étudiants en double (même e-mail une fois normalisé) : on garde l'original (le plus
--      petit id), la copie est tracée dans ETUDIANT_DOUBLON, ses inscriptions sont rattachées
--      à l'original.
--   2. 397 inscriptions non valides au sens du sujet (session inexistante, montant négatif,
--      date après le début de la session) : non chargées, tracées dans INSCRIPTION_REJET
--      avec leur motif.
-- Les autres défauts (doubles confirmations, inscriptions avant la création du compte,
-- sessions sur-réservées) ne rendent pas une opération non valide : ces lignes sont chargées
-- telles quelles et seront empêchées pour les nouvelles opérations en L4.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tables externes : une par CSV, toutes les colonnes lues en texte
--    (la conversion en nombre ou en date se fait à l'insertion, avec un format explicite).
--    DETECTED NEWLINE : accepte les fins de ligne Windows (CRLF) comme Unix (LF).
--    NOLOGFILE / NOBADFILE : Oracle n'a pas le droit d'écrire dans le dossier des CSV.
--    NOTRIM (étudiants seulement) : garde les espaces autour des e-mails, pour tracer le défaut
--    tel qu'il était dans le CSV.
-- ---------------------------------------------------------------------
CREATE TABLE ext_campus (
    id_campus VARCHAR2(20), nom VARCHAR2(100), ville VARCHAR2(100), role VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER DEFAULT DIRECTORY dir_donnees_langues
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY DETECTED NEWLINE CHARACTERSET AL32UTF8 SKIP 1
        NOLOGFILE NOBADFILE NODISCARDFILE
        FIELDS TERMINATED BY ',' MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('campus.csv')
) REJECT LIMIT 0;

CREATE TABLE ext_etudiants (
    id_etudiant VARCHAR2(20), nom VARCHAR2(100), prenom VARCHAR2(100), email VARCHAR2(300),
    telephone VARCHAR2(30), ville VARCHAR2(100), id_campus VARCHAR2(20), date_inscription VARCHAR2(30)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER DEFAULT DIRECTORY dir_donnees_langues
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY DETECTED NEWLINE CHARACTERSET AL32UTF8 SKIP 1
        NOLOGFILE NOBADFILE NODISCARDFILE
        FIELDS TERMINATED BY ',' NOTRIM MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('etudiants.csv')
) REJECT LIMIT 0;

CREATE TABLE ext_sessions (
    id_session VARCHAR2(20), libelle VARCHAR2(100), categorie VARCHAR2(50), id_campus VARCHAR2(20),
    debut VARCHAR2(30), duree_minutes VARCHAR2(20), capacite VARCHAR2(20), prix_unitaire VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER DEFAULT DIRECTORY dir_donnees_langues
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY DETECTED NEWLINE CHARACTERSET AL32UTF8 SKIP 1
        NOLOGFILE NOBADFILE NODISCARDFILE
        FIELDS TERMINATED BY ',' MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('sessions.csv')
) REJECT LIMIT 0;

CREATE TABLE ext_inscriptions (
    id_inscription VARCHAR2(20), id_etudiant VARCHAR2(20), id_session VARCHAR2(20),
    date_inscription VARCHAR2(30), nb_places VARCHAR2(20), montant VARCHAR2(20),
    statut VARCHAR2(20), id_groupe VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER DEFAULT DIRECTORY dir_donnees_langues
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY DETECTED NEWLINE CHARACTERSET AL32UTF8 SKIP 1
        NOLOGFILE NOBADFILE NODISCARDFILE
        FIELDS TERMINATED BY ',' MISSING FIELD VALUES ARE NULL
    )
    LOCATION ('inscriptions.csv')
) REJECT LIMIT 0;


-- ---------------------------------------------------------------------
-- 2. Tables de traçabilité des défauts
-- ---------------------------------------------------------------------

-- Étudiants en double : la copie n'est pas chargée dans ETUDIANT
CREATE TABLE etudiant_doublon (
    id_copie      NUMBER(8)          CONSTRAINT nn_doublon_copie    NOT NULL,
    id_original   NUMBER(8)          CONSTRAINT nn_doublon_original NOT NULL,
    email_source  VARCHAR2(254 CHAR),                     -- e-mail tel qu'il était dans le CSV
    CONSTRAINT pk_etudiant_doublon   PRIMARY KEY (id_copie),
    CONSTRAINT fk_doublon_original   FOREIGN KEY (id_original) REFERENCES etudiant (id_etudiant),
    CONSTRAINT ck_doublon_different  CHECK (id_copie <> id_original)
);

-- Inscriptions non valides : gardées telles qu'elles étaient dans le CSV, avec le motif
CREATE TABLE inscription_rejet (
    id_inscription  NUMBER(10)         CONSTRAINT nn_rejet_id    NOT NULL,
    id_etudiant     NUMBER(8),
    id_session      NUMBER(8),
    date_operation  DATE,
    nb_places       NUMBER(3),
    montant         NUMBER(9,2),
    statut          VARCHAR2(10 CHAR),
    id_groupe       VARCHAR2(10 CHAR),
    motif           VARCHAR2(30 CHAR)  CONSTRAINT nn_rejet_motif NOT NULL,
    CONSTRAINT pk_inscription_rejet PRIMARY KEY (id_inscription),
    CONSTRAINT ck_rejet_motif CHECK (motif IN ('SESSION_INEXISTANTE', 'MONTANT_NEGATIF',
                                               'DATE_APRES_DEBUT'))
);


-- ---------------------------------------------------------------------
-- 3. Campus, siège, sites
--    Le CSV écrit le rôle « siège » / « site » ; on le traduit en SIEGE / SITE.
--    (LIKE 'si_ge' évite d'écrire un accent dans le script.)
-- ---------------------------------------------------------------------
INSERT INTO campus (id_campus, nom, ville, type_campus)
SELECT TO_NUMBER(id_campus), TRIM(nom), TRIM(ville),
       CASE WHEN LOWER(TRIM(role)) = 'site'      THEN 'SITE'
            WHEN LOWER(TRIM(role)) LIKE 'si_ge'  THEN 'SIEGE'
       END                                     -- autre valeur : NULL, refusée par nn_campus_type
FROM   ext_campus;

INSERT INTO siege (id_campus)
SELECT id_campus FROM campus WHERE type_campus = 'SIEGE';

INSERT INTO site (id_campus, id_siege)
SELECT c.id_campus, s.id_campus
FROM   campus c CROSS JOIN siege s
WHERE  c.type_campus = 'SITE';


-- ---------------------------------------------------------------------
-- 4. Étudiants
--    E-mail normalisé : minuscules, sans espaces ; vide -> NULL.
--    Pour chaque e-mail normalisé, l'original est le plus petit id ; les autres sont des copies.
-- ---------------------------------------------------------------------
INSERT INTO etudiant (id_etudiant, nom, prenom, email, telephone, ville, id_campus, date_inscription)
SELECT id_etudiant, nom, prenom, email_norm, telephone, ville, id_campus, date_inscription
FROM (
    SELECT TO_NUMBER(id_etudiant)                         AS id_etudiant,
           TRIM(nom)                                      AS nom,
           TRIM(prenom)                                   AS prenom,
           LOWER(REPLACE(email, ' ', ''))                 AS email_norm,
           TRIM(telephone)                                AS telephone,
           TRIM(ville)                                    AS ville,
           TO_NUMBER(id_campus)                           AS id_campus,
           TO_DATE(TRIM(date_inscription), 'YYYY-MM-DD')  AS date_inscription,
           -- rang dans le groupe des étudiants qui ont le même e-mail normalisé
           CASE WHEN LOWER(REPLACE(email, ' ', '')) IS NULL THEN 1
                ELSE ROW_NUMBER() OVER (PARTITION BY LOWER(REPLACE(email, ' ', ''))
                                        ORDER BY TO_NUMBER(id_etudiant))
           END                                            AS rang
    FROM   ext_etudiants
)
WHERE rang = 1;

INSERT INTO etudiant_doublon (id_copie, id_original, email_source)
SELECT TO_NUMBER(x.id_etudiant), e.id_etudiant, x.email
FROM   ext_etudiants x
JOIN   etudiant e ON e.email = LOWER(REPLACE(x.email, ' ', ''))
WHERE  TO_NUMBER(x.id_etudiant) <> e.id_etudiant;


-- ---------------------------------------------------------------------
-- 5. Catégories et sessions
-- ---------------------------------------------------------------------
INSERT INTO categorie (libelle)
SELECT DISTINCT TRIM(categorie) FROM ext_sessions ORDER BY 1;

INSERT INTO session_cours (id_session, libelle, id_categorie, id_campus, debut,
                           duree_minutes, capacite, prix_unitaire)
SELECT TO_NUMBER(s.id_session), TRIM(s.libelle), c.id_categorie, TO_NUMBER(s.id_campus),
       TO_DATE(TRIM(s.debut), 'YYYY-MM-DD HH24:MI:SS'),
       TO_NUMBER(s.duree_minutes), TO_NUMBER(s.capacite),
       TO_NUMBER(s.prix_unitaire, '999999D99', 'NLS_NUMERIC_CHARACTERS=''.,''')
FROM   ext_sessions s
JOIN   categorie c ON c.libelle = TRIM(s.categorie);


-- ---------------------------------------------------------------------
-- 6. Inscriptions
--    On prépare chaque ligne une seule fois (vue en ligne « src ») : conversion des types,
--    rattachement des copies d'étudiants à l'original, calcul du motif de rejet.
--    Le format numérique est imposé (point décimal) : SQL Developer en français utiliserait
--    sinon la virgule et TO_NUMBER('309.00') échouerait.
-- ---------------------------------------------------------------------
INSERT ALL
    WHEN motif IS NULL THEN
        INTO inscription (id_inscription, id_etudiant, id_session, id_groupe, date_operation,
                          nb_places, montant, statut)
        VALUES (id_inscription, id_etudiant, id_session, id_groupe, date_operation,
                nb_places, montant, statut)
    ELSE
        INTO inscription_rejet (id_inscription, id_etudiant, id_session, date_operation,
                                nb_places, montant, statut, id_groupe, motif)
        VALUES (id_inscription, id_etudiant, id_session, date_operation,
                nb_places, montant, statut, id_groupe, motif)
SELECT i.id_inscription, NVL(d.id_original, i.id_etudiant) AS id_etudiant, i.id_session,
       i.id_groupe, i.date_operation, i.nb_places, i.montant, i.statut,
       CASE WHEN s.id_session IS NULL       THEN 'SESSION_INEXISTANTE'
            WHEN i.montant < 0              THEN 'MONTANT_NEGATIF'
            WHEN i.date_operation > s.debut THEN 'DATE_APRES_DEBUT'
       END AS motif
FROM (
    SELECT TO_NUMBER(id_inscription)                               AS id_inscription,
           TO_NUMBER(id_etudiant)                                  AS id_etudiant,
           TO_NUMBER(id_session)                                   AS id_session,
           TRIM(id_groupe)                                         AS id_groupe,  -- vide -> NULL
           TO_DATE(TRIM(date_inscription), 'YYYY-MM-DD HH24:MI:SS') AS date_operation,
           TO_NUMBER(nb_places)                                    AS nb_places,
           TO_NUMBER(montant, '999999D99', 'NLS_NUMERIC_CHARACTERS=''.,''') AS montant,
           TRIM(statut)                                            AS statut
    FROM   ext_inscriptions
) i
LEFT JOIN session_cours    s ON s.id_session = i.id_session
LEFT JOIN etudiant_doublon d ON d.id_copie   = i.id_etudiant;

COMMIT;


-- ---------------------------------------------------------------------
-- 7. Bilan du chargement (à recopier dans le rapport)
-- ---------------------------------------------------------------------
SELECT 'campus'            AS objet, COUNT(*) AS nb FROM campus
UNION ALL SELECT 'sites',              COUNT(*) FROM site
UNION ALL SELECT 'etudiants (csv)',    COUNT(*) FROM ext_etudiants
UNION ALL SELECT 'etudiants charges',  COUNT(*) FROM etudiant
UNION ALL SELECT 'etudiants doublons', COUNT(*) FROM etudiant_doublon
UNION ALL SELECT 'categories',         COUNT(*) FROM categorie
UNION ALL SELECT 'sessions',           COUNT(*) FROM session_cours
UNION ALL SELECT 'inscriptions (csv)', COUNT(*) FROM ext_inscriptions
UNION ALL SELECT 'inscriptions chargees', COUNT(*) FROM inscription
UNION ALL SELECT 'inscriptions rejetees', COUNT(*) FROM inscription_rejet;

COLUMN motif FORMAT A20
SELECT motif, COUNT(*) AS nb FROM inscription_rejet GROUP BY motif ORDER BY motif;
