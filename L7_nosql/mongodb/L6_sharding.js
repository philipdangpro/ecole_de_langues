// =====================================================================
// L6_sharding.js : collection MongoDB shardée et preuve de la répartition
// Livrable : L6 · Distribution · Responsable : Baptiste (avec Claude Code)
//
// Lancement (après L6_mesures.js, voir README.md) :
//   docker exec mongos mongosh langues --quiet --file /tmp/L6_sharding.js
// Relançable : les deux collections shardées sont supprimées puis recréées.
// Sortie de référence : preuves/L6_mongodb.txt
//
// Clé retenue : { id_etudiant: "hashed" } pour la collection langues.inscriptions.
// Justification (mesures de L6_mesures.js, détail dans docs/L6_distribution/) :
//   - id_site : 3 valeurs, Tours = 45,9 % des données -> déséquilibre (prouvé ici avec
//     la collection de comparaison inscriptions_par_site) ;
//   - date_operation : croissante, le 10/09/2026 concentre 16 068 opérations (4,5 % du
//     total en un jour sur 789) -> toutes les écritures du pic sur un seul shard ;
//   - id_etudiant : 21 471 valeurs, 36 inscriptions au plus pour un étudiant, et un
//     parcours n'a qu'un étudiant -> l'historique et le parcours sont sur UN shard.
//   Haché plutôt que par intervalle : sur l'historique, les deux répartissent bien le pic
//   (33/34/33 % par tranche d'id). Mais le hachage découpe tout de suite la collection
//   vide sur les 3 shards, alors qu'une clé par intervalle laisse nos 36 Mo dans un seul
//   morceau (taille d'un morceau : 128 Mo), donc sur un seul shard, tant qu'on ne choisit
//   pas les coupures à la main. Et nos requêtes par étudiant sont des égalités : le
//   hachage ne fait perdre aucune requête utile.
// =====================================================================

const LOT = 5000;

// Copie la collection d'import dans une collection shardée, par lots
function copier(cible) {
  let lot = [], n = 0;
  db.inscriptions_import.find().sort({ _id: 1 }).forEach(d => {
    lot.push(d);
    if (lot.length === LOT) { db[cible].insertMany(lot, { ordered: false }); n += lot.length; lot = []; }
  });
  if (lot.length) { db[cible].insertMany(lot, { ordered: false }); n += lot.length; }
  return n;
}

// Nombre de documents par shard (statistiques de chaque shard, lues par le routeur)
function parShard(coll) {
  const total = db[coll].countDocuments();
  db[coll].aggregate([{ $collStats: { count: {} } }, { $sort: { shard: 1 } }]).forEach(s =>
    print("  " + s.shard + " : " + String(s.count).padStart(6) + "  " + (100 * s.count / total).toFixed(1) + " %"));
}

// Shards interrogés par une requête, et ce que chacun renvoie
function cibles(coll, filtre, titre) {
  const e = db[coll].find(filtre).explain("executionStats");
  const etapes = e.executionStats.executionStages;
  const shards = (etapes.shards || []).sort((a, b) => a.shardName.localeCompare(b.shardName));
  print("  " + titre);
  print("    étape du routeur : " + etapes.stage + ", shards interrogés : " + shards.length
        + ", documents : " + e.executionStats.nReturned);
  shards.forEach(s => print("      " + s.shardName + " -> " + s.nReturned + " document(s)"));
}

// Les écritures du pic de la rentrée : sur quel shard sont les inscriptions de septembre 2026
const PIC = { date_operation: { $gte: ISODate("2026-09-01"), $lt: ISODate("2026-10-01") } };


// ---------------------------------------------------------------------
// 1. Collection retenue : clé id_etudiant hachée
// ---------------------------------------------------------------------
print("=== 1. langues.inscriptions, clé { id_etudiant: \"hashed\" } ===");
db.inscriptions.drop();
sh.enableSharding("langues");
// Collection vide + clé hachée : MongoDB crée tout de suite des morceaux sur chaque shard
sh.shardCollection("langues.inscriptions", { id_etudiant: "hashed" });
// Historique d'un étudiant trié par date de début (accueil)
db.inscriptions.createIndex({ id_etudiant: 1, debut: -1 });

print("  documents copiés : " + copier("inscriptions"));
print("  morceaux (chunks) par shard :");
db.getSiblingDB("config").chunks.aggregate([
  { $match: { uuid: db.getSiblingDB("config").collections.findOne({ _id: "langues.inscriptions" }).uuid } },
  { $group: { _id: "$shard", n: { $sum: 1 } } }, { $sort: { _id: 1 } }
]).forEach(r => print("    " + r._id + " : " + r.n));
print("  documents par shard :");
parShard("inscriptions");


