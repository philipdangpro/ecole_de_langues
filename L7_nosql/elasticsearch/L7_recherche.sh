#!/bin/bash
# =====================================================================
# L7_recherche.sh : index des étudiants et recherche de l'accueil
# Livrable : L7 · NoSQL (moteur 1 : Elasticsearch, besoin « recherche »)
# Responsable : Baptiste (avec Claude Code)
#
# Besoin réel : à l'accueil ou au téléphone, l'agent retrouve un étudiant à partir de ce
# qu'il entend : un nom mal orthographié, un prénom sans accent. Oracle compare des
# caractères et ne trouve rien (L7_oracle_comparaison.sql : 0 résultat) ; Elasticsearch
# tolère les fautes (fuzziness), ignore les accents (analyseur) et classe les réponses.
#
# Lancement (voir README.md) : docker exec elasticsearch bash /tmp/L7_recherche.sh
# Relançable : l'index est supprimé puis recréé.
# Sortie de référence : preuves/L7_elasticsearch.txt
# =====================================================================
ES=http://localhost:9200
# filter_path : on n'affiche que le nombre de réponses et, pour chacune, son score et
# ses champs (le reste de la réponse JSON est retiré par Elasticsearch lui-même)
RESULTATS='filter_path=hits.total.value,hits.hits._score,hits.hits._source&pretty'

echo "=== 0. Index 'etudiants' : analyseur sans accent, puis import ==="
curl -s -X DELETE "$ES/etudiants" -o /dev/null

# Analyseur « nom » : découpe en mots, minuscules, accents retirés (asciifolding) :
# « Léo », « LEO » et « leo » donnent le même terme « leo ».
# Sous-champ keyword : la valeur exacte, pour compter et regrouper.
curl -s -X PUT "$ES/etudiants?pretty" -H 'Content-Type: application/json' -d '
{
  "settings": {
    "number_of_shards": 1,
    "analysis": { "analyzer": { "nom": {
      "type": "custom", "tokenizer": "standard", "filter": ["lowercase", "asciifolding"] } } }
  },
  "mappings": { "properties": {
    "id_etudiant": { "type": "integer" },
    "nom":    { "type": "text", "analyzer": "nom", "fields": { "keyword": { "type": "keyword" } } },
    "prenom": { "type": "text", "analyzer": "nom", "fields": { "keyword": { "type": "keyword" } } },
    "ville":  { "type": "text", "analyzer": "nom" },
    "id_site": { "type": "integer" },
    "site":   { "type": "keyword" }
  } }
}'

# Import en masse. Le code HTTP 200 ne dit rien de chaque document : on lit « errors »
# (leçon de l'atelier M4-6), puis on compte les documents.
echo "Import _bulk, champ errors :"
curl -s -X POST "$ES/etudiants/_bulk?refresh=true&filter_path=errors" \
     -H 'Content-Type: application/x-ndjson' --data-binary @/tmp/etudiants_es.ndjson
echo
echo "Documents dans l'index (attendu 21 471, comme Oracle) :"
curl -s "$ES/etudiants/_count?filter_path=count"
echo
echo "Ce que l'analyseur fait de « Léo BERTRAND » :"
curl -s -X POST "$ES/etudiants/_analyze?filter_path=tokens.token" -H 'Content-Type: application/json' \
     -d '{ "analyzer": "nom", "text": "Léo BERTRAND" }'
echo


echo
echo "=== Q1. Formulaire de l'accueil : nom « Betrand », prénom « Leo » (une lettre oubliée, pas d'accent) ==="
echo "Oracle : 0 résultat. Attendu ici : les 15 Léo Bertrand en tête, puis des réponses plus"
echo "lointaines, moins bien notées : Léo Legrand (2 lettres d'écart), Léa Bertrand (Leo/Léa)."
curl -s -X GET "$ES/etudiants/_search?size=20&$RESULTATS" -H 'Content-Type: application/json' -d '
{
  "query": { "bool": { "must": [
    { "match": { "nom":    { "query": "Betrand", "fuzziness": "AUTO" } } },
    { "match": { "prenom": { "query": "Leo",     "fuzziness": "AUTO" } } }
  ] } },
  "_source": ["id_etudiant", "prenom", "nom", "site"]
}'
echo "Combien de Léo Bertrand parmi les 15 premières réponses (attendu 15) :"
curl -s -X GET "$ES/etudiants/_search?size=15&filter_path=hits.hits._source.prenom" -H 'Content-Type: application/json' -d '
{
  "query": { "bool": { "must": [
    { "match": { "nom":    { "query": "Betrand", "fuzziness": "AUTO" } } },
    { "match": { "prenom": { "query": "Leo",     "fuzziness": "AUTO" } } }
  ] } },
  "_source": ["prenom"]
}' | grep -o '"Léo"' | wc -l


echo
echo "=== Q2. La même recherche par un agent du site de Tours : filtre sur son site ==="
echo "filter ne change pas le score : il garde ou écarte (et le résultat est mis en cache)."
echo "Attendu : les 5 Léo Bertrand du site de Tours en tête."
curl -s -X GET "$ES/etudiants/_search?size=10&$RESULTATS" -H 'Content-Type: application/json' -d '
{
  "query": { "bool": {
    "must": [
      { "match": { "nom":    { "query": "Betrand", "fuzziness": "AUTO" } } },
      { "match": { "prenom": { "query": "Leo",     "fuzziness": "AUTO" } } }
    ],
    "filter": [ { "term": { "id_site": 3 } } ]
  } },
  "_source": ["id_etudiant", "prenom", "nom", "site"]
}'


echo
echo "=== Q3. Une seule zone de saisie : « leo bertran tours » (sans savoir quel mot va dans quel champ) ==="
echo "multi_match most_fields : chaque mot est cherché dans nom, prénom et ville, les scores s'additionnent."
echo "Attendu : en tête, les 5 Léo Bertrand qui habitent Tours, puis les autres Léo Bertrand."
echo "(Le total est plafonné à 10 000 : tout étudiant de Tours contient un des mots ; seul l'ordre compte.)"
curl -s -X GET "$ES/etudiants/_search?size=8&$RESULTATS" -H 'Content-Type: application/json' -d '
{
  "query": { "multi_match": {
    "query": "leo bertran tours",
    "fields": ["nom", "prenom", "ville"],
    "type": "most_fields",
    "fuzziness": "AUTO"
  } },
  "_source": ["id_etudiant", "prenom", "nom", "ville", "site"]
}'
