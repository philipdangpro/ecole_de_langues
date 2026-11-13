# ADR-02 · Rechercher un étudiant malgré les fautes avec Elasticsearch

Statut : accepté le 31/10/2026. Responsable : Baptiste.

## 1. Contexte et contrainte imposée

- Besoin : l'accueil retrouve un étudiant au téléphone. Le nom est souvent mal tapé (« Betrand Leo »).
- 21 471 étudiants, mais seulement 50 noms et 40 prénoms.
- 2 000 paires nom + prénom : 10,7 homonymes en moyenne, jusqu'à 23. Martin : 484 étudiants.
- Aucun texte libre dans nos données : ce qu'on cherche, ce sont des personnes.
- Contrainte : au pic de la rentrée (16 068 inscriptions le 10/09/2026), Oracle doit rester libre pour les inscriptions.

## 2. Options envisagées

- **A. Oracle seul, distance entre mots** (`UTL_MATCH.EDIT_DISTANCE`).
- **B. Oracle Text** : index `CONTEXT` sur nom et prénom, recherche `FUZZY`.
- **C. Elasticsearch** : un index d'étudiants (nom, prénom, ville, site), accents retirés, `fuzziness: AUTO`.
- **D. Oracle, recherche phonétique** : `SOUNDEX` sur une colonne indexée.

## 3. Critères

| Critère | A · UTL_MATCH | B · Oracle Text | C · Elasticsearch (retenu) | D · SOUNDEX |
|---|---|---|---|---|
| Cohérence | ++ (lit la table) | + (index mis à jour par synchronisation) | − (copie, rechargée depuis Oracle) | ++ |
| Disponibilité | + (celle d'Oracle) | + | + (Oracle reste la référence si l'index tombe) | + |
| Latence, pertinence | − (0,08 s, 49 lignes sans classement) | + (score, non mesuré) | ++ (15 bons en tête, score 6,92) | −− (0 ligne) |
| Volumétrie | − (lecture complète à chaque recherche) | ++ | ++ (index inversé) | ++ (index) |
| Coût | ++ (rien à installer) | + (dans Oracle) | − (un moteur de plus, un export) | ++ |
| Sécurité, chiffrement | ++ (VPD du L5) | ++ | − (copie des noms ; sécurité coupée dans le kit, TLS à activer) | ++ |

## 4. Mesures (preuves/L7_elasticsearch.txt, nosql/elasticsearch/L7_oracle_comparaison.sql)

- Oracle, `=` et `LIKE '%BETRAND%'` : 0 résultat.
- Oracle, `UTL_MATCH` : 49 lignes, dont les 15 Léo Bertrand, en 0,08 s. Plan : `TABLE ACCESS FULL`.
- Oracle, `SOUNDEX` : « Betrand » = B365, « Bertrand » = B636. 0 résultat.
- Elasticsearch : import `"errors": false`, 21 471 documents. Les 15 Léo Bertrand en tête.
- Elasticsearch, filtre sur le site de Tours : ses 5 Léo Bertrand en tête.
- Une seule zone de saisie (« leo bertran tours ») : les Léo Bertrand de Tours en tête.

## 5. Décision

Nous choisissons C. Seul Elasticsearch classe les bonnes réponses en tête, et il décharge Oracle pendant le pic de la rentrée.

## 6. Conséquences et risques

- Facile : recherche sur plusieurs champs, sans accent, avec fautes, classée.
- Difficile : l'index est une copie. Un nouvel étudiant n'y est qu'après le prochain export.
- Inconvénient : un moteur de plus à faire tourner et à sécuriser.
- Risque : les 15 homonymes ont le même score. Parade : l'agent filtre par site ou par ville.
- Risque : index en retard. Parade : export chaque nuit ; la fiche est toujours relue dans Oracle par son identifiant.
- Seuil : si l'index a plus d'un jour de retard plus d'une fois par mois, nous reprendrons B (recherche dans Oracle, sans copie).

## 7. Volet RGPD

- Données personnelles : nom, prénom, ville, site. Ni e-mail, ni téléphone dans l'index.
- Minimisation : l'index sert à trouver l'identifiant. La fiche complète se lit dans Oracle, avec la VPD du L5.
- Conservation : la même que dans Oracle (ADR-01). L'index est reconstruit à chaque export : un étudiant purgé disparaît au suivant.
- Effacement : `DELETE /etudiants/_doc/<id>` en même temps que la suppression dans Oracle. L'export suivant le confirme. Instantanés de l'index : à supprimer aussi.
- Localisation : serveur en France, à côté d'Oracle. Un service managé hors UE est exclu.

## 8. Liens

L7 (`nosql/elasticsearch/`), ADR-01 (localisation de l'étudiant), L5 (VPD).
