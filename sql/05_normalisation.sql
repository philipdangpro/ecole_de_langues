-- =====================================================================
-- 05_normalisation.sql
-- Livrable : L3 · Normalisation
-- Responsable : Younes (analyse de départ, en Python), Baptiste (reprise en SQL)
-- Attendu  : table des opérations à plat + dépendances fonctionnelles + décomposition
--            + dénormalisation assumée. Explications : docs/L3_normalisation/L3_normalisation.md
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Plan :
--   1. OPERATION_A_PLAT : une ligne par opération du CSV, avec son étudiant, sa session et
--      les deux campus (celui de l'étudiant, celui de la session). Construite depuis les
--      CSV bruts (tables externes du L2), donc AVANT tout nettoyage.
--   2. Dépendances fonctionnelles (DF) vérifiées sur cette table, une requête par DF.
--   3. Décomposition : on projette la table à plat en 4 relations, on les rejoint, et on
--      vérifie qu'on retrouve exactement la table à plat (décomposition sans perte).
--   4. Dénormalisation assumée : le site de la session est recopié dans INSCRIPTION
--      (colonne id_site), tenu cohérent par une clé étrangère composite et un trigger.
--
-- Lit les tables externes EXT_* et les tables du L1/L2 : à lancer après 02_chargement.sql.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Table des opérations à plat
--    Mêmes conversions qu'en 02_chargement.sql (format explicite, point décimal imposé).
--    LEFT JOIN : les 220 opérations dont la session n'existe pas sont gardées, avec des
--    colonnes de session vides. Rien n'est corrigé : l'e-mail est gardé tel qu'il est
--    dans le CSV (majuscules, espaces), les copies d'étudiants gardent leur propre id.
--    Le téléphone reste du texte : il garde son 0 initial.
-- ---------------------------------------------------------------------
CREATE TABLE operation_a_plat AS
WITH ins AS (
    SELECT TO_NUMBER(id_inscription)                                 AS id_inscription,
           TO_NUMBER(id_etudiant)                                    AS id_etudiant,
           TO_NUMBER(id_session)                                     AS id_session,
           TRIM(id_groupe)                                           AS id_groupe,
           TO_DATE(TRIM(date_inscription), 'YYYY-MM-DD HH24:MI:SS')  AS date_operation,
           TO_NUMBER(nb_places)                                      AS nb_places,
           TO_NUMBER(montant, '999999D99', 'NLS_NUMERIC_CHARACTERS=''.,''') AS montant,
           TRIM(statut)                                              AS statut
    FROM   ext_inscriptions
), etu AS (
    SELECT TO_NUMBER(id_etudiant)                         AS id_etudiant,
           TRIM(nom)                                      AS nom,
           TRIM(prenom)                                   AS prenom,
           email,                                         -- brut, tel que dans le CSV
           TRIM(telephone)                                AS telephone,
           TRIM(ville)                                    AS ville,
           TO_NUMBER(id_campus)                           AS id_campus,
           TO_DATE(TRIM(date_inscription), 'YYYY-MM-DD')  AS date_creation_compte
    FROM   ext_etudiants
), ses AS (
    SELECT TO_NUMBER(id_session)                               AS id_session,
           TRIM(libelle)                                       AS libelle,
           TRIM(categorie)                                     AS categorie,
           TO_NUMBER(id_campus)                                AS id_campus,
           TO_DATE(TRIM(debut), 'YYYY-MM-DD HH24:MI:SS')       AS debut,
           TO_NUMBER(duree_minutes)                            AS duree_minutes,
           TO_NUMBER(capacite)                                 AS capacite,
           TO_NUMBER(prix_unitaire, '999999D99', 'NLS_NUMERIC_CHARACTERS=''.,''') AS prix_unitaire
    FROM   ext_sessions
), cam AS (
    SELECT TO_NUMBER(id_campus) AS id_campus, TRIM(nom) AS nom, TRIM(ville) AS ville,
           TRIM(role) AS role
    FROM   ext_campus
)
SELECT -- l'opération
       i.id_inscription, i.id_etudiant, i.id_session, i.id_groupe, i.date_operation,
       i.nb_places, i.montant, i.statut,
       -- l'usager
       e.nom, e.prenom, e.email, e.telephone, e.ville,
       e.id_campus  AS id_campus_etudiant, e.date_creation_compte,
       ce.nom       AS nom_campus_etudiant, ce.ville AS ville_campus_etudiant,
       ce.role      AS role_campus_etudiant,
       -- la ressource
       s.libelle    AS libelle_session, s.categorie, s.id_campus AS id_campus_session,
       s.debut, s.duree_minutes, s.capacite, s.prix_unitaire,
       cs.nom       AS nom_campus_session, cs.ville AS ville_campus_session,
       cs.role      AS role_campus_session
FROM   ins i
LEFT JOIN etu e  ON e.id_etudiant  = i.id_etudiant
LEFT JOIN cam ce ON ce.id_campus   = e.id_campus
LEFT JOIN ses s  ON s.id_session   = i.id_session
LEFT JOIN cam cs ON cs.id_campus   = s.id_campus;

-- La clé de la table à plat est id_inscription (la contrainte le prouve : elle serait
-- refusée s'il y avait un doublon).
ALTER TABLE operation_a_plat ADD CONSTRAINT pk_operation_a_plat PRIMARY KEY (id_inscription);

COMMENT ON TABLE operation_a_plat IS 'L3 : opérations du CSV à plat (inscription + étudiant + session + campus), avant nettoyage. Sert à vérifier les DF.';

SELECT COUNT(*) AS lignes_a_plat FROM operation_a_plat;
-- Résultat : 354 855 lignes, 28 colonnes


-- ---------------------------------------------------------------------
-- 2. Dépendances fonctionnelles
--    Méthode : X -> Y tient si chaque valeur de X n'apparaît qu'avec une seule valeur de Y.
--    On prend les couples (X, Y) distincts, on regroupe par X, et on compte les X qui ont
--    plus d'un Y. Ce nombre est la colonne « violations » : 0 = la DF tient sur les données.
--    (SELECT DISTINCT traite deux NULL comme égaux, contrairement à COUNT(DISTINCT) :
--    une valeur vide face à une valeur remplie compte bien comme une violation.)
--    Une DF qui tient sur les données n'est retenue que si une règle métier la justifie.
-- ---------------------------------------------------------------------
COLUMN n          FORMAT A3
COLUMN dependance FORMAT A75
COLUMN conclusion FORMAT A60

-- 2a. Dépendances retenues, et celles que les défauts du CSV violent
SELECT 'D1' AS n, 'id_inscription -> toutes les colonnes' AS dependance,
       COUNT(*) AS violations, 'tient : clé de la table à plat' AS conclusion
FROM  (SELECT id_inscription FROM operation_a_plat GROUP BY id_inscription HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D2', 'id_etudiant -> nom, prenom, email, telephone, ville, id_campus_etudiant, date_creation_compte',
       COUNT(*), 'tient : relation ETUDIANT'
FROM  (SELECT id_etudiant
       FROM  (SELECT DISTINCT id_etudiant, nom, prenom, email, telephone, ville,
                              id_campus_etudiant, date_creation_compte FROM operation_a_plat)
       GROUP BY id_etudiant HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D3', 'id_session -> libelle, categorie, id_campus_session, debut, duree, capacite, prix',
       COUNT(*), 'tient : relation SESSION'
FROM  (SELECT id_session
       FROM  (SELECT DISTINCT id_session, libelle_session, categorie, id_campus_session, debut,
                              duree_minutes, capacite, prix_unitaire FROM operation_a_plat)
       GROUP BY id_session HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D4', 'id_campus -> nom, ville, role (campus de l''étudiant et de la session)',
       COUNT(*), 'tient : relation CAMPUS (une seule pour les deux rôles)'
FROM  (SELECT id_campus
       FROM  (SELECT id_campus_etudiant AS id_campus, nom_campus_etudiant AS nom,
                     ville_campus_etudiant AS ville, role_campus_etudiant AS role
              FROM operation_a_plat
              UNION                                   -- UNION enlève déjà les doublons
              SELECT id_campus_session, nom_campus_session, ville_campus_session, role_campus_session
              FROM operation_a_plat WHERE id_campus_session IS NOT NULL)
       GROUP BY id_campus HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D5', 'libelle_session -> id_session',
       COUNT(*), 'tient : le libellé est une 2e clé de SESSION'
FROM  (SELECT libelle_session
       FROM  (SELECT DISTINCT libelle_session, id_session FROM operation_a_plat
              WHERE libelle_session IS NOT NULL)
       GROUP BY libelle_session HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D6', 'email normalisé (minuscules, sans espaces) -> id_etudiant',
       COUNT(*), 'violée par les 73 copies : fusion au L2 (RG4)'
FROM  (SELECT LOWER(REPLACE(email, ' ', ''))
       FROM  (SELECT DISTINCT email, id_etudiant FROM operation_a_plat WHERE email IS NOT NULL)
       GROUP BY LOWER(REPLACE(email, ' ', '')) HAVING COUNT(DISTINCT id_etudiant) > 1)
UNION ALL
SELECT 'D7', 'id_session, nb_places -> montant',
       COUNT(*), 'violée par des opérations non valides (rejetées au L2)'
FROM  (SELECT id_session, nb_places
       FROM  (SELECT DISTINCT id_session, nb_places, montant FROM operation_a_plat)
       GROUP BY id_session, nb_places HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D8', 'id_groupe -> id_etudiant',
       COUNT(*), 'violée par des copies d''étudiants : tient après fusion'
FROM  (SELECT id_groupe
       FROM  (SELECT DISTINCT id_groupe, id_etudiant FROM operation_a_plat
              WHERE id_groupe IS NOT NULL)
       GROUP BY id_groupe HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D9', 'id_groupe -> statut',
       COUNT(*), 'tient : un parcours est confirmé ou annulé en entier'
FROM  (SELECT id_groupe
       FROM  (SELECT DISTINCT id_groupe, statut FROM operation_a_plat WHERE id_groupe IS NOT NULL)
       GROUP BY id_groupe HAVING COUNT(*) > 1)
ORDER BY 1;
-- Résultat :
--   D1  0      D2  0      D3  0      D4  0      D5  0
--   D6  73     D7  88     D8  9      D9  0
--   D6 : les 73 copies d'étudiants (même e-mail une fois normalisé, id différent).
--   D7 : 80 sessions où un montant négatif côtoie le bon montant (le négatif vaut
--        exactement -nb_places x prix), + 8 id de session inexistants vus avec plusieurs
--        montants. Ce sont les opérations non valides du sujet.
--   D8 : 9 parcours passés en partie sous l'id d'une copie : même personne, deux id.

-- 2b. Les mêmes DF après le chargement du L2 (tables nettoyées) : plus aucune violation
SELECT 'D6' AS n, 'email -> id_etudiant (ETUDIANT)' AS dependance, COUNT(*) AS violations
FROM  (SELECT email FROM etudiant WHERE email IS NOT NULL GROUP BY email HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D7', 'id_session, nb_places -> montant (INSCRIPTION)', COUNT(*)
FROM  (SELECT id_session, nb_places FROM inscription
       GROUP BY id_session, nb_places HAVING COUNT(DISTINCT montant) > 1)
UNION ALL
SELECT 'D7b', 'montant = nb_places x prix_unitaire (INSCRIPTION, RG12)', COUNT(*)
FROM   inscription i JOIN session_cours s ON s.id_session = i.id_session
WHERE  i.montant <> i.nb_places * s.prix_unitaire
UNION ALL
SELECT 'D8', 'id_groupe -> id_etudiant (INSCRIPTION)', COUNT(*)
FROM  (SELECT id_groupe FROM inscription WHERE id_groupe IS NOT NULL
       GROUP BY id_groupe HAVING COUNT(DISTINCT id_etudiant) > 1)
ORDER BY 1;
-- Résultat : 0 partout. D7b : le montant se recalcule toujours à partir de la session
-- (c'est la redondance discutée dans la doc, partie dénormalisation).

-- 2c. Dépendances qu'on pourrait croire vraies, et qu'on ne retient pas
SELECT 'N1' AS n, 'id_etudiant -> id_campus_session' AS dependance,
       COUNT(*) AS violations, 'fausse : un étudiant suit des cours sur plusieurs sites' AS conclusion
FROM  (SELECT id_etudiant
       FROM  (SELECT DISTINCT id_etudiant, id_campus_session FROM operation_a_plat
              WHERE id_campus_session IS NOT NULL)
       GROUP BY id_etudiant HAVING COUNT(*) > 1)
UNION ALL
SELECT 'N2', 'telephone -> id_etudiant', COUNT(*), 'fausse : le téléphone n''identifie personne'
FROM  (SELECT telephone
       FROM  (SELECT DISTINCT telephone, id_etudiant FROM operation_a_plat WHERE telephone IS NOT NULL)
       GROUP BY telephone HAVING COUNT(*) > 1)
UNION ALL
SELECT 'N3', 'categorie -> prix_unitaire', COUNT(*), 'fausse : le prix est fixé session par session'
FROM  (SELECT categorie
       FROM  (SELECT DISTINCT categorie, prix_unitaire FROM operation_a_plat WHERE categorie IS NOT NULL)
       GROUP BY categorie HAVING COUNT(*) > 1)
UNION ALL
SELECT 'N4', 'ville (de l''étudiant) -> id_campus_etudiant', COUNT(*),
       'tient dans les données, pas une règle : non retenue'
FROM  (SELECT ville
       FROM  (SELECT DISTINCT ville, id_campus_etudiant FROM operation_a_plat)
       GROUP BY ville HAVING COUNT(*) > 1)
ORDER BY 1;
-- Résultat : N1 12 369, N2 75, N3 6, N4 0
--   N2 : 73 téléphones partagés par une copie et son original, 2 par deux vraies personnes.
--   N4 : coïncidence du jeu de données (chaque étudiant habite la ville de son campus) ;
--        aucune règle ne l'impose, un étudiant peut habiter ailleurs. Non retenue.


-- ---------------------------------------------------------------------
-- 3. Décomposition et vérification « sans perte »
--    Chaque DF retenue (D2 à D4) donne une relation dont le déterminant est la clé.
--    On projette la table à plat sur ces relations (SELECT DISTINCT), on les rejoint
--    par leurs clés, et on compare avec la table à plat dans les deux sens (MINUS).
--    0 ligne dans les deux sens = la décomposition ne perd et n'invente aucune ligne.
--    Les tables du L1 sont ces relations, après nettoyage (L2), avec en plus :
--    CATEGORIE (liste des langues) et l'héritage SIEGE / SITE.
-- ---------------------------------------------------------------------
WITH r_inscription AS (
    SELECT DISTINCT id_inscription, id_etudiant, id_session, id_groupe, date_operation,
                    nb_places, montant, statut
    FROM   operation_a_plat
), r_etudiant AS (
    SELECT DISTINCT id_etudiant, nom, prenom, email, telephone, ville,
                    id_campus_etudiant AS id_campus, date_creation_compte
    FROM   operation_a_plat
), r_session AS (
    SELECT DISTINCT id_session, libelle_session, categorie, id_campus_session AS id_campus,
                    debut, duree_minutes, capacite, prix_unitaire
    FROM   operation_a_plat
    WHERE  libelle_session IS NOT NULL               -- les 220 sessions inexistantes n'en font pas partie
), r_campus AS (
    SELECT id_campus_etudiant AS id_campus, nom_campus_etudiant AS nom,
           ville_campus_etudiant AS ville, role_campus_etudiant AS role
    FROM   operation_a_plat
    UNION
    SELECT id_campus_session, nom_campus_session, ville_campus_session, role_campus_session
    FROM   operation_a_plat WHERE id_campus_session IS NOT NULL
), rejointure AS (
    SELECT i.id_inscription, i.id_etudiant, i.id_session, i.id_groupe, i.date_operation,
           i.nb_places, i.montant, i.statut,
           e.nom, e.prenom, e.email, e.telephone, e.ville,
           e.id_campus  AS id_campus_etudiant, e.date_creation_compte,
           ce.nom       AS nom_campus_etudiant, ce.ville AS ville_campus_etudiant,
           ce.role      AS role_campus_etudiant,
           s.libelle_session, s.categorie, s.id_campus AS id_campus_session, s.debut,
           s.duree_minutes, s.capacite, s.prix_unitaire,
           cs.nom       AS nom_campus_session, cs.ville AS ville_campus_session,
           cs.role      AS role_campus_session
    FROM   r_inscription i
    JOIN   r_etudiant    e  ON e.id_etudiant = i.id_etudiant
    JOIN   r_campus      ce ON ce.id_campus  = e.id_campus
    LEFT JOIN r_session  s  ON s.id_session  = i.id_session      -- LEFT : sessions inexistantes
    LEFT JOIN r_campus   cs ON cs.id_campus  = s.id_campus
)
SELECT (SELECT COUNT(*) FROM r_inscription) AS nb_inscription,
       (SELECT COUNT(*) FROM r_etudiant)    AS nb_etudiant,
       (SELECT COUNT(*) FROM r_session)     AS nb_session,
       (SELECT COUNT(*) FROM r_campus)      AS nb_campus,
       (SELECT COUNT(*) FROM (SELECT * FROM rejointure MINUS SELECT * FROM operation_a_plat))
                                            AS lignes_inventees,
       (SELECT COUNT(*) FROM (SELECT * FROM operation_a_plat MINUS SELECT * FROM rejointure))
                                            AS lignes_perdues
FROM dual;
-- Résultat : 354 855 inscriptions, 21 544 étudiants, 47 619 sessions, 3 campus,
--            0 ligne inventée, 0 ligne perdue
--   3 campus et non 4 : le siège n'a ni étudiant ni session, il n'apparaît donc dans
--   aucune opération. C'est l'anomalie d'insertion de la table à plat : on ne peut pas y
--   enregistrer un campus (ou un étudiant, une session) qui n'a pas encore d'opération.


-- ---------------------------------------------------------------------
-- 4. Dénormalisation assumée : le site de la session recopié dans INSCRIPTION
--    En 3NF, le site d'une opération se déduit par jointure (RG10, vue V_INSCRIPTION_SITE).
--    On le recopie dans INSCRIPTION.id_site, car C5, C6, C8 et la répartition des données
--    par site (L5, L6) en ont besoin sans passer par SESSION_COURS. Justification et
--    mesures : docs/L3_normalisation/L3_normalisation.md.
--
--    Cohérence garantie de deux façons :
--    - la clé étrangère composite (id_session, id_site) -> SESSION_COURS (id_session,
--      id_campus) refuse tout site différent de celui de la session (même principe que
--      l'héritage CAMPUS / SITE du L1) ;
--    - le trigger TRG_INSCRIPTION_SITE remplit id_site tout seul : les scripts suivants
--      (package du L4, etc.) n'ont pas à s'en occuper.
--    Conséquence : on ne peut plus changer le site d'une session qui a des inscriptions
--    (ORA-02292). C'est voulu : une session ne change pas de ville.
-- ---------------------------------------------------------------------
ALTER TABLE inscription ADD (id_site NUMBER(4));

UPDATE inscription i
SET    i.id_site = (SELECT s.id_campus FROM session_cours s WHERE s.id_session = i.id_session);
COMMIT;

ALTER TABLE inscription MODIFY (id_site CONSTRAINT nn_inscription_site NOT NULL);

-- cible de la clé étrangère composite
ALTER TABLE session_cours ADD CONSTRAINT uq_session_id_site UNIQUE (id_session, id_campus);

ALTER TABLE inscription ADD CONSTRAINT fk_inscription_session_site
      FOREIGN KEY (id_session, id_site) REFERENCES session_cours (id_session, id_campus);

COMMENT ON COLUMN inscription.id_site IS 'Dénormalisation assumée (L3) : copie de SESSION_COURS.id_campus, tenue par fk_inscription_session_site et trg_inscription_site.';

-- Remplit id_site à chaque nouvelle inscription ou changement de session.
-- Une valeur fournie par l'appelant est ignorée : c'est toujours le site de la session.
CREATE OR REPLACE TRIGGER trg_inscription_site
BEFORE INSERT OR UPDATE OF id_session, id_site ON inscription
FOR EACH ROW
BEGIN
    SELECT id_campus INTO :NEW.id_site
    FROM   session_cours
    WHERE  id_session = :NEW.id_session;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001,
            'Session ' || :NEW.id_session || ' inexistante : inscription refusée (RG11)');
END;
/

-- Contrôle : le site recopié est toujours celui de la session
SELECT COUNT(*) AS inscriptions,
       SUM(CASE WHEN i.id_site = s.id_campus THEN 1 ELSE 0 END) AS site_coherent
FROM   inscription i
JOIN   session_cours s ON s.id_session = i.id_session;
-- Résultat : 354 458 inscriptions, 354 458 cohérentes
