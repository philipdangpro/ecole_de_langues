-- =====================================================================
-- L4 · Anomalie de concurrence : SESSION B
-- Responsable : Baptiste (avec Claude Code)
-- À lancer à la main, en même temps que L4_concurrence_session_A.sql,
-- dans deux connexions différentes. N'est PAS lancé par run_all.sql.
-- Mode d'emploi et explication : en-tête de L4_concurrence_session_A.sql.
-- Dans SQL Developer, ouvrir ce fichier dans une feuille NON PARTAGÉE (Ctrl+Maj+N).
-- Commencer par l'étape 0 dans A.
-- =====================================================================


-- =====================================================================
-- PARTIE 1 : L'ANOMALIE
-- =====================================================================

-- ÉTAPE 2 (B) : B regarde les places libres. A s'apprête à s'inscrire mais n'a rien validé.
SELECT pkg_parcours.places_restantes(900001) AS places_libres_vues_par_B FROM dual;
-- Résultat : 1

-- ÉTAPE 4 (B) : B s'inscrit et valide. Rien ne l'en empêche : l'inscription de A n'est
-- pas encore validée, B ne la voit pas, et les deux INSERT touchent des lignes différentes.
INSERT INTO inscription (id_inscription, id_etudiant, id_session, date_operation, nb_places, montant, statut)
VALUES (seq_inscription.NEXTVAL, 2, 900001, DATE '2027-01-10', 1, NULL, 'CONFIRMEE');
COMMIT;
-- Résultat : 1 row inserted, Commit complete

-- (ÉTAPES 5 et 6 : dans A)


-- =====================================================================
-- PARTIE 2 : LA CORRECTION
-- =====================================================================
VARIABLE g VARCHAR2(10)

-- ÉTAPE 8 (B) : B demande un parcours sur les mêmes sessions.
-- B se bloque sur le SELECT ... FOR UPDATE du package : A tient le verrou.
EXEC pkg_parcours.inscrire_parcours(2, t_liste_sessions(900001, 900002), p_date_operation => DATE '2027-01-10', p_id_groupe => :g)
-- Résultat, dès que A fait COMMIT (étape 9) :
--   ORA-20010: Session 900001 : 0 place(s) libre(s) sur 1, 1 demandée(s) : parcours refusé,
--   aucune inscription gardée (RG15)

-- ÉTAPE 10 (B) : B n'a rien gardé, pas même la session 900002 qui avait de la place
ROLLBACK;
SELECT COUNT(*) AS inscriptions_de_B FROM inscription
WHERE  id_session IN (900001, 900002) AND id_etudiant = 2;
-- Résultat : 0

-- (ÉTAPES 11 et 12 : dans A)
