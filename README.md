# Projet Data Storage Systems (SQL & NoSQL), MS DGAI1

# École de langues · groupe 07 composé de :

- Baptiste GERBOUIN
- Younes IFOURAH
- Philip DANG

## TL;DR

- Les livrables sont organisés par dossier.
- Il faut absolument jouer les scripts prérequis en premier afin de créer le schéma et charger les données (cf dossier prerequis)
- Les fichiers Markdown (.md) contiennent les réponses aux questions ouvertes et les remarques de compréhensions.

## Description du projet

Les livrables sont rangés par dossier. Chaque dossier contient les fichiers correspondant au travail demandé : requêtes dans des fichiers SQL, schéma dans des fichiers PNG. Chaque dossier est accompagné d'un ou de plusieurs fichiers Markdown contenant les manipulations à effectuer pour chaque livrablen justifications, remarques et analyses

## Initialisation du projet

Avant tout chose, vous devez créer le schéma du projet, les users et charger les données. Pour cela il faut jouer les scripts du dossier initialisation : installation_system.sql et run_all.sql

Pour créer le schéma et les données, veuillez suivre les actions suivantes :

```powershell
# 1. copier les CSV dans le conteneur
docker exec oracle-bdd mkdir -p /opt/oracle/donnees_langues
docker cp data/. oracle-bdd:/opt/oracle/donnees_langues/

# 2. créer l'utilisateur langues, ses droits, le dossier Oracle, les 3 comptes de test
#    du L5 (agent_bordeaux, agent_tours, direction) et les 3 bases de site du L6
#    (site_bordeaux, site_tours, site_angers), avec le compte administrateur du kit
docker cp sql/installation_system.sql oracle-bdd:/tmp/installation_system.sql
docker exec oracle-bdd sqlplus -s system/oracle@//localhost:1521/FREEPDB1 "@/tmp/installation_system.sql"

# 3. créer l'utilisateur langues, ses droits, le dossier Oracle, les 3 comptes de test
se connecter en tant que system/oracle
exécuter sql/installation_system.sql
se connecter en tant que langues/langues
exécuter sql/run_all.sql
```

## Ordre d'exécution des scripts Oracle

Tout se relance de zéro avec un seul fichier, connecté en **`langues` / `langues`**, service `FREEPDB1` :

- dans SQL Developer : Exécuter `sql/run_all.sql`
- ou en ligne de commande, depuis le dossier `sql/` : `sqlplus langues/langues@//localhost:1521/FREEPDB1 @run_all.sql`

| Ordre | Script                    | Livrable                                                                            |
| ----- | ------------------------- | ----------------------------------------------------------------------------------- |
| 00    | `00_nettoyage.sql`        | supprime tout pour repartir de zéro                                                 |
| 01    | `01_creation_tables.sql`  | L1 · tables et contraintes nommées                                                  |
| 02    | `02_chargement.sql`       | L2 · chargement des CSV et traitement des défauts                                   |
| 03    | `03_valeurs_controle.sql` | L2 · valeurs C1 à C9                                                                |
| 04    | `04_requetes_metier.sql`  | L2 · 10 requêtes métier                                                             |
| 05    | `05_normalisation.sql`    | L3 · table à plat et dénormalisation                                                |
| 06    | `06_triggers.sql`         | L4 · triggers et journal d'audit                                                    |
| 07    | `07_package_parcours.sql` | L4 · parcours multi-sites tout ou rien                                              |
| 08    | `08_performance.sql`      | L5 · requêtes lentes, index, vue matérialisée                                       |
| 09    | `09_securite.sql`         | L5 · rôle, vue de restriction, VPD / masquage / audit                               |
| 10    | `10_distribution.sql`     | L6 · fragmentation par site, db links, vues globales                                |
| 11    | `11_bonus_objet.sql`      | bonus objet-relationnel : type `t_campus` avec méthode, sous-type `t_site`, requête |

Scripts lancés **à la main**, hors `run_all.sql` :

- `installation_system.sql` : une seule fois, en `system`, avant tout le reste (voir plus haut).
- `L4_concurrence_session_A.sql` et `L4_concurrence_session_B.sql` : anomalie de concurrence, deux connexions ouvertes en même temps.
- Preuves, après `run_all.sql` : `preuves/L4_tests_fiabilite.sql` (triggers et package), `preuves/L5_securite.sql` (ce que voit chaque compte ; il se connecte tour à tour avec `agent_bordeaux`, `agent_tours` et `direction`).
- `L6_panne_reprise.sql` : panne du site d'Angers et reprise, étape par étape, en alternant les connexions `langues` et `system`.
- MongoDB shardé (L6) : export depuis Oracle puis scripts `mongosh`, voir `nosql/mongodb/README.md`.
- L7 : Elasticsearch (recherche d'un étudiant, `nosql/elasticsearch/README.md`) et Neo4j (recommandation de sessions, `nosql/neo4j/README.md`). Chacun part d'un export d'Oracle. Le kit demande de lancer un moteur à la fois (`docker compose --profile elasticsearch up -d`, puis `--profile neo4j`, dans `C:\bdd-kit\3-nosql`).

## Vocabulaire du sujet → nos données

| Sujet                  | Chez nous                   | Fichier             |
| ---------------------- | --------------------------- | ------------------- |
| usager                 | étudiant                    | `etudiants.csv`     |
| ressource              | session de cours            | `sessions.csv`      |
| opération              | inscription                 | `inscriptions.csv`  |
| opération groupée      | parcours (même `id_groupe`) | `inscriptions.csv`  |
| catégorie de ressource | langue de la session        | colonne `categorie` |

Une opération est **valide** si sa session existe, si son montant est ≥ 0 et si sa date est ≤ au début de la session.

#### Arborescence

```
.
├── README.md                ce fichier
├── JOURNAL.md               journal de bord daté (obligatoire)
├── IA.md                    déclaration d'usage de l'IA (obligatoire)
├── data/                    les 4 CSV d'origine — ne jamais les modifier
├── sql/                     tous les scripts Oracle, lancés par run_all.sql
├── nosql/                   MongoDB shardé (L6), Elasticsearch et Neo4j (L7)
├── docs/
│   ├── analyse/             premier aperçu des données et des défauts
│   ├── comptes_rendus/      ce qui a été fait à chaque étape, et comment le justifier
│   ├── L1_modele/           règles de gestion, MCD, schéma relationnel
│   ├── L3_normalisation/    DF, décomposition, dénormalisation
│   ├── L8_adr/              les deux ADR
│   ├── sujet/               sujet complet du projet (.odt)
│   └── rapport/             rapport final (12 pages max)
└── preuves/                 sorties à garder : plans d'exécution, blocs lus, captures
```
