-- =====================================================================
-- L4_tests_fiabilite.sql : preuve des triggers (06) et du package du parcours (07)
-- À lancer à la main, connecté en langues, APRÈS run_all.sql (pas lancé par run_all).
--   SQL Developer : ouvrir ce fichier, F5. Résultat attendu : que des lignes « OK ».
-- Chaque test affiche OK ou ECHEC avec le message Oracle obtenu.
-- Le script se termine par ROLLBACK : la base est laissée comme avant
-- (seules les séquences avancent, ce qui est sans conséquence).
--
-- Les données de test sont choisies par requête (pas d'id écrit en dur) :
-- sessions qui commencent après le 01/12/2026, opérations datées du 30/11/2026.
-- =====================================================================
SET SERVEROUTPUT ON
SET DEFINE ON
SET VERIFY OFF
SET LINESIZE 200
SET PAGESIZE 100

-- ---------------------------------------------------------------------
-- Choix des données de test
-- ---------------------------------------------------------------------
COLUMN etu        NEW_VALUE etu
COLUMN etu_recent NEW_VALUE etu_recent
COLUMN etu_ancien NEW_VALUE etu_ancien
COLUMN s2         NEW_VALUE s2
COLUMN s3         NEW_VALUE s3
COLUMN s4         NEW_VALUE s4
COLUMN s_pleine   NEW_VALUE s_pleine
COLUMN s_passee   NEW_VALUE s_passee

-- étudiant de test : le plus ancien compte
SELECT MIN(id_etudiant) KEEP (DENSE_RANK FIRST ORDER BY date_inscription) AS etu,
       MIN(id_etudiant) KEEP (DENSE_RANK LAST  ORDER BY date_inscription) AS etu_recent
FROM   etudiant;

-- une session libre (au moins 2 places) dans chacun des 3 sites, où l'étudiant n'est pas inscrit
SELECT MAX(CASE WHEN id_site = 2 THEN id_session END) AS s2,
       MAX(CASE WHEN id_site = 3 THEN id_session END) AS s3,
       MAX(CASE WHEN id_site = 4 THEN id_session END) AS s4
FROM  (SELECT o.id_site, MIN(o.id_session) AS id_session
       FROM   v_session_occupation o
       JOIN   session_cours s ON s.id_session = o.id_session
       WHERE  s.debut > DATE '2026-12-01'
       AND    o.capacite - o.places_confirmees >= 2
       AND    NOT EXISTS (SELECT 1 FROM inscription i
                          WHERE i.id_session = o.id_session AND i.id_etudiant = &etu)
       GROUP BY o.id_site);

-- une session pleine dont l'id est plus grand que s2, s3 et s4 : dans le parcours du test T3,
-- les autres sessions sont donc inscrites AVANT que s_pleine soit refusée (c'est ce qui
-- prouve le « tout ou rien »)
SELECT MIN(o.id_session) AS s_pleine
FROM   v_session_occupation o
JOIN   session_cours s ON s.id_session = o.id_session
WHERE  s.debut > DATE '2026-12-01'
AND    o.capacite - o.places_confirmees <= 0
AND    o.id_session > GREATEST(&s2, &s3, &s4);

-- une session libre déjà commencée au 30/11/2026
SELECT MIN(o.id_session) AS s_passee
FROM   v_session_occupation o
JOIN   session_cours s ON s.id_session = o.id_session
WHERE  s.debut < DATE '2026-11-01'
AND    o.capacite - o.places_confirmees >= 1
AND    o.id_site = 3;

VARIABLE g VARCHAR2(10)

-- Mise en forme de l'affichage (colonnes VARCHAR2 trop larges sinon)
COLUMN id_groupe      FORMAT A9
COLUMN statut         FORMAT A9
COLUMN ancien_statut  FORMAT A9
COLUMN nouveau_statut FORMAT A9
COLUMN utilisateur    FORMAT A11
COLUMN action         FORMAT A6
COLUMN resultat       FORMAT A70

-- État de départ, pour comparer à la fin
SELECT (SELECT COUNT(*) FROM inscription)        AS inscriptions_avant,
       (SELECT COUNT(*) FROM audit_inscription)  AS lignes_audit_avant,
       pkg_parcours.places_restantes(&s2)        AS libres_s2,
       pkg_parcours.places_restantes(&s3)        AS libres_s3,
       pkg_parcours.places_restantes(&s4)        AS libres_s4,
       pkg_parcours.places_restantes(&s_pleine)  AS libres_s_pleine
FROM   dual;


PROMPT
PROMPT === T1. Parcours sur 3 sites accepté (package, RG16) =====================
BEGIN
    pkg_parcours.inscrire_parcours(&etu, t_liste_sessions(&s4, &s2, &s3),
                                   p_nb_places => 2, p_date_operation => DATE '2026-11-30',
                                   p_id_groupe => :g);
    DBMS_OUTPUT.PUT_LINE('T1 OK     : parcours ' || :g || ' enregistré');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T1 ECHEC  : ' || SQLERRM);
END;
/
-- 3 lignes, même id_groupe, montant = 2 x prix (RG12), id_site rempli (trigger du L3)
SELECT i.id_inscription, i.id_groupe, i.id_session, i.id_site, i.nb_places,
       s.prix_unitaire, i.montant, i.statut
FROM   inscription i JOIN session_cours s ON s.id_session = i.id_session
WHERE  i.id_groupe = :g
ORDER BY i.id_session;

PROMPT === T2. Journal d'audit : une ligne par inscription du parcours ==========
SELECT id_audit, utilisateur, action, id_inscription, id_session, id_groupe,
       ancien_statut, nouveau_statut, nouveau_nb_places, nouveau_montant
FROM   audit_inscription
WHERE  id_groupe = :g
ORDER BY id_audit;


PROMPT
PROMPT === T3. Tout ou rien : une session pleine fait refuser tout le parcours ==
-- s2, s3 et s4 ont encore de la place, s_pleine non, et a le plus grand id : les trois
-- autres sont inscrites avant le refus, puis défaites par le ROLLBACK TO SAVEPOINT.
DECLARE
    v_avant NUMBER;
    v_apres NUMBER;
    v_audit_avant NUMBER;
    v_audit_apres NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_avant FROM inscription;
    SELECT COUNT(*) INTO v_audit_avant FROM audit_inscription;
    BEGIN
        pkg_parcours.inscrire_parcours(&etu_recent, t_liste_sessions(&s_pleine, &s2, &s3, &s4),
                                       p_date_operation => DATE '2026-11-30', p_id_groupe => :g);
        DBMS_OUTPUT.PUT_LINE('T3 ECHEC  : parcours accepté malgré la session pleine');
    EXCEPTION WHEN OTHERS THEN
        SELECT COUNT(*) INTO v_apres FROM inscription;
        SELECT COUNT(*) INTO v_audit_apres FROM audit_inscription;
        DBMS_OUTPUT.PUT_LINE(
            CASE WHEN SQLCODE = -20010 AND v_apres = v_avant AND v_audit_apres = v_audit_avant
                 THEN 'T3 OK     : ' ELSE 'T3 ECHEC  : ' END
            || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('            inscriptions avant / après : ' || v_avant || ' / ' || v_apres
            || ' ; audit avant / après : ' || v_audit_avant || ' / ' || v_audit_apres);
    END;
END;
/


PROMPT
PROMPT === T4. Une inscription directe, hors package, est contrôlée aussi =======
-- RG12 : le montant fourni (1 €) est remplacé par nb_places x prix
INSERT INTO inscription (id_inscription, id_etudiant, id_session, date_operation, nb_places, montant, statut)
VALUES (seq_inscription.NEXTVAL, &etu_recent, &s4, DATE '2026-11-30', 1, 1, 'CONFIRMEE');

SELECT CASE WHEN i.montant = s.prix_unitaire THEN 'T4 OK     : montant recalculé, '
            ELSE 'T4 ECHEC  : ' END || 'montant fourni 1, enregistré ' || i.montant AS resultat
FROM   inscription i JOIN session_cours s ON s.id_session = i.id_session
WHERE  i.id_etudiant = &etu_recent AND i.id_session = &s4
AND    i.date_operation = DATE '2026-11-30';
-- (on ne peut pas filtrer sur seq_inscription.CURRVAL : interdit dans un WHERE, ORA-02287)


PROMPT
PROMPT === T5 à T12. Refus attendus =============================================
-- Chaque bloc doit lever l'erreur indiquée ; sinon il affiche ECHEC.
DECLARE
    PROCEDURE attendu (p_test VARCHAR2, p_code NUMBER, p_sqlcode NUMBER, p_message VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD(p_test, 4)
            || CASE WHEN p_sqlcode = p_code THEN 'OK     : ' ELSE 'ECHEC  : ' END || p_message);
    END;
BEGIN
    -- T5 RG13 : l'étudiant est déjà inscrit en confirmé à s2 (T1)
    BEGIN
        INSERT INTO inscription (id_inscription, id_etudiant, id_session, date_operation, nb_places, montant, statut)
        VALUES (seq_inscription.NEXTVAL, &etu, &s2, DATE '2026-11-30', 1, 0, 'CONFIRMEE');
        attendu('T5', -20004, 0, 'doublon confirmé accepté');
    EXCEPTION WHEN OTHERS THEN attendu('T5', -20004, SQLCODE, SQLERRM);
    END;

    -- T6 RG11 : opération datée après le début de la session
    BEGIN
        pkg_parcours.inscrire_parcours(&etu_recent, t_liste_sessions(&s_passee, &s2),
                                       p_date_operation => DATE '2026-11-30', p_id_groupe => :g);
        attendu('T6', -20003, 0, 'inscription après le début acceptée');
    EXCEPTION WHEN OTHERS THEN attendu('T6', -20003, SQLCODE, SQLERRM);
    END;

    -- T7 RG14 : opération antérieure à la création du compte (compte créé le plus tard)
    BEGIN
        pkg_parcours.inscrire_parcours(&etu_recent, t_liste_sessions(&s2, &s3),
                                       p_date_operation => DATE '2019-01-01', p_id_groupe => :g);
        attendu('T7', -20002, 0, 'inscription avant la création du compte acceptée');
    EXCEPTION WHEN OTHERS THEN attendu('T7', -20002, SQLCODE, SQLERRM);
    END;

    -- T8 : un parcours d'une seule session
    BEGIN
        pkg_parcours.inscrire_parcours(&etu_recent, t_liste_sessions(&s2),
                                       p_date_operation => DATE '2026-11-30', p_id_groupe => :g);
        attendu('T8', -20011, 0, 'parcours d''une session accepté');
    EXCEPTION WHEN OTHERS THEN attendu('T8', -20011, SQLCODE, SQLERRM);
    END;

    -- T9 : la même session deux fois
    BEGIN
        pkg_parcours.inscrire_parcours(&etu_recent, t_liste_sessions(&s2, &s2),
                                       p_date_operation => DATE '2026-11-30', p_id_groupe => :g);
        attendu('T9', -20012, 0, 'session en double acceptée');
    EXCEPTION WHEN OTHERS THEN attendu('T9', -20012, SQLCODE, SQLERRM);
    END;

    -- T10 : une session qui n'existe pas
    BEGIN
        pkg_parcours.inscrire_parcours(&etu_recent, t_liste_sessions(&s2, 99999999),
                                       p_date_operation => DATE '2026-11-30', p_id_groupe => :g);
        attendu('T10', -20013, 0, 'session inexistante acceptée');
    EXCEPTION WHEN OTHERS THEN attendu('T10', -20013, SQLCODE, SQLERRM);
    END;

    -- T11 RG7 : un parrain dont le compte est plus récent que celui du filleul
    BEGIN
        UPDATE etudiant SET id_parrain = &etu_recent WHERE id_etudiant = &etu;
        attendu('T11', -20005, 0, 'parrain plus récent accepté');
    EXCEPTION WHEN OTHERS THEN attendu('T11', -20005, SQLCODE, SQLERRM);
    END;

    -- T12 : annuler un parcours qui n'existe pas
    BEGIN
        pkg_parcours.annuler_parcours('G99998');
        attendu('T12', -20014, 0, 'annulation d''un parcours inexistant acceptée');
    EXCEPTION WHEN OTHERS THEN attendu('T12', -20014, SQLCODE, SQLERRM);
    END;
END;
/


PROMPT
PROMPT === T13. RG7 dans le bon sens : parrain plus ancien accepté ==============
UPDATE etudiant SET id_parrain = &etu WHERE id_etudiant = &etu_recent;
SELECT f.id_etudiant AS filleul, f.date_inscription AS compte_filleul,
       p.id_etudiant AS parrain, p.date_inscription AS compte_parrain
FROM   etudiant f JOIN etudiant p ON p.id_etudiant = f.id_parrain
WHERE  f.id_etudiant = &etu_recent;


PROMPT
PROMPT === T14. Annulation d'un parcours : tout le parcours, tracé dans l'audit ==
DECLARE
    v_groupe inscription.id_groupe%TYPE;
BEGIN
    SELECT MAX(id_groupe) INTO v_groupe FROM inscription WHERE id_etudiant = &etu AND id_session = &s2;
    pkg_parcours.annuler_parcours(v_groupe);
    DBMS_OUTPUT.PUT_LINE('T14 OK    : parcours ' || v_groupe || ' annulé');
    :g := v_groupe;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T14 ECHEC : ' || SQLERRM);
END;
/
SELECT action, id_inscription, id_session, ancien_statut, nouveau_statut
FROM   audit_inscription
WHERE  id_groupe = :g
ORDER BY id_audit;
-- Les places annulées sont rendues : s2 retrouve ses places de départ
SELECT pkg_parcours.places_restantes(&s2) AS libres_s2_apres_annulation FROM dual;


PROMPT
PROMPT === Fin : on annule tout ============================================
ROLLBACK;
SELECT (SELECT COUNT(*) FROM inscription)       AS inscriptions_apres,
       (SELECT COUNT(*) FROM audit_inscription) AS lignes_audit_apres
FROM   dual;
-- Doit redonner les chiffres de départ (354 458 inscriptions, 0 ligne d'audit
-- sur une base qui sort de run_all.sql)
