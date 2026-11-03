-- =====================================================================
-- 04_requetes_metier.sql
-- Livrable : L2 · Requêtes
-- Responsable : à définir
-- Attendu  : 10 requêtes métier (énoncé + résultat) : jointure externe, HAVING, sous-requête corrélée, division, fenêtrage
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
-- =====================================================================

-- ============================================================
-- R1 : Nombre d'inscriptions confirmees valides par categorie
-- ============================================================

SELECT c.libelle AS categorie,
       COUNT(*) AS nombre_inscriptions
FROM inscription i
JOIN session_cours s ON s.id_session = i.id_session
JOIN categorie c ON c.id_categorie = s.id_categorie
WHERE i.statut = 'CONFIRMEE'
  AND i.montant >= 0
  AND i.date_operation <= s.debut
GROUP BY c.libelle
ORDER BY c.libelle;


-- ============================================================
-- R2 : Etudiants ayant au moins 3 inscriptions valides
-- Notion : GROUP BY et HAVING
-- ============================================================

SELECT i.id_etudiant,
       COUNT(*) AS nombre_inscriptions
FROM inscription i
JOIN session_cours s ON s.id_session = i.id_session
WHERE i.montant >= 0
  AND i.date_operation <= s.debut
GROUP BY i.id_etudiant
HAVING COUNT(*) >= 3
ORDER BY nombre_inscriptions DESC;


-- ============================================================
-- R3 : Etudiants n'ayant aucune inscription
-- Notion : jointure externe LEFT JOIN
-- ============================================================

SELECT e.id_etudiant
FROM etudiant e
LEFT JOIN inscription i
       ON i.id_etudiant = e.id_etudiant
WHERE i.id_etudiant IS NULL
ORDER BY e.id_etudiant;


-- ============================================================
-- R4 : Sessions dont les places confirmees depassent
--       la moyenne des sessions de leur categorie
-- Notion : sous-requete correlee
-- ============================================================



SELECT x.id_session,
       x.categorie,
       x.places_confirmees
FROM (
    SELECT s.id_session,
           s.id_categorie,
           c.libelle AS categorie,
           SUM(i.nb_places) AS places_confirmees
    FROM session_cours s
    JOIN categorie c
        ON c.id_categorie = s.id_categorie
    JOIN inscription i
        ON i.id_session = s.id_session
    WHERE i.statut = 'CONFIRMEE'
      AND i.montant >= 0
      AND i.date_operation <= s.debut
    GROUP BY s.id_session, s.id_categorie, c.libelle
) x
WHERE x.places_confirmees > (
    SELECT AVG(y.places_confirmees)
    FROM (
        SELECT s2.id_session,
               s2.id_categorie,
               SUM(i2.nb_places) AS places_confirmees
        FROM session_cours s2
        JOIN inscription i2
            ON i2.id_session = s2.id_session
        WHERE i2.statut = 'CONFIRMEE'
          AND i2.montant >= 0
          AND i2.date_operation <= s2.debut
        GROUP BY s2.id_session, s2.id_categorie
    ) y
    WHERE y.id_categorie = x.id_categorie
)
ORDER BY x.categorie, x.places_confirmees DESC;



-- ============================================================
-- R5 : Etudiants ayant une inscription valide dans toutes
--       les categories
-- Notion : division relationnelle avec double NOT EXISTS
-- ============================================================

SELECT e.id_etudiant
FROM etudiant e
WHERE NOT EXISTS (
    SELECT 1
    FROM categorie c
    WHERE NOT EXISTS (
        SELECT 1
        FROM inscription i
        JOIN session_cours s ON s.id_session = i.id_session
        WHERE i.id_etudiant = e.id_etudiant
          AND s.id_categorie = c.id_categorie
          AND i.montant >= 0
          AND i.date_operation <= s.debut
    )
)
ORDER BY e.id_etudiant;


-- ============================================================
-- R6 : Classement des sessions par places confirmees
--       au sein de chaque categorie
-- Notion : fonction de fenetrage RANK()
-- ============================================================

SELECT id_session,
       categorie,
       places_confirmees,
       RANK() OVER (
           PARTITION BY categorie
           ORDER BY places_confirmees DESC
       ) AS rang_session
FROM (
    SELECT s.id_session,
           c.libelle AS categorie,
           SUM(i.nb_places) AS places_confirmees
    FROM session_cours s
    JOIN categorie c ON c.id_categorie = s.id_categorie
    JOIN inscription i ON i.id_session = s.id_session
    WHERE i.statut = 'CONFIRMEE'
      AND i.montant >= 0
      AND i.date_operation <= s.debut
    GROUP BY s.id_session, c.libelle
)
ORDER BY categorie, rang_session;


-- ============================================================
-- R7 : Nombre de places confirmees par campus
-- ============================================================

SELECT ca.id_campus,
       SUM(i.nb_places) AS places_confirmees
FROM campus ca
JOIN session_cours s ON s.id_campus = ca.id_campus
JOIN inscription i ON i.id_session = s.id_session
WHERE i.statut = 'CONFIRMEE'
  AND i.montant >= 0
  AND i.date_operation <= s.debut
GROUP BY ca.id_campus
ORDER BY places_confirmees DESC;


-- ============================================================
-- R8 : Montant total des inscriptions valides par etudiant
-- ============================================================

SELECT i.id_etudiant,
       SUM(i.montant) AS montant_total
FROM inscription i
JOIN session_cours s ON s.id_session = i.id_session
WHERE i.montant >= 0
  AND i.date_operation <= s.debut
GROUP BY i.id_etudiant
ORDER BY montant_total DESC;


-- ============================================================
-- R9 : Categories classees par nombre de places confirmees
-- Notion : fonction de fenetrage DENSE_RANK()
-- ============================================================

SELECT c.libelle AS categorie,
       SUM(i.nb_places) AS places_confirmees,
       DENSE_RANK() OVER (
           ORDER BY SUM(i.nb_places) DESC
       ) AS rang_categorie
FROM categorie c
JOIN session_cours s ON s.id_categorie = c.id_categorie
JOIN inscription i ON i.id_session = s.id_session
WHERE i.statut = 'CONFIRMEE'
  AND i.montant >= 0
  AND i.date_operation <= s.debut
GROUP BY c.libelle
ORDER BY rang_categorie, c.libelle;


-- ============================================================
-- R10 : Top 3 des sessions par nombre de places confirmees
--        pour chaque categorie
-- Notion : fonction de fenetrage ROW_NUMBER()
-- ============================================================

SELECT id_session,
       categorie,
       places_confirmees,
       rang
FROM (
    SELECT s.id_session,
           c.libelle AS categorie,
           SUM(i.nb_places) AS places_confirmees,
           ROW_NUMBER() OVER (
               PARTITION BY c.libelle
               ORDER BY SUM(i.nb_places) DESC, s.id_session
           ) AS rang
    FROM session_cours s
    JOIN categorie c ON c.id_categorie = s.id_categorie
    JOIN inscription i ON i.id_session = s.id_session
    WHERE i.statut = 'CONFIRMEE'
      AND i.montant >= 0
      AND i.date_operation <= s.debut
    GROUP BY s.id_session, c.libelle
)
WHERE rang <= 3
ORDER BY categorie, rang;