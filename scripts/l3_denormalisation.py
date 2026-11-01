
import pandas as pd
from pathlib import Path

# Chemins
BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / "scripts" / "tables_normalisees"

# Charger les tables
inscriptions = pd.read_csv(
    OUTPUT_DIR / "inscriptions.csv",
    low_memory=False
)
sessions = pd.read_csv(OUTPUT_DIR / "sessions.csv")
campus = pd.read_csv(OUTPUT_DIR / "campus.csv")

# Renommer l'identifiant du campus de la session
sessions = sessions.rename(columns={
    "id_campus": "id_campus_session"
})

# Ajouter les informations de session aux inscriptions
denormalise = inscriptions.merge(
    sessions,
    on="id_session",
    how="left"
)

# Préparer les informations du campus de la session
campus_session = campus.rename(columns={
    "id_campus": "id_campus_session",
    "nom": "nom_campus",
    "ville": "ville_campus",
    "role": "role_campus"
})

# Ajouter les informations du campus
denormalise = denormalise.merge(
    campus_session,
    on="id_campus_session",
    how="left"
)

# Export
output_file = OUTPUT_DIR / "inscriptions_denormalisees.csv"

denormalise.to_csv(
    output_file,
    index=False,
    encoding="utf-8"
)

# Résumé
print("Dénormalisation terminée.")
print(f"Fichier créé : {output_file}")
print(f"Nombre de lignes : {len(denormalise)}")
print(f"Nombre de colonnes : {len(denormalise.columns)}")
print("Sessions sans libellé :", denormalise["libelle"].isna().sum())
print(
    "Campus de session manquant :",
    denormalise["nom_campus"].isna().sum()
)
