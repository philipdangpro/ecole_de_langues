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

Avant toute chose, il faut créer les comptes Oracle et charger les données : `prerequis/installation_system.sql` (une fois, en `system`), puis `prerequis/run_all.sql` (en `langues`). Testé sur un kit neuf le 26/11/2026 : environ 1 min, aucune erreur.

Commandes PowerShell, depuis la racine du dépôt (sous Git Bash, préfixer chaque commande `docker` par `MSYS_NO_PATHCONV=1`) :

```powershell
# 1. copier les CSV dans le conteneur
docker exec oracle-bdd mkdir -p /opt/oracle/donnees_langues
docker cp data/. oracle-bdd:/opt/oracle/donnees_langues/

# 2. en system : utilisateur langues et ses droits, DIRECTORY des CSV, 3 comptes de test
#    du L5 (agent_bordeaux, agent_tours, direction), 3 comptes de site du L6
#    (site_bordeaux, site_tours, site_angers)
docker cp prerequis/installation_system.sql oracle-bdd:/tmp/installation_system.sql
docker exec oracle-bdd sqlplus -s system/oracle@//localhost:1521/FREEPDB1 "@/tmp/installation_system.sql"

# 3. en langues : reconstruction complète (L1 à L6 + bonus). Le dépôt entier est copié,
#    car run_all.sql appelle les scripts des autres dossiers par chemins relatifs.
docker exec oracle-bdd mkdir -p /tmp/projet
docker cp . oracle-bdd:/tmp/projet/
docker exec -w /tmp/projet/prerequis oracle-bdd sqlplus -s langues/langues@//localhost:1521/FREEPDB1 "@run_all.sql"
# journal : /tmp/projet/prerequis/run_all.log dans le conteneur
```

Ou dans SQL Developer : connexion `system` → ouvrir `prerequis/installation_system.sql` → F5 ; puis connexion `langues` → ouvrir `prerequis/run_all.sql` → F5.

## Ordre d'exécution des scripts Oracle

Tout se relance de zéro avec un seul fichier, `prerequis/run_all.sql`, connecté en **`langues` / `langues`**, service `FREEPDB1`. Les chemins sont relatifs au dossier `prerequis/`.

| Ordre | Script                                            | Livrable                                                                            |
| ----- | ------------------------------------------------- | ----------------------------------------------------------------------------------- |
| 00    | `prerequis/00_nettoyage.sql`                      | supprime tout pour repartir de zéro                                                 |
| 01    | `L1_modele/01_creation_tables.sql`                | L1 · tables et contraintes nommées                                                  |
| 02    | `L2_chargement_requetes/02_chargement.sql`        | L2 · chargement des CSV et traitement des défauts                                   |
| 03    | `L2_chargement_requetes/03_valeurs_controle.sql`                     | L2 · valeurs C1 à C9                                                                |
| 04    | `L2_chargement_requetes/04_requetes_metier.sql`                      | L2 · 10 requêtes métier                                                             |
| 05    | `L3_normalisation/05_normalisation.sql`           | L3 · table à plat, DF, décomposition, dénormalisation                               |
| 06    | `L4_fiabilite/06_triggers.sql`                    | L4 · triggers et journal d'audit                                                    |
| 07    | `L4_fiabilite/07_package_parcours.sql`            | L4 · parcours multi-sites tout ou rien                                              |
| 08    | `L5_perf_et_securite/08_performance.sql`                          | L5 · requêtes lentes, index, vue matérialisée                                       |
| 09    | `L5_perf_et_securite/09_securite.sql`                             | L5 · rôles, vues de restriction, sécurité par ligne (VPD)                           |
| 10    | `L6_distribution/10_distribution.sql`                         | L6 · fragmentation par site, liens, vues globales                                   |
| 11    | `bonus_objet/11_bonus_objet.sql`                          | bonus objet-relationnel : type `t_campus` avec méthode, sous-type `t_site`, requête |

Scripts lancés **à la main**, après `run_all.sql` :

