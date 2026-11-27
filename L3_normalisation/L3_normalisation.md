# L3 · Normalisation

Responsables : Younes (première analyse), Baptiste (reprise en SQL)
Script : [`05_normalisation.sql`](05_normalisation.sql), lancé par `prerequis/run_all.sql`
Preuves de la dénormalisation : [`L3_denormalisation.sql`](L3_denormalisation.sql) (lancé à la main), résultat dans `preuves/L3_denormalisation.txt`
Première version en Python : [`exploration_python/`](exploration_python/README.md)

Tous les chiffres ci-dessous sont produits par ces scripts sur notre base.

**En bref.** La table à plat se décompose en 4 relations en BCNF, sans perte. La base réelle s'en écarte volontairement sur une seule table, INSCRIPTION, qui garde trois informations redondantes (le site, le montant, le parcours). Elle est donc en 2NF, par choix. Chaque écart est justifié, garanti par un mécanisme de la base et mesuré (partie 4).

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
| D5 | e-mail normalisé → `id_etudiant` | **73** | 0 | Violée par les 73 copies d'étudiants. RG4 l'impose : fusion au L2, puis contrainte `uq_etudiant_email` |
| D6 | (`id_session`, `nb_places`) → `montant` | **88** | 0 | Violée par les opérations non valides : 80 montants négatifs, qui valent exactement −(places × prix), et 8 identifiants de session inexistants. Après le L2, `montant = nb_places × prix_unitaire` sur les 354 458 opérations (RG12). Vraie **au moment de l'opération** (voir 4.2) |
| D7 | `id_groupe` → `id_etudiant` | **9** | 0 | Les 9 parcours « multi-étudiants » sont passés en partie sous l'id d'une copie : c'est la même personne. Ils sont réglés par la fusion du L2 (RG16) |
| D8 | `id_groupe` → `statut` | 0 | — | Un parcours est confirmé ou annulé en entier (RG16) |

### 2.2 Dépendances écartées

| | Dépendance testée | Violations | Pourquoi on ne la retient pas |
|---|---|---|---|
| N1 | `id_etudiant` → campus de la session | 12 369 | Fausse : un étudiant suit des cours sur plusieurs sites (C6). Le site appartient à la session, pas à l'étudiant. |
| N2 | téléphone → `id_etudiant` | 75 | Fausse : 73 téléphones sont partagés par une copie et son original, et 2 par deux personnes différentes. Le téléphone n'identifie personne. |
| N3 | catégorie → prix | 6 | Fausse : 451 prix différents par langue. Le prix est fixé session par session ; il n'y a pas de grille tarifaire cachée. |
| N4 | ville de l'étudiant → son campus | **0** | Elle tient dans les données, mais aucune règle ne l'impose : un étudiant peut habiter Saumur et étudier à Angers. C'est une coïncidence du jeu de données, et la retenir obligerait à refuser ce cas. |
| N5 | libellé de la session → `id_session` | **0** | Elle tient, mais seulement parce que le libellé est fabriqué à partir de l'identifiant (« Session FLE 1 », « Session italien 2 »). Aucune règle de l'école n'impose deux libellés différents, et aucune contrainte `UNIQUE` ne le garantit au L1. Le libellé n'est donc pas une clé. |

N4 et N5 illustrent une règle de méthode : **une dépendance observée dans les données ne prouve pas une dépendance du métier**.

---

## 3. Décomposition

### 3.1 Décomposition théorique, en BCNF

À partir des DF retenues, chaque déterminant devient la clé d'une relation :

