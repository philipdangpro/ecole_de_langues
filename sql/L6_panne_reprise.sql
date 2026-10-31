-- =====================================================================
-- L6 · Panne d'un site et reprise
-- Responsable : Baptiste (avec Claude Code)
-- Scénario à lancer à la main, étape par étape. N'est PAS lancé par run_all.sql.
-- Prérequis : run_all.sql (avec 10_distribution.sql) vient de tourner.
--
-- Deux connexions :
--   - langues / langues   : le siège (étapes 0, 1, 3, 5, 6) ;
--   - system  / oracle    : l'administrateur, qui « coupe » puis « rallume » le site
--                           d'Angers (étapes 2 et 4).
-- SQL Developer : ouvrir ce fichier sur la connexion langues ; pour les étapes 2 et 4,
-- copier le bloc dans une feuille de la connexion system. Exécuter chaque étape avec F5
-- (sélectionner le bloc de l'étape, puis F5), dans l'ordre des numéros.
-- Résultat attendu : que des lignes « OK ». Sortie de référence : preuves/L6_panne_reprise.txt
--
-- Comment on simule la panne : les trois sites sont trois comptes de la même base. On
-- bloque le compte site_angers et on coupe ses sessions ouvertes : pour le siège, le
-- lien LIEN_ANGERS ne répond plus (ORA-28000), exactement comme un serveur arrêté.
--
-- Ce que montre le scénario :
--   1. en temps normal, un parcours sur 3 sites est validé en une seule transaction
--      (validation à deux phases), et un parcours refusé ne laisse rien sur aucun site ;
--   2. pendant la panne :
--      - les vues globales sont inutilisables, même pour une requête sur un autre site ;
--      - Bordeaux et Tours continuent de travailler sur leur propre fragment ;
--      - un parcours qui passe par Angers est refusé en entier (on préfère la cohérence) ;
--      - une inscription simple à Angers est gardée en attente au siège (on préfère la
--        disponibilité) ;
--   3. à la reprise, les inscriptions en attente sont rejouées et la capacité est
--      revérifiée : celle qui n'a plus de place est refusée, pas forcée ;
--   4. redondance (démarche du Lab 5, parties 5 et 6) : pendant la panne, le catalogue
--      d'Angers est lu dans sa copie au siège (bascule) et le siège y corrige un prix ;
--      à la reprise, un conflit (même session modifiée au siège et à Angers) est réglé
--      par « le dernier écrivain gagne », et la copie et le site sont resynchronisés.
-- =====================================================================


-- =====================================================================
-- ÉTAPE 0 (langues) : préparation et état normal
-- =====================================================================
SET SERVEROUTPUT ON FORMAT WRAPPED
SET DEFINE ON
SET VERIFY OFF
SET LINESIZE 200
SET PAGESIZE 100
COLUMN ville FORMAT A10

COLUMN etu      NEW_VALUE etu
COLUMN etu2     NEW_VALUE etu2
COLUMN s2       NEW_VALUE s2
COLUMN s3       NEW_VALUE s3
COLUMN s4       NEW_VALUE s4
COLUMN s4_une   NEW_VALUE s4_une
COLUMN s4_b     NEW_VALUE s4_b
COLUMN id_debut NEW_VALUE id_debut

-- Deux étudiants de test : les deux plus anciens comptes
SELECT MIN(id_etudiant) AS etu, MAX(id_etudiant) AS etu2
FROM  (SELECT id_etudiant FROM etudiant ORDER BY date_inscription, id_etudiant
       FETCH FIRST 2 ROWS ONLY);

-- Sessions de test, qui commencent après le 01/12/2026 (opérations datées du 30/11/2026) :
--   s2, s3, s4 : une session de Bordeaux, Tours et Angers avec au moins 3 places libres ;
--   s4_une     : une session d'Angers où il reste exactement 1 place ;
--   s4_b       : une autre session d'Angers, dont le siège corrige le prix pendant la panne.
SELECT MIN(CASE WHEN id_site = 2 AND libres >= 3 THEN id_session END) AS s2,
       MIN(CASE WHEN id_site = 3 AND libres >= 3 THEN id_session END) AS s3,
       MIN(CASE WHEN id_site = 4 AND libres >= 3 THEN id_session END) AS s4,
       MAX(CASE WHEN id_site = 4 AND libres  = 1 THEN id_session END) AS s4_une,
       MAX(CASE WHEN id_site = 4 AND libres >= 3 THEN id_session END) AS s4_b
FROM  (SELECT o.id_site, o.id_session, o.capacite - o.places_confirmees AS libres
       FROM   v_session_occupation o
       JOIN   session_cours s ON s.id_session = o.id_session
       WHERE  s.debut > DATE '2026-12-01');

-- Les inscriptions de test auront un numéro >= id_debut (nettoyage de l'étape 6)
SELECT seq_inscription.NEXTVAL AS id_debut FROM dual;

-- État normal : les trois sites répondent
SELECT (SELECT COUNT(*) FROM inscription@lien_bordeaux) AS bordeaux,
       (SELECT COUNT(*) FROM inscription@lien_tours)    AS tours,
       (SELECT COUNT(*) FROM inscription@lien_angers)   AS angers,
       (SELECT COUNT(*) FROM v_g_inscription)           AS vue_globale
FROM dual;
-- Résultat attendu : 78 676 / 162 669 / 113 113, et 354 458 dans la vue globale


-- =====================================================================
-- ÉTAPE 1 (langues) : le parcours réparti en temps normal
-- =====================================================================
VARIABLE g1 VARCHAR2(10)
VARIABLE g2 VARCHAR2(10)

-- 1a. Parcours sur les 3 sites : une transaction, trois bases modifiées.
--     Au COMMIT, Oracle valide en deux phases : chaque site confirme qu'il est prêt,
--     puis tous valident. Aucun site ne peut garder sa ligne si un autre a échoué.
DECLARE
    v_nb NUMBER;
BEGIN
    pkg_reparti.inscrire_parcours(&etu, t_liste_sessions(&s2, &s3, &s4), 1,
                                  DATE '2026-11-30', :g1);
    COMMIT;
    SELECT COUNT(DISTINCT id_site) INTO v_nb FROM v_g_inscription WHERE id_groupe = :g1;
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_nb = 3 THEN 'OK   ' ELSE 'ECHEC' END
        || ' 1a parcours ' || :g1 || ' validé sur ' || v_nb || ' site(s) (attendu 3)');
END;
/

-- Où sont les lignes du parcours : une dans chaque fragment
SELECT 'Bordeaux' AS ville, id_inscription, id_session, id_groupe, montant
FROM   inscription@lien_bordeaux WHERE id_groupe = :g1
UNION ALL
SELECT 'Tours', id_inscription, id_session, id_groupe, montant
FROM   inscription@lien_tours    WHERE id_groupe = :g1
UNION ALL
SELECT 'Angers', id_inscription, id_session, id_groupe, montant
FROM   inscription@lien_angers   WHERE id_groupe = :g1;

-- 1b. Parcours refusé : 2 places demandées, il n'en reste qu'une à Angers (s4_une).
--     La ligne de Tours, posée avant, doit disparaître aussi.
DECLARE
    v_avant NUMBER;
    v_apres NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_avant FROM inscription@lien_tours;
    BEGIN
        pkg_reparti.inscrire_parcours(&etu, t_liste_sessions(&s3, &s4_une), 2,
                                      DATE '2026-11-30', :g2);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('ECHEC 1b le parcours aurait dû être refusé');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            SELECT COUNT(*) INTO v_apres FROM inscription@lien_tours;
            DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20021 AND v_avant = v_apres
                                      THEN 'OK   ' ELSE 'ECHEC' END
                || ' 1b refusé, Tours inchangé (' || v_avant || ' -> ' || v_apres || ') : '
                || SQLERRM);
    END;
