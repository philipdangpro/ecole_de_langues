-- =====================================================================
-- 00_nettoyage.sql
-- Livrable : tous
-- Rôle     : supprime tous les objets du schéma courant (langues) pour pouvoir
--            relancer run_all.sql de zéro, sur une base neuve comme sur une base déjà remplie.
-- Lancé par : sql/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- On parcourt le dictionnaire (USER_OBJECTS) plutôt que d'écrire une liste de DROP :
-- un objet ajouté plus tard par un autre livrable sera supprimé lui aussi, sans
-- erreur ORA-00942 si la table n'existe pas encore.
-- =====================================================================

BEGIN
    FOR o IN (
        SELECT object_name, object_type
        FROM   user_objects
        WHERE  object_type IN ('MATERIALIZED VIEW', 'VIEW', 'TABLE', 'SEQUENCE',
                               'PACKAGE', 'PROCEDURE', 'FUNCTION', 'TYPE', 'SYNONYM',
                               'DATABASE LINK')
        AND    object_name NOT LIKE 'BIN$%'          -- corbeille
        AND    object_name NOT LIKE 'ISEQ$$%'        -- séquences des colonnes IDENTITY
        AND    object_name NOT LIKE 'MLOG$%'         -- journaux de vues matérialisées
        ORDER BY DECODE(object_type, 'MATERIALIZED VIEW', 1, 'VIEW', 2, 'TABLE', 3,
                        'TYPE', 9, 5)
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' "' || o.object_name || '"'
                || CASE o.object_type
                       WHEN 'TABLE' THEN ' CASCADE CONSTRAINTS PURGE'
                       WHEN 'TYPE'  THEN ' FORCE'
                   END;
        EXCEPTION
            -- objet déjà supprimé par un DROP précédent (ex. table d'une vue matérialisée)
            WHEN OTHERS THEN
                IF SQLCODE NOT IN (-942, -4043, -2289, -12003) THEN RAISE; END IF;
        END;
    END LOOP;
END;
/

PURGE RECYCLEBIN;
