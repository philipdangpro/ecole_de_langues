# Justification de la dénormalisation

## 1. Objectif

La dénormalisation consiste à regrouper des informations provenant de plusieurs tables afin de faciliter les consultations et les analyses.

## 2. Choix effectué

Le fichier `inscriptions_denormalisees.csv` regroupe les inscriptions avec les informations des sessions et du campus associé à chaque session.

## 3. Avantages

- Faciliter les analyses par session et par campus.
- Simplifier les rapports statistiques.
- Réduire le nombre de jointures nécessaires aux consultations.

## 4. Inconvénients

- Répétition des informations de session et de campus.
- Augmentation de la taille du fichier.
- Risque d'incohérences si les données sources changent sans actualisation du fichier dénormalisé.

## 5. Contrôles et limites

Le fichier contient 354 855 lignes. Cependant, 220 inscriptions référencent une session absente de la table SESSIONS. Ces lignes sont conservées et doivent être vérifiées à la source.

## 6. Conclusion

Cette dénormalisation est destinée à faciliter les analyses et les consultations. Les tables normalisées restent la référence, tandis que le fichier dénormalisé sert principalement au reporting.