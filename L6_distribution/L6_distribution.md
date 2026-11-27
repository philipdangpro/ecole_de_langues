# L6 · Distribution

Groupe 07 · École de langues. Scripts : `L6_distribution/10_distribution.sql` (lancé par `run_all.sql`), `L6_distribution/L6_panne_reprise.sql` (à la main), `L7_nosql/mongodb/`.
Preuves : `preuves/L6_distribution.txt`, `preuves/L6_panne_reprise.txt`, `preuves/L6_mongodb.txt`.

Ce que demande le sujet : *fragmentation de vos données par site, mise en œuvre avec plusieurs schémas, des liens et des vues globales ; une panne de site et sa reprise ; une collection MongoDB shardée avec une clé de sharding justifiée par la répartition mesurée ; le classement CAP / PACELC de vos choix.*

---

## 1. Fragmentation Oracle par site

### Architecture

| Rôle | Compte Oracle | Contenu |
|---|---|---|
| Siège | `langues` | catalogue de répartition, liens, vues globales, annuaires (id → site), procédures réparties, file d'attente des pannes |
| Site de Bordeaux | `site_bordeaux` | fragments du site 2 |
| Site de Tours | `site_tours` | fragments du site 3 |
| Site d'Angers | `site_angers` | fragments du site 4 |

Le kit n'a qu'une instance Oracle : les trois sites sont trois schémas de la même base, reliés au siège par trois liens (`LIEN_BORDEAUX`, `LIEN_TOURS`, `LIEN_ANGERS`). Sur trois serveurs, seule la chaîne `USING` des liens changerait.

Le siège crée les tables des sites **à distance**, en appelant `DBMS_UTILITY.EXEC_DDL_STATEMENT@lien` : les comptes des sites n'ont besoin que de `CREATE SESSION` et `CREATE TABLE`, et tout reste lancé par `run_all.sql` depuis une seule connexion.

### Schéma de répartition

| Table | Répartition | Prédicat du fragment | Pourquoi |
|---|---|---|---|
| SESSION_COURS | horizontale | `id_campus = site` | une session se tient dans un seul site |
| INSCRIPTION | horizontale dérivée (de SESSION_COURS) | `id_site = site` | stockée avec sa session : la clé étrangère inscription → session reste locale. C'est la raison de la dénormalisation `id_site` du L3 |
| ETUDIANT | horizontale | `id_campus = site de rattachement` | une seule copie des données personnelles, dans le site qui suit l'étudiant |
| CATEGORIE | réplication complète | copie dans chaque site | 6 lignes lues à chaque session, jamais modifiées : une copie ne coûte rien à tenir à jour ; la clé étrangère session → catégorie reste locale |
| CAMPUS, SIEGE, SITE | au siège | — | référentiel de l'organisation |
| SESSION_REPLIQUE | copie redondante, au siège | sessions d'Angers | secours pendant une panne d'Angers (voir « Redondance ») |

Chaque fragment porte son prédicat en contrainte `CHECK` (`ck_inscription_fragment CHECK (id_site = 2)`…) : un site refuse lui-même une ligne d'un autre site.

### Vues globales

`V_G_ETUDIANT`, `V_G_SESSION`, `V_G_INSCRIPTION` : `UNION ALL` des trois fragments à travers les liens. Le siège voit la table entière sans savoir où sont les lignes (transparence de la répartition).

**Localisation.** Les contraintes `CHECK` des sites ne sont pas visibles par l'optimiseur du siège. Chaque branche de la vue répète donc son prédicat (`WHERE id_site = 2`) : pour une requête `WHERE id_site = 3`, l'optimiseur élimine les branches de Bordeaux et d'Angers (`FILTER NULL IS NOT NULL`, `Starts = 0` dans le plan), seul Tours est lu.

### Mesures (preuves/L6_distribution.txt)

| Table | Bordeaux | Tours | Angers | Vue globale | Table centrale |
|---|---|---|---|---|---|
| ETUDIANT | 4 646 | 9 820 | 7 005 | 21 471 | 21 471 |
| SESSION_COURS | 10 486 | 21 963 | 15 170 | 47 619 | 47 619 |
| INSCRIPTION | 78 676 (22,2 %) | 162 669 (45,9 %) | 113 113 (31,9 %) | 354 458 | 354 458 |

