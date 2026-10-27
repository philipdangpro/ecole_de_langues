-- =====================================================================
-- 03_valeurs_controle.sql
-- Livrable : L2 · Valeurs de contrôle
-- Responsable : à définir
-- Attendu  : une requête par valeur C1 à C9, avec le résultat obtenu en commentaire
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Rappel : INSCRIPTION ne contient que les opérations valides (les autres sont dans
-- INSCRIPTION_REJET, voir 02_chargement.sql). Pas besoin de refiltrer pour C3 à C9.
-- =====================================================================


-- ---------------------------------------------------------------------
-- C1 : nombre de personnes distinctes
--    Les doublons (même e-mail une fois en minuscules et sans espaces) ont été fusionnés
--    au chargement : une ligne d'ETUDIANT = une personne.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS c1
FROM etudiant;
-- Résultat : 21 471

-- Vérification sur le CSV brut (table externe, avant fusion), avec la règle du sujet :
--   e-mails distincts une fois normalisés + lignes sans e-mail (une personne chacune).
--   COUNT(*) - COUNT(email) = nombre de lignes sans e-mail (COUNT(email) ignore les NULL).
SELECT COUNT(*) AS lignes_csv,
       COUNT(DISTINCT LOWER(REPLACE(email, ' ', ''))) + COUNT(*) - COUNT(email) AS c1
FROM ext_etudiants;
-- Résultat : 21 544 lignes, 21 471 personnes (identique à C1 : la fusion est juste)


-- ---------------------------------------------------------------------
-- C4 : le jour où le plus d'opérations valides ont été passées, et leur nombre
--    Toutes les opérations valides comptent (confirmées et annulées).
--    TRUNC enlève l'heure de date_operation pour regrouper par jour.
-- ---------------------------------------------------------------------
SELECT TRUNC(date_operation) AS jour, COUNT(*) AS cpt
FROM inscription
GROUP BY TRUNC(date_operation)
ORDER BY cpt DESC
FETCH FIRST 1 ROWS ONLY;
-- Résultat : 10/09/2026, 16 068 opérations
--   Pas d'égalité : le jour suivant au classement en a 552. Le pic vient du CSV
--   (16 082 lignes ce jour-là, dont 14 non valides), heures réparties sur toute la journée.


-- ---------------------------------------------------------------------
-- C7 : nombre de sessions en sur-réservation
--    Pour chaque session : somme des places des inscriptions confirmées, comparée à sa
--    capacité (HAVING filtre après le regroupement). On compte ensuite ces sessions.
--    SUM(nb_places) et pas COUNT(*) : une inscription peut réserver plusieurs places
--    (dans ce jeu de données elles valent toutes 1, d'où le même résultat).
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS c7
FROM (
    SELECT i.id_session
    FROM inscription i
    JOIN session_cours s ON i.id_session = s.id_session
    WHERE i.statut = 'CONFIRMEE'
    GROUP BY i.id_session, s.capacite
    HAVING SUM(i.nb_places) > s.capacite
);
-- Résultat : 15 sessions (même chiffre avec la vue V_SESSION_OCCUPATION du L1)

