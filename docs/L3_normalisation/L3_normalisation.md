# L3 · Normalisation

Responsables : Younes (première analyse), Baptiste (reprise en SQL)
Script : [`sql/05_normalisation.sql`](../../sql/05_normalisation.sql), lancé par `run_all.sql`
Preuves de la dénormalisation : [`preuves/L3_denormalisation.sql`](../../preuves/L3_denormalisation.sql) et son résultat `.txt`

Tous les chiffres ci-dessous sont produits par ces scripts sur notre base.

---

## 1. Fichier des opérations « à plat »

Table `OPERATION_A_PLAT` : une ligne par opération de `inscriptions.csv`, complétée par son étudiant (l'usager), sa session (la ressource) et les deux campus concernés.

| | |
|---|---|
| Lignes | 354 855 (toutes les opérations du CSV, valides ou non) |
| Colonnes | 28 : 8 de l'opération, 10 de l'étudiant et de son campus, 10 de la session et de son campus |
| Construction | Jointure externe (`LEFT JOIN`) des 4 CSV lus par les tables externes du L2 |
| Clé | `id_inscription` (clé primaire `pk_operation_a_plat`, acceptée : aucun doublon) |
| Taille | 88 Mo, contre environ 23 Mo pour les tables décomposées (`INSCRIPTION` 18 Mo, `SESSION_COURS` 3 Mo, `ETUDIANT` 2 Mo) |

Elle est construite à partir des **CSV bruts**, avant tout nettoyage : e-mails tels quels, copies d'étudiants avec leur propre id, opérations non valides gardées. C'est voulu : on veut voir les dépendances que les défauts violent.

Le campus apparaît deux fois, sous deux rôles différents : celui de l'étudiant (`*_campus_etudiant`) et celui de la session (`*_campus_session`). Les deux diffèrent pour 22 955 opérations valides : un étudiant suit des cours ailleurs que dans son campus.

**Les anomalies de la table à plat**, constatées sur nos données :

| Anomalie | Exemple réel |
|---|---|
| Insertion | Le **siège** n'apparaît pas : il n'a ni étudiant ni session, donc aucune opération. Impossible d'enregistrer un campus, un étudiant ou une session sans opération. |
| Modification | Un étudiant a en moyenne 16 opérations : changer son e-mail impose de modifier 16 lignes, sous peine d'incohérence. |
| Suppression | Supprimer la dernière opération d'une session fait disparaître la session elle-même (son prix, sa capacité). |
| Volume | Chaque information est répétée : 88 Mo au lieu de 23 Mo. |

---

## 2. Dépendances fonctionnelles

**Méthode de vérification.** X → Y tient si chaque valeur de X n'apparaît qu'avec une seule valeur de Y. Pour chaque DF, une requête compte les valeurs de X qui ont plusieurs Y : ce sont les « violations ». Une DF qui tient sur les données n'est retenue que si une règle de gestion la justifie.

### 2.1 Dépendances retenues

| | Dépendance | Violations (CSV brut) | Après L2 | Conclusion |
|---|---|---|---|---|
| D1 | `id_inscription` → toutes les colonnes | 0 | — | Clé de la table à plat |
| D2 | `id_etudiant` → nom, prénom, e-mail, téléphone, ville, campus, date de création du compte | 0 | — | Relation ETUDIANT |
| D3 | `id_session` → libellé, catégorie, campus, début, durée, capacité, prix | 0 | — | Relation SESSION |
| D4 | `id_campus` → nom, ville, rôle | 0 | — | Relation CAMPUS (une seule pour les deux rôles) |
| D5 | `libelle_session` → `id_session` | 0 | — | Le libellé est une **deuxième clé** de SESSION |
| D6 | e-mail normalisé → `id_etudiant` | **73** | 0 | Violée par les 73 copies d'étudiants. RG4 l'impose : fusion au L2, puis contrainte `uq_etudiant_email` |
| D7 | (`id_session`, `nb_places`) → `montant` | **88** | 0 | Violée par les opérations non valides : 80 montants négatifs, qui valent exactement −(places × prix), et 8 identifiants de session inexistants. Après le L2, `montant = nb_places × prix_unitaire` sur les 354 458 opérations (RG12) |
| D8 | `id_groupe` → `id_etudiant` | **9** | 0 | Les 9 parcours « multi-étudiants » sont passés en partie sous l'id d'une copie : c'est la même personne. Ils sont réglés par la fusion du L2 (RG16) |
| D9 | `id_groupe` → `statut` | 0 | — | Un parcours est confirmé ou annulé en entier |

### 2.2 Dépendances écartées

| | Dépendance testée | Violations | Pourquoi on ne la retient pas |
|---|---|---|---|
| N1 | `id_etudiant` → campus de la session | 12 369 | Fausse : un étudiant suit des cours sur plusieurs sites (C6). Le site appartient à la session, pas à l'étudiant. |
| N2 | téléphone → `id_etudiant` | 75 | Fausse : 73 téléphones sont partagés par une copie et son original, et 2 par deux personnes différentes. Le téléphone n'identifie personne. |
| N3 | catégorie → prix | 6 | Fausse : 451 prix différents par langue. Le prix est fixé session par session ; il n'y a pas de grille tarifaire cachée. |
| N4 | ville de l'étudiant → son campus | **0** | Elle tient dans les données, mais aucune règle ne l'impose : un étudiant peut habiter Saumur et étudier à Angers. C'est une coïncidence du jeu de données, et la retenir obligerait à refuser ce cas. |

N4 illustre une règle de méthode : **une dépendance observée dans les données ne prouve pas une dépendance du métier**.

---

## 3. Décomposition

### 3.1 Synthèse en 3NF

À partir des DF retenues, chaque déterminant devient la clé d'une relation :

| Relation | Clé | Autres clés | Vient de |
|---|---|---|---|
| CAMPUS(id_campus, nom, ville, role) | id_campus | nom, ville | D4 |
| ETUDIANT(id_etudiant, nom, prenom, email, telephone, ville, id_campus, date_creation_compte) | id_etudiant | email normalisé (s'il est renseigné) | D2, D6 |
| SESSION(id_session, libelle, categorie, id_campus, debut, duree, capacite, prix_unitaire) | id_session | libelle | D3, D5 |
| INSCRIPTION(id_inscription, id_etudiant, id_session, id_groupe, date_operation, nb_places, statut) | id_inscription | — | D1 |

Une 3NF stricte donne aussi deux résultats :
- `montant` disparaît, puisqu'il se recalcule (D7) ;
- D8 et D9 ont un déterminant (`id_groupe`) qui n'est pas une clé d'INSCRIPTION. Ils font apparaître une entité cachée, **l'opération groupée** : OPERATION_GROUPEE(id_groupe, id_etudiant, statut).

Nous gardons volontairement ces deux écarts ; voir la partie 4.

**Forme normale de Boyce-Codd (BCNF).** Dans chacune des quatre relations, tout déterminant est une clé : `id_session` et `libelle` dans SESSION, `id_campus`, `nom` et `ville` dans CAMPUS, etc. Elles sont donc en BCNF, et pas seulement en 3NF.

### 3.2 Vérifications

- **Sans perte** : on projette la table à plat sur les 4 relations (`SELECT DISTINCT`), on les rejoint par leurs clés, puis on compare avec la table à plat dans les deux sens (`MINUS`). Résultat : **0 ligne inventée, 0 ligne perdue**. On obtient 354 855 opérations, 21 544 étudiants, 47 619 sessions et 3 campus. Le siège manque, ce qui illustre l'anomalie d'insertion.
- **Dépendances préservées** : chaque DF retenue tient entièrement dans une seule relation. Chacune peut donc être garantie par une clé ou une contrainte d'unicité, sans jointure.

### 3.3 Lien avec les tables du L1

Les tables du L1 correspondent à cette décomposition, avec quatre ajouts :

| Ajout du L1 | Raison |
|---|---|
| Données nettoyées (L2) | D6 et D8 sont respectées une fois les 73 copies fusionnées ; D7 l'est une fois les 397 opérations non valides rejetées. |
| Table CATEGORIE | La catégorie n'est déterminée par rien d'autre que la session (N3), mais une table de référence empêche les fautes de frappe (`anglais` / `Anglais`). |
| Héritage SIEGE / SITE | Le rôle du campus détermine ce qu'il peut porter : seuls les sites ont des étudiants et des sessions (RG3). |
| Noms des dates : `ETUDIANT.date_inscription` (appelée `date_creation_compte` dans la table à plat) et `INSCRIPTION.date_operation` | Les deux CSV ont une colonne `date_inscription`, avec deux sens différents. |

---

## 4. Dénormalisation assumée

### 4.1 Le site recopié dans INSCRIPTION (`id_site`), mise en place dans `05_normalisation.sql`

**Contexte.** En 3NF, le site d'une opération se déduit de sa session (RG10). Pourtant, presque tout ce qui reste à faire raisonne par site :
- les valeurs de contrôle C5, C6 et C8 ;
- le partitionnement (L5) ;
- la répartition des données entre les sites (L6).

**Options envisagées.**

| Option | Pour | Contre |
|---|---|---|
| A. Jointure à chaque requête (3NF pure) | Aucune redondance | Une jointure de plus partout ; impossible de partitionner INSCRIPTION par site sur une colonne qui n'y est pas |
| B. Partitionnement par référence (Oracle) | Pas de colonne en double | Lié à un seul moteur ; ne sert à rien pour la distribution vers MongoDB (L6), où le site doit figurer dans le document |
| **C. Colonne `id_site` recopiée, tenue automatiquement** | Requêtes par site directes ; clé de partition et de distribution disponible | Une colonne et un trigger de plus ; il faut garantir la cohérence |

**Décision : option C.**

**Cohérence garantie, et pas seulement espérée :**
- La **clé étrangère composite** `(id_session, id_site)` → `SESSION_COURS(id_session, id_campus)` refuse tout site différent de celui de la session. C'est le même mécanisme que l'héritage CAMPUS / SITE du L1.
- Le **trigger** `trg_inscription_site` remplit `id_site` tout seul, à l'insertion comme au changement de session. Le package du L4 n'a pas à s'en occuper.

**Mesures** (blocs lus, cache chaud, 2ᵉ exécution) :

| Requête | Avec jointure | Avec `id_site` | Écart |
|---|---|---|---|
| C5, chiffre d'affaires par site | 2 391 | 2 266 | −5 % |
| C6, personnes sur au moins 2 sites | 2 391 | 2 266 | −5 % |
| C8, parcours sur au moins 2 sites | 2 391 | 2 266 | −5 % |

Les résultats sont identiques avec et sans la colonne : C5 = 27 333 192 / 56 080 982 / 39 082 945, C6 = 12 356, C8 = 1 874. Le gain en lecture est faible, car SESSION_COURS est petite (384 blocs). **La raison principale reste la partition et la distribution par site** (L5, L6), qui exigent la colonne dans la table. Ce gain sera mesuré au L5.

**Coût et risques.**
- La table INSCRIPTION grossit d'environ 3 octets par ligne, soit à peu près 1 Mo (aujourd'hui 2 260 blocs, 44 octets par ligne en moyenne).
- Chaque insertion fait une lecture de plus, par clé primaire, dans SESSION_COURS.
- **On ne peut plus déplacer une session qui a des inscriptions** : le changement est refusé (ORA-02292). C'est un choix assumé : une session déjà vendue ne change pas de ville. On l'annule et on en crée une autre.

**Tests** (`preuves/L3_denormalisation.txt`) :

| Test | Résultat |
|---|---|
| Site faux à l'insertion | Le trigger le corrige |
| Site modifié à la main | Le trigger le remet |
| Session inexistante | ORA-20001, l'inscription est refusée |
| Déplacer une session qui a des inscriptions | ORA-02292, la modification est refusée |

### 4.2 Le montant gardé dans INSCRIPTION (prévu dès le L1)

`montant = nb_places × prix_unitaire` (RG12, D7) : en 3NF stricte, la colonne serait supprimée. On la garde, pour deux raisons :
- **C'est un historique** : le montant est le prix **payé le jour de l'opération**. Si le prix d'une session change plus tard, les anciennes opérations ne doivent pas changer de montant.
- C5 et tous les calculs de chiffre d'affaires lisent directement la somme payée.

La règle sera contrôlée par un trigger pour les nouvelles opérations (L4).

### 4.3 L'opération groupée, gardée dans INSCRIPTION (à trancher dans un ADR)

D8 et D9 montrent qu'une opération groupée a son propre étudiant et son propre statut. La 3NF stricte demanderait une table OPERATION_GROUPEE. Pour l'instant, `id_groupe` reste une colonne d'INSCRIPTION, comme dans le CSV, et RG16 est contrôlée par le package du L4.

Le sujet propose justement « où et comment stocker l'opération groupée » comme thème d'ADR. La décision y sera prise, avec ces dépendances comme argument.

---

## 5. Par rapport à la première version (scripts Python)

| Première version | Version retenue | Pourquoi |
|---|---|---|
| Scripts Python (pandas), hors de `run_all.sql` | SQL dans `05_normalisation.sql` | L'enseignante relance les scripts sur le kit du cours, sans Python |
| 4 fichiers de sortie recopiés à l'identique des CSV d'entrée | Décomposition tirée des DF, vérifiée sans perte | La décomposition doit découler des dépendances |
| DF listées « à vérifier » | Chaque DF vérifiée par une requête, chiffre à l'appui, avec les DF écartées | Une conclusion ferme, démontrée sur nos données |
| CSV bruts, défauts ignorés (220 sessions « à corriger à la source ») | Défauts expliqués par les DF et reliés au traitement du L2 | Cohérence avec le chargement |
| Téléphones sans leur 0, entiers devenus `4.0` (conversion automatique de pandas) | Types imposés, téléphone gardé en texte | RG6 |
| 165 Mo de CSV générés commités | Rien de généré dans Git : la table se reconstruit en quelques secondes | Le dépôt contient le code, pas ses résultats |
| Dénormalisation décrite en termes généraux | Colonne réelle, cohérence garantie, mesures et tests | Le sujet demande une dénormalisation « assumée et justifiée » |

Les idées de la première version sont gardées : renommer les colonnes de campus selon leur rôle, joindre les tables en externe pour ne perdre aucune opération, repérer les 220 sessions absentes.
