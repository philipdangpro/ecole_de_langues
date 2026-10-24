# École de langues · groupe 07

Projet Data Storage Systems (SQL & NoSQL), MS DGAI1.
Plateforme de données d'une école de langues : un siège (Paris) et trois sites (Bordeaux, Tours, Angers).

## Arborescence

```
.
├── README.md                ce fichier
├── JOURNAL.md               journal de bord daté (obligatoire)
├── IA.md                    déclaration d'usage de l'IA (obligatoire)
├── LISEZMOI.txt             description des données fournie avec le zip
├── data/                    les 4 CSV d'origine — ne jamais les modifier
├── sql/                     tous les scripts Oracle, lancés par run_all.sql
├── nosql/                   MongoDB (L6, L7) et le second moteur (L7)
├── docs/
│   ├── analyse/             premier aperçu des données et des défauts
│   ├── L1_modele/           règles de gestion, MCD, schéma relationnel
│   ├── L3_normalisation/    DF, décomposition, dénormalisation
│   ├── L8_adr/              les deux ADR
│   ├── sujet/               sujet complet du projet (.odt)
│   └── rapport/             rapport final (12 pages max)
└── preuves/                 sorties à garder : plans d'exécution, blocs lus, captures
```

## Ordre d'exécution des scripts Oracle

Tout se relance de zéro avec un seul fichier, depuis le dossier `sql/` :

```
sqlplus utilisateur/motdepasse@//localhost:1521/FREEPDB1 @run_all.sql
```

ou dans SQL Developer : ouvrir `sql/run_all.sql` puis **Exécuter le script (F5)**.

| Ordre | Script | Livrable | Responsable |
|---|---|---|---|
| 00 | `00_nettoyage.sql` | supprime tout pour repartir de zéro | à définir |
| 01 | `01_creation_tables.sql` | L1 · tables et contraintes nommées | à définir |
| 02 | `02_chargement.sql` | L2 · chargement des CSV et traitement des défauts | à définir |
| 03 | `03_valeurs_controle.sql` | L2 · valeurs C1 à C9 | à définir |
| 04 | `04_requetes_metier.sql` | L2 · 10 requêtes métier | à définir |
| 05 | `05_normalisation.sql` | L3 · table à plat et dénormalisation | à définir |
| 06 | `06_triggers.sql` | L4 · triggers et journal d'audit | à définir |
| 07 | `07_package_parcours.sql` | L4 · parcours multi-sites tout ou rien | à définir |
| 08 | `08_performance.sql` | L5 · requêtes lentes, index, vue matérialisée | à définir |
| 09 | `09_securite.sql` | L5 · rôle, vue de restriction, VPD / masquage / audit | à définir |
| 10 | `10_distribution.sql` | L6 · fragmentation par site, db links, vues globales | à définir |
| 11 | `11_bonus_objet.sql` | bonus objet-relationnel (optionnel, +2 points) | à définir |

Scripts lancés **à la main**, hors `run_all.sql` :

- `L4_concurrence_session_A.sql` et `L4_concurrence_session_B.sql` : anomalie de concurrence, deux connexions ouvertes en même temps.
- `L6_panne_reprise.sql` : scénario de panne d'un site et reprise.

## Vocabulaire du sujet → nos données

| Sujet | Chez nous | Fichier |
|---|---|---|
| usager | étudiant | `etudiants.csv` |
| ressource | session de cours | `sessions.csv` |
| opération | inscription | `inscriptions.csv` |
| opération groupée | parcours (même `id_groupe`) | `inscriptions.csv` |
| catégorie de ressource | langue de la session | colonne `categorie` |

Une opération est **valide** si sa session existe, si son montant est ≥ 0 et si sa date est ≤ au début de la session.

## Règles de travail

1. **Toute modification de la base passe par un script du dépôt.** Rien à la main dans SQL Developer sans le reporter dans le script : l'enseignante relance les scripts sur un kit neuf.
2. **Une branche par personne ou par livrable**, puis une Pull Request vers `main`. Pas de push direct sur `main`.
3. **Chacun travaille dans son fichier** pour éviter les conflits.
4. **`git pull` avant de commencer**, commit souvent avec un message clair (`L2: chargement des étudiants avec fusion des doublons`).
5. **Chaque membre commit régulièrement** : un dépôt rempli en une fois la veille du rendu ne vaut pas preuve.
6. **Avant de fusionner une étape importante** : recréer son conteneur Oracle et relancer `run_all.sql` pour vérifier qu'il passe sans erreur.
7. **Noter dans `JOURNAL.md`** chaque décision, impasse ou erreur (message exact), et dans `IA.md` chaque usage de l'IA.

## Éléments obligatoires (−1 point chacun s'il manque)

- [ ] Dépôt GitHub partagé avec l'enseignante dès le lancement
- [ ] Scripts qui s'exécutent dans l'ordre, sans erreur, sur un kit neuf, avec nos CSV
- [ ] Journal de bord daté (`JOURNAL.md`)
- [ ] Déclaration d'usage de l'IA (`IA.md`)