| Propriété de la fragmentation | Vérification | Résultat |
|---|---|---|
| Complétude et reconstruction | table centrale `MINUS` vue globale, et l'inverse, sur toutes les colonnes | 0 ligne d'écart, pour les 3 tables |
| Disjonction | identifiants présents dans deux fragments | 0 |
| Intégrité entre sites (aucune contrainte ne traverse un lien) | inscriptions dont l'étudiant n'existe dans aucun fragment ; e-mails présents dans deux sites | 0 ; 0 |
| Coût de la fragmentation d'ETUDIANT | inscriptions dont l'étudiant est stocké dans un autre site | **22 955 (6,5 %)** |
| Valeurs de contrôle sur les fragments | C5 et C6 recalculés sur les vues globales | identiques : 27 333 192 / 56 080 982 / 39 082 945 ; 12 356 |

Piège mesuré : la requête d'intégrité écrite avec `NOT EXISTS` a pris **4 min 27 s**, car Oracle interrogeait le site distant une fois par inscription. Avec une jointure par hachage (hint `USE_HASH`), chaque côté ne vient qu'une fois : **0,3 s**.

### Opérations réparties (`PKG_REPARTI`)

| Procédure | Comportement |
|---|---|
| `inscrire_parcours` | le parcours multi-sites sur les fragments : verrou de chaque session dans son site, contrôle de capacité, insertion. Une transaction pour tous les sites : au `COMMIT`, Oracle valide en deux phases (2PC). Une erreur, ou un site injoignable, défait tout, sur tous les sites |
| `inscrire` | inscription simple ; si le site est en panne, elle est gardée au siège (`OPERATION_EN_ATTENTE`) avec son numéro définitif |
| `rejouer_attente` | reprise : rejoue la file dans l'ordre d'arrivée et revérifie la capacité ; une opération sans place est `REFUSEE` avec son motif |
| `consulter_sessions` | lit le catalogue d'un site ; si le site ne répond pas, bascule sur sa copie au siège (`SESSION_REPLIQUE`) |
| `synchroniser_replique` | remet la copie et le site d'accord, dans les deux sens ; en cas de conflit, la modification la plus récente gagne |

Les procédures trouvent le site d'une session ou d'un étudiant dans les annuaires du siège (`V_ANNUAIRE_SESSION`, `V_ANNUAIRE_ETUDIANT` : identifiant et site, aucune donnée personnelle), pour ne pas dépendre de la disponibilité des trois sites. Les liens sont écrits en SQL dynamique : le package reste valide pendant une panne (sinon Oracle voudrait le recompiler en joignant le site en panne, `PLS-00905`, piège signalé au Lab 5).

### Redondance et résolution des conflits (démarche du Lab 5, parties 5 et 6)

