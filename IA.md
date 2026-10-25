# Déclaration d'usage de l'IA — groupe 07

Obligatoire (−1 point si elle manque). Une page maximum au rendu.
Chacun complète au fur et à mesure.

## Outils utilisés

| Outil | Qui | Pour quoi faire | Livrable |
|---|---|---|---|
| Claude Code (VS Code) | Baptiste | Analyse des CSV, `00_nettoyage.sql`, test des contraintes; exécution des scripts sur le conteneur Oracle du kit | L1 |
| Claude Code (VS Code) | Baptiste | Méthode de chargement et `02_chargement.sql` : l'IA a proposé des tables externes + `INSERT ... SELECT` à la place de notre idée de départ (un `INSERT ... VALUES` par ligne puis `ALTER TABLE` pour les contraintes), trop lente pour 355 000 lignes et qui échouait sur les données fautives. Comparaison détaillée dans `docs/comptes_rendus/02_L2_chargement.md` | L2 |


## Ce qu'on a gardé, ce qu'on a corrigé

- Gardé : Chaque contrainte a été vérifiée par un test qui doit échouer.
- Corrigé : trois tests du script de preuve (voir ci-dessous) et la commande d'installation sous PowerShell (BOM).

## Au moins un cas où l'IA s'est trompée

| Ce que l'IA a proposé | Pourquoi c'était faux | Comment on l'a détecté |
|---|---|---|

