# Compte rendu 03 · L3, normalisation (reprise en SQL) — 27/10/2026

Auteur : Baptiste (avec Claude Code)

## En une phrase

Le L3 de Younes, écrit en Python, est refait en SQL dans `sql/05_normalisation.sql`. Le script crée la table à plat, vérifie chaque dépendance fonctionnelle par une requête, prouve que la décomposition ne perd rien, et met en place une vraie dénormalisation, mesurée et testée. `run_all.sql` tourne sans erreur.

## Les fichiers

| Fichier | Rôle | Pour qui |
|---|---|---|
| `sql/05_normalisation.sql` | Le livrable, relancé par l'enseignante | Enseignante |
| `docs/L3_normalisation/L3_normalisation.md` | Explication complète, à reprendre dans le rapport | Groupe, rapport |
| `preuves/L3_denormalisation.sql` / `.txt` | Mesures et tests de la dénormalisation (hors `run_all`) | Rapport, oral |
| Ce fichier | Ce que j'ai fait, et ce que je dois savoir expliquer | Toi |
| `.gitignore` | Ajout de `scripts/**/*.csv` : plus de CSV générés dans Git | Groupe |

`IA.md` n'a pas été touché : tu t'en occupes.

## Ce qui n'allait pas dans la version Python

1. **Elle ne pouvait pas être relancée.** Le kit du cours n'a pas Python, et 14 points sur 20 dépendent de la relance des scripts.
2. **La « décomposition » recopiait les CSV.** `l3_decomposition.py` relisait les 4 CSV et les réécrivait à l'identique. Rien ne venait des dépendances.
3. **Les dépendances n'étaient jamais vérifiées.** Le texte répétait « à vérifier », « sous réserve » : aucune conclusion.
4. **Les défauts étaient ignorés.** Les doublons et les opérations non valides étaient gardés, en contradiction avec notre L2.
5. **pandas avait abîmé des valeurs.** Les téléphones avaient perdu leur 0 initial, et des entiers étaient devenus `4.0`.
6. **La dénormalisation restait théorique**, sans mesure ni mécanisme de cohérence.
7. **165 Mo de CSV générés** étaient commités (un fichier de 87 Mo, alors que GitHub refuse au-delà de 100 Mo).

## Ce que fait le nouveau script, étape par étape

### 1. La table à plat (`OPERATION_A_PLAT`)
- Une ligne par opération du CSV (354 855), avec son étudiant, sa session et les deux campus : 28 colonnes.
- Elle est construite depuis les **CSV bruts**, pour que les défauts restent visibles.
- `LEFT JOIN` : on ne perd aucune opération, même celles dont la session n'existe pas.

### 2. Les dépendances fonctionnelles, vérifiées une par une
**Le principe à savoir expliquer** : X → Y est vraie si chaque X n'a qu'un seul Y. On regroupe par X, et on compte les X qui ont plusieurs Y. Si on trouve 0, la dépendance tient.

**Ce qu'on trouve** :
- Les dépendances « normales » tiennent : chaque id détermine sa ligne.
- Trois dépendances sont violées par les **défauts du CSV**, et c'est exactement ce que le L2 corrige :
  - e-mail → étudiant : 73 violations, ce sont les 73 copies ;
  - (session, places) → montant : 88 violations, dues aux montants négatifs et aux sessions inexistantes ;
  - groupe → étudiant : 9 violations.
- **Au passage, la question « à discuter » des 9 groupes multi-étudiants est réglée.** Ce sont des parcours passés en partie sous l'id d'une copie : la même personne sous deux id. Après la fusion du L2, il en reste 0.
- **Nouveautés** :
  - le libellé de session est une deuxième clé (« Session FLE 1 » est unique) ;
  - les 80 montants négatifs valent exactement −(places × prix) : c'est une erreur de signe.

### 3. La décomposition, vérifiée « sans perte »
- On découpe la table à plat en 4 relations (opération, étudiant, session, campus), on les recolle, et on compare : 0 ligne en trop, 0 ligne perdue.
- On ne retrouve que **3 campus sur 4** : le siège n'a aucune opération, donc il n'existe pas dans la table à plat. C'est l'exemple concret d'**anomalie d'insertion**, à citer à l'oral.