- **Table copiée : SESSION_COURS d'Angers**, dans `SESSION_REPLIQUE` au siège (15 170 lignes). C'est le catalogue : lu à chaque consultation et à chaque inscription, rarement modifié (création d'une session, changement de prix ou de capacité). Une copie coûte donc peu à tenir à jour. Les inscriptions changent sans arrêt : on ne les recopie pas, la file d'attente s'en charge. Angers seulement, parce que c'est le site dont on simule la panne ; pour un autre site, ce serait la même table avec ses lignes.
- **Bascule** : `consulter_sessions` lit le site ; si l'erreur est une erreur de lien (`ORA-28000`, `ORA-03150`…), elle lit la copie et le dit (« Bascule sur la copie du siège »).
- **Horodatage** : chaque session porte `derniere_maj` (dans les fragments et dans la copie). Toute modification la met à jour.
- **Conflit** : la même session modifiée dans le site et dans la copie. **Le dernier écrivain gagne** : `synchroniser_replique` recopie dans le site les lignes plus récentes au siège, puis recopie au siège les lignes plus récentes dans le site (`MERGE`). Le siège et le site sont modifiés dans la même transaction (2PC).
- **Mise à jour de la copie** : différée. On lance `synchroniser_replique` à la reprise, et en temps normal à intervalle régulier (par exemple chaque nuit). Entre deux synchronisations, la copie peut être en retard sur le site.
- **Vérification** (partie 7.7 de `10_distribution.sql`) : 15 170 lignes dans la copie et à Angers, 0 écart, dates comprises.

---

## 2. Panne d'un site et reprise (preuves/L6_panne_reprise.txt)

Panne simulée : `system` bloque le compte `site_angers` et coupe ses sessions. Pour le siège, le lien ne répond plus, comme un serveur arrêté.

| Étape | Ce qui se passe | Résultat mesuré |
|---|---|---|
| 1a | parcours sur les 3 sites, avant la panne | validé, une ligne dans chaque fragment (2PC) |
| 1b | parcours Tours + Angers, 2 places demandées, 1 seule libre à Angers | refusé (`ORA-20021`), la ligne de Tours déjà posée est défaite : Tours 162 670 → 162 670 |
| 1c | catalogue d'Angers, avant la panne | lu dans le site (`SITE`) |
| 3a | vue globale, même limitée à Tours | `ORA-03150` (connexion coupée), puis `ORA-28000: The account is locked` : **Oracle ouvre tous les liens de la vue, même ceux des branches éliminées** |
| 3c | Tours lit son propre fragment | répond normalement : la panne d'Angers ne bloque pas les autres sites |
| 3d | inscriptions de Tours dont l'étudiant est rattaché à Angers | 4 854 inscriptions (3 379 étudiants) dont Tours ne peut plus afficher le nom |
| 3e | parcours Bordeaux + Angers | refusé en entier (`ORA-20020`), Bordeaux inchangé |
| 3f | parcours Bordeaux + Tours | validé : la panne d'Angers ne bloque pas les autres sites |
| 3g | 3 inscriptions simples à Angers (dont 2 sur une session à 1 place) | les 3 mises en attente au siège |
| 3h | catalogue d'Angers pendant la panne | `ORA-28000` capté, **bascule sur la copie** (`REPLIQUE`), mêmes sessions affichées |
| 3i | le siège corrige le prix d'une session d'Angers (+10) | modifié dans la copie, seule base qu'il peut atteindre |
| 5a-5c | reprise : déblocage, rejeu de la file | 2 rejouées, 1 refusée (« 0 place libre sur 10 ») ; pas de sur-réservation ; vue globale de nouveau disponible |
| 5d | conflit : la même session modifiée au siège (capacité + 5), puis à Angers (capacité + 2) | les deux versions et leur `derniere_maj` affichées (requête du Lab 5) |
| 5e | resynchronisation | 1 ligne copie → Angers (le prix corrigé pendant la panne), 1 ligne Angers → copie (le conflit : **Angers a écrit en dernier, son + 2 gagne**, le + 5 du siège est écrasé) ; copie et site identiques, 0 écart |
| 6 | nettoyage | 354 458 inscriptions, sessions remises à leurs valeurs, copie = table centrale (0 écart) |

Rejeu complet : **18 lignes OK, 0 échec**.

---

## 3. MongoDB shardé (preuves/L6_mongodb.txt)

Cluster du kit : 1 serveur de configuration, 3 shards (replica sets d'un nœud), 1 routeur `mongos`. Les 354 458 inscriptions valides sont exportées d'Oracle (mêmes données, mêmes valeurs de contrôle). Un document = une inscription avec le site, la ville, la langue et le début de la session.

### Mesures des clés candidates (`L6_mesures.js`)

| Clé candidate | Mesure | Verdict |
|---|---|---|
| `id_site` | 3 valeurs ; Tours = **45,9 %** des inscriptions | au plus 3 morceaux, non redécoupables ; un shard porte la moitié des données |
| `date_operation` | croissante ; **16 068 opérations le 10/09/2026** (4,5 % du total en un jour, 449 par jour en moyenne) | toutes les écritures du pic iraient dans le dernier morceau, donc sur un seul shard |
| `id_etudiant` | 21 471 valeurs ; 36 inscriptions au plus pour un étudiant (0,01 %) ; **chaque parcours n'a qu'un étudiant** (2 667 parcours, dont 1 874 multi-sites) | forte cardinalité, aucune valeur trop fréquente ; historique et parcours sur un seul shard |

### Clé retenue : `{ id_etudiant: "hashed" }`

| Mesure après sharding | Clé `id_etudiant` hachée (retenue) | Clé `id_site` (comparaison) |
|---|---|---|
| Documents par shard | 33,5 % / 32,3 % / 34,2 % | 22,2 % / 45,9 % / 31,9 % |
| Inscriptions de septembre 2026 par shard | 8 579 / 8 446 / 8 667 | 5 756 / 11 927 / 8 009 |
| Historique de l'étudiant 2141 | **1 shard** (`SINGLE_SHARD`, 17 documents) | 3 shards |
| Parcours G00001 (2 sites) | **1 shard** (`SINGLE_SHARD`) | 3 shards (le routeur ne sait pas où est l'étudiant) |
| Tableau de bord de Tours (rare) | 3 shards (`SHARD_MERGE`) | 1 shard |

Pourquoi pas **un shard par site**, comme au Lab 6 (zones `addShardToZone` / `updateZoneKeyRange` sur l'antenne) : c'est exactement ce que mesure la collection de comparaison (un morceau par site, placé à la main sur son shard). Chez nous, Tours porte 45,9 % des inscriptions : son shard aurait deux fois plus de données et d'écritures que celui de Bordeaux, et les requêtes par étudiant (historique, parcours) interrogeraient les 3 shards. Les zones restent utiles si une règle impose de garder les données d'un site sur un serveur donné (localisation) ; ce n'est pas notre cas, tous les sites sont en France.

Pourquoi **haché** plutôt que par intervalle sur `id_etudiant` : sur l'historique, couper les identifiants en trois tranches répartit aussi le pic (33,1 / 33,6 / 33,3 %), car les numéros d'étudiant ne suivent pas la date de création du compte (corrélation mesurée ≈ 0). Mais avec une clé par intervalle, nos 36 Mo tiennent dans un seul morceau (128 Mo par défaut) et restent sur un seul shard tant qu'on ne place pas les coupures à la main. La clé hachée découpe tout de suite la collection vide sur les 3 shards. Et nos requêtes par étudiant sont des égalités : le hachage ne fait perdre aucune requête utile.

Valeurs de contrôle recalculées sur la collection shardée : 354 458 documents, C5 = 27 333 192 / 56 080 982 / 39 082 945, C6 = 12 356, C8 = 1 874, identiques à Oracle.

---

## 4. Classement CAP / PACELC de nos choix

Rappel : **CAP** dit qu'en cas de partition (P, un site injoignable), il faut choisir entre la cohérence (C, refuser plutôt que répondre faux) et la disponibilité (A, répondre quand même). **PACELC** ajoute : sinon (E, en fonctionnement normal), il faut choisir entre la latence (L) et la cohérence (C).

| Choix | Pendant une panne (P) | En temps normal (E) | Classement | Preuve |
|---|---|---|---|---|
| Vues globales Oracle (requêtes multi-sites, C5, C6 du siège) | erreur dès qu'un site manque, même pour une requête sur un autre site : jamais de total faux | chaque requête lit les fragments en direct, à travers 3 liens : pas de copie périmée, mais la latence des liens | **PC / EC** | étape 3a |
| Parcours réparti (`inscrire_parcours`, 2PC) | refusé en entier si un site manque | 2PC : un aller-retour de plus par site au `COMMIT`, en échange de « tout ou rien » | **PC / EC** | étapes 1a, 1b, 3e |
| Inscription simple pendant une panne (file d'attente) | acceptée au siège, vérifiée et appliquée à la reprise : le contrôle de capacité est différé (1 refus sur 3 au rejeu) | synchrone et vérifiée dans le site | **PA / EC** | étapes 3g, 5 |
| ETUDIANT en une seule copie | Tours ne peut plus afficher 4 854 de ses inscriptions (étudiants d'Angers) | pas de copie à synchroniser ; 6,5 % des inscriptions demandent un lien | **PC / EC** | étape 3d, partie 7.4 |
| CATEGORIE répliquée | lue localement par chaque site | lecture locale ; la mise à jour (rare) se fait en redéployant | **PA / EL** | — |
| Copie des sessions d'Angers (`SESSION_REPLIQUE`) | le catalogue reste lisible et modifiable au siège ; la réponse peut être en retard sur Angers, et une modification faite des deux côtés crée un conflit, réglé à la reprise (le dernier écrivain gagne : l'une des deux modifications est perdue) | les lectures vont au site, à jour ; la copie n'est mise à jour qu'à la synchronisation (pas de coût à chaque écriture) | **PA / EC** | étapes 3h, 3i, 5d, 5e |
| MongoDB (lecture et écriture sur le primaire, réglages par défaut) | les données du shard en panne sont indisponibles, les autres restent servies ; avec un replica set d'un nœud, aucune copie ne prend le relais | écriture confirmée par la majorité du replica set (défaut depuis MongoDB 5.0), lecture sur le primaire : pas de lecture périmée | **PC / EC** | réglages par défaut de MongoDB (cours NoSQL, « PACELC en MongoDB ») |

En résumé : pour l'argent et les places (parcours, totaux du siège), on choisit la **cohérence**. On n'accepte la disponibilité que là où une incohérence se rattrape à la reprise sans conséquence, sans jamais forcer : l'inscription simple mise en attente, revérifiée au rejeu, et le catalogue lu dans sa copie, dont les conflits sont réglés à la reprise.

Ce qui changerait le classement :
- répliquer ETUDIANT dans les sites où l'étudiant suit des cours rendrait Tours disponible pendant une panne d'Angers (PA), au prix d'une synchronisation et de copies supplémentaires de données personnelles ;
- avec 3 nœuds par shard MongoDB (profil `replication` du kit), une panne de nœud déclencherait une élection (quelques secondes d'indisponibilité, puis reprise automatique), et des lectures sur les secondaires donneraient de la latence en échange de données parfois en retard (EL).

## 5. Volet RGPD (à reprendre dans l'ADR « comment répartir les données entre les sites »)

- Données personnelles d'un étudiant : **une seule copie**, dans le fragment ETUDIANT de son site de rattachement. Les autres sites et MongoDB n'ont que son identifiant.
- Droit à l'effacement : supprimer la ligne dans son site, ses inscriptions dans les trois fragments (via les vues globales) et ses documents MongoDB. Avec la clé `id_etudiant`, cette suppression ne touche **qu'un shard**.
- Localisation : toutes les bases sont en France (sites et siège) ; dans le kit, un seul conteneur.

## 6. Limites assumées

- Les trois sites sont trois schémas d'une même instance : la panne est simulée par le blocage du compte, pas par un serveur arrêté.
- Les tables centrales du L1-L5 sont gardées au siège : elles prouvent la reconstruction, et les annuaires (id → site) s'appuient dessus. Dans un vrai déploiement, le siège ne garderait que ces annuaires.
- Les mots de passe des sites sont écrits dans la définition des liens (mots de passe de TP).
- La sécurité par ligne du L5 protège les tables du siège ; sur les sites, chaque agent se connecterait à sa propre base et ne verrait de toute façon que son fragment.
- « Le dernier écrivain gagne » suppose des horloges synchronisées entre les sites (ici, une seule instance) et perd en silence la modification la plus ancienne. Le M3-3 cite les alternatives : copie primaire (seul le site écrit), ou fusion des deux versions.
- `derniere_maj` est mise à jour par chaque `UPDATE`, comme au Lab 5 : une modification qui l'oublierait ne serait pas vue par la synchronisation. Un déclencheur sur chaque fragment l'éviterait (il faudrait donner `CREATE TRIGGER` aux comptes des sites).
- Une session supprimée dans le site n'est pas supprimée de la copie (le cas ne se présente pas dans nos données : une session n'est jamais supprimée).
