-- =====================================================================
-- 06_triggers.sql
-- Livrable : L4 · Fiabilité
-- Responsable : Baptiste (avec Claude Code)
-- Attendu  : au moins 2 triggers, dont un journal d'audit
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Contenu :
--   1. AUDIT_INSCRIPTION + trigger TRG_INSCRIPTION_AUDIT   : journal d'audit des opérations
--   2. TRG_INSCRIPTION_REGLES   : RG12 (montant calculé), RG11 (date <= début), RG14 (compte)
--   3. TRG_INSCRIPTION_DOUBLON  : RG13 (une seule inscription confirmée par étudiant et session)
--   4. TRG_ETUDIANT_PARRAIN     : RG7 (le parrain a un compte plus ancien)
--   Le trigger TRG_INSCRIPTION_SITE (remplit id_site) est créé au L3 (05_normalisation.sql).
--
-- Les triggers sont créés APRÈS le chargement (02) : ils ne contrôlent que les nouvelles
-- opérations. Les données historiques qui violent RG13 et RG14 restent telles quelles
-- (décision du L2 : elles sont valides au sens du sujet et comptent dans C3 à C9).
--
-- Codes d'erreur (RAISE_APPLICATION_ERROR) :
--   -20001 session inexistante (L3)     -20002 inscription avant la création du compte (RG14)
--   -20003 inscription après le début   -20004 étudiant déjà inscrit en confirmé (RG13)
--   -20005 parrain plus récent (RG7)    -20010 à -20019 : package du parcours (07)
-- Tests : preuves/L4_tests_fiabilite.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Journal d'audit des inscriptions
--    Une ligne par inscription créée, modifiée ou supprimée : qui, quand, quoi, avant / après.
--    Pas de clé étrangère vers INSCRIPTION : la trace doit rester après un DELETE.
--    Pas de nom ni d'e-mail : l'id de l'étudiant suffit (minimisation RGPD).
--    Le trigger écrit dans la même transaction que l'opération : si l'opération est
--    annulée (ROLLBACK, parcours refusé), sa trace l'est aussi. Le journal ne contient donc
--    que ce qui a vraiment été enregistré. (Une transaction autonome garderait aussi les
--    tentatives refusées, mais elle tracerait des opérations qui n'ont jamais existé.)
-- ---------------------------------------------------------------------
CREATE TABLE audit_inscription (
    id_audit          NUMBER(12) GENERATED ALWAYS AS IDENTITY,
    date_action       TIMESTAMP          DEFAULT SYSTIMESTAMP
                                         CONSTRAINT nn_audit_date        NOT NULL,
    utilisateur       VARCHAR2(128 CHAR) CONSTRAINT nn_audit_utilisateur NOT NULL,
    action            VARCHAR2(6 CHAR)   CONSTRAINT nn_audit_action      NOT NULL,
    id_inscription    NUMBER(10)         CONSTRAINT nn_audit_inscription NOT NULL,
    id_etudiant       NUMBER(8),
    id_session        NUMBER(8),
    id_groupe         VARCHAR2(10 CHAR),
    ancien_statut     VARCHAR2(10 CHAR),
    nouveau_statut    VARCHAR2(10 CHAR),
    ancien_nb_places  NUMBER(3),
    nouveau_nb_places NUMBER(3),
    ancien_montant    NUMBER(9,2),
    nouveau_montant   NUMBER(9,2),
    CONSTRAINT pk_audit_inscription PRIMARY KEY (id_audit),
    CONSTRAINT ck_audit_action      CHECK (action IN ('INSERT', 'UPDATE', 'DELETE'))
);

COMMENT ON TABLE audit_inscription IS 'L4 : journal d''audit des opérations (INSCRIPTION), rempli par trg_inscription_audit.';

CREATE OR REPLACE TRIGGER trg_inscription_audit
AFTER INSERT OR UPDATE OR DELETE ON inscription
FOR EACH ROW
DECLARE
    v_action audit_inscription.action%TYPE;
BEGIN
    v_action := CASE WHEN INSERTING THEN 'INSERT' WHEN UPDATING THEN 'UPDATE' ELSE 'DELETE' END;

    INSERT INTO audit_inscription (
        utilisateur, action, id_inscription, id_etudiant, id_session, id_groupe,
        ancien_statut, nouveau_statut, ancien_nb_places, nouveau_nb_places,
        ancien_montant, nouveau_montant)
    VALUES (
        SYS_CONTEXT('USERENV', 'SESSION_USER'), v_action,
        NVL(:NEW.id_inscription, :OLD.id_inscription),
        NVL(:NEW.id_etudiant,    :OLD.id_etudiant),
        NVL(:NEW.id_session,     :OLD.id_session),
        NVL(:NEW.id_groupe,      :OLD.id_groupe),
        :OLD.statut,    :NEW.statut,             -- :OLD est vide pour un INSERT,
        :OLD.nb_places, :NEW.nb_places,          -- :NEW est vide pour un DELETE
        :OLD.montant,   :NEW.montant);
END;
/


-- ---------------------------------------------------------------------
-- 2. Règles d'une inscription qui ne portent que sur la ligne et ses parents
--    RG12 : le montant est calculé (nb_places x prix de la session) ; une valeur fournie
--           par l'appelant est remplacée. Même principe que id_site au L3.
--    RG11 : une opération passée après le début de la session n'est pas valide : refusée.
--    RG14 : une inscription ne peut pas précéder la création du compte de l'étudiant.
--           Le compte est daté au jour près : une inscription le même jour est acceptée.
--    Ne se déclenche pas sur un simple changement de statut (annulation) : les lignes
--    historiques peuvent donc être annulées sans être revérifiées.
--    FOLLOWS : passe après TRG_INSCRIPTION_SITE, qui refuse déjà une session inexistante.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_inscription_regles
BEFORE INSERT OR UPDATE OF id_session, id_etudiant, nb_places, montant, date_operation
ON inscription
FOR EACH ROW
FOLLOWS trg_inscription_site
DECLARE
    v_prix      session_cours.prix_unitaire%TYPE;
    v_debut     session_cours.debut%TYPE;
    v_creation  etudiant.date_inscription%TYPE;
BEGIN
    SELECT prix_unitaire, debut INTO v_prix, v_debut
    FROM   session_cours
    WHERE  id_session = :NEW.id_session;

    -- RG12
    :NEW.montant := :NEW.nb_places * v_prix;

    -- RG11 (définition d'une opération valide)
    IF :NEW.date_operation > v_debut THEN
        RAISE_APPLICATION_ERROR(-20003,
            'Inscription du ' || TO_CHAR(:NEW.date_operation, 'DD/MM/YYYY HH24:MI')
            || ' après le début de la session ' || :NEW.id_session
            || ' (' || TO_CHAR(v_debut, 'DD/MM/YYYY HH24:MI') || ') : refusée (RG11)');
    END IF;

    -- RG14
    IF INSERTING OR UPDATING('date_operation') OR UPDATING('id_etudiant') THEN
        -- MAX renvoie NULL au lieu de NO_DATA_FOUND : un étudiant inexistant est
        -- refusé ensuite par la clé étrangère fk_inscription_etudiant.
        SELECT MAX(date_inscription) INTO v_creation
        FROM   etudiant
        WHERE  id_etudiant = :NEW.id_etudiant;

        IF TRUNC(:NEW.date_operation) < v_creation THEN
            RAISE_APPLICATION_ERROR(-20002,
                'Inscription du ' || TO_CHAR(:NEW.date_operation, 'DD/MM/YYYY')
                || ' antérieure à la création du compte de l''étudiant ' || :NEW.id_etudiant
                || ' (' || TO_CHAR(v_creation, 'DD/MM/YYYY') || ') : refusée (RG14)');
        END IF;
    END IF;
END;
/


-- ---------------------------------------------------------------------
-- 3. RG13 : un étudiant n'a qu'une inscription confirmée par session
--    La règle porte sur plusieurs lignes d'INSCRIPTION. Un trigger ligne ne peut pas lire
--    la table qu'il modifie (ORA-04091, table en mutation) dès qu'un ordre touche plusieurs
--    lignes. D'où un trigger composé : chaque ligne note son couple (étudiant, session),
--    et la vérification se fait une fois l'ordre terminé (AFTER STATEMENT).
--    Pas d'index unique : les 154 couples historiques en double l'empêcheraient.
--    Seuls les couples touchés par l'ordre sont vérifiés : l'historique n'est pas relu.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_inscription_doublon
FOR INSERT OR UPDATE OF statut, id_etudiant, id_session ON inscription
COMPOUND TRIGGER

    TYPE t_couple  IS RECORD (id_etudiant NUMBER(8), id_session NUMBER(8));
    TYPE t_couples IS TABLE OF t_couple;
    g_couples t_couples := t_couples();

    AFTER EACH ROW IS
    BEGIN
        IF :NEW.statut = 'CONFIRMEE' THEN
            g_couples.EXTEND;
            g_couples(g_couples.LAST).id_etudiant := :NEW.id_etudiant;
            g_couples(g_couples.LAST).id_session  := :NEW.id_session;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_nb NUMBER;
    BEGIN
        FOR k IN 1 .. g_couples.COUNT LOOP
            SELECT COUNT(*) INTO v_nb
            FROM   inscription
            WHERE  id_etudiant = g_couples(k).id_etudiant
            AND    id_session  = g_couples(k).id_session
            AND    statut      = 'CONFIRMEE';

            IF v_nb > 1 THEN
                RAISE_APPLICATION_ERROR(-20004,
                    'L''étudiant ' || g_couples(k).id_etudiant
                    || ' est déjà inscrit en confirmé à la session '
                    || g_couples(k).id_session || ' : refusé (RG13)');
            END IF;
        END LOOP;
    END AFTER STATEMENT;

END trg_inscription_doublon;
/


-- ---------------------------------------------------------------------
-- 4. RG7 : le parrain a un compte strictement plus ancien que son filleul
--    Même raison que pour RG13 (le parrain est dans la même table ETUDIANT) : trigger composé.
--    On vérifie l'étudiant modifié comme filleul (son parrain) et comme parrain (ses
--    filleuls), car changer la date de création d'un parrain peut casser la règle.
--    Le CHECK ck_etudiant_pas_son_parrain (L1) refuse déjà d'être son propre parrain.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_etudiant_parrain
FOR INSERT OR UPDATE OF id_parrain, date_inscription ON etudiant
COMPOUND TRIGGER

    TYPE t_ids IS TABLE OF NUMBER(8);
    g_ids t_ids := t_ids();

    AFTER EACH ROW IS
    BEGIN
        g_ids.EXTEND;
        g_ids(g_ids.LAST) := :NEW.id_etudiant;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_filleul NUMBER(8);
        v_parrain NUMBER(8);
    BEGIN
        FOR k IN 1 .. g_ids.COUNT LOOP
            SELECT MIN(f.id_etudiant), MIN(p.id_etudiant) INTO v_filleul, v_parrain
            FROM   etudiant f
            JOIN   etudiant p ON p.id_etudiant = f.id_parrain
            WHERE  (f.id_etudiant = g_ids(k) OR p.id_etudiant = g_ids(k))
            AND    p.date_inscription >= f.date_inscription;

            IF v_filleul IS NOT NULL THEN
                RAISE_APPLICATION_ERROR(-20005,
                    'Le parrain ' || v_parrain || ' n''a pas un compte plus ancien que son filleul '
                    || v_filleul || ' : refusé (RG7)');
            END IF;
        END LOOP;
    END AFTER STATEMENT;

END trg_etudiant_parrain;
/


-- Contrôle : les 5 triggers du schéma (1 du L3, 4 du L4) sont compilés et actifs
COLUMN trigger_name FORMAT A25
COLUMN table_name   FORMAT A15
COLUMN trigger_type FORMAT A20
SELECT t.trigger_name, t.table_name, t.trigger_type, t.status, o.status AS compilation
FROM   user_triggers t
JOIN   user_objects  o ON o.object_name = t.trigger_name AND o.object_type = 'TRIGGER'
ORDER BY t.table_name, t.trigger_name;
-- Résultat attendu : 5 lignes, ENABLED et VALID
