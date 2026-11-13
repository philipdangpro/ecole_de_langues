-- =====================================================================
-- preuves/L3_denormalisation.sql
-- Preuves de la dénormalisation du L3 (INSCRIPTION.id_site). Hors run_all.sql.
-- À lancer en sqlplus, compte langues, APRÈS run_all.sql :
--   sqlplus langues/langues@//localhost:1521/FREEPDB1 @L3_denormalisation.sql
-- Résultat obtenu : preuves/L3_denormalisation.txt
--
-- 1. Mesures : blocs lus (consistent gets) avec la jointure vers SESSION_COURS, puis avec
--    la colonne recopiée. Chaque requête est lancée deux fois, on garde la 2e (cache chaud).
-- 2. Tests : le trigger corrige un site faux, refuse une session inexistante, et la clé
--    étrangère composite empêche de déplacer une session qui a des inscriptions.
--    Tout est annulé à la fin (ROLLBACK) : la base n'est pas modifiée.
-- =====================================================================
SET LINESIZE 150 PAGESIZE 100 FEEDBACK ON
SPOOL L3_denormalisation.txt

PROMPT ===== 1. Les deux versions donnent les mêmes résultats =====
PROMPT C5 avec jointure / avec id_site
SELECT s.id_campus AS site, SUM(i.montant) AS ca
FROM   inscription i JOIN session_cours s ON s.id_session = i.id_session
WHERE  i.statut = 'CONFIRMEE' GROUP BY s.id_campus ORDER BY 1;
SELECT id_site AS site, SUM(montant) AS ca
FROM   inscription WHERE statut = 'CONFIRMEE' GROUP BY id_site ORDER BY 1;

PROMPT C6 avec jointure / avec id_site
SELECT COUNT(*) AS c6 FROM (
    SELECT i.id_etudiant FROM inscription i JOIN session_cours s ON s.id_session = i.id_session
    GROUP BY i.id_etudiant HAVING COUNT(DISTINCT s.id_campus) >= 2);
SELECT COUNT(*) AS c6 FROM (
    SELECT id_etudiant FROM inscription GROUP BY id_etudiant HAVING COUNT(DISTINCT id_site) >= 2);

PROMPT C8 avec jointure / avec id_site
SELECT COUNT(*) AS c8 FROM (
    SELECT i.id_groupe FROM inscription i JOIN session_cours s ON s.id_session = i.id_session
    WHERE i.id_groupe IS NOT NULL GROUP BY i.id_groupe HAVING COUNT(DISTINCT s.id_campus) >= 2);
SELECT COUNT(*) AS c8 FROM (
    SELECT id_groupe FROM inscription
    WHERE id_groupe IS NOT NULL GROUP BY id_groupe HAVING COUNT(DISTINCT id_site) >= 2);

PROMPT ===== 2. Mesures (2e exécution de chaque requête) =====
SET AUTOTRACE TRACEONLY STATISTICS

PROMPT --- C5 avec jointure
SELECT s.id_campus, SUM(i.montant) FROM inscription i JOIN session_cours s ON s.id_session = i.id_session
WHERE i.statut = 'CONFIRMEE' GROUP BY s.id_campus;
SELECT s.id_campus, SUM(i.montant) FROM inscription i JOIN session_cours s ON s.id_session = i.id_session
WHERE i.statut = 'CONFIRMEE' GROUP BY s.id_campus;
PROMPT --- C5 avec id_site
SELECT id_site, SUM(montant) FROM inscription WHERE statut = 'CONFIRMEE' GROUP BY id_site;
SELECT id_site, SUM(montant) FROM inscription WHERE statut = 'CONFIRMEE' GROUP BY id_site;

PROMPT --- C6 avec jointure
SELECT COUNT(*) FROM (SELECT i.id_etudiant FROM inscription i JOIN session_cours s ON s.id_session = i.id_session
GROUP BY i.id_etudiant HAVING COUNT(DISTINCT s.id_campus) >= 2);
SELECT COUNT(*) FROM (SELECT i.id_etudiant FROM inscription i JOIN session_cours s ON s.id_session = i.id_session
GROUP BY i.id_etudiant HAVING COUNT(DISTINCT s.id_campus) >= 2);
PROMPT --- C6 avec id_site
SELECT COUNT(*) FROM (SELECT id_etudiant FROM inscription GROUP BY id_etudiant HAVING COUNT(DISTINCT id_site) >= 2);
SELECT COUNT(*) FROM (SELECT id_etudiant FROM inscription GROUP BY id_etudiant HAVING COUNT(DISTINCT id_site) >= 2);

PROMPT --- C8 avec jointure
SELECT COUNT(*) FROM (SELECT i.id_groupe FROM inscription i JOIN session_cours s ON s.id_session = i.id_session
WHERE i.id_groupe IS NOT NULL GROUP BY i.id_groupe HAVING COUNT(DISTINCT s.id_campus) >= 2);
SELECT COUNT(*) FROM (SELECT i.id_groupe FROM inscription i JOIN session_cours s ON s.id_session = i.id_session
WHERE i.id_groupe IS NOT NULL GROUP BY i.id_groupe HAVING COUNT(DISTINCT s.id_campus) >= 2);
PROMPT --- C8 avec id_site
SELECT COUNT(*) FROM (SELECT id_groupe FROM inscription
WHERE id_groupe IS NOT NULL GROUP BY id_groupe HAVING COUNT(DISTINCT id_site) >= 2);
SELECT COUNT(*) FROM (SELECT id_groupe FROM inscription
WHERE id_groupe IS NOT NULL GROUP BY id_groupe HAVING COUNT(DISTINCT id_site) >= 2);

SET AUTOTRACE OFF

PROMPT ===== 3. Tests de cohérence (annulés à la fin) =====
PROMPT Test A : on insère avec un site faux (2) pour la session 1, qui est à Angers (4).
PROMPT          Attendu : le trigger remplace 2 par 4.
INSERT INTO inscription (id_inscription, id_etudiant, id_session, date_operation,
                         nb_places, montant, statut, id_site)
VALUES (999999001, 1, 1, TO_DATE('2026-04-01', 'YYYY-MM-DD'), 1, 309, 'ANNULEE', 2);
SELECT id_inscription, id_session, id_site FROM inscription WHERE id_inscription = 999999001;

PROMPT Test B : session inexistante. Attendu : ORA-20001.
INSERT INTO inscription (id_inscription, id_etudiant, id_session, date_operation,
                         nb_places, montant, statut)
VALUES (999999002, 1, 99999999, TO_DATE('2026-04-01', 'YYYY-MM-DD'), 1, 309, 'ANNULEE');

PROMPT Test C : changer le site d'une inscription à la main. Attendu : le trigger le remet.
UPDATE inscription SET id_site = 2 WHERE id_inscription = 1;
SELECT id_inscription, id_session, id_site FROM inscription WHERE id_inscription = 1;

PROMPT Test D : déplacer la session 1 (qui a des inscriptions) à Tours. Attendu : ORA-02292.
UPDATE session_cours SET id_campus = 3 WHERE id_session = 1;

ROLLBACK;
SPOOL OFF
