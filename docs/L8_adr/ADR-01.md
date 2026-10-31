# ADR-01 · Répartir les données selon le site de la session

Statut : accepté le 31/10/2026. Responsable : Baptiste.

## 1. Contexte et contrainte imposée

- Un siège (Paris) et trois sites : Bordeaux, Tours, Angers.
- 21 471 étudiants, 47 619 sessions, 354 458 inscriptions.
- Répartition des inscriptions : Bordeaux 22,2 %, Tours 45,9 %, Angers 31,9 %.
- Opération groupée : le parcours qui combine plusieurs campus. 2 667 parcours, dont 1 874 multi-sites. Tout ou rien.
- Pic : la rentrée de septembre. 16 068 inscriptions le 10/09/2026, contre 449 par jour en moyenne.
- Contrainte : un site en panne ne doit bloquer ni les autres sites, ni les places (pas de sur-réservation).

## 2. Options envisagées

- **A. Tout au siège.** Une seule base Oracle, les sites s'y connectent.
- **B. Fragments par site.** Session et inscription dans le site de la session ; étudiant dans son site de rattachement ; catégories copiées partout ; copie du catalogue d'Angers au siège. Liens Oracle et vues globales.
- **C. B, avec l'étudiant copié** dans chaque site où il suit des cours.
- **D. Une base, partitionnée par site** (`PARTITION BY LIST (id_site)`). Pas de lien, pas de 2PC.
- **E. Inscriptions rangées avec l'étudiant**, pas avec la session.

## 3. Critères

| Critère | A · siège | B · fragments (retenu) | C · étudiant copié | D · partitions | E · avec l'étudiant |
|---|---|---|---|---|---|
| Cohérence | ++ (ACID local) | + (2PC pour le parcours) | − (copies à synchroniser) | ++ | − (capacité contrôlée à distance) |
| Disponibilité | −− (siège en panne = tout bloqué) | + (Tours et Bordeaux continuent, étape 3f) | ++ (plus d'étudiants illisibles) | −− (une seule base) | + |
| Latence | − (chaque site passe par le réseau) | ++ (93,5 % des inscriptions ont leur étudiant dans le même site) | ++ | − (réseau) | − (contrôle de place par lien) |
| Volumétrie | + | + (Tours porte 45,9 %) | + | ++ | + |
| Coût | ++ (une base) | − (4 bases, liens, file d'attente) | −− (synchronisation en plus) | ++ | − |
| Sécurité, chiffrement | + (VPD du L5) | + (chaque site ne voit que son fragment ; TDE et chiffrement des liens à activer) | − (données perso en plusieurs copies) | + | + |

## 4. Mesures (preuves/L6_distribution.txt, preuves/L6_panne_reprise.txt)

- Reconstruction : table centrale `MINUS` vue globale = 0 ligne d'écart, sur les 3 tables.
- Coût de B : 22 955 inscriptions (6,5 %) ont leur étudiant dans un autre site.
- Panne d'Angers : Tours ne peut plus afficher 4 854 inscriptions (étape 3d).
- Panne d'Angers : parcours Bordeaux + Tours validé, parcours Bordeaux + Angers refusé en entier (`ORA-20020`).
- File d'attente : 3 inscriptions gardées au siège ; à la reprise, 2 rejouées, 1 refusée (« 0 place libre sur 10 »).
- Piège mesuré : contrôle entre sites avec `NOT EXISTS` = 4 min 27 s ; en jointure par hachage = 0,3 s.

## 5. Décision

Nous choisissons B. La session décide du site : une inscription reste avec sa session, donc le contrôle de place reste local. Le parcours multi-sites passe par le 2PC.

## 6. Conséquences et risques

- Facile : chaque site travaille seul, même au pic ; une panne n'arrête que son site.
- Difficile : les totaux du siège (vues globales) échouent dès qu'un site manque (étape 3a).
- Inconvénient : 6,5 % des inscriptions demandent un lien pour afficher le nom.
- Risque : conflit sur le catalogue copié. Parade : le dernier écrivain gagne (`derniere_maj`). Perte silencieuse de la modification la plus ancienne.
- Risque : horloges des sites décalées. Parade : synchronisation NTP.
- Seuil : si plus de 20 % des inscriptions ont leur étudiant dans un autre site, nous reprendrons l'option C.

## 7. Volet RGPD

- Données personnelles : nom, prénom, e-mail, téléphone, ville de l'étudiant.
- Minimisation : une seule copie, dans le site de rattachement. Le siège n'a que des annuaires (identifiant → site). Les agents ne voient que leur site (VPD du L5).
- Conservation : 3 ans après la dernière inscription (à valider avec le délégué à la protection des données). Purge par tâche planifiée (`DBMS_SCHEDULER`), pas encore écrite.
- Effacement : la ligne dans son site, ses inscriptions dans les 3 fragments, la file d'attente, le journal d'audit du L4, ses documents MongoDB (un seul shard). Sauvegardes : effacées à l'expiration.
- Localisation : siège et sites en France. Aucun transfert hors UE.

## 8. Liens

L3 (colonne `id_site`), L4 (parcours tout ou rien), L6 (`sql/10_distribution.sql`, `docs/L6_distribution/L6_distribution.md`), ADR-02.
