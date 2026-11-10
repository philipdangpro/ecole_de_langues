-- =====================================================================
-- L7_oracle_comparaison.sql : la même recherche faite par Oracle
-- Livrable : L7 · NoSQL (moteur 1 : Elasticsearch)
-- Responsable : Baptiste (avec Claude Code)
--
-- À lancer en langues (après run_all.sql). Donne la mesure qui justifie le moteur :
-- ce que l'accueil obtient d'Oracle quand le nom est mal tapé, et le nombre exact de
-- bonnes réponses, que L7_recherche.sh doit retrouver.
-- =====================================================================
SET PAGESIZE 100
SET LINESIZE 120

-- 1. Les homonymes : 50 noms et 40 prénoms pour 21 471 étudiants. Un nom seul ne
--    désigne presque personne : il faut combiner nom, prénom et site.
SELECT COUNT(DISTINCT nom) AS noms, COUNT(DISTINCT prenom) AS prenoms, COUNT(*) AS etudiants
FROM   etudiant;

SELECT COUNT(*) AS paires_nom_prenom, MAX(n) AS max_homonymes, ROUND(AVG(n), 1) AS moyenne
FROM  (SELECT nom, prenom, COUNT(*) AS n FROM etudiant GROUP BY nom, prenom);
-- Résultat attendu : 50, 40, 21 471 ; 2 000 paires, jusqu'à 23 homonymes, 10,7 en moyenne

-- 2. L'accueil cherche « Léo Bertrand » mais tape « Betrand » et « Leo » (une lettre
--    oubliée, pas d'accent), comme cela arrive au téléphone
SELECT COUNT(*) AS egalite      FROM etudiant WHERE nom = 'Betrand' AND prenom = 'Leo';
SELECT COUNT(*) AS like_partiel FROM etudiant WHERE UPPER(nom) LIKE '%BETRAND%'
                                              AND UPPER(prenom) LIKE '%LEO%';
-- Résultat attendu : 0 et 0. Oracle compare des caractères : une faute, et il ne trouve rien.

-- 3. Les bonnes réponses, avec l'orthographe exacte (ce qu'Elasticsearch doit retrouver)
SELECT COUNT(*) AS leo_bertrand,
       SUM(CASE WHEN id_campus = 3 THEN 1 ELSE 0 END) AS dont_site_tours
FROM   etudiant
WHERE  nom = 'Bertrand' AND prenom = 'Léo';
SELECT COUNT(*) AS lea_bertrand FROM etudiant WHERE nom = 'Bertrand' AND prenom = 'Léa';
-- Résultat attendu : 15 Léo Bertrand, dont 5 au site de Tours ; 11 Léa Bertrand
-- (« Leo » et « Léa » ne diffèrent que d'une lettre)

-- 4. Pour l'ADR-02 : la même recherche tolérante aux fautes, dans Oracle seul
--    (distance entre mots, UTL_MATCH : 2 fautes sur le nom, 1 sur le prénom sans accent)
SET TIMING ON
SELECT COUNT(*) AS total,
       SUM(CASE WHEN nom = 'Bertrand' AND prenom = 'Léo' THEN 1 ELSE 0 END) AS bons
FROM   etudiant
WHERE  UTL_MATCH.EDIT_DISTANCE(UPPER(nom), 'BETRAND') <= 2
AND    UTL_MATCH.EDIT_DISTANCE(UPPER(CONVERT(prenom, 'US7ASCII')), 'LEO') <= 1;
SET TIMING OFF
-- Résultat mesuré : 49 lignes, dont les 15 Léo Bertrand, en 0,08 s, sans classement.
-- Plan : TABLE ACCESS FULL (aucun index possible sur une distance).

-- 5. Pour l'ADR-02 : recherche phonétique (SOUNDEX, indexable)
SELECT SOUNDEX('Betrand') AS faute, SOUNDEX('Bertrand') AS exact FROM dual;
SELECT COUNT(*) AS soundex_trouves FROM etudiant
WHERE  SOUNDEX(nom) = SOUNDEX('Betrand') AND SOUNDEX(prenom) = SOUNDEX('Leo');
-- Résultat mesuré : B365 et B636, donc 0 ligne. La lettre oubliée change le code.
EXIT
