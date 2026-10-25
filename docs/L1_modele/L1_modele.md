# L1 · Modèle — École de langues (groupe 07) — version 3

## 1. Vocabulaire du sujet

| Mot du sujet | Chez nous |
|---|---|
| usager | `ETUDIANT` |
| ressource datée | `SESSION_COURS` |
| opération | `INSCRIPTION` (une ligne de `inscriptions.csv`) |
| opération groupée | inscriptions qui partagent le même `id_groupe` (colonne facultative de `INSCRIPTION`) |

## 2. Règles de gestion

| N° | Règle | Garantie par |
|---|---|---|
| RG1 | Un campus est soit le siège, soit un site, jamais les deux (héritage exclusif et total). | `ck_campus_type`, `fk_siege_campus`, `fk_site_campus` |
| RG2 | Il y a un seul siège ; chaque site dépend du siège. | `uq_siege_unique`, `fk_site_siege` |
| RG3 | Les étudiants et les sessions sont rattachés à un **site**, jamais au siège. | `fk_etudiant_site`, `fk_session_site` |
| RG4 | Une personne est identifiée par son e-mail normalisé (minuscules, sans espaces), unique. | `uq_etudiant_email`, `ck_etudiant_email_norm` |
| RG5 | L'e-mail est facultatif : un étudiant sans e-mail compte pour une personne. | `email` nullable |
| RG6 | Le téléphone, s'il est renseigné, a 10 chiffres et commence par 0. | `ck_etudiant_telephone` |
| RG7 | Un étudiant a au plus un parrain, qui n'est pas lui-même ; le parrain a un compte plus ancien. | `fk_etudiant_parrain`, `ck_etudiant_pas_son_parrain`, trigger L4 |
| RG8 | Une session appartient à une catégorie et se tient dans un site ; durée de 45, 60, 90 ou 120 min, capacité > 0, prix ≥ 0. | `fk_session_*`, `ck_session_*` |
| RG9 | Une inscription relie un étudiant à une session avec `nb_places` ≥ 1, `montant` ≥ 0 et un statut `CONFIRMEE` ou `ANNULEE`. | `ck_inscription_*` |
| RG10 | Le site d'une opération est celui de sa session. | vue `v_inscription_site` |
| RG11 | Une opération est valide si sa session existe, son montant est ≥ 0 et sa date est ≤ au début de la session. Le sort des opérations non valides est défini en L2. | `fk_inscription_session`, `ck_inscription_montant`, chargement L2 |
| RG12 | Le montant vaut `nb_places × prix_unitaire`, y compris pour une annulation ; seules les confirmées comptent dans le chiffre d'affaires. | trigger L4 |
| RG13 | Un étudiant ne s'inscrit qu'une fois en confirmé à la même session. | trigger L4 |
| RG14 | Une inscription est postérieure à la création du compte de l'étudiant. | trigger L4 |
| RG15 | Les places confirmées d'une session ne dépassent pas sa capacité. | package L4, vue `v_session_occupation` |
| RG16 | Les inscriptions d'une même opération groupée (`id_groupe`) sont passées en une fois, en tout ou rien, par le même étudiant. | `ck_inscription_groupe` (format), procédure L4 |

Les règles RG13 à RG15 valent pour les **nouvelles** opérations. Les données historiques qui les violent (154 couples en double, 126 inscriptions avant la création du compte, 15 sessions sur-réservées) seront traitées en L2.

## 3. Schéma entité-association

- **Héritage** : `CAMPUS` se décline en `SIEGE` et `SITE`. Les étudiants et les sessions pointent vers `SITE`, donc « le siège n'a ni étudiants ni sessions » est garanti par une clé étrangère.
- **Association réflexive** : `PARRAINER` sur `ETUDIANT` (un parrain, plusieurs filleuls). 
- **Association porteuse** : `INSCRIRE` entre `ETUDIANT` (0,n) et `SESSION_COURS` (0,n). Elle porte date, places, montant, statut et `id_groupe`. Elle a un identifiant propre, car un étudiant peut avoir plusieurs inscriptions à la même session (annulation puis réinscription) et que l'audit (L4) doit viser une inscription précise.

## 4. Schéma relationnel (`#` = clé primaire, `→` = clé étrangère)

```
CAMPUS(#id_campus, nom, ville, type_campus)
SIEGE(#id_campus, type_campus)                      → CAMPUS(id_campus, type_campus)
SITE(#id_campus, type_campus, id_siege → SIEGE)     → CAMPUS(id_campus, type_campus)
ETUDIANT(#id_etudiant, nom, prenom, email, telephone, ville,
         id_campus → SITE, date_inscription, id_parrain → ETUDIANT)
CATEGORIE(#id_categorie, libelle)
SESSION_COURS(#id_session, libelle, id_categorie → CATEGORIE, id_campus → SITE,
              debut, duree_minutes, capacite, prix_unitaire)
INSCRIPTION(#id_inscription, id_etudiant → ETUDIANT, id_session → SESSION_COURS,
            id_groupe, date_operation, nb_places, montant, statut)
```

**Traduction de l'héritage** : une table par type. Le type est recopié dans chaque sous-table, avec une clé étrangère composite `(id_campus, type_campus)` : un campus de type `SIEGE` ne peut pas être inséré dans `SITE`. Que chaque campus ait une ligne dans un sous-type ne peut pas se déclarer en contrainte ; c'est respecté par l'ordre de chargement.

## 5. Script de création

Voir [`sql/01_creation_tables.sql`](../../sql/01_creation_tables.sql) (Oracle 23ai Free du kit) : toutes les contraintes sont nommées (`pk_`, `fk_`, `uq_`, `ck_`, `nn_`). La table s'appelle `SESSION_COURS` parce que `SESSION` est un mot réservé Oracle. Les index sur clés étrangères sont laissés à L5.

Description colonne par colonne et justification des choix : [`L1_schema_relationnel.md`](L1_schema_relationnel.md).
Preuve que les contraintes refusent les mauvaises données : [`preuves/L1_tests_contraintes.txt`](../../preuves/L1_tests_contraintes.txt).

## 6. Reporté à plus tard

- Traitement des défauts (doublons d'étudiants, e-mails vides, sessions inconnues, montants négatifs, dates après le début, doubles confirmations, sur-réservations) : décidé et tracé en L2.
- Entité `PARCOURS` : possible plus tard, à partir de `INSCRIPTION.id_groupe`.
