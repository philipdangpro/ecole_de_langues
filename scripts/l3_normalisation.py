
import pandas as pd
from pathlib import Path

# Chemins des fichiers
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = BASE_DIR / "scripts"

# Chargement des CSV
inscriptions = pd.read_csv(
    DATA_DIR / "inscriptions.csv",
    low_memory=False
)
etudiants = pd.read_csv(DATA_DIR / "etudiants.csv")
sessions = pd.read_csv(DATA_DIR / "sessions.csv")
campus = pd.read_csv(DATA_DIR / "campus.csv")

# Renommer les colonnes des étudiants pour éviter les confusions
etudiants = etudiants.rename(columns={
    "id_campus": "id_campus_etudiant",
    "date_inscription": "date_inscription_etudiant"
})

# Renommer les colonnes des sessions
sessions = sessions.rename(columns={
    "id_campus": "id_campus_session"
})

# Renommer les colonnes du campus
campus_etudiant = campus.rename(columns={
    "id_campus": "id_campus_etudiant",
    "nom": "nom_campus_etudiant",
    "ville": "ville_campus_etudiant",
    "role": "role_campus_etudiant"
})

campus_session = campus.rename(columns={
    "id_campus": "id_campus_session",
    "nom": "nom_campus_session",
    "ville": "ville_campus_session",
    "role": "role_campus_session"
})

# Fusion des inscriptions avec les étudiants
df = inscriptions.merge(
    etudiants,
    on="id_etudiant",
    how="left"
)

# Fusion avec les sessions
df = df.merge(
    sessions,
    on="id_session",
    how="left"
)

# Ajouter les informations du campus de l'étudiant
df = df.merge(
    campus_etudiant,
    on="id_campus_etudiant",
    how="left"
)

# Ajouter les informations du campus de la session
df = df.merge(
    campus_session,
    on="id_campus_session",
    how="left"
)

# Export du fichier à plat
output_file = OUTPUT_DIR / "operations_a_plat.csv"

df.to_csv(
    output_file,
    index=False,
    encoding="utf-8"
)

# Résumé de l'exécution
print(f"Fichier créé : {output_file}")
print(f"Nombre de lignes : {len(df)}")
print(f"Nombre de colonnes : {len(df.columns)}")

print("\nAperçu du fichier :")
print(df.head())

# Vérifications
print("\nVérifications :")
print(
    "Inscriptions sans étudiant :",
    df["nom"].isna().sum()
)
print(
    "Inscriptions sans session :",
    df["libelle"].isna().sum()
)
print(
    "Campus de session manquant :",
    df["nom_campus_session"].isna().sum()
)