| Script | Livrable | Connexion | Résultat de référence |
| --- | --- | --- | --- |
| `L3_normalisation/L3_denormalisation.sql` | L3 · tests de la dénormalisation | `langues` | `preuves/L3_denormalisation.txt` |
| `L4_fiabilite/L4_tests_fiabilite.sql` | L4 · tests des triggers et du package (12 contrôles OK + 2 tableaux à lire) | `langues` | `preuves/L4_tests_fiabilite.txt` |
| `L4_fiabilite/L4_concurrence_session_A.sql` + `_B.sql` | L4 · anomalie de concurrence | deux connexions `langues` ouvertes en même temps (feuille non partagée), étapes en alternance | `preuves/L4_concurrence.txt` |
| `L5_perf_et_securite/L5_securite.sql` | L5 · ce que voit chaque compte | se connecte tour à tour avec `agent_bordeaux`, `agent_tours`, `direction` | `preuves/L5_securite.txt` |
| `L6_distribution/L6_panne_reprise.sql` | L6 · panne d'Angers et reprise | `langues`, sauf étapes 2 et 4 en `system` | `preuves/L6_panne_reprise.txt` (18 OK) |
| `L7_nosql/mongodb/` | L6 · collection MongoDB shardée | voir `L7_nosql/mongodb/README.md` | `preuves/L6_mongodb.txt` |
| `L7_nosql/elasticsearch/` | L7 · recherche d'un étudiant | voir `L7_nosql/elasticsearch/README.md` | `preuves/L7_elasticsearch.txt` |
| `L7_nosql/neo4j/` | L7 · recommandation de sessions | voir `L7_nosql/neo4j/README.md` | `preuves/L7_neo4j.txt` |

Le kit demande de lancer un moteur NoSQL à la fois (`docker compose --profile elasticsearch up -d`, puis `--profile neo4j`, dans `C:\bdd-kit\3-nosql`).

## Où trouver chaque livrable

| Livrable | Documents |
| --- | --- |
| L1 | `L1_modele/L1_modele.md` (16 règles de gestion, E/A, relationnel), `L1_modele/L1_schema_relationnel.md`, `L1_modele/modele E_A.png` |
| L2 | `L2_chargement_requetes/L2_chargement_requetes.md`, `L2_chargement_requetes/03_valeurs_controle.sql`, `L2_chargement_requetes/04_requetes_metier.sql` |
| L3 | `L3_normalisation/L3_normalisation.md` (version SQL, rejouable) ; exploration Python initiale (Younes) dans `L3_normalisation/exploration_python/` |
| L4 | `L4_fiabilite/` (triggers, package, tests, concurrence) |
| L5 | `L5_perf_et_securite/` (performance, sécurité, preuve par compte) |
| L6 | `L6_distribution/` (fragmentation, panne et reprise), `L7_nosql/mongodb/` (MongoDB shardé) ; `L6_distribution/L6_distribution.md` (mesures, panne, MongoDB, CAP / PACELC, RGPD) |
| L7 | `L7_nosql/` |
| L8 | `L8_adr/ADR-01.md`, `L8_adr/ADR-02.md`, `L8_adr/options_ADR.md` |
| Bonus | `bonus_objet/11_bonus_objet.sql` (type `t_campus`, sous-type `t_site`, méthode, requête) |
| Rapport | `RAPPORT.md` |

## Vocabulaire du sujet → nos données

| Sujet                  | Chez nous                   | Fichier             |
| ---------------------- | --------------------------- | ------------------- |
| usager                 | étudiant                    | `etudiants.csv`     |
| ressource              | session de cours            | `sessions.csv`      |
| opération              | inscription                 | `inscriptions.csv`  |
| opération groupée      | parcours (même `id_groupe`) | `inscriptions.csv`  |
| catégorie de ressource | langue de la session        | colonne `categorie` |

Une opération est **valide** si sa session existe, si son montant est ≥ 0 et si sa date est ≤ au début de la session.
