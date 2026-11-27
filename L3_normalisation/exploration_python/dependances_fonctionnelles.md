# L3 — Dépendances fonctionnelles

## 1. Fichier à plat

Le fichier `operations_a_plat.csv` regroupe les inscriptions, les étudiants, les sessions et les campus.

## 2. Dépendances fonctionnelles candidates

À vérifier à partir des données et des règles de gestion :

- `id_inscription` → `id_etudiant, id_session, date_inscription, nb_places, montant, statut, id_groupe`
- `id_etudiant` → `nom, prenom, email, telephone, ville, id_campus, date_inscription_etudiant`
- `id_session` → `libelle, categorie, id_campus_session, debut, duree_minutes, capacite, prix_unitaire`
- `id_campus` → `nom_campus, ville_campus, role`

## 3. Attention aux colonnes de campus

Le fichier contient `id_campus`, `id_campus_session` et les colonnes du campus. Il faut vérifier si `id_campus` correspond au campus de l'étudiant et `id_campus_session` au campus de la session. Ces deux informations ne doivent pas être confondues.

## 4. Validation

Ces dépendances sont des hypothèses à confirmer avec les règles de gestion et les données. Une dépendance observée dans les données ne suffit pas, à elle seule, à prouver qu'elle est toujours vraie.
