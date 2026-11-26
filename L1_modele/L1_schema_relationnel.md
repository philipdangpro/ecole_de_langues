# L1 · Schéma relationnel — École de langues (groupe 07)

Ce fichier décrit les tables créées par [`L1_modele/01_creation_tables.sql`](01_creation_tables.sql), colonne par colonne.
Les règles de gestion RG1 à RG16 sont définies dans [`L1_modele.md`](L1_modele.md).

## 1. Vue d'ensemble

Notation : `#` clé primaire, `→` clé étrangère, `?` colonne facultative (`NULL` permis).

```
CAMPUS        (#id_campus, nom, ville, type_campus)
SIEGE         (#id_campus, type_campus)              (id_campus, type_campus) → CAMPUS
SITE          (#id_campus, type_campus, id_siege)    (id_campus, type_campus) → CAMPUS
                                                     id_siege → SIEGE
ETUDIANT      (#id_etudiant, nom, prenom, email?, telephone?, ville?,
               id_campus, date_inscription, id_parrain?)
                                                     id_campus  → SITE
                                                     id_parrain → ETUDIANT   (réflexive)
CATEGORIE     (#id_categorie, libelle)
SESSION_COURS (#id_session, libelle, id_categorie, id_campus, debut,
               duree_minutes, capacite, prix_unitaire)
                                                     id_categorie → CATEGORIE
                                                     id_campus    → SITE
INSCRIPTION   (#id_inscription, id_etudiant, id_session, id_groupe?,
               date_operation, nb_places, montant, statut)
                                                     id_etudiant → ETUDIANT
                                                     id_session  → SESSION_COURS
```

Ordre de création (et de chargement), imposé par les clés étrangères :
`CAMPUS → SIEGE → SITE → ETUDIANT → CATEGORIE → SESSION_COURS → INSCRIPTION`.

## 2. D'où vient chaque table

| Table | Fichier source | Élément du MCD |
|---|---|---|
| `CAMPUS` | `campus.csv` | entité mère de l'héritage |
| `SIEGE` | `campus.csv` (ligne `role = siège`) | sous-type de CAMPUS |
| `SITE` | `campus.csv` (lignes `role = site`) | sous-type de CAMPUS |
| `ETUDIANT` | `etudiants.csv` | entité usager + association réflexive PARRAINER |
| `CATEGORIE` | `sessions.csv` (valeurs distinctes de `categorie`) | entité extraite (évite de répéter le libellé 47 619 fois) |
| `SESSION_COURS` | `sessions.csv` | entité ressource datée |
| `INSCRIPTION` | `inscriptions.csv` | association porteuse INSCRIRE |

## 3. Détail des tables

### CAMPUS
| Colonne | Type | Null | Contraintes | Remarque |
|---|---|---|---|---|
| id_campus | NUMBER(4) | non | `pk_campus` | 1 = siège, 2 à 4 = sites |
| nom | VARCHAR2(60 CHAR) | non | `nn_campus_nom` | |
| ville | VARCHAR2(60 CHAR) | non | `nn_campus_ville` | |
| type_campus | VARCHAR2(5 CHAR) | non | `ck_campus_type` : `SIEGE` ou `SITE` | colonne `role` du CSV (`siège`/`site`), mise en majuscules sans accent |

Contrainte de table : `uq_campus_id_type` UNIQUE (id_campus, type_campus), cible des clés composites de SIEGE et SITE.

### SIEGE
| Colonne | Type | Null | Contraintes | Remarque |
|---|---|---|---|---|
| id_campus | NUMBER(4) | non | `pk_siege` | |
| type_campus | VARCHAR2(5 CHAR) | non | `ck_siege_type` = `SIEGE`, `uq_siege_unique` | valeur par défaut `SIEGE` |

`fk_siege_campus` : (id_campus, type_campus) → CAMPUS. Un campus de type SITE ne peut donc pas entrer dans SIEGE (RG1).
`uq_siege_unique` sur une colonne qui vaut toujours `SIEGE` : une seule ligne possible (RG2).

