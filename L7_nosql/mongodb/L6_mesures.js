// =====================================================================
// L6_mesures.js : mesurer la répartition des inscriptions AVANT de choisir la clé
// de sharding.
// Livrable : L6 · Distribution · Responsable : Baptiste (avec Claude Code)
//
// Lancement (voir README.md) :
//   docker exec mongos mongosh langues --quiet --file /tmp/L6_mesures.js
// Lit la collection non shardée langues.inscriptions_import (import du CSV exporté
// d'Oracle). Ne modifie rien. Sortie de référence : preuves/L6_mongodb.txt
//
// Une bonne clé de sharding doit :
//   1. avoir beaucoup de valeurs distinctes (sinon on ne peut pas découper) ;
//   2. ne pas avoir de valeur trop fréquente (sinon un morceau ne se découpe plus) ;
//   3. répartir les ÉCRITURES du pic (rentrée de septembre) sur tous les shards ;
//   4. permettre aux requêtes fréquentes de n'interroger qu'un seul shard.
// Chaque mesure ci-dessous teste une clé candidate sur un de ces critères.
// =====================================================================

const c = db.inscriptions_import;
const total = c.countDocuments();
const pct = (n) => (100 * n / total).toFixed(1) + " %";
print("Documents : " + total + "  (attendu 354 458, comme Oracle)");

// ---------------------------------------------------------------------
// Clé candidate 1 : id_site
// ---------------------------------------------------------------------
print("\n=== 1. Clé id_site : répartition par site ===");
c.aggregate([
  { $group: { _id: { site: "$id_site", ville: "$ville" }, n: { $sum: 1 } } },
  { $sort: { "_id.site": 1 } }
]).forEach(r => print("  site " + r._id.site + " " + r._id.ville.padEnd(9) + r.n + "  " + pct(r.n)));
print("  -> 3 valeurs seulement : au plus 3 morceaux (chunks), impossibles à redécouper ;");
print("     le shard qui reçoit Tours porte près de la moitié des données.");

// ---------------------------------------------------------------------
// Clé candidate 2 : date_operation (le pic de la rentrée)
// ---------------------------------------------------------------------
print("\n=== 2. Clé date_operation : le pic de la rentrée ===");
c.aggregate([
  { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$date_operation" } }, n: { $sum: 1 } } },
  { $sort: { n: -1 } }, { $limit: 3 }
]).forEach(r => print("  mois " + r._id + " : " + r.n + "  " + pct(r.n)));
c.aggregate([
  { $group: { _id: { $dateToString: { format: "%Y-%m-%d", date: "$date_operation" } }, n: { $sum: 1 } } },
  { $sort: { n: -1 } }, { $limit: 3 }
]).forEach(r => print("  jour " + r._id + " : " + r.n + "  " + pct(r.n)));
const moyJour = c.aggregate([
  { $group: { _id: { $dateToString: { format: "%Y-%m-%d", date: "$date_operation" } } } },
  { $count: "jours" }
]).toArray()[0].jours;
print("  jours avec des opérations : " + moyJour + ", soit " + Math.round(total / moyJour) + " opérations par jour en moyenne");
print("  -> une date croît toujours : avec une clé par intervalle, toutes les nouvelles");
print("     inscriptions vont dans le DERNIER morceau, donc sur un seul shard,");
print("     précisément le jour du pic (C4).");

// ---------------------------------------------------------------------
// Clé candidate 3 : id_etudiant
// ---------------------------------------------------------------------
print("\n=== 3. Clé id_etudiant : cardinalité et fréquence ===");
const parEtu = c.aggregate([
  { $group: { _id: "$id_etudiant", n: { $sum: 1 } } },
  { $group: { _id: null, etudiants: { $sum: 1 }, max: { $max: "$n" }, moy: { $avg: "$n" } } }
]).toArray()[0];
print("  étudiants distincts : " + parEtu.etudiants);
print("  inscriptions par étudiant : " + parEtu.moy.toFixed(1) + " en moyenne, " + parEtu.max
      + " au plus (" + (100 * parEtu.max / total).toFixed(3) + " % du total)");
print("  -> des milliers de valeurs, aucune trop fréquente : découpage possible à volonté.");

// Les parcours (opérations groupées) : un seul étudiant par id_groupe ?
const grp = c.aggregate([
  { $match: { id_groupe: { $exists: true } } },
  { $group: { _id: "$id_groupe", etudiants: { $addToSet: "$id_etudiant" }, sites: { $addToSet: "$id_site" } } },
  { $group: { _id: null, parcours: { $sum: 1 },
              multi_etudiants: { $sum: { $cond: [{ $gt: [{ $size: "$etudiants" }, 1] }, 1, 0] } },
              multi_sites:     { $sum: { $cond: [{ $gt: [{ $size: "$sites" }, 1] }, 1, 0] } } } }
]).toArray()[0];
print("  parcours : " + grp.parcours + ", dont " + grp.multi_sites + " sur plusieurs sites ; "
      + grp.multi_etudiants + " avec plusieurs étudiants");
print("  -> un parcours n'a qu'un étudiant : avec la clé id_etudiant, toutes ses inscriptions");
print("     sont sur le même shard, même quand il combine plusieurs sites.");

// ---------------------------------------------------------------------
// id_etudiant par intervalle ou haché ? Les écritures du pic par tranche d'id
// ---------------------------------------------------------------------
print("\n=== 4. id_etudiant par intervalle : qui écrit pendant le pic ? ===");
const bornes = c.aggregate([{ $group: { _id: null, min: { $min: "$id_etudiant" }, max: { $max: "$id_etudiant" } } }]).toArray()[0];
const tiers = Math.ceil((bornes.max - bornes.min + 1) / 3);
print("  ids de " + bornes.min + " à " + bornes.max + ", coupés en 3 tranches égales (une par shard)");
const pic = { date_operation: { $gte: ISODate("2026-09-01"), $lt: ISODate("2026-10-01") } };
const nPic = c.countDocuments(pic);
c.aggregate([
  { $match: pic },
  { $group: { _id: { $floor: { $divide: [{ $subtract: ["$id_etudiant", bornes.min] }, tiers] } }, n: { $sum: 1 } } },
  { $sort: { _id: 1 } }
]).forEach(r => print("  tranche " + (r._id + 1) + " : " + r.n + " inscriptions de septembre 2026  ("
                      + (100 * r.n / nPic).toFixed(1) + " %)"));
print("  -> à comparer avec le hachage, mesuré après le sharding (L6_sharding.js)");

// ---------------------------------------------------------------------
// Requêtes fréquentes de la plateforme
// ---------------------------------------------------------------------
print("\n=== 5. Requêtes fréquentes et clé qui les sert ===");
print("  - historique d'un étudiant (accueil, à chaque visite)  : filtre id_etudiant");
print("  - parcours d'un étudiant (opération groupée)           : filtre id_etudiant + id_groupe");
print("  - nouvelle inscription au pic de la rentrée            : écriture, doit se répartir");
print("  - tableau de bord par site (direction, rare)           : filtre id_site, toutes données");