END;
/

-- 1c. Consultation du catalogue d'Angers en temps normal : lue dans le site lui-même
VARIABLE src VARCHAR2(10)
BEGIN
    pkg_reparti.consulter_sessions(4, DATE '2026-12-01', 3, :src);
    DBMS_OUTPUT.PUT_LINE(CASE WHEN :src = 'SITE' THEN 'OK   ' ELSE 'ECHEC' END
        || ' 1c catalogue d''Angers lu dans : ' || :src || ' (attendu SITE)');
END;
/


-- =====================================================================
-- ÉTAPE 2 (system) : PANNE du site d'Angers
-- À lancer dans une feuille connectée en system / oracle.
-- =====================================================================
ALTER USER site_angers ACCOUNT LOCK;

-- coupe les sessions déjà ouvertes par le lien du siège
BEGIN
    FOR s IN (SELECT sid, serial# FROM v$session WHERE username = 'SITE_ANGERS') LOOP
        EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial#
                       || ''' IMMEDIATE';
    END LOOP;
END;
/


-- =====================================================================
-- ÉTAPE 3 (langues) : pendant la panne
-- =====================================================================

-- 3a. La vue globale ne répond plus, même pour une requête qui ne porte que sur Tours :
--     Oracle ouvre les trois liens de la vue avant d'éliminer les branches inutiles.
--     Lancée deux fois :
--     - 1re fois : la session ouverte par le lien a été coupée pendant la panne
--       ORA-03150: end-of-file on communication channel for database link
--       ORA-02063: preceding line from LIEN_ANGERS
--     - 2e fois : le lien essaie de se reconnecter, le site refuse
--       ORA-28000: The account is locked; login denied.
--       ORA-02063: preceding line from LIEN_ANGERS
SELECT COUNT(*) FROM v_g_inscription WHERE id_site = 3;
SELECT COUNT(*) FROM v_g_inscription WHERE id_site = 3;

-- 3c. Tours continue de travailler sur son propre fragment
SELECT COUNT(*) AS inscriptions_tours, SUM(montant) AS ca_tours
FROM   inscription@lien_tours
WHERE  statut = 'CONFIRMEE';

-- 3d. Le coût de la fragmentation d'ETUDIANT : les inscriptions de Tours dont l'étudiant
--     est rattaché à Angers. Tours sait qu'elles existent, mais ne peut plus afficher
--     le nom de ces étudiants tant qu'Angers est en panne.
SELECT COUNT(*) AS insc_tours_etudiant_angers,
       COUNT(DISTINCT i.id_etudiant) AS etudiants_concernes
FROM   inscription@lien_tours i
JOIN   v_annuaire_etudiant a ON a.id_etudiant = i.id_etudiant
WHERE  a.id_site = 4;

-- 3e. Un parcours qui passe par Angers est refusé EN ENTIER, Bordeaux n'est pas modifié
DECLARE
    v_avant NUMBER;
    v_apres NUMBER;
    v_g     VARCHAR2(10);
BEGIN
    SELECT COUNT(*) INTO v_avant FROM inscription@lien_bordeaux;
    BEGIN
        pkg_reparti.inscrire_parcours(&etu2, t_liste_sessions(&s2, &s4), 1,
                                      DATE '2026-11-30', v_g);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('ECHEC 3e le parcours aurait dû être refusé');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            SELECT COUNT(*) INTO v_apres FROM inscription@lien_bordeaux;
            DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20020 AND v_avant = v_apres
                                      THEN 'OK   ' ELSE 'ECHEC' END
                || ' 3e refusé, Bordeaux inchangé (' || v_avant || ' -> ' || v_apres || ')');
            DBMS_OUTPUT.PUT_LINE('      ' || SQLERRM);
    END;
END;
/

-- 3f. Un parcours entre Bordeaux et Tours passe : la panne d'Angers ne les bloque pas
DECLARE
    v_g VARCHAR2(10);
BEGIN
    pkg_reparti.inscrire_parcours(&etu2, t_liste_sessions(&s2, &s3), 1,
                                  DATE '2026-11-30', v_g);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_g IS NOT NULL THEN 'OK   ' ELSE 'ECHEC' END
        || ' 3f parcours ' || v_g || ' Bordeaux + Tours validé pendant la panne d''Angers');
END;
/

-- 3g. Trois inscriptions simples à Angers : mises en attente au siège.
--     Les deux premières visent s4_une, où il ne reste qu'une place : le siège ne peut
--     pas le vérifier pendant la panne, la reprise devra trancher.
DECLARE
    v_id   NUMBER;
    v_etat VARCHAR2(10);
    PROCEDURE essai (p_etu NUMBER, p_session NUMBER, p_nom VARCHAR2) IS
    BEGIN
        pkg_reparti.inscrire(p_etu, p_session, 1, DATE '2026-11-30', v_id, v_etat);
        DBMS_OUTPUT.PUT_LINE(CASE WHEN v_etat = 'EN_ATTENTE' THEN 'OK   ' ELSE 'ECHEC' END
            || ' ' || p_nom || ' étudiant ' || p_etu || ', session ' || p_session
            || ' : ' || v_etat || ' (inscription ' || v_id || ')');
    END;
BEGIN
    essai(&etu,  &s4_une, '3g-1');
    essai(&etu2, &s4_une, '3g-2');
    essai(&etu,  &s4,     '3g-3');
    COMMIT;
END;
/

COLUMN motif FORMAT A60
SELECT id_attente, id_site, id_inscription, id_etudiant, id_session, etat, motif
FROM   operation_en_attente
ORDER BY id_attente;

-- 3h. Bascule : le catalogue d'Angers reste consultable, lu dans la copie du siège
BEGIN
    pkg_reparti.consulter_sessions(4, DATE '2026-12-01', 3, :src);
    DBMS_OUTPUT.PUT_LINE(CASE WHEN :src = 'REPLIQUE' THEN 'OK   ' ELSE 'ECHEC' END
        || ' 3h catalogue d''Angers lu dans : ' || :src || ' (attendu REPLIQUE)');
END;
/

-- 3i. Pendant la panne, le siège corrige le prix d'une session d'Angers dans la copie
--     (la seule qu'il peut atteindre). Angers ne le sait pas encore.
DECLARE
    v_nb NUMBER;
BEGIN
    UPDATE session_replique
    SET    prix_unitaire = prix_unitaire + 10, derniere_maj = SYSTIMESTAMP
    WHERE  id_session = &s4_b;
    v_nb := SQL%ROWCOUNT;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_nb = 1 THEN 'OK   ' ELSE 'ECHEC' END
        || ' 3i prix de la session ' || &s4_b || ' corrigé (+10) dans la copie du siège');
END;
/


-- =====================================================================
-- ÉTAPE 4 (system) : REPRISE du site d'Angers
-- À lancer dans la feuille system.
-- =====================================================================
ALTER USER site_angers ACCOUNT UNLOCK;


-- =====================================================================
-- ÉTAPE 5 (langues) : reprise et resynchronisation
-- =====================================================================

-- 5a. Angers répond de nouveau
SELECT COUNT(*) AS inscriptions_angers FROM inscription@lien_angers;

-- 5b. Rejeu des opérations en attente, dans l'ordre d'arrivée
BEGIN
    pkg_reparti.rejouer_attente(4);
    COMMIT;
END;
/

SELECT id_attente, id_inscription, id_etudiant, id_session, etat, motif
FROM   operation_en_attente
ORDER BY id_attente;
-- Résultat attendu : 3g-1 REJOUEE, 3g-2 REFUSEE (plus de place), 3g-3 REJOUEE

-- 5c. Contrôles de la reprise
DECLARE
    v_rejouees  NUMBER;
    v_refusees  NUMBER;
    v_presentes NUMBER;
    v_capacite  NUMBER;
    v_occupees  NUMBER;
    v_global    NUMBER;
BEGIN
    SELECT COUNT(CASE WHEN etat = 'REJOUEE' THEN 1 END),
           COUNT(CASE WHEN etat = 'REFUSEE' THEN 1 END)
    INTO   v_rejouees, v_refusees
    FROM   operation_en_attente;

    -- les opérations rejouées sont bien dans le fragment d'Angers
    SELECT COUNT(*) INTO v_presentes
    FROM   inscription@lien_angers
    WHERE  id_inscription IN (SELECT id_inscription FROM operation_en_attente
                              WHERE etat = 'REJOUEE');

    -- la session à une place n'est pas sur-réservée
    SELECT capacite INTO v_capacite FROM session_cours@lien_angers WHERE id_session = &s4_une;
    SELECT SUM(nb_places) INTO v_occupees FROM inscription@lien_angers
    WHERE  id_session = &s4_une AND statut = 'CONFIRMEE';

    SELECT COUNT(*) INTO v_global FROM v_g_inscription;

    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_rejouees = 2 AND v_refusees = 1 THEN 'OK   ' ELSE 'ECHEC' END
        || ' 5c ' || v_rejouees || ' rejouée(s), ' || v_refusees || ' refusée(s) (attendu 2 et 1)');
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_presentes = v_rejouees THEN 'OK   ' ELSE 'ECHEC' END
        || ' 5c ' || v_presentes || ' opération(s) rejouée(s) présente(s) à Angers');
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_occupees <= v_capacite THEN 'OK   ' ELSE 'ECHEC' END
        || ' 5c session ' || &s4_une || ' : ' || v_occupees || ' place(s) pour '
        || v_capacite || ', pas de sur-réservation');
    -- 354 458 + 3 (parcours 1a) + 2 (parcours 3f) + 2 (rejouées)
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_global = 354458 + 7 THEN 'OK   ' ELSE 'ECHEC' END
        || ' 5c vue globale de nouveau disponible : ' || v_global || ' inscriptions');
END;
/

-- 5d. Conflit (Lab 5, partie 6) : la même session s4 est modifiée des deux côtés.
--     D'abord le siège, dans la copie : capacité + 5 ;
--     puis Angers, dans son fragment, juste après : capacité + 2.
--     Chaque modification met à jour derniere_maj.
UPDATE session_replique
SET    capacite = capacite + 5, derniere_maj = SYSTIMESTAMP
WHERE  id_session = &s4;
COMMIT;

UPDATE session_cours@lien_angers
SET    capacite = capacite + 2, derniere_maj = SYSTIMESTAMP
WHERE  id_session = &s4;
COMMIT;

-- Quelle version est la plus récente ? (requête du Lab 5, partie 6.3)
-- s4 : modifiée des deux côtés, Angers en dernier ; s4_b : modifiée seulement au siège
COLUMN source FORMAT A14
COLUMN derniere_maj FORMAT A28
SELECT 'Site Angers' AS source, id_session, capacite, prix_unitaire, derniere_maj
FROM   session_cours@lien_angers WHERE id_session IN (&s4, &s4_b)
UNION ALL
SELECT 'Copie siège', id_session, capacite, prix_unitaire, derniere_maj
FROM   session_replique         WHERE id_session IN (&s4, &s4_b)
ORDER BY id_session, derniere_maj DESC;

-- 5e. Resynchronisation : le dernier écrivain gagne, dans les deux sens
--     - s4   : Angers a écrit en dernier, sa capacité (+2) est recopiée au siège ;
--     - s4_b : seul le siège l'a modifiée, son prix (+10) est recopié à Angers.
--     Le siège et Angers sont modifiés dans la même transaction (validation à deux phases).
DECLARE
    v_vers_site     NUMBER;
    v_vers_replique NUMBER;
    v_cap_ref       NUMBER;
    v_prix_ref      NUMBER;
    v_cap_copie     NUMBER;
    v_prix_angers   NUMBER;
    v_ecarts        NUMBER;
BEGIN
    pkg_reparti.synchroniser_replique(4, v_vers_site, v_vers_replique);
    COMMIT;

    -- valeurs d'origine, dans la table centrale (non modifiée par le scénario)
    SELECT capacite      INTO v_cap_ref  FROM session_cours WHERE id_session = &s4;
    SELECT prix_unitaire INTO v_prix_ref FROM session_cours WHERE id_session = &s4_b;
    SELECT capacite      INTO v_cap_copie   FROM session_replique          WHERE id_session = &s4;
    SELECT prix_unitaire INTO v_prix_angers FROM session_cours@lien_angers WHERE id_session = &s4_b;

    SELECT COUNT(*) INTO v_ecarts
    FROM  (SELECT id_session, libelle, id_categorie, id_campus, debut,
                  duree_minutes, capacite, prix_unitaire, derniere_maj
           FROM   session_cours@lien_angers
           MINUS  SELECT * FROM session_replique);

    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_vers_site = 1 AND v_vers_replique = 1 THEN 'OK   ' ELSE 'ECHEC' END
        || ' 5e ' || v_vers_site || ' ligne(s) copie -> Angers, ' || v_vers_replique
        || ' ligne(s) Angers -> copie (attendu 1 et 1)');
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_cap_copie = v_cap_ref + 2 THEN 'OK   ' ELSE 'ECHEC' END
        || ' 5e conflit sur ' || &s4 || ' : capacité ' || v_cap_copie || ' (+2 d''Angers, '
        || 'le dernier écrivain gagne ; le +5 du siège est écrasé)');
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_prix_angers = v_prix_ref + 10 THEN 'OK   ' ELSE 'ECHEC' END
        || ' 5e prix corrigé pendant la panne arrivé à Angers : ' || v_prix_angers
        || ' (' || v_prix_ref || ' + 10)');
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_ecarts = 0 THEN 'OK   ' ELSE 'ECHEC' END
        || ' 5e copie et site identiques : ' || v_ecarts || ' écart');
END;
/


-- =====================================================================
-- ÉTAPE 6 (langues) : nettoyage, retour à l'état de run_all.sql
-- =====================================================================
DELETE FROM inscription@lien_bordeaux WHERE id_inscription >= &id_debut;
DELETE FROM inscription@lien_tours    WHERE id_inscription >= &id_debut;
DELETE FROM inscription@lien_angers   WHERE id_inscription >= &id_debut;
DELETE FROM operation_en_attente;
COMMIT;

SELECT COUNT(*) AS inscriptions_vue_globale FROM v_g_inscription;
-- Résultat attendu : 354 458, comme la table centrale

-- Sessions s4 et s4_b remises à leurs valeurs d'origine à Angers, puis copie resynchronisée
DECLARE
    v_vers_site     NUMBER;
    v_vers_replique NUMBER;
    v_ecarts        NUMBER;
BEGIN
    FOR c IN (SELECT id_session, capacite, prix_unitaire FROM session_cours
              WHERE  id_session IN (&s4, &s4_b)) LOOP
        UPDATE session_cours@lien_angers
        SET    capacite = c.capacite, prix_unitaire = c.prix_unitaire,
               derniere_maj = SYSTIMESTAMP
        WHERE  id_session = c.id_session;
    END LOOP;
    pkg_reparti.synchroniser_replique(4, v_vers_site, v_vers_replique);
    COMMIT;

    SELECT COUNT(*) INTO v_ecarts
    FROM  (SELECT id_session, libelle, id_categorie, id_campus, debut,
                  duree_minutes, capacite, prix_unitaire
           FROM   session_cours WHERE id_campus = 4
           MINUS  SELECT id_session, libelle, id_categorie, id_campus, debut,
                         duree_minutes, capacite, prix_unitaire
                  FROM   session_replique);
    DBMS_OUTPUT.PUT_LINE('Copie du siège = table centrale pour Angers : ' || v_ecarts
        || ' écart (attendu 0)');
END;
/
