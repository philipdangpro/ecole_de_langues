-- =====================================================================
-- 03_valeurs_controle.sql
-- Livrable : L2 · Valeurs de contrôle
-- Responsable : à définir
-- Attendu  : une requête par valeur C1 à C9, avec le résultat obtenu en commentaire
-- Lancé par : prerequis/run_all.sql (ne pas changer l'ordre sans prévenir)
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
-- C2 : nombre d'opérations non valides, et leur répartition par motif
--    Les opérations non valides sont dans INSCRIPTION_REJET, avec leur motif
--    (02_chargement.sql). ROLLUP ajoute une ligne de total sous le détail par motif.
--    Chaque opération n'a qu'un motif : aucune n'a deux défauts à la fois (vérifié sur le CSV).
-- ---------------------------------------------------------------------
--    Alias différent du nom de colonne : sinon ORDER BY motif vise l'alias (ORA-00979).
SELECT NVL(motif, 'TOTAL (C2)') AS motif_rejet, COUNT(*) AS nb
FROM inscription_rejet
GROUP BY ROLLUP (motif)
ORDER BY GROUPING(motif), motif_rejet;
-- Résultat : DATE_APRES_DEBUT 97, MONTANT_NEGATIF 80, SESSION_INEXISTANTE 220
--            TOTAL 397 opérations non valides



-- ============================================================
-- C3 : nombre d'operations valides confirmees
-- ============================================================
SELECT COUNT(*) AS c3
FROM inscription i
JOIN session_cours s
  ON s.id_session = i.id_session
WHERE i.statut = 'CONFIRMEE'
  AND i.montant >= 0
  AND i.date_operation <= s.debut;

-- Resultat attendu : 326469





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
-- C5	chiffre d'affaires de chaque site (somme des montants des opérations valides confirmées)
--    Le site d'une opération est celui de sa session : on passe par SESSION_COURS
--    (la colonne INSCRIPTION.id_site n'existe qu'après 05_normalisation.sql).
-- ---------------------------------------------------------------------
SELECT s.id_campus AS id_site, c.nom AS site, SUM(i.montant) AS chiffre_affaires
FROM inscription i
JOIN session_cours s ON s.id_session = i.id_session
JOIN campus c        ON c.id_campus  = s.id_campus
WHERE i.statut = 'CONFIRMEE'
GROUP BY s.id_campus, c.nom
ORDER BY s.id_campus;
-- Résultat : Bordeaux (2) 27 333 192 ; Tours (3) 56 080 982 ; Angers (4) 39 082 945

-- ============================================================
-- C6 : personnes ayant des operations valides
--      sur au moins deux campus distincts
-- ============================================================
SELECT COUNT(*) AS c6
FROM (
    SELECT i.id_etudiant
    FROM inscription i
    JOIN session_cours s
      ON s.id_session = i.id_session
    WHERE i.montant >= 0
      AND i.date_operation <= s.debut
    GROUP BY i.id_etudiant
    HAVING COUNT(DISTINCT s.id_campus) >= 2
);

-- Resultat attendu : 12356


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

-------------------------------------------------------------------------
-- C8 nombre d'opérations groupées (même id_groupe) dont les opérations valides engagent au moins deux sites
--    Toutes les opérations valides comptent (confirmées et annulées), comme le dit la
--    définition. Le site vient de la session (id_site n'existe pas encore à cette étape).
-------------------------------------------------------------------------
SELECT COUNT(*) AS c8
FROM (
    SELECT i.id_groupe
    FROM inscription i
    JOIN session_cours s ON s.id_session = i.id_session
    WHERE i.id_groupe IS NOT NULL
    GROUP BY i.id_groupe
    HAVING COUNT(DISTINCT s.id_campus) >= 2
);
-- Résultat : 1 874 parcours multi-sites (sur 2 667 parcours)



-- ============================================================
-- C9 : nombre de places confirmees par categorie
-- ============================================================
SELECT 'C9' AS controle,
       c.libelle AS categorie,
       SUM(i.nb_places) AS places_confirmees
FROM inscription i
JOIN session_cours s
  ON s.id_session = i.id_session
JOIN categorie c
  ON c.id_categorie = s.id_categorie
WHERE i.statut = 'CONFIRMEE'
  AND i.montant >= 0
  AND i.date_operation <= s.debut
GROUP BY c.libelle
ORDER BY c.libelle;

-- Resultats attendus :
-- C9 | FLE      | 55104
-- C9 | allemand | 52705
-- C9 | anglais  | 54870
-- C9 | chinois  | 54681
-- C9 | espagnol | 54579
-- C9 | italien  | 54530
-- Total       : 326469


