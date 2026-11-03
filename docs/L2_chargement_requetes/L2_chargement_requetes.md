### Valeurs de contrôle C3, C6 et C9

**C3 — Nombre d'opérations valides confirmées**

La requête SQL retourne **326 469 opérations valides confirmées**. Une opération est considérée comme valide lorsque la ressource associée existe, que son montant est positif ou nul et que sa date est antérieure ou égale à la date de début de la ressource. Le résultat est ensuite limité aux opérations confirmées.

**C6 — Nombre de personnes ayant des opérations valides sur au moins deux campus**

La requête retourne **12 356 personnes**. Pour chaque étudiant, les opérations valides sont regroupées et le nombre de campus distincts est calculé. Seuls les étudiants associés à au moins deux campus sont retenus. Chaque étudiant n'est compté qu'une seule fois.

**C9 — Nombre de places confirmées par catégorie de ressource**

Les résultats obtenus sont les suivants :

| Catégorie | Places confirmées |
|---|---:|
| FLE | 55 104 |
| Allemand | 52 705 |
| Anglais | 54 870 |
| Chinois | 54 681 |
| Espagnol | 54 579 |
| Italien | 54 530 |
| **Total** | **326 469** |

La requête joint les inscriptions aux sessions et aux catégories, filtre les opérations valides confirmées, puis additionne le nombre de places par catégorie. Dans ce jeu de données, chaque inscription représentant une place, le total de C9 correspond au nombre d'opérations comptées en C3.

Les trois valeurs ont été obtenues par exécution des requêtes sur la base Oracle du projet, avec la connexion dédiée `LANGUES`.