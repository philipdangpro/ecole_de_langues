# Options des ADR : évidentes et non évidentes

## Les options évidentes (étudiées ensemble pendant le projet)

| ADR | Option | Où on l'a vue |
|---|---|---|
| ADR-01 | A. Tout au siège | point de départ du L1 au L5 |
| ADR-01 | B. Fragments par site (retenue) | L6, `sql/10_distribution.sql` |
| ADR-01 | C. B avec l'étudiant copié | L6, « ce qui changerait le classement » |
| ADR-02 | A. Oracle seul (`=`, `LIKE`, puis `UTL_MATCH`) | L7, `L7_oracle_comparaison.sql` |
| ADR-02 | C. Elasticsearch (retenue) | L7, `L7_nosql/elasticsearch/` |

## Les options non évidentes (on aurait pu passer à côté)

**ADR-01 · D. Une seule base, partitionnée par site** (`PARTITION BY LIST (id_site)`)
- Même découpage par site, sans lien ni 2PC.
- Les requêtes d'un site ne lisent que sa partition.
- Écartée : une seule base, donc une seule panne arrête tout. Ne répond pas à la contrainte de panne.

**ADR-01 · E. Inscriptions rangées avec l'étudiant**
- L'historique et le parcours d'un étudiant seraient sur un seul site (comme la clé MongoDB `id_etudiant`).
- Écartée : la place se contrôle sur la session. Le contrôle de capacité passerait par un lien à chaque inscription.

**ADR-02 · B. Oracle Text**
- Index plein texte dans Oracle, recherche `FUZZY`, score.
- Pas de copie des noms hors d'Oracle.
- Non retenue : l'index s'ajoute à la base qui porte le pic. Gardée comme repli (seuil de l'ADR-02).

**ADR-02 · D. Recherche phonétique `SOUNDEX`**
- Simple, indexable, dans Oracle.
- Écartée par la mesure : « Betrand » = B365, « Bertrand » = B636. 0 résultat.
