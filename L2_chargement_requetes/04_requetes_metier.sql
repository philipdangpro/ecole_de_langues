-- =====================================================================
-- 04_requetes_metier.sql
-- Livrable : L2 · Requêtes métier
-- Responsable : Philip (requêtes), Baptiste (sorties bornées et résultats)
-- Attendu  : 10 requêtes métier (énoncé + résultat) : jointure externe, HAVING,
--            sous-requête corrélée, division, fenêtrage
-- Lancé par : prerequis/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Rappel : INSCRIPTION ne contient que les opérations valides (les non valides sont
-- dans INSCRIPTION_REJET, voir 02_chargement.sql) : pas besoin de refiltrer ici.
-- Les requêtes qui portent sur des milliers de lignes affichent un total et les
-- 10 premières lignes (FETCH FIRST), pour que run_all.log reste lisible.
--
-- | Requête | Notion exigée                     |
-- | R2      | HAVING                            |
-- | R3      | jointure externe (LEFT JOIN)      |
-- | R4      | sous-requête corrélée             |
-- | R5      | division (double NOT EXISTS)      |
-- | R6, R9, R10 | fonctions de fenêtrage        |
-- =====================================================================
SET PAGESIZE 100
SET LINESIZE 160
COLUMN categorie FORMAT A12
COLUMN site      FORMAT A16


