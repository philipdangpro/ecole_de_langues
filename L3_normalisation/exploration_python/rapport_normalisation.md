# L3 — Normalisation de la base de données

## 1. Objectif

L’objectif est de réduire les redondances et d’améliorer la cohérence des données de l’école de langues.

## 2. Fichier à plat

Le fichier `operations_a_plat.csv` rassemble les inscriptions, les étudiants, les sessions et les informations des campus.

Il contient 354 855 lignes et 28 colonnes.

## 3. Dépendances fonctionnelles candidates

Les dépendances suivantes sont proposées à partir des identifiants et des règles métier :

- `id_campus → nom, ville, role`
- `id_etudiant → nom, prenom, email, telephone, ville, id_campus, date_inscription`
- `id_session → libelle, categorie, id_campus, debut, duree_minutes, capacite, prix_unitaire`
- `id_inscription → id_etudiant, id_session, date_inscription, nb_places, montant, statut, id_groupe`

Ces dépendances doivent être confirmées par les règles métier. Les contrôles sur les données permettent de détecter des contradictions, mais ne prouvent pas à eux seuls toutes les dépendances.

## 4. Décomposition proposée

La décomposition utilise quatre tables :

- **CAMPUS** (`id_campus` clé primaire)
- **ETUDIANTS** (`id_etudiant` clé primaire, `id_campus` clé étrangère)
- **SESSIONS** (`id_session` clé primaire, `id_campus` clé étrangère)
- **INSCRIPTIONS** (`id_inscription` clé primaire, `id_etudiant` et `id_session` clés étrangères attendues)

Les informations propres aux campus, aux étudiants et aux sessions sont séparées des inscriptions afin de limiter les répétitions.

## 5. Contrôles effectués

Les contrôles réalisés sur les données ont permis de constater :

- Aucun identifiant dupliqué dans les tables vérifiées.
- Aucun étudiant ne référence un campus absent.
- Aucune session ne référence un campus absent.
- Aucune inscription ne référence un étudiant absent.
- 220 inscriptions référencent un identifiant de session absent de la table SESSIONS.

Ces résultats confirment plusieurs propriétés des données, mais ne suffisent pas à démontrer à eux seuls la conformité formelle à la 3NF.

## 6. Anomalies et limites

Les 220 inscriptions dont la session est absente ont été conservées dans les fichiers produits afin de ne pas perdre de données. Ces références doivent être examinées avec le producteur des données avant toute correction.

Le fichier à plat contient également 527 valeurs d'email manquantes. Ce nombre correspond aux valeurs manquantes observées dans le fichier et ne représente pas nécessairement le nombre d'étudiants distincts concernés.

Enfin, les contrôles effectués sur les données ne remplacent pas la validation des contraintes et des règles métier.

## 7. Justification de la normalisation

La séparation des entités CAMPUS, ETUDIANTS, SESSIONS et INSCRIPTIONS réduit la répétition des informations descriptives et facilite leur mise à jour. Elle limite également les anomalies d'insertion, de modification et de suppression.

La conformité formelle à la troisième forme normale (3NF) doit être établie en identifiant les clés candidates et en vérifiant les dépendances fonctionnelles de chaque table à partir des règles métier.

La décomposition proposée constitue une base cohérente pour cette analyse, sous réserve de la validation formelle de ces dépendances et de la résolution des anomalies d'intégrité référentielle identifiées.