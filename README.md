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

## Installation sur un kit neuf (une seule fois)

Le kit du cours (Oracle Free, conteneur `oracle-bdd`) ne crée que le compte `club`. Notre projet travaille dans le schéma **`langues`** (mot de passe `langues`), et le chargement lit les CSV directement dans le conteneur. Depuis la racine du dépôt, dans **PowerShell** :

```powershell
# 1. copier les CSV dans le conteneur
docker exec oracle-bdd mkdir -p /opt/oracle/donnees_langues
docker cp data/. oracle-bdd:/opt/oracle/donnees_langues/

# 2. créer l'utilisateur langues, ses droits, le dossier Oracle, les 3 comptes de test
#    du L5 (agent_bordeaux, agent_tours, direction) et les 3 bases de site du L6
#    (site_bordeaux, site_tours, site_angers), avec le compte administrateur du kit
docker cp sql/installation_system.sql oracle-bdd:/tmp/installation_system.sql
docker exec oracle-bdd sqlplus -s system/oracle@//localhost:1521/FREEPDB1 "@/tmp/installation_system.sql"
```

(Ne pas passer le script par `Get-Content ... |` : PowerShell 5.1 ajoute un caractère invisible en tête et abîme les accents.)

(Dans SQL Developer, l'étape 2 revient à ouvrir `sql/installation_system.sql` avec une connexion `system` / `oracle`, service `FREEPDB1`, puis F5.)

> Sous Git Bash, préfixer les commandes `docker` par `MSYS_NO_PATHCONV=1` : sinon le chemin `/opt/...` est réécrit en chemin Windows et la copie échoue sans message.

## Ordre d'exécution des scripts Oracle

Tout se relance de zéro avec un seul fichier, connecté en **`langues` / `langues`**, service `FREEPDB1` :

- dans SQL Developer (ou l'extension SQL Developer de VS Code) : ouvrir `sql/run_all.sql` puis **Exécuter le script (F5)** ;
- ou en ligne de commande, depuis le dossier `sql/` : `sqlplus langues/langues@//localhost:1521/FREEPDB1 @run_all.sql`.

| Ordre | Script | Livrable |
|---|---|---|---|
| 00 | `00_nettoyage.sql` | supprime tout pour repartir de zéro |
| 01 | `01_creation_tables.sql` | L1 · tables et contraintes nommées |
| 02 | `02_chargement.sql` | L2 · chargement des CSV et traitement des défauts |
| 03 | `03_valeurs_controle.sql` | L2 · valeurs C1 à C9 |
| 04 | `04_requetes_metier.sql` | L2 · 10 requêtes métier |
| 05 | `05_normalisation.sql` | L3 · table à plat et dénormalisation |
| 06 | `06_triggers.sql` | L4 · triggers et journal d'audit |
| 07 | `07_package_parcours.sql` | L4 · parcours multi-sites tout ou rien |
| 08 | `08_performance.sql` | L5 · requêtes lentes, index, vue matérialisée |
| 09 | `09_securite.sql` | L5 · rôle, vue de restriction, VPD / masquage / audit |
| 10 | `10_distribution.sql` | L6 · fragmentation par site, db links, vues globales |
| 11 | `11_bonus_objet.sql` | bonus objet-relationnel : type `t_campus` avec méthode, sous-type `t_site`, requête |

Scripts lancés **à la main**, hors `run_all.sql` :

- `installation_system.sql` : une seule fois, en `system`, avant tout le reste (voir plus haut).
- `L4_concurrence_session_A.sql` et `L4_concurrence_session_B.sql` : anomalie de concurrence, deux connexions ouvertes en même temps.
- Preuves, après `run_all.sql` : `preuves/L4_tests_fiabilite.sql` (triggers et package), `preuves/L5_securite.sql` (ce que voit chaque compte ; il se connecte tour à tour avec `agent_bordeaux`, `agent_tours` et `direction`).
- `L6_panne_reprise.sql` : panne du site d'Angers et reprise, étape par étape, en alternant les connexions `langues` et `system`.
- MongoDB shardé (L6) : export depuis Oracle puis scripts `mongosh`, voir `nosql/mongodb/README.md`.
- L7 : Elasticsearch (recherche d'un étudiant, `nosql/elasticsearch/README.md`) et Neo4j (recommandation de sessions, `nosql/neo4j/README.md`). Chacun part d'un export d'Oracle. Le kit demande de lancer un moteur à la fois (`docker compose --profile elasticsearch up -d`, puis `--profile neo4j`, dans `C:\bdd-kit\3-nosql`).

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
