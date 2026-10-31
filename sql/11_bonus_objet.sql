-- =====================================================================
-- 11_bonus_objet.sql
-- Livrable : Bonus objet-relationnel
-- Responsable : Baptiste (avec Claude Code)
-- Attendu  : type objet avec héritage et méthode, utilisé dans une requête
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- On reprend l'héritage déjà présent dans le modèle (L1) : un CAMPUS est soit
-- le siège, soit un site. Ici il est écrit en types objet :
--   t_campus (type parent, NOT FINAL pour pouvoir en hériter) et sa méthode presenter()
--   t_site UNDER t_campus : hérite des attributs et de la méthode, ajoute id_siege
-- Une seule table objet de type t_campus accueille les deux (le siège en t_campus,
-- les sites en t_site), puis une requête appelle la méthode sur chaque ligne.
-- Le nettoyage (00_nettoyage.sql) supprime déjà les types (DROP TYPE ... FORCE).
-- =====================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200

-- Type parent : NOT FINAL autorise l'héritage
CREATE OR REPLACE TYPE t_campus AS OBJECT (
    id_campus  NUMBER(4),
    nom        VARCHAR2(60 CHAR),
    ville      VARCHAR2(60 CHAR),
    MEMBER FUNCTION presenter RETURN VARCHAR2
) NOT FINAL;
/

CREATE OR REPLACE TYPE BODY t_campus AS
    MEMBER FUNCTION presenter RETURN VARCHAR2 IS
    BEGIN
        RETURN nom || ' (' || ville || ')';
    END;
END;
/

-- Sous-type : un site est un campus qui dépend du siège
CREATE OR REPLACE TYPE t_site UNDER t_campus (
    id_siege   NUMBER(4)
);
/

-- Table objet : chaque ligne est un objet t_campus, ou d'un sous-type (t_site)
CREATE TABLE campus_objet OF t_campus (
    CONSTRAINT pk_campus_objet PRIMARY KEY (id_campus)
);

-- Remplissage à partir des tables du L1
INSERT INTO campus_objet
SELECT t_campus(c.id_campus, c.nom, c.ville)
FROM   campus c JOIN siege g ON g.id_campus = c.id_campus;

INSERT INTO campus_objet
SELECT t_site(c.id_campus, c.nom, c.ville, s.id_siege)
FROM   campus c JOIN site s ON s.id_campus = c.id_campus;

COMMIT;

-- Requête : la méthode presenter() est appelée sur le siège comme sur les sites
-- (les sites l'ont héritée). TREAT lit l'attribut propre au sous-type t_site
-- (vide pour le siège, qui n'est pas un t_site).
COLUMN campus FORMAT A40
COLUMN type_objet FORMAT A10
SELECT c.id_campus,
       c.presenter()                          AS campus,
       CASE WHEN VALUE(c) IS OF (t_site) THEN 'T_SITE' ELSE 'T_CAMPUS' END AS type_objet,
       TREAT(VALUE(c) AS t_site).id_siege     AS id_siege
FROM   campus_objet c
ORDER BY c.id_campus;
