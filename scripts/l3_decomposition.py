
import pandas as pd
from pathlib import Path

# Chemins des fichiers
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = BASE_DIR / "scripts" / "tables_normalisees"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Chargement des données sources
inscriptions = pd.read_csv(
    DATA_DIR / "inscriptions.csv",
    low_memory=False
)
etudiants = pd.read_csv(DATA_DIR / "etudiants.csv")
sessions = pd.read_csv(DATA_DIR / "sessions.csv")
campus = pd.read_csv(DATA_DIR / "campus.csv")

# 1. Table CAMPUS
campus.to_csv(
    OUTPUT_DIR / "campus.csv",
    index=False,
    encoding="utf-8"
)

# 2. Table ETUDIANTS
etudiants.to_csv(
    OUTPUT_DIR / "etudiants.csv",
    index=False,
    encoding="utf-8"
)

# 3. Table SESSIONS
sessions.to_csv(
    OUTPUT_DIR / "sessions.csv",
    index=False,
    encoding="utf-8"
)

# 4. Table INSCRIPTIONS
inscriptions.to_csv(
    OUTPUT_DIR / "inscriptions.csv",
    index=False,
    encoding="utf-8"
)

# Résumé
print("Décomposition terminée.")
print(f"Dossier de sortie : {OUTPUT_DIR}")

for fichier in OUTPUT_DIR.glob("*.csv"):
    df = pd.read_csv(fichier, low_memory=False)
    print(f"{fichier.name} : {len(df)} lignes, {len(df.columns)} colonnes")

print("\nTables créées :")
print("- CAMPUS")
print("- ETUDIANTS")
print("- SESSIONS")
print("- INSCRIPTIONS")