// ---------------------------------------------------------------------
// 2. Collection de comparaison : clé id_site (option rejetée)
//    Morceaux coupés à la main, un site par shard : c'est ce que donnerait le
//    « un site = un shard » le plus naturel.
// ---------------------------------------------------------------------
print("\n=== 2. Comparaison : langues.inscriptions_par_site, clé { id_site: 1 } ===");
db.inscriptions_par_site.drop();
sh.shardCollection("langues.inscriptions_par_site", { id_site: 1 });
sh.splitAt("langues.inscriptions_par_site", { id_site: 3 });
sh.splitAt("langues.inscriptions_par_site", { id_site: 4 });
const ns = db.adminCommand({ listShards: 1 }).shards.map(s => s._id).sort();
[[2, ns[0]], [3, ns[1]], [4, ns[2]]].forEach(([site, shard]) => {
  try { sh.moveChunk("langues.inscriptions_par_site", { id_site: site }, shard); }
  catch (e) { if (!/already/.test(e.message)) throw e; }   // déjà sur ce shard
});
print("  documents copiés : " + copier("inscriptions_par_site"));
print("  documents par shard :");
parShard("inscriptions_par_site");


// ---------------------------------------------------------------------
// 3. Le pic de la rentrée : où vont les inscriptions de septembre 2026
// ---------------------------------------------------------------------
print("\n=== 3. Inscriptions de septembre 2026 (pic de la rentrée) par shard ===");
cibles("inscriptions",          PIC, "clé id_etudiant hachée :");
cibles("inscriptions_par_site", PIC, "clé id_site :");


// ---------------------------------------------------------------------
// 4. Requêtes fréquentes : combien de shards chacune interroge-t-elle ?
// ---------------------------------------------------------------------
print("\n=== 4. Ciblage des requêtes (collection retenue) ===");
// étudiant de test : celui du L5 (historique de 17 inscriptions)
const etu = 2141;
// premier parcours qui combine plusieurs sites
const parcours = db.inscriptions.aggregate([
  { $match: { id_groupe: { $exists: true } } },
  { $group: { _id: "$id_groupe", id_etudiant: { $first: "$id_etudiant" }, sites: { $addToSet: "$id_site" } } },
  { $match: { "sites.1": { $exists: true } } }, { $sort: { _id: 1 } }, { $limit: 1 }
]).toArray()[0];
parcours.id_groupe = parcours._id;
cibles("inscriptions", { id_etudiant: etu }, "historique de l'étudiant " + etu + " :");
cibles("inscriptions", { id_etudiant: parcours.id_etudiant, id_groupe: parcours.id_groupe },
       "parcours " + parcours.id_groupe + " (étudiant " + parcours.id_etudiant + ", "
       + parcours.sites.length + " sites) :");
cibles("inscriptions", { id_site: 3, statut: "CONFIRMEE" }, "tableau de bord de Tours (rare) :");
print("\n  Mêmes requêtes sur la collection de comparaison (clé id_site) :");
cibles("inscriptions_par_site", { id_etudiant: etu }, "historique de l'étudiant " + etu + " :");
cibles("inscriptions_par_site", { id_etudiant: parcours.id_etudiant, id_groupe: parcours.id_groupe },
       "parcours " + parcours.id_groupe + " :");
cibles("inscriptions_par_site", { id_site: 3, statut: "CONFIRMEE" }, "tableau de bord de Tours :");


// ---------------------------------------------------------------------
// 5. Valeurs de contrôle recalculées sur la collection shardée (= Oracle)
// ---------------------------------------------------------------------
print("\n=== 5. Valeurs de contrôle sur la collection shardée ===");
print("  documents : " + db.inscriptions.countDocuments() + "  (Oracle : 354 458)");
print("  C5, chiffre d'affaires par site (Oracle : 27 333 192 / 56 080 982 / 39 082 945) :");
db.inscriptions.aggregate([
  { $match: { statut: "CONFIRMEE" } },
  { $group: { _id: { site: "$id_site", ville: "$ville" }, ca: { $sum: "$montant" } } },
  { $sort: { "_id.site": 1 } }
]).forEach(r => print("    " + r._id.site + " " + r._id.ville.padEnd(9) + r.ca));
const c6 = db.inscriptions.aggregate([
  { $group: { _id: "$id_etudiant", sites: { $addToSet: "$id_site" } } },
  { $match: { "sites.1": { $exists: true } } }, { $count: "n" }
]).toArray()[0].n;
print("  C6, personnes sur au moins deux sites : " + c6 + "  (Oracle : 12 356)");
const c8 = db.inscriptions.aggregate([
  { $match: { id_groupe: { $exists: true } } },
  { $group: { _id: "$id_groupe", sites: { $addToSet: "$id_site" } } },
  { $match: { "sites.1": { $exists: true } } }, { $count: "n" }
]).toArray()[0].n;
print("  C8, parcours sur au moins deux sites : " + c8 + "  (Oracle : 1 874)");
