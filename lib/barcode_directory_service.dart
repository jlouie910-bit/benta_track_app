
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Result returned by [BarcodeDirectoryService.lookup].
class BarcodeDirectoryResult {
  final String itemName;
  final String category;

  const BarcodeDirectoryResult({
    required this.itemName,
    required this.category,
  });
}

class BarcodeDirectoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'barcodeDirectory';

  // Must match the rules: itemName and category are limited to 100 characters.
  static const int _maxLen = 100;

  // Barcode document IDs must match the rules: 6-20 letters, digits or dashes.
  static final RegExp _barcodeRe = RegExp(r'^[A-Za-z0-9\-]{6,20}$');

  // ── In-memory cache so repeated scans of the same barcode
  //    don't hit Firestore every time (cleared when app restarts).
  //    Only FOUND barcodes are cached, so a barcode another user adds
  //    later is picked up on the next scan.
  static final Map<String, BarcodeDirectoryResult> _cache = {};

  static String _clip(String s) {
    final t = s.trim();
    return t.length > _maxLen ? t.substring(0, _maxLen) : t;
  }

  // ─────────────────────────────────────────────────────────────
  // LOOKUP
  // Returns the globally known name + category for [barcode],
  // or null if nobody has contributed it yet.
  // ─────────────────────────────────────────────────────────────
  static Future<BarcodeDirectoryResult?> lookup(String barcode) async {
    final key = barcode.trim();
    if (key.isEmpty) return null;

    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final doc = await _db.collection(_collection).doc(key).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final name = (data['itemName'] as String? ?? '').trim();
      final cat = (data['category'] as String? ?? '').trim();

      if (name.isEmpty) return null;

      final result = BarcodeDirectoryResult(
        itemName: name,
        category: cat.isNotEmpty ? cat : 'Canned Goods & Staples',
      );
      _cache[key] = result;
      return result;
    } catch (e) {
      debugPrint('BarcodeDirectory.lookup error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CONTRIBUTE
  // Called after a user saves an inventory item with a barcode.
  // • New barcode      → creates the document (confirmedBy = [me]).
  // • Existing barcode → adds one confirmation, but only once per user.
  //   It never overwrites the original itemName/category, so one user
  //   cannot pollute the data for everyone else.
  // ─────────────────────────────────────────────────────────────
  static Future<void> contribute({
    required String barcode,
    required String itemName,
    required String category,
  }) async {
    final key = barcode.trim();
    final name = _clip(itemName);
    final cat = _clip(category);
    if (key.isEmpty || name.isEmpty) return;

    // Only real barcodes (6-20 letters/digits/dashes). Rejects AI-returned
    // product names that were routed here by mistake.
    if (!_barcodeRe.hasMatch(key)) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final ref = _db.collection(_collection).doc(key);
      final snap = await ref.get();

      if (!snap.exists) {
        // First contributor — create the document.
        await ref.set({
          'itemName': name,
          'category': cat,
          'contributedBy': uid,
          'contributedAt': FieldValue.serverTimestamp(),
          'confirmCount': 1,
          'confirmedBy': [uid],
          'lastConfirmedAt': FieldValue.serverTimestamp(),
        });
        _cache[key] = BarcodeDirectoryResult(itemName: name, category: cat);
        debugPrint('BarcodeDirectory: contributed new barcode $key → $name');
        return;
      }

      // Already exists. Documents created before "confirmedBy" existed
      // only know their original contributor.
      final data = snap.data() ?? {};
      final confirmedBy = (data['confirmedBy'] as List?)
              ?.whereType<String>()
              .toList() ??
          [if (data['contributedBy'] is String) data['contributedBy'] as String];

      if (confirmedBy.contains(uid)) {
        // This user already confirmed (or created) it: nothing to add.
        return;
      }

      await ref.update({
        'confirmCount': FieldValue.increment(1),
        'confirmedBy': FieldValue.arrayUnion([uid]),
        'lastConfirmedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('BarcodeDirectory: confirmed barcode $key (count +1)');
    } catch (e) {
      // Non-fatal: contribution failure should never block the user.
      debugPrint('BarcodeDirectory.contribute error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CLEAR CACHE (call if you need a fresh lookup, e.g. after edit)
  // ─────────────────────────────────────────────────────────────
  static void clearCache([String? barcode]) {
    if (barcode != null) {
      _cache.remove(barcode.trim());
    } else {
      _cache.clear();
    }
  }
}