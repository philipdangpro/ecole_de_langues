# Exploration Python du L3 (première version, Younes)

Ce dossier garde la première analyse du L3, faite en Python (pandas) en octobre 2026. Elle n'est **pas** le livrable :

- le livrable est [`../05_normalisation.sql`](../05_normalisation.sql), lancé par `prerequis/run_all.sql` ;
- ses explications sont dans [`../L3_normalisation.md`](../L3_normalisation.md).

Pourquoi elle a été reprise en SQL (détail : [`../03_L3_normalisation.md`](../03_L3_normalisation.md)) :

- l'enseignante relance les scripts sur le kit du cours, qui n'a pas Python ;
- la « décomposition » recopiait les CSV d'entrée au lieu de découler des dépendances fonctionnelles ;
- les dépendances étaient listées « à vérifier », sans requête ni chiffre.

Les idées reprises dans la version SQL : renommer les colonnes de campus selon leur rôle (campus de l'étudiant, campus de la session), joindre en externe pour ne perdre aucune opération, repérer les 220 sessions absentes.

Les documents de ce dossier (`dependances_fonctionnelles.md`, `justification_3NF.md`, `justification_denormalisation.md`, `rapport_normalisation.md`) décrivent cette première version. Leurs conclusions (« conformité à confirmer », « sessions à corriger à la source ») sont remplacées par celles de `L3_normalisation.md`.

Les scripts ne sont plus exécutables tels quels : ils lisent et écrivent dans un dossier `scripts/` qui n'existe plus depuis la réorganisation du dépôt. Les CSV qu'ils produisaient (environ 160 Mo) ne sont pas versionnés (`.gitignore`).
