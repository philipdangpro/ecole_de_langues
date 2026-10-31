-- =====================================================================
-- L4 · Anomalie de concurrence : SESSION A
-- Responsable : Baptiste (avec Claude Code)
-- À lancer à la main, en même temps que L4_concurrence_session_B.sql,
-- dans deux connexions différentes. N'est PAS lancé par run_all.sql.
--
-- Comment faire dans SQL Developer :
--   - ouvrir ce fichier sur la connexion langues ;
--   - ouvrir L4_concurrence_session_B.sql dans une feuille NON PARTAGÉE
--     (Ctrl+Maj+N, ou icône « Unshared SQL Worksheet ») : sinon les deux feuilles
--     utilisent la même session Oracle et il n'y a pas de concurrence ;
--   - exécuter les étapes une par une, dans l'ordre des numéros, en alternant A et B :
--     sélectionner le bloc de l'étape puis F5.
--   (Ou deux fenêtres sqlplus : copier-coller chaque étape.)
--
-- Le problème : deux étudiants veulent la DERNIÈRE place d'une session en même temps.
-- Chacun vérifie qu'il reste une place, puis s'inscrit. Les deux vérifications ont lieu
-- avant que l'une des deux inscriptions soit validée : chacune voit 1 place libre, les
-- deux inscriptions passent, la session est sur-réservée (2 places pour une capacité de 1).
-- C'est une « écriture biaisée » (write skew) : chaque transaction est correcte seule,
-- leur mélange viole la règle RG15.
--
-- Données : deux sessions créées pour le test (900001 capacité 1, 900002 capacité 10),
-- supprimées à la fin. Étudiant 1 dans la session A, étudiant 2 dans la session B.
-- =====================================================================


-- =====================================================================
-- ÉTAPE 0 (A) : préparation
-- =====================================================================
-- on efface les restes d'un essai précédent
DELETE FROM inscription   WHERE id_session IN (900001, 900002);
DELETE FROM session_cours WHERE id_session IN (900001, 900002);

INSERT INTO session_cours (id_session, libelle, id_categorie, id_campus, debut,
                           duree_minutes, capacite, prix_unitaire)
SELECT 900001, 'Test L4 concurrence (Bordeaux)', MIN(id_categorie), 2,
       TO_DATE('2027-01-15 10:00', 'YYYY-MM-DD HH24:MI'), 60, 1, 100
FROM   categorie;

INSERT INTO session_cours (id_session, libelle, id_categorie, id_campus, debut,
                           duree_minutes, capacite, prix_unitaire)
SELECT 900002, 'Test L4 concurrence (Tours)', MIN(id_categorie), 3,
       TO_DATE('2027-01-16 10:00', 'YYYY-MM-DD HH24:MI'), 60, 10, 100
FROM   categorie;

COMMIT;


-- =====================================================================
-- PARTIE 1 : L'ANOMALIE (vérifier, puis insérer, sans verrou)
-- C'est ce que ferait le package sans la ligne SELECT ... FOR UPDATE.
-- =====================================================================

-- ÉTAPE 1 (A) : A regarde les places libres
SELECT pkg_parcours.places_restantes(900001) AS places_libres_vues_par_A FROM dual;
-- Résultat : 1

-- (ÉTAPE 2 : dans B)

-- ÉTAPE 3 (A) : il reste une place, A s'inscrit (pas encore de COMMIT)
INSERT INTO inscription (id_inscription, id_etudiant, id_session, date_operation, nb_places, montant, statut)
VALUES (seq_inscription.NEXTVAL, 1, 900001, DATE '2027-01-10', 1, NULL, 'CONFIRMEE');
-- Résultat : 1 row inserted

-- (ÉTAPE 4 : dans B)

-- ÉTAPE 5 (A) : A valide, puis constate le résultat
COMMIT;

SELECT id_session, capacite, places_confirmees, sur_reservee
FROM   v_session_occupation
WHERE  id_session = 900001;
-- Résultat : capacité 1, 2 places confirmées, sur_reservee = 'O'  -> ANOMALIE

-- ÉTAPE 6 (A) : on efface la partie 1 avant de tester la correction
DELETE FROM inscription WHERE id_session IN (900001, 900002);
COMMIT;


-- =====================================================================
-- PARTIE 2 : LA CORRECTION (le package verrouille la session)
-- pkg_parcours.inscrire_parcours fait SELECT ... FROM session_cours ... FOR UPDATE
-- avant de compter les places. La deuxième transaction attend que la première se
-- termine, puis compte les places en voyant l'inscription validée par la première.
-- =====================================================================
VARIABLE g VARCHAR2(10)

-- ÉTAPE 7 (A) : A demande un parcours qui contient la session 900001 (pas encore de COMMIT)
EXEC pkg_parcours.inscrire_parcours(1, t_liste_sessions(900001, 900002), p_date_operation => DATE '2027-01-10', p_id_groupe => :g)
PRINT g
-- Résultat : parcours accepté (G0xxxx). A tient maintenant le verrou des deux sessions.

-- (ÉTAPE 8 : dans B. B reste bloqué : « en cours d'exécution » sans fin.)

-- ÉTAPE 9 (A) : A valide. Aussitôt, B se débloque et reçoit son refus.
COMMIT;

-- (ÉTAPE 10 : dans B)

-- ÉTAPE 11 (A) : bilan
SELECT id_session, capacite, places_confirmees, sur_reservee
FROM   v_session_occupation
WHERE  id_session IN (900001, 900002)
ORDER BY id_session;
-- Résultat : 900001 : 1 place sur 1, sur_reservee = 'N' ; 900002 : 1 place sur 10

-- Ce que dit le journal d'audit (parties 1 et 2) :
SELECT id_audit, utilisateur, action, id_inscription, id_session, id_etudiant, id_groupe, nouveau_statut
FROM   audit_inscription
WHERE  id_session IN (900001, 900002)
ORDER BY id_audit;

-- ÉTAPE 12 (A) : nettoyage (l'audit garde la trace des suppressions)
DELETE FROM inscription   WHERE id_session IN (900001, 900002);
DELETE FROM session_cours WHERE id_session IN (900001, 900002);
COMMIT;