### SITE
| Colonne | Type | Null | Contraintes | Remarque |
|---|---|---|---|---|
| id_campus | NUMBER(4) | non | `pk_site` | |
| type_campus | VARCHAR2(5 CHAR) | non | `ck_site_type` = `SITE` | valeur par défaut `SITE` |
| id_siege | NUMBER(4) | non | `fk_site_siege` → SIEGE | chaque site dépend du siège (RG2) |

`fk_site_campus` : (id_campus, type_campus) → CAMPUS (RG1).

### ETUDIANT
| Colonne | Type | Null | Contraintes | Remarque |
|---|---|---|---|---|
| id_etudiant | NUMBER(8) | non | `pk_etudiant` | |
| nom | VARCHAR2(80 CHAR) | non | `nn_etudiant_nom` | |
| prenom | VARCHAR2(80 CHAR) | non | `nn_etudiant_prenom` | |
| email | VARCHAR2(254 CHAR) | **oui** | `uq_etudiant_email`, `ck_etudiant_email_norm` | RG4, RG5 : stocké en minuscules et sans espaces |
| telephone | VARCHAR2(10 CHAR) | oui | `ck_etudiant_telephone` : `^0[0-9]{9}$` | texte et non nombre, pour garder le 0 initial (RG6) |
| ville | VARCHAR2(60 CHAR) | oui | | |
| id_campus | NUMBER(4) | non | `fk_etudiant_site` → **SITE** | site de rattachement (RG3) |
| date_inscription | DATE | non | `nn_etudiant_date` | date de **création du compte** (RG14) |
| id_parrain | NUMBER(8) | oui | `fk_etudiant_parrain` → ETUDIANT, `ck_etudiant_pas_son_parrain` | association réflexive (RG7), vide au chargement |

### CATEGORIE
| Colonne | Type | Null | Contraintes | Remarque |
|---|---|---|---|---|
| id_categorie | NUMBER(4) IDENTITY | non | `pk_categorie` | numéro généré par Oracle |
| libelle | VARCHAR2(40 CHAR) | non | `uq_categorie_libelle`, `ck_categorie_libelle_net` | FLE, anglais, espagnol, allemand, italien, chinois |

### SESSION_COURS
| Colonne | Type | Null | Contraintes | Remarque |
|---|---|---|---|---|
| id_session | NUMBER(8) | non | `pk_session` | |
| libelle | VARCHAR2(80 CHAR) | non | `nn_session_libelle` | |
| id_categorie | NUMBER(4) | non | `fk_session_categorie` → CATEGORIE | |
| id_campus | NUMBER(4) | non | `fk_session_site` → **SITE** | RG3 |
| debut | DATE | non | `nn_session_debut` | date et heure de début |
| duree_minutes | NUMBER(3) | non | `ck_session_duree` : 45, 60, 90 ou 120 | RG8 |
| capacite | NUMBER(3) | non | `ck_session_capacite` > 0 | RG8 |
| prix_unitaire | NUMBER(7,2) | non | `ck_session_prix` ≥ 0 | RG8 |

### INSCRIPTION
| Colonne | Type | Null | Contraintes | Remarque |
|---|---|---|---|---|
| id_inscription | NUMBER(10) | non | `pk_inscription` | identifiant propre de l'association |
| id_etudiant | NUMBER(8) | non | `fk_inscription_etudiant` → ETUDIANT | |
| id_session | NUMBER(8) | non | `fk_inscription_session` → SESSION_COURS | RG11 : la session doit exister |
| id_groupe | VARCHAR2(10 CHAR) | oui | `ck_inscription_groupe` : `^G[0-9]{5}$` | opération groupée (RG16) |
| date_operation | DATE | non | `nn_inscription_date` | colonne `date_inscription` du CSV, renommée |
| nb_places | NUMBER(3) | non | `ck_inscription_places` ≥ 1 | RG9 |
| montant | NUMBER(9,2) | non | `ck_inscription_montant` ≥ 0 | RG9, RG11 |
| statut | VARCHAR2(10 CHAR) | non | `ck_inscription_statut` : CONFIRMEE ou ANNULEE | RG9 |

