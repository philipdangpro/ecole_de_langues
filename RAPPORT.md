# Plateforme de données d'une école de langues multi-sites

Data Storage Systems (SQL & NoSQL) · MS DGAI1 · **groupe 07** : Baptiste GERBOUIN, Younes IFOURAH, Philip DANG

Organisation : école de langues, un siège (Paris) et trois campus (Bordeaux, Tours, Angers). Opération groupée : le **parcours** qui combine plusieurs campus (`id_groupe`). Pic de trafic : la **rentrée de septembre**.

Tous les chiffres de ce rapport sont produits par nos scripts sur notre base, reconstruite sur un kit neuf (Oracle 23ai Free du kit, `prerequis/installation_system.sql` puis `prerequis/run_all.sql` : 1 min 06 s, 0 erreur, rejoué le 26/11/2026).

## Valeurs de contrôle

| Valeur | Ce qu'elle mesure | Résultat |
|---|---|---|
| C1 | personnes distinctes | **21 471** (21 544 lignes ; 73 copies d'un même e-mail normalisé fusionnées ; les 32 lignes sans e-mail comptent chacune pour une personne) |
| C2 | opérations non valides, par motif | **397** : session inexistante 220, date après le début 97, montant négatif 80 |
| C3 | opérations valides confirmées | **326 469** |
| C4 | jour avec le plus d'opérations valides | **10/09/2026 : 16 068** opérations (le jour suivant au classement : 552) |
| C5 | chiffre d'affaires par site | **Bordeaux 27 333 192 · Tours 56 080 982 · Angers 39 082 945** (total 122 497 119) |
| C6 | personnes avec des opérations valides sur au moins deux sites | **12 356** |
| C7 | sessions en sur-réservation | **15** |
| C8 | opérations groupées engageant au moins deux sites | **1 874** (sur 2 667 parcours) |
| C9 | places confirmées par catégorie | **FLE 55 104 · allemand 52 705 · anglais 54 870 · chinois 54 681 · espagnol 54 579 · italien 54 530** (total 326 469 = C3) |

Requêtes : annexe A (`L2_chargement_requetes/03_valeurs_controle.sql`). C5, C6 et C8 sont recalculés à l'identique sur la collection MongoDB shardée (L6), et C1 sur le CSV brut, avec la règle du sujet.

C2 compte les défauts des données reçues, pas ceux de la base : les opérations non valides ne sont pas chargées dans `INSCRIPTION`, mais gardées dans `INSCRIPTION_REJET` avec leur motif (rejet tracé). C'est ce qui permet de les compter et de les retrouver ; un refus silencieux par contrainte les aurait fait disparaître. Pour vérifier que notre logique de rejet ne se trompe pas, la règle du sujet a aussi été appliquée directement aux tables externes, sans passer par le chargement : 397 opérations non valides sur 354 855 lignes du CSV, le même nombre que dans `INSCRIPTION_REJET`. Requête de vérification :

```sql
SELECT COUNT(*) AS lignes_csv,
       SUM(CASE WHEN s.id_session IS NULL
                  OR TO_NUMBER(i.montant, '999999D99', 'NLS_NUMERIC_CHARACTERS=''.,''') < 0
                  OR TO_DATE(TRIM(i.date_inscription), 'YYYY-MM-DD HH24:MI:SS')
                     > TO_DATE(TRIM(s.debut), 'YYYY-MM-DD HH24:MI:SS')
                THEN 1 ELSE 0 END) AS c2
FROM ext_inscriptions i
LEFT JOIN ext_sessions s ON s.id_session = i.id_session;
```

---

## L1 · Modèle

| Décision | Justification / mesure | Fichier |
|---|---|---|
| 16 règles de gestion (RG1 à RG16), chacune liée à la contrainte ou au trigger qui la garantit | 12 exigées | `L1_modele/L1_modele.md` |
| **Héritage** CAMPUS → SIEGE / SITE, une table par sous-type, clé étrangère composite `(id_campus, type_campus)` | un étudiant ou une session ne peut pas pointer vers le siège (RG3), garanti par une clé étrangère | `L1_modele/01_creation_tables.sql` |
| **Association réflexive** PARRAINER sur ETUDIANT | RG7 (parrain plus ancien, pas lui-même) | idem |
| **Association porteuse** INSCRIRE (date, places, montant, statut, groupe), avec un identifiant propre | un étudiant peut s'inscrire, annuler puis se réinscrire à la même session ; l'audit vise une inscription précise | idem |
| `SESSION_COURS` (et non `SESSION`, mot réservé) ; `INSCRIPTION.date_operation` | les deux CSV ont une colonne `date_inscription` de sens différent | idem |
| Toutes les contraintes nommées (`pk_`, `fk_`, `uq_`, `ck_`, `nn_`) ; pas d'index sur les clés étrangères | les index sont décidés au L5, sur mesure | idem |

Schéma entité-association : `L1_modele/modele E_A.png`. Schéma relationnel colonne par colonne : `L1_modele/L1_schema_relationnel.md`. 26 refus de contraintes testés (`preuves/L1_tests_contraintes.txt`, local).

## L2 · Chargement et requêtes

| Défaut trouvé dans les CSV | Volume | Traitement | Justification |
|---|---|---|---|
| Étudiants en double (même e-mail une fois en minuscules et sans espaces) | 73 copies | fusion vers le plus petit id, copies tracées dans `ETUDIANT_DOUBLON`, inscriptions rattachées à l'original | définition « même personne » du sujet (C1) ; contrainte `uq_etudiant_email` ensuite |
| Étudiants sans e-mail | 32 | gardés, une personne chacun | définition du sujet |
| Opérations sur une session inexistante / montant négatif / date après le début | 220 / 80 / 97 | **rejet tracé** dans `INSCRIPTION_REJET` avec le motif, jamais corrigées | corriger un montant fausserait C3 et C5 ; chaque opération n'a qu'un motif |
| Doubles confirmations, inscriptions avant la création du compte, sessions sur-réservées | 154 / 126 / 15 | **chargées** (elles sont valides au sens du sujet, C7 les compte) | bloquées pour les nouvelles opérations par les triggers et le package du L4 |

Chargement : tables externes + `INSERT … SELECT` (354 855 lignes en quelques secondes ; `DETECTED NEWLINE`, point décimal imposé). Bilan : 21 471 étudiants, 47 619 sessions, 354 458 inscriptions chargées, 397 rejetées.

**10 requêtes métier** (`L2_chargement_requetes/04_requetes_metier.sql`, énoncé et résultat en commentaire) :

| | Énoncé | Notion | Résultat |
|---|---|---|---|
| R1 | Taux d'annulation par langue | agrégat conditionnel | de 7,80 % (chinois) à 8,05 % (italien) |
| R2 | Étudiants avec au moins 30 inscriptions confirmées | **HAVING** | maximum 34 (étudiants 19039 et 19165) |
| R3 | Sessions sans aucun inscrit confirmé, par site | **jointure externe** | Angers 1, Bordeaux 2, Tours 1 |
| R4 | Sessions mieux remplies que la moyenne de leur langue | **sous-requête corrélée** | de 3 879 (allemand) à 4 084 (anglais) par langue |
| R5 | Étudiants ayant suivi les 6 langues | **division** (double `NOT EXISTS`) | 12 985 |
| R6 | CA mensuel et cumul | **fenêtrage** `SUM() OVER` | pic 2026-09 : 23 641 inscriptions, 8,9 M€ (≈ 5,1 M€ les autres mois) |
| R7 | Places et CA par campus, siège compris | jointure externe | siège 0 ; totaux = C5 |
| R8 | 10 plus gros clients | tri + `FETCH FIRST` | 13 706 € au plus (étudiant 12856) |
| R9 | Langues classées par places confirmées | **fenêtrage** `DENSE_RANK` | FLE 1er, allemand 6e |
| R10 | Top 3 des sessions par langue | **fenêtrage** `ROW_NUMBER` | maximum 17 places (session 23879, espagnol) |

R5 : la forme d'école de la division a été arrêtée après 5 min (pas encore d'index sur `INSCRIPTION.id_etudiant` à cette étape : Oracle relisait la table pour chaque couple étudiant × langue). Elle est réécrite pour que les couples manquants soient construits dans un seul bloc : anti-jointure par hachage, 0,15 s, même résultat que la division par comptage.

## L3 · Normalisation

