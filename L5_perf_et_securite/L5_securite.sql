-- =====================================================================
-- L5_securite.sql : preuve de ce que voit (et ne voit pas) chaque compte
-- À lancer à la main APRÈS run_all.sql (pas lancé par run_all), dans SQL Developer
-- (F5) ou sqlplus. Le script se connecte successivement avec chaque compte
-- (CONNECT), puis revient sur langues à la fin.
-- Les erreurs ORA-00904, ORA-00942 et ORA-41900 sont ATTENDUES : ce sont les refus.
-- Résultat obtenu : preuves/L5_securite.txt
-- =====================================================================
SET LINESIZE 160
SET PAGESIZE 100
SET FEEDBACK ON
COLUMN session_libelle FORMAT A22
COLUMN nom             FORMAT A12
COLUMN prenom          FORMAT A10
COLUMN telephone       FORMAT A10
COLUMN statut          FORMAT A9
COLUMN ville_site      FORMAT A9
COLUMN langue          FORMAT A9
COLUMN compte          FORMAT A15


PROMPT
PROMPT ##################################################################
PROMPT # 1. langues (propriétaire) : référence, voit tout
PROMPT ##################################################################
CONNECT langues/langues@//localhost:1521/FREEPDB1
SELECT id_site, COUNT(*) AS inscriptions FROM v_inscrits_site GROUP BY id_site ORDER BY id_site;
SELECT COUNT(*) AS lignes_activite FROM v_activite_site;


PROMPT
PROMPT ##################################################################
PROMPT # 2. agent_bordeaux (role_agent_site, site 2)
PROMPT ##################################################################
CONNECT agent_bordeaux/agent_bordeaux@//localhost:1521/FREEPDB1
SELECT USER AS compte, role FROM session_roles;

PROMPT --- Ce qu'il voit : les inscriptions du site 2 SEULEMENT (même vue que langues)
SELECT id_site, COUNT(*) AS inscriptions FROM langues.v_inscrits_site GROUP BY id_site;

PROMPT --- Exemple de lignes : nom, prénom, téléphone, et rien d'autre
SELECT id_session, session_libelle, nom, prenom, telephone, nb_places, statut
FROM   langues.v_inscrits_site
WHERE  id_session = (SELECT MIN(id_session) FROM langues.v_inscrits_site)
ORDER BY nom;

PROMPT --- Une session de Tours (session 67) : invisible pour lui, 0 ligne
SELECT COUNT(*) AS lignes_session_tours FROM langues.v_inscrits_site WHERE id_session = 67;

PROMPT --- Refus attendu : l'e-mail n'est pas dans sa vue (ORA-00904)
SELECT email FROM langues.v_inscrits_site WHERE ROWNUM = 1;

PROMPT --- Refus attendu : pas d'accès aux tables (ORA-00942)
SELECT COUNT(*) FROM langues.etudiant;
SELECT COUNT(*) FROM langues.inscription;

PROMPT --- Refus attendu : pas d'accès à la vue de la direction (ORA-00942)
SELECT COUNT(*) FROM langues.v_activite_site;

PROMPT --- Refus attendu : lecture seule (ORA-41900, missing UPDATE privilege)
UPDATE langues.v_inscrits_site SET statut = 'ANNULEE' WHERE ROWNUM = 1;


PROMPT
PROMPT ##################################################################
PROMPT # 3. agent_tours (role_agent_site, site 3)
PROMPT ##################################################################
CONNECT agent_tours/agent_tours@//localhost:1521/FREEPDB1

PROMPT --- Même vue, même requête : il ne voit que le site 3
SELECT id_site, COUNT(*) AS inscriptions FROM langues.v_inscrits_site GROUP BY id_site;

PROMPT --- La session 67 (Tours) est visible pour lui
SELECT COUNT(*) AS lignes_session_tours FROM langues.v_inscrits_site WHERE id_session = 67;


PROMPT
PROMPT ##################################################################
PROMPT # 4. direction (role_direction, tous les sites)
PROMPT ##################################################################
CONNECT direction/direction@//localhost:1521/FREEPDB1

PROMPT --- Les colonnes de sa vue : aucune donnée personnelle (ni nom, ni e-mail, ni id étudiant)
DESCRIBE langues.v_activite_site

PROMPT --- Il voit les 3 sites : chiffre d'affaires confirmé par site (= C5)
SELECT id_site, ville_site, SUM(montant) AS ca_confirme
FROM   langues.v_activite_site
WHERE  statut = 'CONFIRMEE'
GROUP BY id_site, ville_site
ORDER BY id_site;

PROMPT --- Refus attendu : pas de liste nominative (ORA-00942)
SELECT nom, prenom FROM langues.v_inscrits_site WHERE ROWNUM = 1;
SELECT COUNT(*) FROM langues.etudiant;


PROMPT
PROMPT ##################################################################
PROMPT # 5. Refus par défaut : un compte qui a le rôle mais aucun site ne voit rien
PROMPT #    (cas d'un agent qui quitte l'école : on retire sa ligne de COMPTE_SITE)
PROMPT ##################################################################
CONNECT langues/langues@//localhost:1521/FREEPDB1
DELETE FROM compte_site WHERE nom_compte = 'AGENT_TOURS';
COMMIT;

CONNECT agent_tours/agent_tours@//localhost:1521/FREEPDB1
SELECT role FROM session_roles;
SELECT COUNT(*) AS inscriptions_vues FROM langues.v_inscrits_site;

PROMPT --- On remet agent_tours sur son site
CONNECT langues/langues@//localhost:1521/FREEPDB1
INSERT INTO compte_site (nom_compte, id_site) VALUES ('AGENT_TOURS', 3);
COMMIT;
SELECT USER AS compte FROM dual;