## 4. Vues

| Vue | Règle | Contenu |
|---|---|---|
| `v_inscription_site` | RG10 | chaque inscription avec `id_site`, le site de sa session |
| `v_session_occupation` | RG15 | par session : capacité, places confirmées, `sur_reservee` = O/N |

## 5. Ce qui n'est pas une contrainte déclarative, et pourquoi

Un `CHECK` Oracle ne peut lire que la ligne en cours. Les règles qui comparent plusieurs lignes ou plusieurs tables sont donc reportées :

| Règle | Pourquoi pas un CHECK | Où elle sera garantie |
|---|---|---|
| RG7 le parrain a un compte plus ancien | compare deux lignes d'ETUDIANT | trigger (L4) |
| RG12 montant = nb_places × prix_unitaire | lit SESSION_COURS | trigger (L4) |
| RG13 une seule inscription confirmée par (étudiant, session) | compare des lignes d'INSCRIPTION ; un index unique refuserait les 154 doublons historiques que les valeurs de contrôle doivent compter | trigger (L4), nouvelles lignes seulement |
| RG14 inscription après la création du compte | lit ETUDIANT | trigger (L4) |
| RG15 pas de sur-réservation | somme sur plusieurs lignes ; 15 sessions déjà sur-réservées doivent rester visibles (valeur C7) | package (L4) |
| RG16 groupe en tout ou rien | porte sur une transaction | procédure du package (L4) |
| chaque CAMPUS a une ligne dans SIEGE ou SITE | une contrainte ne peut pas exiger qu'une ligne existe ailleurs | ordre de chargement (L2) |

## 6. Choix de conception et leur justification

| Choix | Pourquoi |
|---|---|
| Héritage traduit par **une table par type** avec clé composite (id_campus, type_campus) | Les étudiants et sessions pointent vers SITE : « le siège n'a ni étudiants ni sessions » est garanti par une simple clé étrangère, sans trigger. |
| `CATEGORIE` séparée de `SESSION_COURS` | La catégorie est une valeur répétée 47 619 fois ; une table à part évite les fautes de frappe (`Anglais` / `anglais`) et prépare la normalisation (L3). |
| `SESSION_COURS` et non `SESSION` | `SESSION` est un mot réservé Oracle. |
| `INSCRIPTION.date_operation` au lieu de `date_inscription` | Les deux CSV ont une colonne `date_inscription` qui ne veut pas dire la même chose (création du compte / date de l'opération). Renommer évite les confusions dans les jointures. |
| Le site n'est **pas** stocké dans INSCRIPTION | Il se déduit de la session (RG10) ; le stocker créerait une redondance qui pourrait diverger. La vue `v_inscription_site` le donne. |
| `VARCHAR2(n CHAR)` | La taille compte des caractères ; « Siège » fait 5 caractères mais 6 octets en UTF-8. |
| `DATE` pour les dates et heures | La DATE Oracle garde l'heure à la seconde, et les CSV n'ont pas de fraction de seconde. Plus simple que TIMESTAMP pour les calculs (`debut + duree_minutes/1440`). |
| Téléphone en texte | Un nombre perdrait le 0 initial. |
| E-mail facultatif mais unique | Le sujet dit qu'une ligne sans adresse compte pour une personne. Oracle n'indexe pas les NULL : plusieurs étudiants sans e-mail ne violent pas l'unicité. |
| `CATEGORIE.id_categorie` en IDENTITY | Le CSV ne donne que le libellé ; Oracle numérote. |
| Contraintes NOT NULL nommées (`nn_`) | Le sujet demande des contraintes nommées ; le nom apparaît dans le dictionnaire (`USER_CONSTRAINTS`). |
| Pas d'index sur les clés étrangères à ce stade | Ils seront ajoutés et mesurés en L5 (plans avant/après). |
