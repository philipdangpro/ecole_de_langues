-- =====================================================================
-- 07_package_parcours.sql
-- Livrable : L4 · Fiabilité
-- Responsable : Baptiste (avec Claude Code)
-- Attendu  : package : procédure du parcours multi-sites, tout ou rien, qui refuse la sur-réservation
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Le parcours (opération groupée, RG16) : un étudiant s'inscrit en une fois à plusieurs
-- sessions, souvent dans plusieurs sites. Toutes les inscriptions partagent un id_groupe.
-- On impose au moins 2 sessions (comme les 2 667 parcours du CSV, qui en ont 2 à 4), mais
-- pas 2 sites : 793 parcours historiques restent sur un seul site, et C8 les distingue.
--
-- Contenu :
--   1. Séquences SEQ_INSCRIPTION et SEQ_GROUPE (numéros des nouvelles opérations)
--   2. Type T_LISTE_SESSIONS (la liste des sessions passée à la procédure)
--   3. Package PKG_PARCOURS :
--        inscrire_parcours  : tout ou rien, refuse la sur-réservation (RG15, RG16)
--        annuler_parcours   : annule toutes les inscriptions d'un parcours
--        places_restantes   : capacité - places confirmées d'une session
--
-- Le package ne fait ni COMMIT ni ROLLBACK complet : c'est l'appelant qui valide.
--   - en cas de succès : les inscriptions sont posées, l'appelant fait COMMIT ;
--   - en cas d'erreur  : ROLLBACK TO SAVEPOINT, la base revient à l'état d'avant l'appel
--     (même les inscriptions déjà posées dans la boucle), puis l'erreur est renvoyée.
-- Tests : preuves/L4_tests_fiabilite.sql. Concurrence : sql/L4_concurrence_session_A/B.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Séquences
--    Elles démarrent après le plus grand numéro déjà utilisé, rejets compris : un id
--    écarté au chargement (INSCRIPTION_REJET) n'est jamais réattribué, la trace reste claire.
--    START WITH n'accepte pas de sous-requête, d'où le SQL dynamique.
-- ---------------------------------------------------------------------
DECLARE
    v_inscription NUMBER;
    v_groupe      NUMBER;
BEGIN
    SELECT NVL(MAX(id_inscription), 0) + 1 INTO v_inscription
    FROM  (SELECT id_inscription FROM inscription
           UNION ALL
           SELECT id_inscription FROM inscription_rejet);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(id_groupe, 2))), 0) + 1 INTO v_groupe
    FROM  (SELECT id_groupe FROM inscription       WHERE id_groupe IS NOT NULL
           UNION ALL
           SELECT id_groupe FROM inscription_rejet WHERE id_groupe IS NOT NULL);

    EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_inscription START WITH ' || v_inscription;
    -- MAXVALUE : le format G + 5 chiffres (ck_inscription_groupe) s'arrête à G99999
    EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_groupe START WITH ' || v_groupe || ' MAXVALUE 99999';
END;
/

COLUMN sequence_name FORMAT A16
SELECT sequence_name, last_number AS prochain_numero
FROM   user_sequences
WHERE  sequence_name IN ('SEQ_INSCRIPTION', 'SEQ_GROUPE')
ORDER BY 1;
-- Résultat : SEQ_GROUPE 2668 (dernier parcours : G02667), SEQ_INSCRIPTION 354856


-- ---------------------------------------------------------------------
-- 2. Type de la liste de sessions
--    Type SQL (et non type déclaré dans le package) : il s'écrit directement à l'appel,
--    t_liste_sessions(101, 2045, 3310), et se lit en SQL avec TABLE(...).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TYPE t_liste_sessions AS TABLE OF NUMBER(8);
/


-- ---------------------------------------------------------------------
-- 3. Package
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_parcours AS

    -- Inscrit p_id_etudiant à toutes les sessions de p_sessions, p_nb_places chacune,
    -- sous un nouvel id_groupe (renvoyé dans p_id_groupe). Tout ou rien : si une seule
    -- session est pleine ou si une règle est violée, aucune inscription n'est gardée.
    -- p_date_operation : date de l'opération, maintenant par défaut (paramètre utile pour
    -- les tests, les sessions du jeu de données s'arrêtant au 31/12/2026).
    PROCEDURE inscrire_parcours (
        p_id_etudiant     IN  etudiant.id_etudiant%TYPE,
        p_sessions        IN  t_liste_sessions,
        p_nb_places       IN  inscription.nb_places%TYPE DEFAULT 1,
        p_date_operation  IN  DATE DEFAULT SYSDATE,
        p_id_groupe       OUT inscription.id_groupe%TYPE);

    -- Annule toutes les inscriptions confirmées d'un parcours, en un seul ordre UPDATE
    -- (un parcours est confirmé ou annulé en entier : DF D9 du L3).
    PROCEDURE annuler_parcours (p_id_groupe IN inscription.id_groupe%TYPE);

    -- Places encore libres d'une session (négatif pour une session sur-réservée).
    FUNCTION places_restantes (p_id_session IN session_cours.id_session%TYPE) RETURN NUMBER;

END pkg_parcours;
/