-- ============================================================
-- R1 : Taux d'annulation par langue
--      (quelles langues perdent le plus d'inscrits avant le cours ?)
-- ============================================================
SELECT c.libelle AS categorie,
       COUNT(*) AS inscriptions,
       SUM(CASE WHEN i.statut = 'ANNULEE' THEN 1 ELSE 0 END) AS annulees,
       ROUND(100 * AVG(CASE WHEN i.statut = 'ANNULEE' THEN 1 ELSE 0 END), 2) AS pct_annulation
FROM inscription i
JOIN session_cours s ON s.id_session = i.id_session
JOIN categorie c     ON c.id_categorie = s.id_categorie
GROUP BY c.libelle
ORDER BY pct_annulation DESC;
-- Résultat (6 lignes) : italien 8,05 % (4 774 / 59 304) ; allemand 7,95 % ; espagnol 7,89 % ;
--   FLE 7,86 % ; anglais 7,83 % ; chinois 7,80 %. Écart faible : aucune langue à part.


-- ============================================================
-- R2 : Étudiants les plus fidèles : au moins 30 inscriptions confirmées
-- Notion : GROUP BY et HAVING
-- ============================================================
SELECT i.id_etudiant,
       COUNT(*) AS inscriptions_confirmees
FROM inscription i
WHERE i.statut = 'CONFIRMEE'
GROUP BY i.id_etudiant
HAVING COUNT(*) >= 30
ORDER BY inscriptions_confirmees DESC, i.id_etudiant
FETCH FIRST 10 ROWS ONLY;
-- Résultat (10 premières) : 19039 et 19165 (34), 12856 et 18494 (33),
--   905, 5171, 5461, 19566 (32), 2197, 3019 (31)


-- ============================================================
-- R3 : Sessions qui n'ont aucun inscrit confirmé, par site
--      (créneaux ouverts pour rien : à fermer ou à regrouper)
-- Notion : jointure externe LEFT JOIN depuis SESSION_COURS : une session sans
--          inscription confirmée garde une ligne, avec id_inscription à NULL.
--          (Le même test depuis ETUDIANT ne donne aucune ligne : tous les
--          étudiants ont au moins une inscription.)
-- ============================================================
SELECT ca.nom AS site,
       COUNT(*) AS sessions_sans_inscrit
FROM session_cours s
JOIN campus ca          ON ca.id_campus  = s.id_campus
LEFT JOIN inscription i ON i.id_session  = s.id_session
                       AND i.statut      = 'CONFIRMEE'
WHERE i.id_inscription IS NULL
GROUP BY ca.nom
ORDER BY ca.nom;
-- Résultat : Angers 1, Bordeaux 2, Tours 1 (4 sessions sur 47 619)


-- ============================================================
-- R4 : Sessions mieux remplies que la moyenne des sessions de leur langue
--      (nombre de sessions concernées par langue)
-- Notion : sous-requête corrélée (la moyenne est recalculée pour la langue
--          de la ligne courante : o2.id_categorie = o.id_categorie)
-- ============================================================
WITH occupation AS (
    SELECT s.id_session, s.id_categorie, SUM(i.nb_places) AS places_confirmees
    FROM session_cours s
    JOIN inscription i ON i.id_session = s.id_session
    WHERE i.statut = 'CONFIRMEE'
    GROUP BY s.id_session, s.id_categorie
)
SELECT c.libelle AS categorie,
       COUNT(*)  AS sessions_au_dessus_moyenne
FROM occupation o
JOIN categorie c ON c.id_categorie = o.id_categorie
WHERE o.places_confirmees > (SELECT AVG(o2.places_confirmees)
                             FROM occupation o2
                             WHERE o2.id_categorie = o.id_categorie)
GROUP BY c.libelle
ORDER BY c.libelle;
-- Résultat : FLE 4 058, allemand 3 879, anglais 4 084, chinois 3 991,
--   espagnol 3 950, italien 3 978 sessions au-dessus de la moyenne de leur langue


-- ============================================================
-- R5 : Étudiants ayant suivi TOUTES les langues proposées
--      (une inscription confirmée dans chaque catégorie)
-- Notion : division relationnelle, double NOT EXISTS : « il n'existe pas de
--          langue pour laquelle il n'existe pas d'inscription de l'étudiant »
-- Écriture : la forme d'école (NOT EXISTS sur CATEGORIE corrélé deux fois à e) a été
--   arrêtée après 5 min : à ce stade il n'y a pas encore d'index sur
--   INSCRIPTION(id_etudiant) (créé au L5), et Oracle relisait INSCRIPTION pour chaque
--   couple étudiant × langue. Ici les couples (étudiant, langue) manquants sont
--   construits dans un seul bloc (produit ETUDIANT × CATEGORIE), ce qui permet une
--   anti-jointure par hachage : 0,15 s. Même résultat que la division par comptage
--   (HAVING COUNT(DISTINCT id_categorie) = nombre de langues).
-- ============================================================
SELECT COUNT(*) AS etudiants_toutes_langues
FROM etudiant e
WHERE NOT EXISTS (
    SELECT 1
    FROM etudiant e2 CROSS JOIN categorie c
    WHERE e2.id_etudiant = e.id_etudiant
      AND NOT EXISTS (
          SELECT 1
          FROM inscription i
          JOIN session_cours s ON s.id_session = i.id_session
          WHERE i.id_etudiant  = e2.id_etudiant
            AND s.id_categorie = c.id_categorie
            AND i.statut       = 'CONFIRMEE'
      )
);
-- Résultat : 12 985 étudiants (sur 21 471) ont suivi les 6 langues


-- ============================================================
-- R6 : Chiffre d'affaires mensuel et cumul de l'année (pic de la rentrée)
-- Notion : fonction de fenêtrage SUM() OVER (ORDER BY …) : cumul glissant
-- ============================================================
SELECT TO_CHAR(TRUNC(i.date_operation, 'MM'), 'YYYY-MM') AS mois,
       COUNT(*)       AS inscriptions,
       SUM(i.montant) AS ca_mois,
       SUM(SUM(i.montant)) OVER (ORDER BY TRUNC(i.date_operation, 'MM')) AS ca_cumule
FROM inscription i
WHERE i.statut = 'CONFIRMEE'
GROUP BY TRUNC(i.date_operation, 'MM')
ORDER BY TRUNC(i.date_operation, 'MM');
-- Résultat (26 mois, 2024-11 à 2026-12) : environ 13 500 inscriptions et 5,1 M€ par
--   mois, sauf 2026-09 : 23 641 inscriptions, 8 892 954 € (pic de la rentrée, dont
--   16 068 le 10/09 : voir C4). Cumul final 122 497 119 € = somme des C5.


-- ============================================================
-- R7 : Places confirmées et chiffre d'affaires par campus,
--      siège compris (0 : il n'a pas de sessions)
-- Notion : jointure externe depuis CAMPUS
-- ============================================================
SELECT ca.id_campus,
       ca.nom AS site,
       NVL(SUM(i.nb_places), 0) AS places_confirmees,
       NVL(SUM(i.montant), 0)   AS chiffre_affaires
FROM campus ca
LEFT JOIN session_cours s ON s.id_campus  = ca.id_campus
LEFT JOIN inscription i   ON i.id_session = s.id_session AND i.statut = 'CONFIRMEE'
GROUP BY ca.id_campus, ca.nom
ORDER BY ca.id_campus;
-- Résultat : Siège 0 / 0 ; Bordeaux 72 595 places, 27 333 192 € ;
--   Tours 149 658 places, 56 080 982 € ; Angers 104 216 places, 39 082 945 € (= C5)


-- ============================================================
-- R8 : Les 10 étudiants qui ont dépensé le plus (inscriptions confirmées)
-- ============================================================
SELECT i.id_etudiant,
       COUNT(*)       AS inscriptions,
       SUM(i.montant) AS montant_total
FROM inscription i
WHERE i.statut = 'CONFIRMEE'
GROUP BY i.id_etudiant
ORDER BY montant_total DESC, i.id_etudiant
FETCH FIRST 10 ROWS ONLY;
-- Résultat (10 premiers) : 12856 (13 706 €), 19039 (13 000), 19165 (12 580),
--   862 (12 245), 19566 (12 192), 2197 (12 187), 20405 (12 078), 1654 (12 031),
--   13105 (12 027), 5940 (11 949)


-- ============================================================
-- R9 : Langues classées par nombre de places confirmées
-- Notion : fonction de fenêtrage DENSE_RANK()
-- ============================================================
SELECT c.libelle AS categorie,
       SUM(i.nb_places) AS places_confirmees,
       DENSE_RANK() OVER (ORDER BY SUM(i.nb_places) DESC) AS rang_categorie
FROM categorie c
JOIN session_cours s ON s.id_categorie = c.id_categorie
JOIN inscription i   ON i.id_session   = s.id_session
WHERE i.statut = 'CONFIRMEE'
GROUP BY c.libelle
ORDER BY rang_categorie, c.libelle;
-- Résultat : FLE 55 104 (1), anglais 54 870 (2), chinois 54 681 (3),
--   espagnol 54 579 (4), italien 54 530 (5), allemand 52 705 (6)


-- ============================================================
-- R10 : Top 3 des sessions par places confirmées, pour chaque langue
-- Notion : fonction de fenêtrage ROW_NUMBER() OVER (PARTITION BY …)
-- ============================================================
SELECT id_session, categorie, places_confirmees, rang
FROM (
    SELECT s.id_session,
           c.libelle AS categorie,
           SUM(i.nb_places) AS places_confirmees,
           ROW_NUMBER() OVER (PARTITION BY c.libelle
                              ORDER BY SUM(i.nb_places) DESC, s.id_session) AS rang
    FROM session_cours s
    JOIN categorie c   ON c.id_categorie = s.id_categorie
    JOIN inscription i ON i.id_session   = s.id_session
    WHERE i.statut = 'CONFIRMEE'
    GROUP BY s.id_session, c.libelle
)
WHERE rang <= 3
ORDER BY categorie, rang;
-- Résultat (18 lignes) : maximum 17 places (session 23879, espagnol) ; les autres
--   langues plafonnent à 16 (FLE 30448, allemand 2853, anglais 45833, chinois 18890)
--   ou 15 (italien 4886)

CLEAR COLUMNS
