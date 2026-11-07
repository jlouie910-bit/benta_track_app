// ═══════════════════════════════════════════════════════════════
// product_catalog.dart — shared helpers for BentaTrack scanning
//  • loads the store's inventory
//  • remembers barcodes + AI names (aliases) on inventory items
//  • shared "Products" catalog (document id = barcode)
//  • fuzzy matching of AI names to your own items
//  • small dialogs used by NewSalesScreen and Inventory
// ═══════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

class ProductCatalog {
  ProductCatalog._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const Color _navy = Color(0xFF1E3A5F);

  static bool _validBarcode(String b) =>
      b.isNotEmpty && b.length <= 64 && !b.contains('/');

  static String nameOf(Map<String, dynamic> item) =>
      (item['itemName'] ?? '').toString().trim();

  // ── Inventory ────────────────────────────────────────────────
  /// All of this user's items. Each map also has '_docId'.
  static Future<List<Map<String, dynamic>>> loadInventory(String uid) async {
    final snap = await _db
        .collection('Inventory')
        .where('userId', isEqualTo: uid)
        .get();
    return snap.docs
        .map((d) => <String, dynamic>{'_docId': d.id, ...d.data()})
        .toList();
  }

  /// Names sent to the AI. Items with aliases look like
  /// "Lucky Me Chilimansi 60g (also seen as: lucky me pancit canton chilimansi)".
  static List<String> namesForAI(List<Map<String, dynamic>> items) {
    final out = <String>[];
    for (final it in items) {
      final name = nameOf(it);
      if (name.isEmpty) continue;
      final aliases = ((it['aliases'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      out.add(aliases.isEmpty
          ? name
          : '$name (also seen as: ${aliases.join(', ')})');
    }
    return out;
  }

  static Map<String, dynamic>? findByBarcode(
      List<Map<String, dynamic>> items, String barcode) {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    for (final it in items) {
      if ((it['barcode'] ?? '').toString().trim() == b) return it;
    }
    return null;
  }

  /// True when the scanned name equals the item's name or one of its aliases.
  static bool isExactMatch(Map<String, dynamic> item, String scan) {
    final q = scan.trim().toLowerCase();
    if (q.isEmpty) return false;
    if (nameOf(item).toLowerCase() == q) return true;
    final aliases = (item['aliases'] as List?) ?? const [];
    return aliases.any((a) => a.toString().toLowerCase() == q);
  }

  /// alias → exact → contains (longest name wins) → word overlap.
  /// Returns null when nothing is close enough (so the app asks instead of guessing).
  static Map<String, dynamic>? fuzzyMatch(
      String scan, List<Map<String, dynamic>> items) {
    final query = scan.trim().toLowerCase();
    if (query.isEmpty) return null;

    // 1. alias / exact
    for (final it in items) {
      if (isExactMatch(it, query)) return it;
    }

    // 2. contains (either direction), longest item name wins
    Map<String, dynamic>? best;
    var bestLen = 0;
    for (final it in items) {
      final n = nameOf(it).toLowerCase();
      if (n.length < 4) continue; // empty / tiny names match everything
      final hit = query.contains(n) || (query.length >= 4 && n.contains(query));
      if (hit && n.length > bestLen) {
        best = it;
        bestLen = n.length;
      }
    }
    if (best != null) return best;

    // 3. word overlap
    Set<String> words(String s) => s
        .split(RegExp(r'[^a-z0-9ñ]+'))
        .where((w) => w.length >= 3)
        .toSet();
    final qw = words(query);
    if (qw.isEmpty) return null;

    var bestScore = 0;
    for (final it in items) {
      final nw = words(nameOf(it).toLowerCase());
      if (nw.isEmpty) continue;
      final overlap = qw.intersection(nw).length;
      final enough =
          overlap >= 2 || (overlap == 1 && (qw.length == 1 || nw.length == 1));
      if (enough && overlap > bestScore) {
        bestScore = overlap;
        best = it;
      }
    }
    return best;
  }

  // ── Learning: aliases + barcodes ─────────────────────────────
  static Future<void> addAlias(String docId, String alias) async {
    final a = alias.trim().toLowerCase();
    if (a.isEmpty) return;
    try {
      await _db.collection('Inventory').doc(docId).update({
        'aliases': FieldValue.arrayUnion([a]),
      });
    } catch (e) {
      debugPrint('addAlias failed: $e');
    }
  }

  static Future<void> attachBarcode(String docId, String barcode) async {
    final b = barcode.trim();
    if (b.isEmpty) return;
    try {
      await _db.collection('Inventory').doc(docId).update({'barcode': b});
    } catch (e) {
      debugPrint('attachBarcode failed: $e');
    }
  }

  // ── Shared catalog (Products/{barcode}) ──────────────────────
  static Future<Map<String, dynamic>?> lookup(String barcode) async {
    if (!_validBarcode(barcode)) return null;
    try {
      final doc = await _db.collection('Products').doc(barcode).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('Catalog lookup failed: $e');
      return null;
    }
  }

  /// Call after the Add Item screen closes. If the user really saved an item
  /// with this barcode, its name + category are shared (no price, stock or cost).
  static Future<void> saveFromInventory(String uid, String barcode) async {
    if (!_validBarcode(barcode)) return;
    try {
      final inv = await _db
          .collection('Inventory')
          .where('userId', isEqualTo: uid)
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();
      if (inv.docs.isEmpty) return;

      final ref = _db.collection('Products').doc(barcode);
      if ((await ref.get()).exists) return; // never overwrite

      final d = inv.docs.first.data();
      final name = (d['itemName'] ?? '').toString().trim();
      if (name.isEmpty) return;

      await ref.set({
        'itemName': name,
        'category': (d['category'] ?? '').toString(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Catalog save failed: $e');
    }
  }

  // ── Dialogs ──────────────────────────────────────────────────

  /// "AI saw X, is it your item Y?"  true = yes, false = no, null = dismissed.
  static Future<bool?> confirmMatch(
      BuildContext context, String scanned, String matchedName) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Is this your item?',
              style: TextStyle(
                  color: isDark ? Colors.white : _navy,
                  fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Camera saw:',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(scanned,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Closest item in your inventory:',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(matchedName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _navy),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// Searchable list of the user's items. Returns the picked item or null.
  static Future<Map<String, dynamic>?> pickItem(
      BuildContext context, List<Map<String, dynamic>> items) {
    var q = '';
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final filtered = items
              .where((i) => nameOf(i).toLowerCase().contains(q))
              .toList();
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Choose your item',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(ctx).size.height * 0.5,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search item name...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onChanged: (v) => setS(() => q = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching items.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final it = filtered[i];
                              return ListTile(
                                dense: true,
                                title: Text(nameOf(it),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    'Stock: ${(it['stock'] as num?)?.toInt() ?? 0}  •  ₱${((it['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
                                onTap: () => Navigator.pop(ctx, it),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shown when a scan matches nothing. The user either links it to an item
  /// they already sell ('link') or adds a new item ('new'). Null = cancelled.
  static Future<({String action, String name})?> showUnknownDialog(
    BuildContext context, {
    String? barcode,
    String? aiName,
    String? suggestedName,
    bool fromCatalog = false,
  }) {
    final controller =
        TextEditingController(text: suggestedName ?? aiName ?? '');
    return showDialog<({String action, String name})>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            barcode != null ? 'New Barcode Detected' : 'New Product Detected',
            style: TextStyle(
                color: isDark ? Colors.white : _navy,
                fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (barcode != null)
                Text('Barcode: $barcode',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey)),
              if (fromCatalog)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Name found in the shared catalog',
                      style: TextStyle(color: Colors.green, fontSize: 12)),
                ),
              const SizedBox(height: 12),
              const Text('Item name:'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'e.g., Safeguard Soap 135g',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Already selling this item? Tap "Link to existing" so it is not added twice.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                  ctx, (action: 'link', name: controller.text.trim())),
              child: const Text('Link to existing'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _navy),
              onPressed: () => Navigator.pop(
                  ctx, (action: 'new', name: controller.text.trim())),
              child:
                  const Text('Add new', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}