CREATE OR REPLACE PACKAGE BODY pkg_parcours AS

    FUNCTION places_restantes (p_id_session IN session_cours.id_session%TYPE) RETURN NUMBER IS
        v_capacite  session_cours.capacite%TYPE;
        v_occupees  NUMBER;
    BEGIN
        SELECT capacite INTO v_capacite FROM session_cours WHERE id_session = p_id_session;

        SELECT NVL(SUM(nb_places), 0) INTO v_occupees
        FROM   inscription
        WHERE  id_session = p_id_session
        AND    statut     = 'CONFIRMEE';

        RETURN v_capacite - v_occupees;
    END places_restantes;


    PROCEDURE inscrire_parcours (
        p_id_etudiant     IN  etudiant.id_etudiant%TYPE,
        p_sessions        IN  t_liste_sessions,
        p_nb_places       IN  inscription.nb_places%TYPE DEFAULT 1,
        p_date_operation  IN  DATE DEFAULT SYSDATE,
        p_id_groupe       OUT inscription.id_groupe%TYPE)
    IS
        v_nb_sessions  NUMBER;
        v_nb_distinct  NUMBER;
        v_capacite     session_cours.capacite%TYPE;
        v_restantes    NUMBER;
    BEGIN
        -- Contrôles de la demande, avant toute écriture
        SELECT COUNT(*), COUNT(DISTINCT column_value) INTO v_nb_sessions, v_nb_distinct
        FROM   TABLE(p_sessions);

        IF v_nb_sessions < 2 THEN
            RAISE_APPLICATION_ERROR(-20011,
                'Un parcours compte au moins 2 sessions (' || v_nb_sessions || ' reçue(s))');
        END IF;
        IF v_nb_distinct < v_nb_sessions THEN
            RAISE_APPLICATION_ERROR(-20012, 'La même session apparaît deux fois dans le parcours');
        END IF;

        -- Point de retour du « tout ou rien »
        SAVEPOINT avant_parcours;

        BEGIN
            p_id_groupe := 'G' || TO_CHAR(seq_groupe.NEXTVAL, 'FM00000');

            -- Sessions prises dans l'ordre croissant de leur id : deux parcours qui
            -- partagent des sessions les verrouillent dans le même ordre, ce qui évite
            -- l'interblocage (ORA-00060) entre eux.
            FOR s IN (SELECT column_value AS id_session FROM TABLE(p_sessions) ORDER BY 1) LOOP

                -- Verrou sur la ligne de la session (correction de l'anomalie de
                -- concurrence) : une autre transaction qui veut des places dans cette
                -- session attend ici notre COMMIT ou ROLLBACK. Le comptage qui suit voit
                -- donc toutes les places déjà validées par les autres.
                BEGIN
                    SELECT capacite INTO v_capacite
                    FROM   session_cours
                    WHERE  id_session = s.id_session
                    FOR UPDATE;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        RAISE_APPLICATION_ERROR(-20013,
                            'Session ' || s.id_session || ' inexistante : parcours refusé (RG11)');
                END;

                -- RG15 : refus de la sur-réservation
                v_restantes := places_restantes(s.id_session);
                IF v_restantes < p_nb_places THEN
                    RAISE_APPLICATION_ERROR(-20010,
                        'Session ' || s.id_session || ' : ' || GREATEST(v_restantes, 0)
                        || ' place(s) libre(s) sur ' || v_capacite || ', ' || p_nb_places
                        || ' demandée(s) : parcours refusé, aucune inscription gardée (RG15)');
                END IF;

                -- montant et id_site sont remplis par les triggers (RG12, L3) ;
                -- RG11, RG13 et RG14 sont vérifiées par les triggers à cet INSERT.
                INSERT INTO inscription (id_inscription, id_etudiant, id_session, id_groupe,
                                         date_operation, nb_places, montant, statut)
                VALUES (seq_inscription.NEXTVAL, p_id_etudiant, s.id_session, p_id_groupe,
                        p_date_operation, p_nb_places, NULL, 'CONFIRMEE');
            END LOOP;

        EXCEPTION
            WHEN OTHERS THEN
                -- Tout ou rien : on défait les inscriptions déjà posées par cet appel
                -- (et leurs lignes d'audit), puis on renvoie l'erreur d'origine.
                ROLLBACK TO SAVEPOINT avant_parcours;
                p_id_groupe := NULL;
                RAISE;
        END;
    END inscrire_parcours;


    PROCEDURE annuler_parcours (p_id_groupe IN inscription.id_groupe%TYPE) IS
    BEGIN
        UPDATE inscription
        SET    statut = 'ANNULEE'
        WHERE  id_groupe = p_id_groupe
        AND    statut    = 'CONFIRMEE';

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20014,
                'Parcours ' || p_id_groupe || ' introuvable ou déjà annulé');
        END IF;
    END annuler_parcours;

END pkg_parcours;
/


-- Contrôle : package compilé sans erreur
COLUMN object_name FORMAT A16
COLUMN object_type FORMAT A12
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name IN ('PKG_PARCOURS', 'T_LISTE_SESSIONS')
ORDER BY object_type;
-- Résultat attendu : PACKAGE, PACKAGE BODY et TYPE, tous VALID
