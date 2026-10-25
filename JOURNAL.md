# Journal de bord — groupe 07 · École de langues

Obligatoire (−1 point s'il manque). Une entrée par décision, impasse ou erreur.
Pour une erreur, copier le **message exact** (ex. `ORA-02291: integrity constraint ... violated`) et dire comment on l'a résolue.
Les entrées les plus récentes vont en haut.

| Date | Qui | Livrable | Type | Ce qui s'est passé | Résolution / décision |
|---|---|---|---|---|---|
| 2026-10-25 | Groupe | L1 | décision | Création des tables (`01_creation_tables.sql`) écrite à la main par le groupe, à partir du modèle de `L1_modele.md` | Les commentaires du script ont été ajoutés avec l'IA (Claude), plus rapide pour documenter chaque contrainte et la règle de gestion qu'elle garantit |
| 2026-10-25 | Baptiste | L1 | décision | `00_nettoyage.sql` fait avec Claude | Script propre et reproductible : il supprime tous les objets du schéma pour relancer `run_all.sql` de zéro, sur une base vide comme déjà remplie |
| 2026-10-25 | Baptiste | — | erreur | `docker cp data/. oracle-bdd:/opt/oracle/donnees_langues/` lancé depuis Git Bash : aucun message, mais dossier vide dans le conteneur | Git Bash réécrit `/opt/...` en chemin Windows. Commandes passées sous PowerShell (ou `MSYS_NO_PATHCONV=1`), noté dans le README |
| 2026-10-25 | Baptiste | — | erreur | Script d'installation envoyé par `Get-Content ... \| docker exec -i ... sqlplus` : `SP2-0734: unknown command beginning "﻿-- ======..." - rest of line ignored.` | PowerShell 5.1 ajoute un BOM en tête du flux. On copie le fichier dans le conteneur (`docker cp`) puis `sqlplus @/tmp/...` |
| 2026-10-25 | Baptiste | — | décision | Le kit ne crée que le compte `club` ; notre schéma `langues` n'existerait pas chez l'enseignante | `sql/installation_system.sql` (lancé une fois en `system`) crée `langues` avec les droits de `club` et le DIRECTORY des CSV |
| 2026-10-25 | Baptiste | L2 | décision | Méthode de chargement : tables externes (ORACLE_LOADER) plutôt que SQL\*Loader ou scripts d'INSERT | Tout reste en SQL dans `run_all.sql`, 355 000 lignes en quelques secondes. `RECORDS DELIMITED BY DETECTED NEWLINE` car les CSV sont en LF dans Git et en CRLF après checkout Windows (testé : `siège` lu sur 5 caractères, sans `\r`) |
| 2026-10-24 | Baptiste | — | consigne | Sujet mis à jour par l'enseignante : jalon supprimé, 2 ADR au lieu de 3, plus de demande de changement à J+12, nouvelle grille (C1–C9 : 3, L1–L7 : 14, ADR : 3, bonus +2) | Arborescence adaptée (ADR-03 et script de demande de changement retirés) |
| 2026-10-24 | Baptiste | — | décision | Mise en place de l'arborescence du dépôt | Voir README.md |
