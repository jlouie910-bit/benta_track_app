import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_items_screen.dart';
import 'Camera.dart';
import 'product_catalog.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  // Only two stock states are used now: In Stock and Low Stock
  static const List<String> _statusTabs = ['All Items', 'In Stock', 'Low Stock'];

  String _selectedStatusTab = 'All Items';
  String _selectedCategory = 'All Categories';

  // --- GMAIL-STYLE MULTI-SELECT STATE ---
  final Set<String> _selectedDocIds = {};
  bool get _isMultiSelecting => _selectedDocIds.isNotEmpty;

  // Theme Colors
  final Color fbDarkBg = const Color(0xFF18191A);
  final Color fbCardBg = const Color(0xFF242526);
  final Color fbTextGrey = const Color(0xFFB0B3B8);
  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color tealAccent = const Color(0xFF4FD1C5);

  // Default baseline sari-sari store categories
  final List<String> _defaultCategories = [
    'Canned Goods & Staples',
    'Snacks & Treats',
    'Beverages & Drinks',
    'Condiments & Sauces',
    'Personal Care & Hygiene',
    'Household & Cleaning Supplies',
    'Cigarettes & Tobacco',
  ];

  Stream<QuerySnapshot> _getInventoryStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('Inventory')
        .where('userId', isEqualTo: user.uid)
        .snapshots();
  }

  // Low Stock when the remaining stock would be sold out within this many days
  static const double _lowStockDays = 7.0;

  // Items with no sales yet are only flagged when almost gone
  static const int _noSalesMinUnits = 3;

  /// Status is based on how fast the item sells:
  /// days left = current stock / units sold per day.
  /// Slow sellers stay 'In Stock' even with few units left.
  /// Returns only 'Low Stock' or 'In Stock'.
  String _calculateDynamicStatus(Map<String, dynamic> data) {
    int currentStock = (data['stock'] as num?)?.toInt() ?? 0;
    if (currentStock <= 0) return 'Low Stock'; // sold out, needs restocking

    int totalSold = (data['totalSold'] as num?)?.toInt() ?? 0;
    Timestamp? createdAt = data['createdAt'] as Timestamp?;

    // No sales history yet: we can't measure speed, so only flag when
    // the item is almost gone.
    if (totalSold <= 0 || createdAt == null) {
      return currentStock <= _noSalesMinUnits ? 'Low Stock' : 'In Stock';
    }

    int daysActive = DateTime.now().difference(createdAt.toDate()).inDays;
    if (daysActive < 1) daysActive = 1;

    double salesVelocityPerDay = totalSold / daysActive;
    double estimatedDaysRemaining = currentStock / salesVelocityPerDay;

    return estimatedDaysRemaining <= _lowStockDays ? 'Low Stock' : 'In Stock';
  }

  // --- SECURE MPIN VERIFICATION FOR RESTOCK / EDIT ---
  Future<void> _verifyAndRestock(Map<String, dynamic> data, String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        _showSnackBar("User profile record not found.", isError: true);
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>?;
      final String? storedMpin = userData?['mpin'];

      if (storedMpin == null || storedMpin.isEmpty) {
        _showSnackBar("Please set up your MPIN in Store Settings first.", isError: true);
        return;
      }

      if (!mounted) return;

      final TextEditingController mpinInputController = TextEditingController();
      bool isVerified = false;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              "Security MPIN Required",
              style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Enter your 4-digit MPIN to authorize modifying this inventory item:"),
                const SizedBox(height: 15),
                TextField(
                  controller: mpinInputController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontSize: 24, letterSpacing: 10, color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.grey[200],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: navyBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (mpinInputController.text == storedMpin) {
                    isVerified = true;
                    Navigator.pop(context);
                  } else {
                    _showSnackBar("Incorrect MPIN", isError: true);
                  }
                },
                child: const Text("Verify", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );

      if (isVerified && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddItemScreen(
              initialData: data,
              documentId: docId,
            ),
          ),
        );
      }
    } catch (e) {
      _showSnackBar("Error verifying MPIN: $e", isError: true);
    }
  }

  // --- SECURE MPIN VERIFICATION & MULTI-DELETE ITEMS ---
  Future<void> _verifyAndBatchDelete() async {
    if (_selectedDocIds.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        _showSnackBar("User profile record not found.", isError: true);
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>?;
      final String? storedMpin = userData?['mpin'];

      if (storedMpin == null || storedMpin.isEmpty) {
        _showSnackBar("Please set up your MPIN in Store Settings first.", isError: true);
        return;
      }

      if (!mounted) return;

      final TextEditingController mpinInputController = TextEditingController();
      bool isVerified = false;
      int count = _selectedDocIds.length;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              "Authorize Deletion",
              style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Enter your 4-digit MPIN to delete $count selected item(s):"),
                const SizedBox(height: 15),
                TextField(
                  controller: mpinInputController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontSize: 24, letterSpacing: 10, color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.grey[200],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (mpinInputController.text == storedMpin) {
                    isVerified = true;
                    Navigator.pop(context);
                  } else {
                    _showSnackBar("Incorrect MPIN", isError: true);
                  }
                },
                child: const Text("Confirm Delete", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );

      if (isVerified && mounted) {
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (String docId in _selectedDocIds) {
          DocumentReference docRef = FirebaseFirestore.instance.collection('Inventory').doc(docId);
          batch.delete(docRef);
        }
        await batch.commit();

        setState(() {
          _selectedDocIds.clear();
          _selectedCategory = 'All Categories';
        });
        _showSnackBar("Selected items deleted successfully", isError: false);
      }
    } catch (e) {
      _showSnackBar("Error deleting items: $e", isError: true);
    }
  }

  // --- SECURE MPIN VERIFICATION & CONTINUOUS ADD MODE ---
  // [initialData] pre-fills the FIRST Add Item screen (used by "Scan to Add").
  Future<void> _verifyAndAddNew({Map<String, dynamic>? initialData}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        _showSnackBar("User profile record not found.", isError: true);
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>?;
      final String? storedMpin = userData?['mpin'];

      if (storedMpin == null || storedMpin.isEmpty) {
        _showSnackBar("Please set up your MPIN in Store Settings first.", isError: true);
        return;
      }

      if (!mounted) return;

      final TextEditingController mpinInputController = TextEditingController();
      bool isVerified = false;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              "Security MPIN Required",
              style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Enter your 4-digit MPIN to authorize adding new items:"),
                const SizedBox(height: 15),
                TextField(
                  controller: mpinInputController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontSize: 24, letterSpacing: 10, color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.grey[200],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: navyBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (mpinInputController.text == storedMpin) {
                    isVerified = true;
                    Navigator.pop(context);
                  } else {
                    _showSnackBar("Incorrect MPIN", isError: true);
                  }
                },
                child: const Text("Verify", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );

      if (isVerified && mounted) {
        bool addMore = true;
        bool first = true;
        while (addMore && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddItemScreen(initialData: first ? initialData : null),
            ),
          );

          // Scanned a barcode and really saved it? Share name + category in the catalog.
          final scannedBarcode = (initialData?['barcode'] ?? '').toString().trim();
          if (first && scannedBarcode.isNotEmpty) {
            await ProductCatalog.saveFromInventory(user.uid, scannedBarcode);
          }
          first = false;

          if (!mounted) break;

          addMore = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) {
                  final bool isDark = Theme.of(context).brightness == Brightness.dark;
                  return AlertDialog(
                    backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
                    title: Text("Add Another Item?", style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold)),
                    content: const Text("Would you like to add another item, or are you finished?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Done", style: TextStyle(color: Colors.grey)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: tealAccent),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Add Another", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  );
                },
              ) ??
              false;
        }
      }
    } catch (e) {
      _showSnackBar("Error verifying MPIN: $e", isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SCAN TO ADD
  //  • Item already in inventory  → opens Restock for it
  //  • Barcode known in catalog   → Add Item pre-filled with the shared name
  //  • New product                → Add Item pre-filled (or link to existing)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _scanToAdd() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    List<Map<String, dynamic>> items = [];
    try {
      items = await ProductCatalog.loadInventory(user.uid);
    } catch (_) {}
    if (!mounted) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(knownItems: ProductCatalog.namesForAI(items)),
      ),
    );
    if (result == null || !mounted) return;

    final bool isAi = result['source'] == 'ai';
    final String scan =
        ((isAi ? result['itemName'] : result['barcode']) ?? '').toString().trim();
    if (scan.isEmpty) return;

    // ── Is it already in the inventory? ────────────────────────
    Map<String, dynamic>? existing;
    if (isAi) {
      existing = ProductCatalog.fuzzyMatch(scan, items);
      if (existing != null && !ProductCatalog.isExactMatch(existing, scan)) {
        final ok = await ProductCatalog.confirmMatch(
            context, scan, ProductCatalog.nameOf(existing));
        if (!mounted) return;
        if (ok == null) return;
        if (ok == true) {
          await ProductCatalog.addAlias(existing['_docId'] as String, scan);
        } else {
          existing = null;
        }
      }
    } else {
      existing = ProductCatalog.findByBarcode(items, scan);
    }

    if (existing != null) {
      _showSnackBar('Already in inventory. Opening restock.');
      _openRestockFor(existing);
      return;
    }

    // ── Not found: catalog name (barcode only) ─────────────────
    String? suggested;
    bool fromCatalog = false;
    if (!isAi) {
      final cat = await ProductCatalog.lookup(scan);
      final n = (cat?['itemName'] ?? '').toString().trim();
      if (n.isNotEmpty) {
        suggested = n;
        fromCatalog = true;
      }
    }
    if (!mounted) return;

    final choice = await ProductCatalog.showUnknownDialog(
      context,
      barcode: isAi ? null : scan,
      aiName: isAi ? scan : null,
      suggestedName: suggested,
      fromCatalog: fromCatalog,
    );
    if (choice == null || !mounted) return;

    // ── Link to an item that already exists ────────────────────
    if (choice.action == 'link') {
      if (items.isEmpty) {
        _showSnackBar('No items in your inventory yet.', isError: true);
        return;
      }
      final picked = await ProductCatalog.pickItem(context, items);
      if (picked == null || !mounted) return;

      final id = picked['_docId'] as String;
      if (isAi) {
        await ProductCatalog.addAlias(id, scan);
      } else {
        await ProductCatalog.attachBarcode(id, scan);
        picked['barcode'] = scan;
      }
      _showSnackBar('Linked. Opening restock.');
      _openRestockFor(picked);
      return;
    }

    // ── Add as a new item ──────────────────────────────────────
    final name = choice.name.isNotEmpty ? choice.name : (isAi ? scan : 'New Item');
    final prefill = <String, dynamic>{
      'itemName': name,
      if (!isAi) 'barcode': scan,
    };

    final category = (result['category'] ?? '').toString();
    if (isAi && category.isNotEmpty) prefill['category'] = category;

    // The AI price is only a rough guess: the owner confirms it in the form.
    final price = double.tryParse(
        (result['estimatedPrice'] ?? '').toString().replaceAll(RegExp(r'[^0-9.]'), ''));
    if (isAi && price != null && price > 0) prefill['price'] = price;

    final photo = (result['imagePath'] ?? '').toString();
    if (isAi && photo.isNotEmpty) prefill['imagePath'] = photo;

    await _verifyAndAddNew(initialData: prefill);
  }

  void _openRestockFor(Map<String, dynamic> item) {
    final data = Map<String, dynamic>.from(item);
    final id = data.remove('_docId') as String;
    _verifyAndRestock(data, id);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : navyBlue),
    );
  }

  Widget _buildProductThumbnail(String? imagePath, Widget fallbackIcon) {
    if (imagePath == null || imagePath.isEmpty) {
      return fallbackIcon;
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imagePath,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallbackIcon,
        ),
      );
    }

    final file = File(imagePath);
    if (file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallbackIcon,
        ),
      );
    }

    return fallbackIcon;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Safety: if an old tab (e.g. 'Critical') is still selected, reset it
    if (!_statusTabs.contains(_selectedStatusTab)) {
      _selectedStatusTab = 'All Items';
    }

    return Scaffold(
      backgroundColor: isDark ? fbDarkBg : navyBlue,
      appBar: AppBar(
        title: Text(
          _isMultiSelecting ? "${_selectedDocIds.length} Selected" : "Inventory Stocks",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: navyBlue,
        elevation: 0,
        leading: _isMultiSelecting
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() => _selectedDocIds.clear()),
              )
            : null,
        actions: [
          if (_isMultiSelecting)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              tooltip: "Delete Selected",
              onPressed: _verifyAndBatchDelete,
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getInventoryStream(),
        builder: (context, snapshot) {
          Set<String> activeCategories = {'All Categories', ..._defaultCategories};
          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              var data = doc.data() as Map<String, dynamic>;
              String? cat = data['category'];
              if (cat != null && cat.isNotEmpty) {
                activeCategories.add(cat);
              }
            }
          }

          if (!activeCategories.contains(_selectedCategory)) {
            _selectedCategory = 'All Categories';
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: isDark ? fbCardBg : navyBlue,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusTabs.map((tab) {
                      bool isSelected = _selectedStatusTab == tab;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ChoiceChip(
                          label: Text(tab),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedStatusTab = tab),
                          selectedColor: tealAccent,
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.white.withValues(alpha: 0.1),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : (isDark ? fbTextGrey : Colors.black),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? fbCardBg : Colors.white,
                  boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5)],
                ),
                child: DropdownButtonFormField<String>(
                  dropdownColor: isDark ? fbCardBg : Colors.white,
                  value: _selectedCategory,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    labelText: "Filter by Category",
                    labelStyle: TextStyle(color: isDark ? tealAccent : navyBlue, fontSize: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: activeCategories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() => _selectedCategory = newValue);
                    }
                  },
                ),
              ),
              Expanded(
                child: Container(
                  color: isDark ? fbDarkBg : const Color(0xFFF0FAFC),
                  child: () {
                    if (snapshot.hasError) {
                      return Center(child: Text("Error fetching data: ${snapshot.error}", style: const TextStyle(color: Colors.redAccent)));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(child: Text("No items found", style: TextStyle(color: isDark ? fbTextGrey : Colors.grey)));
                    }

                    final docs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;

                      if (_selectedCategory != 'All Categories') {
                        if ((data['category'] ?? '') != _selectedCategory) {
                          return false;
                        }
                      }

                      if (_selectedStatusTab != 'All Items') {
                        String calculatedStatus = _calculateDynamicStatus(data);
                        if (calculatedStatus != _selectedStatusTab) {
                          return false;
                        }
                      }

                      return true;
                    }).toList();

                    if (docs.isEmpty) {
                      return Center(child: Text("No items match selected filters", style: TextStyle(color: isDark ? fbTextGrey : Colors.grey)));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(15, 15, 15, 150), // room for the two buttons
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        var doc = docs[index];
                        var data = doc.data() as Map<String, dynamic>;
                        bool isSelected = _selectedDocIds.contains(doc.id);

                        double price = (data['price'] as num?)?.toDouble() ?? 0.0;
                        double cost = (data['cost'] as num?)?.toDouble() ?? 0.0;
                        double margin = price - cost;
                        int currentStock = (data['stock'] as num?)?.toInt() ?? 0;
                        bool isOutOfStock = currentStock <= 0;
                        String? imagePath = data['imagePath'] ?? data['imageUrl'];

                        String effectiveStatus = _calculateDynamicStatus(data);
                        Widget statusIcon = _buildStatusIcon(effectiveStatus);

                        return GestureDetector(
                          onLongPress: () {
                            setState(() {
                              if (isSelected) {
                                _selectedDocIds.remove(doc.id);
                              } else {
                                _selectedDocIds.add(doc.id);
                              }
                            });
                          },
                          child: Card(
                            color: isSelected
                                ? (isDark ? Colors.teal.shade900.withValues(alpha: 0.4) : Colors.teal.shade50)
                                : (isDark ? fbCardBg : Colors.white),
                            margin: const EdgeInsets.only(bottom: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: isSelected
                                  ? BorderSide(color: tealAccent, width: 2)
                                  : BorderSide.none,
                            ),
                            child: Column(
                              children: [
                                Opacity(
                                  opacity: isOutOfStock ? 0.4 : 1.0,
                                  child: ListTile(
                                    leading: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isMultiSelecting)
                                          Checkbox(
                                            value: isSelected,
                                            activeColor: tealAccent,
                                            onChanged: (bool? value) {
                                              setState(() {
                                                if (value == true) {
                                                  _selectedDocIds.add(doc.id);
                                                } else {
                                                  _selectedDocIds.remove(doc.id);
                                                }
                                              });
                                            },
                                          ),
                                        _buildProductThumbnail(imagePath, statusIcon),
                                      ],
                                    ),
                                    title: Text(
                                      data['itemName'] ?? 'Product',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Stock: $currentStock | ${data['category'] ?? 'General'}", style: TextStyle(color: isDark ? fbTextGrey : Colors.black54)),
                                        Text("Barcode: ${data['barcode'] ?? 'N/A'}", style: TextStyle(color: isDark ? tealAccent : navyBlue, fontSize: 11, fontWeight: FontWeight.w500)),
                                        Text(
                                          "Capital/Unit: ₱${cost.toStringAsFixed(2)}",
                                          style: TextStyle(
                                            color: isDark ? fbTextGrey : Colors.black87,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text("₱${price.toStringAsFixed(2)}", style: TextStyle(color: isDark ? tealAccent : navyBlue, fontWeight: FontWeight.bold, fontSize: 16)),
                                        Text(
                                          "Profit: ${margin >= 0 ? '+' : ''}₱${margin.toStringAsFixed(2)}",
                                          style: TextStyle(
                                            color: margin >= 0 ? Colors.green : Colors.redAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 12, bottom: 12, left: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => _verifyAndRestock(data, doc.id),
                                        icon: const Icon(Icons.add_business, size: 16, color: Colors.white),
                                        label: const Text("RESTOCK", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: tealAccent,
                                          elevation: 2,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }(),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'scanToAdd',
            onPressed: _scanToAdd,
            label: const Text("Scan to Add", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            icon: const Icon(Icons.camera_alt, color: Colors.white),
            backgroundColor: navyBlue,
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'addNew',
            onPressed: () => _verifyAndAddNew(),
            label: const Text("Add New", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            icon: const Icon(Icons.add, color: Colors.white),
            backgroundColor: tealAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    Color color = status == 'Low Stock' ? Colors.orange : Colors.green;
    return CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(Icons.inventory_2, color: color, size: 20));
  }
}