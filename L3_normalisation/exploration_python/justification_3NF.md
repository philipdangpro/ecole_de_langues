# Justification de la troisième forme normale (3NF)

## 1. Clés primaires

Chaque table possède une clé primaire permettant d'identifier chaque ligne de manière unique :

- **CAMPUS** : `id_campus`
- **ETUDIANTS** : `id_etudiant`
- **SESSIONS** : `id_session`
- **INSCRIPTIONS** : `id_inscription`

Les contrôles réalisés n'ont détecté aucun doublon dans ces identifiants. Leur absence de valeurs manquantes doit également être vérifiée.

## 2. Dépendances fonctionnelles

Les dépendances fonctionnelles candidates retenues sont :

- `id_campus → nom, ville, role` dans CAMPUS
- `id_etudiant → nom, prenom, email, telephone, ville, id_campus, date_inscription` dans ETUDIANTS
- `id_session → libelle, categorie, id_campus, debut, duree_minutes, capacite, prix_unitaire` dans SESSIONS
- `id_inscription → id_etudiant, id_session, date_inscription, nb_places, montant, statut, id_groupe` dans INSCRIPTIONS

Ces dépendances sont fondées sur les identifiants des entités. Elles doivent être confirmées par les règles métier. L'identifiant du campus dans ETUDIANTS désigne le campus associé à l'étudiant, tandis que celui de SESSIONS désigne le campus où se déroule la session.

## 3. Analyse de la troisième forme normale

La décomposition sépare les principales entités de l'application : les campus, les étudiants, les sessions et les inscriptions.

Sous réserve que les dépendances fonctionnelles retenues soient correctes et que les clés candidates soient identifiées, chaque table est compatible avec une conception en troisième forme normale si, pour chaque dépendance fonctionnelle non triviale, le déterminant est une superclé ou l'attribut déterminé est un attribut premier.

Cette organisation limite la répétition des informations descriptives et réduit les risques d'anomalies de mise à jour, d'insertion et de suppression.

La conformité formelle à la 3NF reste conditionnée à la validation des dépendances fonctionnelles et des clés candidates à partir des règles métier.

## 4. Intégrité référentielle

Les contrôles réalisés indiquent :

- Aucun étudiant ne référence un campus absent.
- Aucune session ne référence un campus absent.
- Aucune inscription ne référence un étudiant absent.
- 220 inscriptions référencent une session absente de la table SESSIONS.

Ces 220 cas constituent une anomalie d'intégrité référentielle. Les lignes ont été conservées dans les fichiers produits afin de ne pas perdre de données. Les références concernées doivent être examinées et corrigées à la source.

## 5. Conclusion

La décomposition en quatre tables permet de séparer les entités principales de l'école de langues et de limiter les redondances.

Les identifiants ont été contrôlés et les relations entre les inscriptions, les étudiants et les campus ont été examinées. Une anomalie concernant 220 références de session a été identifiée et documentée.

La conformité formelle à la troisième forme normale doit être confirmée par la validation des dépendances fonctionnelles, des clés candidates et des règles métier.