| Relation | Clé | Autres clés | Vient de |
|---|---|---|---|
| CAMPUS(id_campus, nom, ville, role) | id_campus | nom, ville | D4 |
| ETUDIANT(id_etudiant, nom, prenom, email, telephone, ville, id_campus, date_creation_compte) | id_etudiant | e-mail normalisé (s'il est renseigné) | D2, D5 |
| SESSION(id_session, libelle, categorie, id_campus, debut, duree, capacite, prix_unitaire) | id_session | — | D3 |
| OPERATION_GROUPEE(id_groupe, id_etudiant, statut) | id_groupe | — | D7, D8 |
| INSCRIPTION(id_inscription, id_session, id_groupe, date_operation, nb_places) | id_inscription | — | D1 |

Dans cette décomposition :
- `montant` disparaît d'INSCRIPTION, puisqu'il se recalcule à partir de la session et du nombre de places (D6) ;
- l'opération groupée devient une relation à part, puisque `id_groupe` détermine l'étudiant et le statut (D7, D8). Une inscription seule (sans parcours) garderait son étudiant et son statut : en toute rigueur, il faudrait distinguer les deux cas, ce qui montre déjà le coût de cette décomposition.

**Forme normale de Boyce-Codd (BCNF).** Dans chacune de ces relations, tout déterminant est une clé : `id_campus`, `nom` et `ville` dans CAMPUS, `id_etudiant` et l'e-mail dans ETUDIANT, `id_session` dans SESSION, `id_groupe` dans OPERATION_GROUPEE, `id_inscription` dans INSCRIPTION. Elles sont donc en BCNF, et pas seulement en 3NF.

### 3.2 Vérifications

- **Sans perte** : on projette la table à plat sur les relations (`SELECT DISTINCT`), on les rejoint par leurs clés, puis on compare avec la table à plat dans les deux sens (`MINUS`). Résultat : **0 ligne inventée, 0 ligne perdue**. On obtient 354 855 opérations, 21 544 étudiants, 47 619 sessions et 3 campus. Le siège manque, ce qui illustre l'anomalie d'insertion. (La vérification est faite sur CAMPUS, ETUDIANT, SESSION et INSCRIPTION avec ses colonnes du CSV ; isoler l'opération groupée n'enlève rien, puisque D7 et D8 la déterminent entièrement.)
- **Dépendances préservées** : chaque DF retenue tient entièrement dans une seule relation. Chacune peut donc être garantie par une clé ou une contrainte d'unicité, sans jointure.

### 3.3 La base réelle : ce qui change par rapport à la décomposition théorique

Les tables du L1 suivent cette décomposition, avec des ajouts et trois écarts volontaires.

**Ajouts** :

| Ajout du L1 | Raison |
|---|---|
| Données nettoyées (L2) | D5 et D7 sont respectées une fois les 73 copies fusionnées ; D6 l'est une fois les 397 opérations non valides rejetées. |
| Table CATEGORIE | La catégorie n'est déterminée par rien d'autre que la session (N3), mais une table de référence empêche les fautes de frappe (`anglais` / `Anglais`). |
| Héritage SIEGE / SITE | Le rôle du campus détermine ce qu'il peut porter : seuls les sites ont des étudiants et des sessions (RG3). |
| Noms des dates : `ETUDIANT.date_inscription` (appelée `date_creation_compte` dans la table à plat) et `INSCRIPTION.date_operation` | Les deux CSV ont une colonne `date_inscription`, avec deux sens différents. |

**Écarts volontaires, tous dans INSCRIPTION** :

| Écart | Dépendance qui n'a pas une clé pour déterminant | Partie |
|---|---|---|
| `id_site`, le site de la session, recopié | `id_session` → `id_site` | 4.1 |
| `montant` gardé | (`id_session`, `nb_places`) → `montant` (D6) | 4.2 |
| `id_groupe`, avec l'étudiant et le statut, gardés dans INSCRIPTION | `id_groupe` → `id_etudiant`, `statut` (D7, D8) | 4.3 |

**Forme normale de la base réelle.** CAMPUS, SIEGE, SITE, CATEGORIE, ETUDIANT et SESSION_COURS sont en BCNF. INSCRIPTION est en **2NF** : sa clé n'a qu'une colonne, donc aucune dépendance partielle, mais les trois écarts sont des dépendances transitives (`id_inscription` → `id_session` → `id_site`, par exemple), ce qui l'empêche d'être en 3NF. C'est un choix : chaque écart est justifié et tenu par la base dans la partie 4.

---

## 4. Dénormalisations assumées

Le sujet demande « une dénormalisation assumée et justifiée ». La principale est `id_site` (4.1), mise en place et mesurée dans ce livrable. Les deux autres (4.2, 4.3) viennent du L1 : nous les justifions ici, car la décomposition les fait apparaître.

### 4.1 Le site recopié dans INSCRIPTION (`id_site`), mise en place dans `05_normalisation.sql`

**Contexte.** En 3NF, le site d'une opération se déduit de sa session (RG10). Pourtant, une grande partie de la suite du projet raisonne par site :
- les valeurs de contrôle C5, C6 et C8 ;
- la fragmentation par site du L6 : chaque inscription va dans le schéma du site de sa session (fragmentation dérivée), soit 78 676 / 162 669 / 113 113 inscriptions pour Bordeaux, Tours et Angers ;
- la sécurité par ligne du L5, qui filtre les inscriptions par site.

**Options envisagées.**

| Option | Pour | Contre |
|---|---|---|
| A. Jointure à chaque requête (3NF pure) | Aucune redondance | Une jointure de plus partout ; la fragmentation du L6 devrait passer par une jointure vers SESSION_COURS pour chaque inscription, et chaque filtre par site aussi |
| B. Partitionnement par référence (Oracle) | Pas de colonne en double | Lié à un seul moteur et à une seule base : ne sert pas quand les inscriptions sont réparties dans des schémas de site différents (L6), ni pour un export vers un autre moteur où le site doit figurer dans la donnée |
| **C. Colonne `id_site` recopiée, tenue automatiquement** | Requêtes par site directes ; critère de fragmentation disponible dans la table | Une colonne et un trigger de plus ; il faut garantir la cohérence |

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

Les résultats sont identiques avec et sans la colonne : C5 = 27 333 192 / 56 080 982 / 39 082 945, C6 = 12 356, C8 = 1 874. Le gain en lecture est faible, car SESSION_COURS est petite (384 blocs). **La raison principale est la fragmentation par site du L6**, qui a besoin du site dans la table INSCRIPTION elle-même : c'est ce qui permet de répartir les inscriptions sans jointure, et de vérifier la reconstruction (vues globales identiques aux tables centrales, 0 ligne d'écart).