### 4. La dénormalisation : `INSCRIPTION.id_site`
- Le site de la session est recopié dans chaque inscription.
- **Cohérence** : une clé étrangère composite refuse un site faux, et un trigger le remplit tout seul.
- **Mesure** : 2 391 → 2 266 blocs lus sur C5, C6 et C8 (−5 %). C'est faible, et on le dit tel quel.
- **La vraie raison** : le L5 (partitionnement) et le L6 (répartition par site) ont besoin de la colonne dans la table.

## Ce que tu dois savoir dire à l'oral

- **Pourquoi normaliser ?** La table à plat fait 88 Mo, contre 23 Mo pour les tables décomposées. Elle a aussi trois anomalies :
  - le siège ne peut pas y figurer ;
  - changer un e-mail oblige à modifier environ 16 lignes ;
  - supprimer la dernière inscription d'une session fait disparaître la session.
- **Pourquoi BCNF et pas seulement 3NF ?** Dans chaque table, tout ce qui détermine une colonne est une clé. Exemple : `libelle` détermine `id_session`, mais `libelle` est lui-même une clé.
- **Le piège de N4.** La ville de l'étudiant détermine son campus dans 100 % des données. On ne la retient pas : aucune règle ne l'impose, c'est une coïncidence du jeu de données. Une dépendance observée ne prouve pas une règle du métier.
- **Trois écarts à la 3NF, tous assumés** :
  - `id_site`, ajouté au L3 : mesuré, cohérence garantie ;
  - `montant` : c'est le prix payé le jour J, un historique ;
  - `id_groupe` : il cache une entité « opération groupée ». La décision est renvoyée à un ADR, puisque le sujet propose ce thème.
- **Si l'enseignante demande pourquoi on ne peut plus déplacer une session** : c'est voulu. Une session déjà vendue ne change pas de ville. La clé étrangère refuse le changement (ORA-02292).

## Comment vérifier

1. SQL Developer, connexion `langues` : `sql/run_all.sql`, F5. La reconstruction complète prend environ 50 secondes ; c'est la table à plat de 88 Mo qui prend le plus de temps.
2. Les résultats du L3 s'affichent à la fin du journal d'exécution : les tableaux D1 à D9, N1 à N4, puis la vérification sans perte.
3. Preuves de la dénormalisation : lancer `preuves/L3_denormalisation.sql` en sqlplus, ou lire `preuves/L3_denormalisation.txt`. Les tests sont annulés à la fin (`ROLLBACK`).

## Problèmes rencontrés pendant le travail

- **Deux chiffres différents de ce que j'attendais :**
  - D7 donne 88 violations, pas 80. La décomposition a montré que 8 viennent de sessions inexistantes.
  - La décomposition ne retrouve que 3 campus au lieu de 4, à cause du siège.

  Les deux sont expliqués dans le script et dans la doc.
- **Première relance de `run_all` lancée depuis PowerShell** : j'ai lu par erreur l'ancien `run_all.log`, copié depuis ton poste. J'ai relancé depuis Git Bash avec `MSYS_NO_PATHCONV=1`, et le résultat était sans erreur.

## Ce qu'il faut faire avec la branche `younes`

- **Ne pas la fusionner telle quelle.** Elle ferait entrer 165 Mo de CSV dans l'historique de `main`, définitivement.
- Le contenu utile est repris dans `docs/L3_normalisation/L3_normalisation.md`, qui le crédite.
- **Attention à la note « dépôt alimenté par chaque membre ».** Younes doit avoir des commits à lui dans `main`. Proposition : il crée une nouvelle branche depuis `main`, relit et complète la doc du L3, et reporte `date_operation` sur le MCD, ce qui était déjà prévu. Puis il fait sa propre Pull Request.
- Pour information : son `requirements.txt` est encodé en UTF-16. C'est l'effet de `pip freeze > requirements.txt` sous PowerShell. Sans Python dans le projet, ce fichier n'a plus de raison d'être.

## Points ouverts

- **Valeurs de contrôle :** les mesures ont déjà calculé **C5** (27 333 192 / 56 080 982 / 39 082 945 pour les sites 2, 3 et 4), **C6** (12 356) et **C8** (1 874). Ces chiffres sont à reprendre dans `03_valeurs_controle.sql`, avec leurs requêtes.
- **L4** : le trigger du L3 utilise le code d'erreur `-20001`. Les triggers du L4 doivent prendre d'autres numéros.
- **ADR** : « où stocker l'opération groupée » a maintenant des arguments chiffrés (D8, D9).
- La vue `V_INSCRIPTION_SITE` (L1) pourrait lire `id_site` directement. Je ne l'ai pas modifiée, puisque ce n'était pas demandé.