| Étape | Résultat mesuré | Fichier |
|---|---|---|
| Table à plat `OPERATION_A_PLAT` (opération + étudiant + session + 2 campus) | 354 855 lignes, 28 colonnes, 88 Mo (23 Mo décomposée). Anomalies constatées : le siège ne peut pas y figurer (insertion), 16 lignes par e-mail à modifier (modification), une session disparaît avec sa dernière opération (suppression) | `L3_normalisation/05_normalisation.sql` |
| 8 DF retenues, vérifiées par requête (violations comptées) | D5 e-mail → étudiant : 73 violations sur le CSV brut, 0 après le L2 ; D6 (session, places) → montant : 88, puis 0 ; D7 groupe → étudiant : 9, puis 0 | `L3_normalisation/L3_normalisation.md` |
| 5 DF écartées | N4 ville → campus et N5 libellé → session : 0 violation, mais aucune règle ne les impose (le libellé est fabriqué à partir de l'identifiant) : une DF observée n'est pas une DF du métier | idem |
| Décomposition théorique | CAMPUS, ETUDIANT, SESSION, OPERATION_GROUPEE, INSCRIPTION (sans montant) : **BCNF** (tout déterminant est une clé) ; **sans perte** : 0 ligne inventée, 0 ligne perdue (`MINUS` dans les deux sens) ; dépendances préservées | idem |
| Base réelle | toutes les tables en BCNF sauf INSCRIPTION, en **2NF par choix** : trois dépendances transitives assumées (site, montant, parcours), chacune tenue par un mécanisme de la base | idem |
| **Dénormalisation assumée** : `INSCRIPTION.id_site` (le site de la session, recopié) | tenue par une clé étrangère composite vers `(id_session, id_campus)` et le trigger `trg_inscription_site` : jamais incohérente (déplacer une session qui a des inscriptions est refusé, ORA-02292). Lecture : 2 391 → 2 266 blocs (−5 %). Raison principale : fragmenter par site au L6 sans jointure | `L3_normalisation/L3_denormalisation.sql`, `preuves/L3_denormalisation.txt` |

**Justification des deux autres écarts.**
- **`montant` gardé** : D6 n'est vraie qu'au moment de l'opération. Le montant est le prix payé ce jour-là ; si le prix d'une session change ensuite, les anciennes inscriptions gardent leur montant, sinon le chiffre d'affaires passé (C5) changerait. C'est un fait historique, pas une copie. À l'insertion, le trigger du L4 le calcule.
- **Opération groupée gardée dans INSCRIPTION** : une table OPERATION_GROUPEE ne contiendrait que l'étudiant et le statut, déjà présents sur chaque inscription (3 lignes par parcours en moyenne). Le tout ou rien est garanti par la transaction du package du L4, pas par une table. Et avec la fragmentation du L6, une table à part devrait vivre sur un seul site : chaque parcours multi-sites toucherait une base de plus. Limite assumée : D7 et D8 sont tenues par le package, pas par une contrainte ; contrôle par requête, 0 violation.

Une première exploration en Python (Younes) est gardée dans `L3_normalisation/exploration_python/` ; elle n'est pas rejouable sur le kit et a été reprise en SQL.

## L4 · Fiabilité

| Élément | Ce qu'il fait | Preuve |
|---|---|---|
| `TRG_INSCRIPTION_AUDIT` (**journal d'audit**) | une ligne par INSERT / UPDATE / DELETE : qui, quand, avant / après. Dans la transaction (pas autonome) : un parcours refusé ne laisse aucune trace d'inscription fantôme. Ni nom ni e-mail (RGPD) | T2 |
| `TRG_INSCRIPTION_REGLES` | RG12 calcule le montant (places × prix), RG11 date ≤ début, RG14 après la création du compte | T4, T6, T7 |
| `TRG_INSCRIPTION_DOUBLON`, `TRG_ETUDIANT_PARRAIN` (triggers composés) | RG13 une seule confirmation par session, RG7 parrain plus ancien. Composés car un trigger ligne lirait une table en mutation (ORA-04091). Pas d'index unique pour RG13 : les 154 doublons historiques l'empêchent | T5, T11, T13 |
| `PKG_PARCOURS.inscrire_parcours` | parcours multi-sites **tout ou rien** (`SAVEPOINT`), verrouille chaque session (`SELECT … FOR UPDATE`) puis compte les places : refuse la sur-réservation (ORA-20010) | T1, T3, T8 à T10, T12, T14 |

14 tests, tous OK (`L4_fiabilite/L4_tests_fiabilite.sql`, `preuves/L4_tests_fiabilite.txt`).

**Anomalie de concurrence** (`sql/L4_concurrence_session_A.sql` / `_B.sql`, deux sessions) : deux étudiants voient chacun la dernière place d'une session (capacité 1) et s'inscrivent : **2 places confirmées pour 1** (écriture biaisée). Le niveau `SERIALIZABLE` ne corrige pas (les deux INSERT touchent des lignes différentes). Correction : le verrou `FOR UPDATE` du package. B attend le COMMIT de A, puis reçoit ORA-20010 et ne garde rien, pas même la session qui avait de la place. Rejoué le 26/11/2026 avec deux connexions réelles.

## L5 · Performance et sécurité

| Requête lente | Avant | Optimisation | Après |
|---|---|---|---|
| Q1 historique d'un étudiant (accueil) | 2 301 blocs, lecture complète | index `ix_inscription_etudiant (id_etudiant, id_session, statut)` | **56** (÷ 41) |
| Q2 places confirmées d'une session (contrôle du package, appelé à chaque inscription, donc au pic) | 2 265 | index **couvrant** `ix_inscription_session (id_session, statut, nb_places)` : plus d'accès à la table | **3** (÷ 755) |
| Q3 tableau de bord site × langue (326 000 lignes lues, aucun index n'aide) | 2 644 | **vue matérialisée** `mv_activite_mensuelle` (432 lignes), réécriture automatique de la requête inchangée | **4** (÷ 661) |

Mesure : hint `GATHER_PLAN_STATISTICS` + `DBMS_XPLAN.DISPLAY_CURSOR('ALLSTATS LAST')`, colonne Buffers (lectures logiques, indépendantes du cache). Vue rafraîchie à la demande ; périmée, elle n'est plus utilisée (`query_rewrite_integrity = enforced`) : lente, jamais fausse.

| Compte | Rôle / vue | Lignes vues | Données personnelles |
|---|---|---|---|
| `agent_bordeaux`, `agent_tours` | `role_agent_site` / `v_inscrits_site` | son site seulement (78 676 / 162 669 inscriptions) | nom, prénom, téléphone (ni e-mail, ni ville, ni parrain) |
| `direction` | `role_direction` / `v_activite_site` | 3 sites | **aucune**, pas même l'identifiant |
| tout autre compte | — | rien (`1 = 0`) | — |

Mécanisme : **sécurité par ligne (VPD)** sur INSCRIPTION et SESSION_COURS, site lu dans la table `COMPTE_SITE` (ajouter un agent = une ligne, sans code). Preuve compte par compte (`L5_perf_et_securite/L5_securite.sql`, `preuves/L5_securite.txt`) : même requête, résultats différents ; refus ORA-00904 (e-mail hors vue), ORA-00942 (tables, vue d'un autre rôle), ORA-41900 (modification).

## L6 · Distribution

| Élément | Décision | Mesure |
|---|---|---|
| Fragmentation horizontale | 3 schémas de site (`site_bordeaux`, `site_tours`, `site_angers`) ; SESSION et INSCRIPTION selon le site de la session (fragmentation dérivée, grâce à `id_site` du L3) ; ETUDIANT selon le site de rattachement ; CATEGORIE répliquée | inscriptions 78 676 / 162 669 / 113 113 ; étudiants 4 646 / 9 820 / 7 005 |
| Liens et vues globales | 3 liens, vues `V_G_*` en `UNION ALL` avec le prédicat de chaque fragment (localisation : une requête « Tours » n'exécute que la branche Tours) | reconstruction : table centrale `MINUS` vue globale = 0 ligne, dans les deux sens ; 0 doublon |
| Coût | 22 955 inscriptions (6,5 %) ont leur étudiant dans un autre site : la clé étrangère ne traverse pas un lien, vérifiée par requête | 0 orpheline. Piège : `NOT EXISTS` à travers le lien = 4 min 27 s ; jointure par hachage = 0,3 s |
| Panne d'Angers et reprise | parcours via Angers refusé en entier (2PC) ; Bordeaux + Tours continue ; inscription simple mise en attente au siège, rejouée à la reprise avec nouveau contrôle de capacité ; catalogue lu dans une copie au siège (bascule), conflit réglé par « le dernier écrivain gagne » | **18 OK, 0 échec** ; au rejeu 2 inscriptions appliquées, 1 refusée (plus de place), aucune sur-réservation |
| MongoDB shardé (3 shards) | `langues.inscriptions`, clé **`{ id_etudiant: "hashed" }`** | clé par site : 22 / 46 / 32 % et 3 valeurs seulement ; par date : le 10/09 concentre 16 068 opérations sur le dernier morceau ; **étudiant haché : 33,5 / 32,3 / 34,2 %**, historique et parcours d'un étudiant sur 1 shard (`SINGLE_SHARD`) ; C5, C6, C8 identiques à Oracle |

**CAP / PACELC** (détail : `L6_distribution/L6_distribution.md`) : vues globales, parcours 2PC, étudiant en une seule copie, MongoDB par défaut : **PC/EC** (pour l'argent et les places, on refuse plutôt que de répondre faux) ; file d'attente des inscriptions simples, copie du catalogue : **PA/EC** (l'écart se rattrape à la reprise, sans jamais forcer une place) ; CATEGORIE répliquée : **PA/EL**.

## L7 · NoSQL

| Moteur | Besoin réel (mesuré dans Oracle) | Résultat |
|---|---|---|
| **Elasticsearch** : retrouver un étudiant malgré les fautes | 50 noms et 40 prénoms pour 21 471 étudiants (jusqu'à 23 homonymes) ; « Betrand Leo » : Oracle `=` et `LIKE` → 0 résultat | index minimal (nom, prénom, ville, site ; ni e-mail ni téléphone), analyseur sans accent, `fuzziness: AUTO` : 21 471 documents, `errors: false`, **les 15 Léo Bertrand en tête** ; filtre sur le site : les 5 de Tours |
| **Neo4j** : recommander des sessions à venir | 60 % des étudiants ont déjà suivi les 6 langues : on recommande des sessions, pas des langues | graphe Étudiant–INSCRIT→Session (326 469 relations) ; 5 sessions recommandées à l'étudiant 2141, 5 193 accès |

Mesure écrite telle quelle : la même recommandation en SQL donne les mêmes 5 sessions plus vite (633 blocs, 0,02 s contre 0,1 à 0,25 s). Neo4j est gardé pour la lisibilité des parcours de longueur variable ; nous ne prétendons pas qu'il est plus rapide sur ce volume. Comparaisons : `L7_nosql/*/L7_oracle_comparaison.sql`.

## Bonus objet-relationnel

`t_campus` (`NOT FINAL`, méthode `presenter()`), `t_site UNDER t_campus`, table objet `campus_objet`, requête avec `IS OF` / `TREAT` qui appelle la méthode : « Site Tours (Tours) », type `T_SITE` (`sql/11_bonus_objet.sql`). L'exemple reprend l'héritage réel du L1.

## Demande de changement

Sans objet : la version révisée du sujet (24/10/2026) ne prévoit pas de demande de changement.

## ADR

Les deux ADR sont reproduits ci-dessous (`L8_adr/`). Options non évidentes étudiées : `L8_adr/options_ADR.md`. Chacun repose sur nos mesures (L6, L7) et fixe sa contrainte imposée : ADR-01, « un site en panne ne doit bloquer ni les autres sites, ni les places » ; ADR-02, « au pic de la rentrée, Oracle doit rester libre pour les inscriptions ».

<!-- PARTIES GÉNÉRÉES -->

## ADR-01 · Répartir les données selon le site de la session

Statut : accepté le 31/10/2026. Responsable : Baptiste.

### 1. Contexte et contrainte imposée

- Un siège (Paris) et trois sites : Bordeaux, Tours, Angers.
- 21 471 étudiants, 47 619 sessions, 354 458 inscriptions.
- Répartition des inscriptions : Bordeaux 22,2 %, Tours 45,9 %, Angers 31,9 %.
- Opération groupée : le parcours qui combine plusieurs campus. 2 667 parcours, dont 1 874 multi-sites. Tout ou rien.
- Pic : la rentrée de septembre. 16 068 inscriptions le 10/09/2026, contre 449 par jour en moyenne.
- Contrainte : un site en panne ne doit bloquer ni les autres sites, ni les places (pas de sur-réservation).

### 2. Options envisagées

- **A. Tout au siège.** Une seule base Oracle, les sites s'y connectent.
- **B. Fragments par site.** Session et inscription dans le site de la session ; étudiant dans son site de rattachement ; catégories copiées partout ; copie du catalogue d'Angers au siège. Liens Oracle et vues globales.
- **C. B, avec l'étudiant copié** dans chaque site où il suit des cours.
- **D. Une base, partitionnée par site** (`PARTITION BY LIST (id_site)`). Pas de lien, pas de 2PC.
- **E. Inscriptions rangées avec l'étudiant**, pas avec la session.

### 3. Critères

| Critère | A · siège | B · fragments (retenu) | C · étudiant copié | D · partitions | E · avec l'étudiant |
|---|---|---|---|---|---|
| Cohérence | ++ (ACID local) | + (2PC pour le parcours) | − (copies à synchroniser) | ++ | − (capacité contrôlée à distance) |
| Disponibilité | −− (siège en panne = tout bloqué) | + (Tours et Bordeaux continuent, étape 3f) | ++ (plus d'étudiants illisibles) | −− (une seule base) | + |
| Latence | − (chaque site passe par le réseau) | ++ (93,5 % des inscriptions ont leur étudiant dans le même site) | ++ | − (réseau) | − (contrôle de place par lien) |
| Volumétrie | + | + (Tours porte 45,9 %) | + | ++ | + |
| Coût | ++ (une base) | − (4 bases, liens, file d'attente) | −− (synchronisation en plus) | ++ | − |
| Sécurité, chiffrement | + (VPD du L5) | + (chaque site ne voit que son fragment ; TDE et chiffrement des liens à activer) | − (données perso en plusieurs copies) | + | + |

### 4. Mesures (preuves/L6_distribution.txt, preuves/L6_panne_reprise.txt)

- Reconstruction : table centrale `MINUS` vue globale = 0 ligne d'écart, sur les 3 tables.
- Coût de B : 22 955 inscriptions (6,5 %) ont leur étudiant dans un autre site.
- Panne d'Angers : Tours ne peut plus afficher 4 854 inscriptions (étape 3d).
- Panne d'Angers : parcours Bordeaux + Tours validé, parcours Bordeaux + Angers refusé en entier (`ORA-20020`).
- File d'attente : 3 inscriptions gardées au siège ; à la reprise, 2 rejouées, 1 refusée (« 0 place libre sur 10 »).
- Piège mesuré : contrôle entre sites avec `NOT EXISTS` = 4 min 27 s ; en jointure par hachage = 0,3 s.

### 5. Décision

Nous choisissons B. La session décide du site : une inscription reste avec sa session, donc le contrôle de place reste local. Le parcours multi-sites passe par le 2PC.

### 6. Conséquences et risques

- Facile : chaque site travaille seul, même au pic ; une panne n'arrête que son site.
- Difficile : les totaux du siège (vues globales) échouent dès qu'un site manque (étape 3a).
- Inconvénient : 6,5 % des inscriptions demandent un lien pour afficher le nom.
- Risque : conflit sur le catalogue copié. Parade : le dernier écrivain gagne (`derniere_maj`). Perte silencieuse de la modification la plus ancienne.
- Risque : horloges des sites décalées. Parade : synchronisation NTP.
- Seuil : si plus de 20 % des inscriptions ont leur étudiant dans un autre site, nous reprendrons l'option C.

### 7. Volet RGPD

- Données personnelles : nom, prénom, e-mail, téléphone, ville de l'étudiant.
- Minimisation : une seule copie, dans le site de rattachement. Le siège n'a que des annuaires (identifiant → site). Les agents ne voient que leur site (VPD du L5).
- Conservation : 3 ans après la dernière inscription (à valider avec le délégué à la protection des données). Purge par tâche planifiée (`DBMS_SCHEDULER`), pas encore écrite.
- Effacement : la ligne dans son site, ses inscriptions dans les 3 fragments, la file d'attente, le journal d'audit du L4, ses documents MongoDB (un seul shard). Sauvegardes : effacées à l'expiration.
- Localisation : siège et sites en France. Aucun transfert hors UE.

### 8. Liens

L3 (colonne `id_site`), L4 (parcours tout ou rien), L6 (`sql/10_distribution.sql`, `L6_distribution/L6_distribution.md`), ADR-02.

## ADR-02 · Rechercher un étudiant malgré les fautes avec Elasticsearch

Statut : accepté le 31/10/2026. Responsable : Baptiste.

### 1. Contexte et contrainte imposée

- Besoin : l'accueil retrouve un étudiant au téléphone. Le nom est souvent mal tapé (« Betrand Leo »).
- 21 471 étudiants, mais seulement 50 noms et 40 prénoms.
- 2 000 paires nom + prénom : 10,7 homonymes en moyenne, jusqu'à 23. Martin : 484 étudiants.
- Aucun texte libre dans nos données : ce qu'on cherche, ce sont des personnes.
- Contrainte : au pic de la rentrée (16 068 inscriptions le 10/09/2026), Oracle doit rester libre pour les inscriptions.

### 2. Options envisagées

- **A. Oracle seul, distance entre mots** (`UTL_MATCH.EDIT_DISTANCE`).
- **B. Oracle Text** : index `CONTEXT` sur nom et prénom, recherche `FUZZY`.
- **C. Elasticsearch** : un index d'étudiants (nom, prénom, ville, site), accents retirés, `fuzziness: AUTO`.
- **D. Oracle, recherche phonétique** : `SOUNDEX` sur une colonne indexée.

### 3. Critères

| Critère | A · UTL_MATCH | B · Oracle Text | C · Elasticsearch (retenu) | D · SOUNDEX |
|---|---|---|---|---|
| Cohérence | ++ (lit la table) | + (index mis à jour par synchronisation) | − (copie, rechargée depuis Oracle) | ++ |
| Disponibilité | + (celle d'Oracle) | + | + (Oracle reste la référence si l'index tombe) | + |
| Latence, pertinence | − (0,08 s, 49 lignes sans classement) | + (score, non mesuré) | ++ (15 bons en tête, score 6,92) | −− (0 ligne) |
| Volumétrie | − (lecture complète à chaque recherche) | ++ | ++ (index inversé) | ++ (index) |
| Coût | ++ (rien à installer) | + (dans Oracle) | − (un moteur de plus, un export) | ++ |
| Sécurité, chiffrement | ++ (VPD du L5) | ++ | − (copie des noms ; sécurité coupée dans le kit, TLS à activer) | ++ |

### 4. Mesures (preuves/L7_elasticsearch.txt, L7_nosql/elasticsearch/L7_oracle_comparaison.sql)

- Oracle, `=` et `LIKE '%BETRAND%'` : 0 résultat.
- Oracle, `UTL_MATCH` : 49 lignes, dont les 15 Léo Bertrand, en 0,08 s. Plan : `TABLE ACCESS FULL`.
- Oracle, `SOUNDEX` : « Betrand » = B365, « Bertrand » = B636. 0 résultat.
- Elasticsearch : import `"errors": false`, 21 471 documents. Les 15 Léo Bertrand en tête.
- Elasticsearch, filtre sur le site de Tours : ses 5 Léo Bertrand en tête.
- Une seule zone de saisie (« leo bertran tours ») : les Léo Bertrand de Tours en tête.

### 5. Décision

Nous choisissons C. Seul Elasticsearch classe les bonnes réponses en tête, et il décharge Oracle pendant le pic de la rentrée.

### 6. Conséquences et risques

- Facile : recherche sur plusieurs champs, sans accent, avec fautes, classée.
- Difficile : l'index est une copie. Un nouvel étudiant n'y est qu'après le prochain export.
- Inconvénient : un moteur de plus à faire tourner et à sécuriser.
- Risque : les 15 homonymes ont le même score. Parade : l'agent filtre par site ou par ville.
- Risque : index en retard. Parade : export chaque nuit ; la fiche est toujours relue dans Oracle par son identifiant.
- Seuil : si l'index a plus d'un jour de retard plus d'une fois par mois, nous reprendrons B (recherche dans Oracle, sans copie).

### 7. Volet RGPD

- Données personnelles : nom, prénom, ville, site. Ni e-mail, ni téléphone dans l'index.
- Minimisation : l'index sert à trouver l'identifiant. La fiche complète se lit dans Oracle, avec la VPD du L5.
- Conservation : la même que dans Oracle (ADR-01). L'index est reconstruit à chaque export : un étudiant purgé disparaît au suivant.
- Effacement : `DELETE /etudiants/_doc/<id>` en même temps que la suppression dans Oracle. L'export suivant le confirme. Instantanés de l'index : à supprimer aussi.
- Localisation : serveur en France, à côté d'Oracle. Un service managé hors UE est exclu.

### 8. Liens

L7 (`L7_nosql/elasticsearch/`), ADR-01 (localisation de l'étudiant), L5 (VPD).

---

# Annexes

## Annexe A · Requêtes des valeurs de contrôle (`L2_chargement_requetes/03_valeurs_controle.sql`)

```sql
-- =====================================================================
-- 03_valeurs_controle.sql
-- Livrable : L2 · Valeurs de contrôle
-- Responsable : à définir
-- Attendu  : une requête par valeur C1 à C9, avec le résultat obtenu en commentaire
-- Lancé par : prerequis/run_all.sql (ne pas changer l'ordre sans prévenir)
--
-- Rappel : INSCRIPTION ne contient que les opérations valides (les autres sont dans
-- INSCRIPTION_REJET, voir 02_chargement.sql). Pas besoin de refiltrer pour C3 à C9.
-- =====================================================================


-- ---------------------------------------------------------------------
-- C1 : nombre de personnes distinctes
--    Les doublons (même e-mail une fois en minuscules et sans espaces) ont été fusionnés
--    au chargement : une ligne d'ETUDIANT = une personne.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS c1
FROM etudiant;
-- Résultat : 21 471

-- Vérification sur le CSV brut (table externe, avant fusion), avec la règle du sujet :
--   e-mails distincts une fois normalisés + lignes sans e-mail (une personne chacune).
--   COUNT(*) - COUNT(email) = nombre de lignes sans e-mail (COUNT(email) ignore les NULL).
SELECT COUNT(*) AS lignes_csv,
       COUNT(DISTINCT LOWER(REPLACE(email, ' ', ''))) + COUNT(*) - COUNT(email) AS c1
FROM ext_etudiants;
-- Résultat : 21 544 lignes, 21 471 personnes (identique à C1 : la fusion est juste)


-- ---------------------------------------------------------------------
-- C2 : nombre d'opérations non valides, et leur répartition par motif
--    Les opérations non valides sont dans INSCRIPTION_REJET, avec leur motif
--    (02_chargement.sql). ROLLUP ajoute une ligne de total sous le détail par motif.
--    Chaque opération n'a qu'un motif : aucune n'a deux défauts à la fois (vérifié sur le CSV).
-- ---------------------------------------------------------------------
--    Alias différent du nom de colonne : sinon ORDER BY motif vise l'alias (ORA-00979).
SELECT NVL(motif, 'TOTAL (C2)') AS motif_rejet, COUNT(*) AS nb
FROM inscription_rejet
GROUP BY ROLLUP (motif)
ORDER BY GROUPING(motif), motif_rejet;
-- Résultat : DATE_APRES_DEBUT 97, MONTANT_NEGATIF 80, SESSION_INEXISTANTE 220
--            TOTAL 397 opérations non valides



-- ============================================================
-- C3 : nombre d'operations valides confirmees
-- ============================================================
SELECT COUNT(*) AS c3
FROM inscription i
JOIN session_cours s
  ON s.id_session = i.id_session
WHERE i.statut = 'CONFIRMEE'
  AND i.montant >= 0
  AND i.date_operation <= s.debut;

-- Resultat attendu : 326469





-- ---------------------------------------------------------------------
-- C4 : le jour où le plus d'opérations valides ont été passées, et leur nombre
--    Toutes les opérations valides comptent (confirmées et annulées).
--    TRUNC enlève l'heure de date_operation pour regrouper par jour.
-- ---------------------------------------------------------------------
SELECT TRUNC(date_operation) AS jour, COUNT(*) AS cpt
FROM inscription
GROUP BY TRUNC(date_operation)
ORDER BY cpt DESC
FETCH FIRST 1 ROWS ONLY;
-- Résultat : 10/09/2026, 16 068 opérations
--   Pas d'égalité : le jour suivant au classement en a 552. Le pic vient du CSV
--   (16 082 lignes ce jour-là, dont 14 non valides), heures réparties sur toute la journée.

-- ---------------------------------------------------------------------
-- C5	chiffre d'affaires de chaque site (somme des montants des opérations valides confirmées)
--    Le site d'une opération est celui de sa session : on passe par SESSION_COURS
--    (la colonne INSCRIPTION.id_site n'existe qu'après 05_normalisation.sql).
-- ---------------------------------------------------------------------
SELECT s.id_campus AS id_site, c.nom AS site, SUM(i.montant) AS chiffre_affaires
FROM inscription i
JOIN session_cours s ON s.id_session = i.id_session
JOIN campus c        ON c.id_campus  = s.id_campus
WHERE i.statut = 'CONFIRMEE'
GROUP BY s.id_campus, c.nom
ORDER BY s.id_campus;
-- Résultat : Bordeaux (2) 27 333 192 ; Tours (3) 56 080 982 ; Angers (4) 39 082 945

-- ============================================================
-- C6 : personnes ayant des operations valides
--      sur au moins deux campus distincts
-- ============================================================
SELECT COUNT(*) AS c6
FROM (
    SELECT i.id_etudiant
    FROM inscription i
    JOIN session_cours s
      ON s.id_session = i.id_session
    WHERE i.montant >= 0
      AND i.date_operation <= s.debut
    GROUP BY i.id_etudiant
    HAVING COUNT(DISTINCT s.id_campus) >= 2
);

-- Resultat attendu : 12356


-- ---------------------------------------------------------------------
-- C7 : nombre de sessions en sur-réservation
--    Pour chaque session : somme des places des inscriptions confirmées, comparée à sa
--    capacité (HAVING filtre après le regroupement). On compte ensuite ces sessions.
--    SUM(nb_places) et pas COUNT(*) : une inscription peut réserver plusieurs places
--    (dans ce jeu de données elles valent toutes 1, d'où le même résultat).
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS c7
FROM (
    SELECT i.id_session
    FROM inscription i
    JOIN session_cours s ON i.id_session = s.id_session
    WHERE i.statut = 'CONFIRMEE'
    GROUP BY i.id_session, s.capacite
    HAVING SUM(i.nb_places) > s.capacite
);
-- Résultat : 15 sessions (même chiffre avec la vue V_SESSION_OCCUPATION du L1)

-------------------------------------------------------------------------
-- C8 nombre d'opérations groupées (même id_groupe) dont les opérations valides engagent au moins deux sites
--    Toutes les opérations valides comptent (confirmées et annulées), comme le dit la
--    définition. Le site vient de la session (id_site n'existe pas encore à cette étape).
-------------------------------------------------------------------------
SELECT COUNT(*) AS c8
FROM (
    SELECT i.id_groupe
    FROM inscription i
    JOIN session_cours s ON s.id_session = i.id_session
    WHERE i.id_groupe IS NOT NULL
    GROUP BY i.id_groupe
    HAVING COUNT(DISTINCT s.id_campus) >= 2
);
-- Résultat : 1 874 parcours multi-sites (sur 2 667 parcours)



-- ============================================================
-- C9 : nombre de places confirmees par categorie
-- ============================================================
SELECT 'C9' AS controle,
       c.libelle AS categorie,
       SUM(i.nb_places) AS places_confirmees
FROM inscription i
JOIN session_cours s
  ON s.id_session = i.id_session
JOIN categorie c
  ON c.id_categorie = s.id_categorie
WHERE i.statut = 'CONFIRMEE'
  AND i.montant >= 0
  AND i.date_operation <= s.debut
GROUP BY c.libelle
ORDER BY c.libelle;

-- Resultats attendus :
-- C9 | FLE      | 55104
-- C9 | allemand | 52705
-- C9 | anglais  | 54870
-- C9 | chinois  | 54681
-- C9 | espagnol | 54579
-- C9 | italien  | 54530
-- Total       : 326469
```

## Annexe B · Journal de bord

### Journal de bord — groupe 07 · École de langues

Obligatoire (−1 point s'il manque). Une entrée par décision, impasse ou erreur.
Pour une erreur, copier le **message exact** (ex. `ORA-02291: integrity constraint ... violated`) et dire comment on l'a résolue.
Les entrées les plus récentes vont en haut.

| Date       | Qui      | Livrable | Type     | Ce qui s'est passé                                                                                                                                                        | Résolution / décision                                                                                                                                                                                                                 |
| ---------- | -------- | -------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-27 | Baptiste | L3 | décision | Relecture du L3 : la DF « libellé → session » était retenue comme 2e clé de SESSION, alors que les libellés sont fabriqués à partir de l'identifiant (« Session FLE 1 ») et qu'aucune contrainte `UNIQUE` ne la garantit. Le document annonçait aussi INSCRIPTION en BCNF alors qu'elle garde le site, le montant et le parcours, et renvoyait l'opération groupée à un ADR qui ne la traite pas | DF déplacée dans les DF écartées (N5, même raisonnement que N4), numérotation D5 à D8 décalée. Forme normale réelle écrite : décomposition théorique en BCNF, INSCRIPTION en 2NF par choix ; les trois écarts (site, montant historisé, parcours) justifiés dans `L3_normalisation.md`, partie 4. Ajout du contrôle D8 après chargement (0 violation) |
| 2026-11-26 | Baptiste | — | erreur | Relance sur un kit neuf (comptes supprimés, `installation_system.sql`, puis `run_all.sql`) après la réorganisation des dossiers (PR #11, #12) : seuls L1 et L2 étaient reconstruits. Dans `prerequis/run_all.sql`, les étapes 05 à 11 étaient commentées, 03 et 04 marquées « à enlever », et les chemins visaient l'ancien dossier `sql/` | Chemins relatifs corrigés depuis `prerequis/` (`@@../L1_modele/…`, `@@../sql/…`), toutes les étapes réactivées, recompilation finale du schéma. Kit neuf : 1 min 06 s, 0 erreur ORA/SP2/PLS, 0 objet invalide. Preuves manuelles rejouées : L3, L4 (14 tests, concurrence), L5, L6 (18 OK), MongoDB, Elasticsearch, Neo4j |
| 2026-11-26 | Baptiste | L2 | erreur | `04_requetes_metier.sql` dans `run_all` : plus de 10 min, `run_all.log` de 230 000 lignes (R2, R3, R4, R5, R6, R8 affichaient toutes leurs lignes) ; R5 (division en double `NOT EXISTS`) seule tournait encore après 5 min | Sorties bornées (totaux ou `FETCH FIRST 10`), résultats écrits en commentaire. R5 : pas d'index sur `INSCRIPTION.id_etudiant` avant le L5, Oracle relisait la table pour chaque couple étudiant × langue ; couples manquants construits dans un seul bloc → anti-jointure par hachage, 0,15 s, 12 985 (= division par comptage). R3 sur les étudiants : 0 ligne, remplacée par les sessions sans inscrit (4) |
| 2026-11-26 | Baptiste | L7 | erreur | `docker exec elasticsearch bash /tmp/L7_recherche.sh` : `$'
': command not found`, `-H: command not found` | Le dépôt stocke le script en LF, mais `core.autocrlf=true` le récupère en CRLF sous Windows. Ajout de `.gitattributes` (`*.sh`, `*.js`, `*.cypher`, `*.sql` en `eol=lf`) |
| 2026-11-26 | Baptiste | L6, L8 | décision | `docs/` est dans le `.gitignore` : le document du L6 (CAP / PACELC, exigé par le sujet), `options_ADR.md` et `L1_schema_relationnel.md` n'auraient pas été rendus | Déplacés dans `L6_distribution/`, `L8_adr/`, `L1_modele/` ; références de chemins corrigées partout (`nosql/` → `L7_nosql/`, `preuves/*.sql` → dossiers des livrables) ; README réécrit ; rapport `RAPPORT.md` rédigé |
| 2026-11-10 | Philip   | L1       | décision | review fichiers                                                                                                                                                           | NA                                                                                                                                                                                                                                    |
| 2026-11-01 | Philip   | L1       | décision | écriture de requêtes de contrôle                                                                                                                                          | NA                                                                                                                                                                                                                                    |
| 2026-10-31 | Baptiste | L8 | décision | 2 ADR (sujet à jour ; le document de consignes en annonce 3, il date d'avant) : ADR-01 répartir les données selon le site de la session, ADR-02 rechercher un étudiant avec Elasticsearch | Mesures reprises du L6 et du L7. Options non évidentes listées dans `docs/L8_adr/options_ADR.md` |
| 2026-10-31 | Baptiste | L8 | décision | Mesure de l'option la plus sérieuse contre Elasticsearch : Oracle `UTL_MATCH` trouve les 15 Léo Bertrand parmi 49 lignes, en 0,08 s, sans classement (lecture complète). `SOUNDEX` : 0 résultat (B365 ≠ B636) | Elasticsearch gardé pour le classement et pour décharger Oracle au pic. Oracle Text gardé comme repli. Requêtes ajoutées à `L7_oracle_comparaison.sql` |
| 2026-10-31 | Baptiste | Bonus | décision | Exemple pour le type objet avec héritage | Reprise de l'héritage du L1 (un campus est le siège ou un site) : `t_campus` avec la méthode `presenter()`, `t_site UNDER t_campus`, table objet `campus_objet`, requête avec `IS OF` et `TREAT`. Activé dans `run_all.sql`, aucune erreur |
| 2026-10-31 | Baptiste | Bonus | erreur | Requête avec un nombre de sessions par campus : `ORA-00979: "C"."SYS_NC_ROWINFO$": must appear in the GROUP BY clause or be used in an aggregate function` | Oracle ne regroupe pas sur un objet. Le compte n'était pas demandé par le sujet : retiré |
| 2026-10-31 | Baptiste | L7 | décision | Choix des deux moteurs. Mesuré dans Oracle : aucun texte libre (libellés « Session FLE 1 »), 50 noms et 40 prénoms pour 21 471 étudiants (jusqu'à 23 homonymes), parrainage vide, 60 % des étudiants ont déjà suivi les 6 langues | Elasticsearch pour la recherche d'un étudiant malgré les fautes, Neo4j pour recommander des sessions à venir (pas des langues). Les deux besoins cités par le sujet (« recherche et recommandation ») |
| 2026-10-31 | Baptiste | L7 | décision | Recherche « Betrand Leo » : Oracle `=` et `LIKE` → 0 résultat. Elasticsearch (`fuzziness: AUTO`, analyseur sans accent) → les 15 Léo Bertrand en tête, puis Legrand et Léa Bertrand moins bien notés | Index minimal : nom, prénom, ville, site (ni e-mail ni téléphone). Import `_bulk` généré par `JSON_OBJECT` : `"errors": false`, 21 471 documents |
| 2026-10-31 | Baptiste | L7 | décision | Recommandation de l'étudiant 2141 : Neo4j et Oracle donnent les mêmes 5 sessions, mais Oracle est plus rapide (633 blocs lus, 0,02 s, contre 5 193 accès et 0,1 à 0,25 s ; à 3 sauts : 0,16 s contre 1,2 s) | Neo4j gardé (besoin réel, requête lisible, chemins de longueur variable), mesure écrite telle quelle : on ne prétend pas qu'il est plus rapide. Matériau pour l'ADR « quel moteur pour la recommandation » |
| 2026-10-31 | Baptiste | L7 | erreur | Deuxième import Neo4j : `Java heap space`, puis toutes les requêtes échouent avec le même message | `DETACH DELETE` de tout le graphe d'un coup dépasse le tas de 1 Go du kit. Redémarrage du conteneur, puis suppression des relations, puis des nœuds, par lots de 5 000. Testé sur un graphe plein |
| 2026-10-31 | Baptiste | L7 | erreur | Fichier `_bulk` exporté par SQL*Plus : une ligne vide après chaque étudiant | `SET RECSEP OFF` dans le script d'export |
| 2026-10-31 | Baptiste | L7 | impasse | Import Neo4j par `LOAD CSV` impossible : le kit monte le dossier d'import en lecture seule sur les données du cours | Oracle génère des ordres Cypher (`UNWIND [...]` par lots de 5 000), exécutés par `cypher-shell -f` |
| 2026-10-31 | Baptiste | L6 | décision | Revue de ce que le L6 fait sans que le sujet le demande | Règle : ne faire que ce qui est demandé. Retirés : la panne d'un shard MongoDB (`L6_panne_shard.js` ; le sujet demande une panne de site, faite côté Oracle), le mode dégradé (`nb_inscriptions`, `ca_site`) et la table descriptive `CATALOGUE_FRAGMENT`. Gardés : ce qui sert une demande du sujet ou sa preuve. Après retrait : `run_all` 0 erreur, rejeu de la panne 18 OK |
| 2026-10-31 | Baptiste | L6 | décision | Relecture du L6 avec les supports de cours (M3, M4) : le Lab 5 (parties 5 et 6), le devoir Libris et le cours M3-3 attendent une **table redondante**, une **procédure de bascule** et un **conflit résolu** ; le L6 n'avait qu'un mode dégradé et une file d'attente | Ajout de `SESSION_REPLIQUE` (copie au siège des 15 170 sessions d'Angers : catalogue très lu, peu modifié), `pkg_reparti.consulter_sessions` (bascule sur la copie si Angers ne répond pas), colonne `derniere_maj` et `pkg_reparti.synchroniser_replique` (le dernier écrivain gagne, dans les deux sens). Rejeu de la panne : 18 OK, 0 échec |
| 2026-10-31 | Baptiste | L6 | décision | Stratégie de résolution des conflits entre la copie et le site | « Le dernier écrivain gagne », comme au Lab 5 : simple, mais la modification la plus ancienne est perdue sans prévenir et il faut des horloges synchronisées (ici une seule instance). Mesuré : capacité + 5 au siège puis + 2 à Angers → + 2 gardé partout. Limite notée dans la doc L6 |
| 2026-10-31 | Baptiste | L6 | erreur | `PKG_REPARTI.erreur_de_lien` ne contenait pas `ORA-03150: end-of-file on communication channel for database link`, l'erreur de la première requête après la panne (le compte rendu disait le contraire) | Code -3150 ajouté à la liste en même temps que la copie |
| 2026-10-31 | Baptiste | L6 | décision | Fragmentation : un compte Oracle par site (`site_bordeaux`, `site_tours`, `site_angers`), reliés au siège `langues` par 3 liens. SESSION_COURS et INSCRIPTION par site (l'inscription suit sa session, grâce à `id_site` du L3), ETUDIANT par site de rattachement, CATEGORIE répliquée | Mesuré : 78 676 / 162 669 / 113 113 inscriptions ; vues globales = tables centrales (0 ligne d'écart par `MINUS`), 0 doublon. Coût : 22 955 inscriptions (6,5 %) ont leur étudiant dans un autre site, la clé étrangère ne peut pas traverser un lien → vérifiée par requête (0 orpheline) |
| 2026-10-31 | Baptiste | L6 | décision | Comment créer les tables des sites depuis `run_all.sql` (une seule connexion, `langues`) ? | Le siège appelle `DBMS_UTILITY.EXEC_DDL_STATEMENT@lien` : l'ordre s'exécute dans le site, avec ses droits. Les comptes des sites n'ont que `CREATE SESSION` et `CREATE TABLE` (créés dans `installation_system.sql`) |
| 2026-10-31 | Baptiste | L6 | erreur | Requête d'intégrité entre sites (inscriptions sans étudiant) écrite avec `NOT EXISTS` sur les vues globales : **4 min 27 s** | Oracle interrogeait le site distant une fois par inscription. Hint `USE_HASH` + `NO_MERGE` : chaque côté ne vient qu'une fois, 0,3 s |
| 2026-10-31 | Baptiste | L6 | erreur | `PKG_REPARTI` : `Warning: Package Body created with compilation errors`, puis `ORA-04063: package body "LANGUES.PKG_REPARTI" has errors`. Dans `USER_ERRORS` : `PL/SQL: ORA-00984: column not allowed here` et `PL/SQL: ORA-00904: "SQLERRM": invalid identifier` | `SQLERRM` ne peut pas être écrit dans un INSERT ou un UPDATE : rangé d'abord dans une variable (de même pour `SQLCODE`, lu avant le `ROLLBACK TO SAVEPOINT`) |
| 2026-10-31 | Baptiste | L6 | décision | Panne simulée : `ALTER USER site_angers ACCOUNT LOCK` + coupure de ses sessions (en system). Parcours qui passe par Angers : refusé en entier ; inscription simple : mise en attente au siège, rejouée à la reprise avec nouveau contrôle de capacité | Rejeu : 11 OK. Pendant la panne, la vue globale échoue même pour une requête sur Tours (Oracle ouvre tous les liens). À la reprise, 2 inscriptions rejouées, 1 refusée (plus de place), pas de sur-réservation |
| 2026-10-31 | Baptiste | L6 | erreur | 1re requête après la panne : `ORA-03150: end-of-file on communication channel for database link` / `ORA-02063: preceding line from LIEN_ANGERS`, au lieu de `ORA-28000` attendu | Le lien réutilisait la session coupée par system. La requête suivante reconnecte et reçoit `ORA-28000: The account is locked; login denied.` Les deux codes sont traités comme « site injoignable » dans `PKG_REPARTI` |
| 2026-10-31 | Baptiste | L6 | décision | Clé de sharding MongoDB : `id_site` (Tours = 45,9 %), `date_operation` (16 068 opérations le 10/09/2026, 449 par jour en moyenne) ou `id_etudiant` (21 471 valeurs, 36 au plus, 1 étudiant par parcours) ? | `{ id_etudiant: "hashed" }` : 33,5 / 32,3 / 34,2 % par shard (22 / 46 / 32 % avec la clé par site, mesuré sur une collection de comparaison) ; historique et parcours sur 1 seul shard. Haché plutôt que par intervalle : nos 36 Mo tiendraient dans un seul morceau de 128 Mo |
| 2026-10-31 | Baptiste | L6 | impasse | Panne d'un shard (`docker stop shard3a`) : essai de `allowPartialResults` pour obtenir une réponse partielle sur une requête qui touche tous les shards | Pas de réponse partielle avec MongoDB 8.0.34 : `FailedToSatisfyReadPreference` après 15 s, avec ou sans l'option. Noté tel quel dans la preuve |
| 2026-10-31 | Baptiste | L6 | erreur | Script de panne MongoDB : l'étudiant censé être sur le shard arrêté répondait encore | Les bornes des morceaux sont des entiers 64 bits (`Long`) : la comparaison `<=` en JavaScript donnait un faux résultat. Comparaison refaite en `BigInt` |
| 2026-10-31 | Baptiste | — | erreur | Test de `run_all.sql` dans le conteneur : `run_all.log` pas mis à jour, sans aucun message | Le dossier copié contenait un ancien `run_all.log` appartenant à root : sqlplus (utilisateur oracle) ne pouvait pas l'écraser, le SPOOL échouait en silence. Fichier supprimé, `chmod 777` sur le dossier |
| 2026-10-29 | Baptiste | L5 | décision | Trois requêtes lentes (lecture complète d'INSCRIPTION, 2 265 blocs) : historique d'un étudiant, places libres d'une session (contrôle du package L4), tableau de bord par site et langue | Index `ix_inscription_etudiant` : 2 301 → 56 blocs ; index couvrant `ix_inscription_session` : 2 265 → 3 ; vue matérialisée `mv_activite_mensuelle` avec réécriture automatique : 2 644 → 4. Mesure : `GATHER_PLAN_STATISTICS` + `DBMS_XPLAN.DISPLAY_CURSOR` (colonne Buffers) |
| 2026-10-29 | Baptiste | L5 | décision | Vue matérialisée ou partitionnement ? | Vue matérialisée : le tableau de bord lit 326 000 lignes, aucun index n'aide. Partitionnement par site laissé au L6 (fragmentation). Rafraîchissement à la demande : une vue périmée n'est plus utilisée (`query_rewrite_integrity = enforced`), jamais de chiffre faux |
| 2026-10-29 | Baptiste | L5 | décision | Sécurité : quel mécanisme ? | Sécurité par ligne (VPD) sur INSCRIPTION et SESSION_COURS : chaque agent ne voit que son site, la direction tout mais sans donnée personnelle, tout autre compte rien. Pas de politique sur ETUDIANT (12 356 personnes suivent des cours sur plusieurs sites) |
| 2026-10-29 | Baptiste | L5 | erreur | `installation_system.sql` en system : `GRANT EXECUTE ON SYS.DBMS_RLS TO langues` → `ORA-01031: insufficient privileges` | system ne peut pas redonner ce droit, seuls des rôles l'ont. Remplacé par `GRANT DB_DEVELOPER_ROLE TO langues` (rôle développeur d'Oracle 23ai, qui contient DBMS_RLS) |
| 2026-10-29 | Baptiste | L5 | décision | Les rôles ne sont pas supprimés par `00_nettoyage.sql` (ce ne sont pas des objets du schéma) : le 2e `run_all` aurait échoué | `09_securite.sql` supprime `role_agent_site` et `role_direction` s'ils existent avant de les recréer. Vérifié par deux `run_all` de suite, 0 erreur |
| 2026-10-29 | Baptiste | L4 | décision | Anomalie de concurrence : deux sessions voient chacune la dernière place libre d'une session et s'inscrivent toutes les deux → 2 places confirmées pour une capacité de 1 | Correction dans `pkg_parcours` : `SELECT … FROM session_cours … FOR UPDATE` avant de compter les places. Testé : la 2e session attend le COMMIT de la 1re (≈ 3 s dans le rejeu), puis reçoit `ORA-20010` |
| 2026-10-29 | Baptiste | L4 | impasse | Essai du niveau `SERIALIZABLE` à la place du verrou | Ne corrige pas : on obtient toujours 2 places pour 1. Oracle ne voit un conflit que sur une même ligne modifiée, et les deux inscriptions sont deux lignes différentes. Verrou explicite gardé |
| 2026-10-29 | Baptiste | L4 | décision | RG13 (doublon confirmé) et RG7 (parrain) comparent des lignes de la même table : un trigger ligne lèverait `ORA-04091: table is mutating` | Triggers composés (`COMPOUND TRIGGER`) : vérification en `AFTER STATEMENT`. Pas d'index unique pour RG13 : les 154 doublons historiques l'empêchent |
| 2026-10-29 | Baptiste | L4 | décision | Journal d'audit : transaction autonome ou non ? | Non : l'audit est dans la transaction de l'opération, une opération annulée (parcours refusé) ne laisse pas de trace d'une inscription qui n'a jamais existé. Pas de nom ni d'e-mail dans l'audit (RGPD) |
| 2026-10-29 | Baptiste | L4 | erreur | Script de test : `ORA-02287: sequence number not allowed here` sur `WHERE id_inscription = seq_inscription.CURRVAL` | Filtre sur étudiant, session et date à la place |
| 2026-10-29 | Baptiste | L4 | erreur | Script de concurrence : `ORA-03405: End of query reached; no additional text should follow.` ; ailleurs, une requête ignorée sans message | Cause : un commentaire `--` après le `;` sur la même ligne. Commentaires déplacés sur leur propre ligne |
| 2026-10-27 | Baptiste | L3 | décision | La première version du L3 (branche `younes`) est en Python : elle ne peut pas être relancée sur le kit du cours, sa « décomposition » recopie les CSV d'entrée, et elle commite 165 Mo de CSV générés | L3 refait en SQL dans `05_normalisation.sql` (avec Claude) : table à plat, DF vérifiées par requête, décomposition prouvée sans perte. Branche `younes` à ne pas fusionner telle quelle ; `scripts/**/*.csv` ajouté au `.gitignore` |
| 2026-10-27 | Baptiste | L3 | décision | Les 9 parcours (`id_groupe`) qui semblaient mélanger plusieurs étudiants | La DF `id_groupe → id_etudiant` montre qu'il s'agit de copies d'étudiants : 9 violations sur le CSV brut, 0 après la fusion du L2. Question close |
| 2026-10-27 | Baptiste | L3 | décision | Dénormalisation : où mettre le site d'une opération, dont C5, C6, C8, L5 et L6 ont besoin | Colonne `INSCRIPTION.id_site`, tenue par une clé étrangère composite et le trigger `trg_inscription_site`. Mesuré : 2 391 → 2 266 blocs lus (−5 %). Raison principale : la partition et la distribution par site |
| 2026-10-25 | Groupe   | L1       | décision | Création des tables (`01_creation_tables.sql`) écrite à la main par le groupe, à partir du modèle de `L1_modele.md`                                                       | Les commentaires du script ont été ajoutés avec l'IA (Claude), plus rapide pour documenter chaque contrainte et la règle de gestion qu'elle garantit                                                                                  |
| 2026-10-25 | Baptiste | L1       | décision | `00_nettoyage.sql` fait avec Claude                                                                                                                                       | Script propre et reproductible : il supprime tous les objets du schéma pour relancer `run_all.sql` de zéro, sur une base vide comme déjà remplie                                                                                      |
| 2026-10-25 | Baptiste | —        | erreur   | `docker cp data/. oracle-bdd:/opt/oracle/donnees_langues/` lancé depuis Git Bash : aucun message, mais dossier vide dans le conteneur                                     | Git Bash réécrit `/opt/...` en chemin Windows. Commandes passées sous PowerShell (ou `MSYS_NO_PATHCONV=1`), noté dans le README                                                                                                       |
| 2026-10-25 | Baptiste | —        | erreur   | Script d'installation envoyé par `Get-Content ... \| docker exec -i ... sqlplus` : `SP2-0734: unknown command beginning "﻿-- ======..." - rest of line ignored.`          | PowerShell 5.1 ajoute un BOM en tête du flux. On copie le fichier dans le conteneur (`docker cp`) puis `sqlplus @/tmp/...`                                                                                                            |
| 2026-10-25 | Baptiste | —        | décision | Le kit ne crée que le compte `club` ; notre schéma `langues` n'existerait pas chez l'enseignante                                                                          | `sql/installation_system.sql` (lancé une fois en `system`) crée `langues` avec les droits de `club` et le DIRECTORY des CSV                                                                                                           |
| 2026-10-25 | Baptiste | L2       | décision | Méthode de chargement : tables externes (ORACLE_LOADER) plutôt que SQL\*Loader ou scripts d'INSERT                                                                        | Tout reste en SQL dans `run_all.sql`, 355 000 lignes en quelques secondes. `RECORDS DELIMITED BY DETECTED NEWLINE` car les CSV sont en LF dans Git et en CRLF après checkout Windows (testé : `siège` lu sur 5 caractères, sans `\r`) |
| 2026-10-24 | Baptiste | —        | consigne | Sujet mis à jour par l'enseignante : jalon supprimé, 2 ADR au lieu de 3, plus de demande de changement à J+12, nouvelle grille (C1–C9 : 3, L1–L7 : 14, ADR : 3, bonus +2) | Arborescence adaptée (ADR-03 et script de demande de changement retirés)                                                                                                                                                              |
| 2026-10-24 | Baptiste | —        | décision | Mise en place de l'arborescence du dépôt                                                                                                                                  | Voir README.md                                                                                                                                                                                                                        |

## Annexe C · Déclaration d'usage de l'IA

### Déclaration d'usage de l'IA — groupe 07

Obligatoire (−1 point si elle manque). Une page maximum au rendu.
Chacun complète au fur et à mesure.

#### Outils utilisés

| Outil                 | Qui      | Pour quoi faire                                                                                                                                                                                                                                                                                                                                                      | Livrable |
| --------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| Claude Code (VS Code) | Baptiste | Analyse des CSV, `00_nettoyage.sql`, test des contraintes; exécution des scripts sur le conteneur Oracle du kit                                                                                                                                                                                                                                                      | L1       |
| Claude Code (VS Code) | Baptiste | Méthode de chargement et `02_chargement.sql` : l'IA a proposé des tables externes + `INSERT ... SELECT` à la place de notre idée de départ (un `INSERT ... VALUES` par ligne puis `ALTER TABLE` pour les contraintes), trop lente pour 355 000 lignes et qui échouait sur les données fautives. Comparaison détaillée dans `docs/comptes_rendus/02_L2_chargement.md` | L2       |
| Claude Code (VS Code) | Baptiste | Écriture de `06_triggers.sql`, `07_package_parcours.sql`, des deux scripts de concurrence et des tests (`L4_fiabilite/L4_tests_fiabilite.sql`) ; rejeu automatique des deux sessions pour vérifier l'anomalie et sa correction | L4 |
| Claude Code (VS Code) | Baptiste | Choix des 3 requêtes lentes et méthode de mesure (`08_performance.sql`), vue matérialisée ; rôles, vues de restriction et sécurité par ligne (`09_securite.sql`), droits ajoutés dans `installation_system.sql`, preuve compte par compte (`L5_perf_et_securite/L5_securite.sql`) | L5 |
| Claude Code (VS Code) | Baptiste | L6 : architecture répartie (comptes de site, liens, création des tables à distance), `10_distribution.sql`, package `PKG_REPARTI` (parcours réparti, file d'attente), scénario `L6_panne_reprise.sql` et son rejeu automatique ; comparaison du L6 avec les supports de cours M3 et M4, puis ajout de la copie redondante `SESSION_REPLIQUE`, de la bascule et de la résolution des conflits (le dernier écrivain gagne) ; MongoDB : export depuis Oracle, mesures des clés candidates, sharding ; document CAP / PACELC ; liste de ce qui dépassait le sujet (panne d'un shard, mode dégradé, `CATALOGUE_FRAGMENT`), retiré à la demande de Baptiste | L6 |
| Claude Code (VS Code) | Baptiste | L7 : mesures dans Oracle pour choisir les besoins (homonymes, langues déjà suivies), export des étudiants vers Elasticsearch et index de recherche avec tolérance aux fautes ; export du graphe vers Neo4j, requête de recommandation et comparaison mesurée avec la même requête en SQL ; README de lancement et compte rendu | L7 |
| Claude Code (VS Code) | Baptiste | Bonus : choix de l'exemple (héritage campus / site du L1), `11_bonus_objet.sql`, activation dans `run_all.sql` et test complet | Bonus |
| Claude Code (VS Code) | Baptiste | Rédaction des 2 ADR à partir des mesures du L6 et du L7 ; propositions d'options non évidentes (partitions dans une base, inscriptions avec l'étudiant, Oracle Text, `SOUNDEX`) et mesure de `UTL_MATCH` et `SOUNDEX` | L8 |
| Claude Code (VS Code) | Baptiste | 26/11 : audit complet du dépôt par rapport au sujet, relance sur un kit neuf (Oracle, MongoDB, Elasticsearch, Neo4j) ; correction de `run_all.sql` et des chemins après la réorganisation, sorties bornées et résultats de `04_requetes_metier.sql` (R3, R5 réécrites), `.gitattributes`, README ; premier jet de `RAPPORT.md` à partir des comptes rendus, relu par le groupe | Tous |
| Gemini                | Philip   | syntaxe oracle                                                                                                                                                                                                                                                                                                                                                       | L2       |

#### Ce qu'on a gardé, ce qu'on a corrigé

- Gardé : Chaque contrainte a été vérifiée par un test qui doit échouer.
- Corrigé : trois tests du script de preuve (voir ci-dessous) et la commande d'installation sous PowerShell (BOM).

#### Au moins un cas où l'IA s'est trompée

| Ce que l'IA a proposé | Pourquoi c'était faux | Comment on l'a détecté |
| --------------------- | --------------------- | ---------------------- |
| L4 : dans le script de test, retrouver l'inscription qu'on vient de créer avec `WHERE id_inscription = seq_inscription.CURRVAL` | Oracle interdit une séquence dans un `WHERE` | En lançant le script : `ORA-02287: sequence number not allowed here`. Remplacé par un filtre sur l'étudiant, la session et la date |
| L4 : des commentaires `-- …` placés sur la même ligne, juste après le `;` d'un ordre SQL | SQL*Plus ne reconnaît plus le `;` comme fin d'ordre : une requête de test a été **ignorée sans aucun message**, et un `DELETE` a échoué | La ligne « T4 OK » manquait dans la sortie des tests ; puis `ORA-03405: End of query reached; no additional text should follow.` dans le script de concurrence. Commentaires déplacés sur leur propre ligne |
| L5 : donner l'accès à la sécurité par ligne avec `GRANT EXECUTE ON SYS.DBMS_RLS TO langues` dans `installation_system.sql` (lancé en system) | system n'a pas le droit de redonner ce privilège : seuls des rôles l'ont | En lançant le script : `ORA-01031: insufficient privileges`. Remplacé par `GRANT DB_DEVELOPER_ROLE TO langues` |
| L6 : vérifier l'intégrité entre sites avec `NOT EXISTS` sur les vues globales | Oracle interroge le site distant une fois par inscription, à travers le lien : 4 min 27 s | En chronométrant le script (`SET TIMING ON`). Réécrit en jointure par hachage (`USE_HASH`) : 0,3 s |
| L6 : écrire `SQLERRM` directement dans un `INSERT` du package | Interdit dans un ordre SQL | `ORA-00904: "SQLERRM": invalid identifier` à la compilation. Rangé d'abord dans une variable |
| L6 : retrouver le shard d'un étudiant en comparant les bornes MongoDB avec `<=` | Les bornes sont des entiers 64 bits (`Long`), mal comparés en JavaScript | Pendant la panne du shard 3, l'étudiant censé y être répondait encore. Comparaison refaite en `BigInt` (script retiré ensuite : le sujet ne demande pas de panne de shard) |
| L6 : écrire dans le compte rendu que `PKG_REPARTI` reconnaît `ORA-03150` comme « site injoignable » | Le code -3150 n'était pas dans la liste de `erreur_de_lien` | En relisant le package pour ajouter la bascule. Code ajouté, compte rendu corrigé |
| L7 : rendre l'import Neo4j relançable en vidant le graphe par un seul `DETACH DELETE` de tous les nœuds | Sur un graphe déjà plein (326 469 relations), le tas de 1 Go du kit ne suffit pas | Au deuxième import : `Java heap space`, puis la preuve n'avait plus de résultats. Relations supprimées d'abord, puis nœuds, par lots de 5 000 |
| L7 : recommander Neo4j pour la recommandation en reprenant l'argument du cours (« en SQL, chaque saut coûte de plus en plus cher ») | Sur nos données (sessions de 7 étudiants, index du L5), Oracle répond plus vite : 0,02 s contre 0,1 à 0,25 s, mêmes résultats | En écrivant la même requête en SQL pour vérifier le résultat, et en comparant les plans. Neo4j gardé par choix du groupe, mesure écrite telle quelle |
| Bonus : ajouter à la requête un nombre de sessions par campus, regroupé (`GROUP BY`) sur l'objet | Non demandé par le sujet, et Oracle ne regroupe pas sur un objet | En lançant le script : `ORA-00979`. Compte retiré, requête simple gardée |
| L6 : dans le document, « avec la clé par site, un parcours sur 2 sites interroge 2 shards » | Sans le site dans le filtre, le routeur interroge les 3 shards | Vérifié par `explain()` avant de garder la phrase : 3 shards. Corrigé, et la mesure ajoutée à la preuve |
| Rapport : écrire un chemin Windows (`C:\bdd-kit\3-nosql`) dans le README au moyen d'un script Python | Dans une chaîne Python, `\b` et `\3` sont des caractères d'échappement : le README contenait des caractères de contrôle à la place de `\b` et `\3` | En relisant la ligne (affiché `C:dd-kit-nosql`, octet 0x08 à la place de `\b`). Corrigé en écrivant les octets du `\` explicitement |