**Coût et risques.**
- La table INSCRIPTION grossit d'environ 3 octets par ligne, soit à peu près 1 Mo (aujourd'hui 2 260 blocs, 44 octets par ligne en moyenne).
- Chaque insertion fait une lecture de plus, par clé primaire, dans SESSION_COURS.
- **On ne peut plus déplacer une session qui a des inscriptions** : le changement est refusé (ORA-02292). C'est un choix assumé : une session déjà vendue ne change pas de ville. On l'annule et on en crée une autre.

**Tests** (`L3_denormalisation.sql`, résultat dans `preuves/L3_denormalisation.txt`) :

| Test | Résultat |
|---|---|
| Site faux à l'insertion | Le trigger le corrige |
| Site modifié à la main | Le trigger le remet |
| Session inexistante | ORA-20001, l'inscription est refusée |
| Déplacer une session qui a des inscriptions | ORA-02292, la modification est refusée |

### 4.2 Le montant gardé dans INSCRIPTION

Sur les données, D6 tient : `montant = nb_places × prix_unitaire` (RG12). La décomposition théorique supprime donc la colonne. Nous la gardons, parce que **D6 n'est vraie qu'au moment de l'opération** :

- Le montant est le prix **payé le jour de l'inscription**. Si le prix d'une session change plus tard, les anciennes inscriptions doivent garder leur montant : sinon le chiffre d'affaires passé (C5) changerait après coup.
- Après un changement de prix, `montant` n'est donc plus déductible de la session : ce n'est pas une copie, c'est un fait historique. La recalculer à chaque lecture donnerait un résultat faux.
- Au moment de l'opération, la règle est garantie : le trigger `trg_inscription_regles` (L4) calcule le montant à l'insertion. Aucune saisie à la main ne peut le contredire.

Le coût est faible : une colonne numérique. Le bénéfice est la justesse de l'historique, et des calculs de chiffre d'affaires qui lisent directement la somme payée, sans jointure.

### 4.3 L'opération groupée gardée dans INSCRIPTION

D7 et D8 montrent qu'un parcours a son propre étudiant et son propre statut. La décomposition théorique crée donc une relation OPERATION_GROUPEE(id_groupe, id_etudiant, statut). Nous gardons `id_groupe` comme une colonne d'INSCRIPTION, comme dans le CSV.

**Pourquoi :**
- **La table n'apporterait aucune information nouvelle.** Le CSV ne donne rien sur le parcours en dehors de son étudiant et de son statut, qui figurent déjà sur chaque inscription. Une inscription seule (sans parcours) a aussi besoin de son étudiant et de son statut : ils resteraient dans INSCRIPTION de toute façon.
- **La redondance est petite.** 2 667 parcours pour 354 458 inscriptions : l'étudiant et le statut d'un parcours sont répétés sur 3 lignes en moyenne (3,01).
- **Le tout ou rien est garanti par une transaction, pas par une table.** RG16 (même étudiant, tout ou rien) est tenue par le package `PKG_PARCOURS` du L4 : il insère toutes les inscriptions du parcours dans une seule transaction, avec un `SAVEPOINT`, et annule tout si une seule échoue.
- **Avec la fragmentation du L6, une table à part serait plus coûteuse.** Les inscriptions d'un parcours multi-sites sont rangées dans des sites différents (celui de chaque session). Une table OPERATION_GROUPEE devrait être placée sur un seul site : chaque parcours toucherait une base de plus, à travers un lien.

**Ce que ça coûte :** D7 et D8 ne sont garanties par aucune contrainte, seulement par le package. Une inscription insérée directement, sans passer par le package, pourrait les violer. C'est une limite assumée. Elle est contrôlée par requête : 0 violation de D7 et de D8 après le chargement (`05_normalisation.sql`, partie 2b).

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

Les idées de la première version sont gardées : renommer les colonnes de campus selon leur rôle, joindre les tables en externe pour ne perdre aucune opération, repérer les 220 sessions absentes. Les scripts et leurs documents sont rangés dans [`exploration_python/`](exploration_python/README.md).
