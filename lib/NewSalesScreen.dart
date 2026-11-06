import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Camera.dart';
import 'add_items_screen.dart';

class NewSalesScreen extends StatefulWidget {
  const NewSalesScreen({super.key});

  @override
  State<NewSalesScreen> createState() => _NewSalesScreenState();
}

class _NewSalesScreenState extends State<NewSalesScreen> {
  final Color navyBlue = const Color(0xFF1E3A5F);
  final User? user = FirebaseAuth.instance.currentUser;

  // Cart item schema: { id, name, price, cost, quantity, maxStock, isSellingAsPack, piecesPerPack }
  final List<Map<String, dynamic>> _cartItems = [];
  double _totalAmount = 0.0;

  // Standard Sari-Sari Store Categories
  final List<String> _standardCategories = [
    'Canned Goods & Staples',
    'Snacks & Treats',
    'Beverages & Drinks',
    'Condiments & Sauces',
    'Personal Care & Hygiene',
    'Household & Cleaning Supplies',
    'Cigarettes & Tobacco',
  ];

  void _calculateTotal() {
    double total = 0;
    for (var item in _cartItems) {
      bool asPack = item['isSellingAsPack'] ?? false;
      int pieces = item['piecesPerPack'] ?? 1;
      double piecePrice = item['price'] ?? 0.0;
      double effectivePrice = asPack ? (piecePrice * pieces) : piecePrice;
      total += (effectivePrice * item['quantity']);
    }
    setState(() => _totalAmount = total);
  }

  void _addItemToCart({
    required String id,
    required String name,
    required double piecePrice,
    required double pieceCost,
    required int stock,
    required int quantityToAdd,
    required int piecesPerPack,
    bool isSellingAsPack = false,
  }) {
    if (stock <= 0 || quantityToAdd <= 0) return;

    setState(() {
      int index = _cartItems.indexWhere((item) => item['id'] == id && item['isSellingAsPack'] == isSellingAsPack);

      int requiredStockUnits = isSellingAsPack ? (quantityToAdd * piecesPerPack) : quantityToAdd;

      if (index != -1) {
        int existingQty = _cartItems[index]['quantity'];
        int newQty = existingQty + quantityToAdd;
        int requiredNewUnits = isSellingAsPack ? (newQty * piecesPerPack) : newQty;

        if (requiredNewUnits <= stock) {
          _cartItems[index]['quantity'] = newQty;
        } else {
          _cartItems[index]['quantity'] = isSellingAsPack ? (stock ~/ piecesPerPack) : stock;
        }
      } else {
        if (requiredStockUnits <= stock) {
          _cartItems.add({
            'id': id,
            'name': name,
            'price': piecePrice,
            'cost': pieceCost,
            'quantity': quantityToAdd,
            'maxStock': stock,
            'piecesPerPack': piecesPerPack,
            'isSellingAsPack': isSellingAsPack,
          });
        } else {
          int maxAllowed = isSellingAsPack ? (stock ~/ piecesPerPack) : stock;
          if (maxAllowed > 0) {
            _cartItems.add({
              'id': id,
              'name': name,
              'price': piecePrice,
              'cost': pieceCost,
              'quantity': maxAllowed,
              'maxStock': stock,
              'piecesPerPack': piecesPerPack,
              'isSellingAsPack': isSellingAsPack,
            });
          }
        }
      }
      _calculateTotal();
    });
  }

  Future<void> _verifyAndNavigateToAddItemWithData(Map<String, dynamic> initialData) async {
    if (user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user!.uid)
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
                const Text("Enter your 4-digit MPIN to authorize adding this product:"),
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
              initialData: initialData,
            ),
          ),
        );
      }
    } catch (e) {
      _showSnackBar("Error verifying MPIN: $e", isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : navyBlue),
    );
  }

  void _showEditQuantityDialog(StateSetter setModalState, String docId, int currentQty, int maxLimit, Map<String, Map<String, dynamic>> tempSelections) {
    final TextEditingController qtyController = TextEditingController(text: currentQty.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Enter Quantity", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: qtyController,
          keyboardType: TextInputType.number,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: "Enter qty",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: navyBlue),
            onPressed: () {
              int? parsed = int.tryParse(qtyController.text);
              if (parsed != null && parsed > 0) {
                if (parsed <= maxLimit) {
                  setModalState(() {
                    tempSelections[docId]!['qty'] = parsed;
                  });
                } else {
                  setModalState(() {
                    tempSelections[docId]!['qty'] = maxLimit;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Quantity adjusted to maximum available stock!")),
                  );
                }
              }
              Navigator.pop(context);
            },
            child: const Text("Set", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openMultiSelectSearchModal() async {
    if (user == null) return;

    final Map<String, Map<String, dynamic>> tempSelections = {};
    String searchQuery = "";
    String selectedCategory = "All Categories";

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Search & Select Items", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.60,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Search item name or barcode...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val.trim().toLowerCase();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('Inventory')
                        .where('userId', isEqualTo: user?.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      Set<String> categories = {"All Categories"};
                      categories.addAll(_standardCategories);

                      if (snapshot.hasData) {
                        for (var doc in snapshot.data!.docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          String? cat = data['category'];
                          if (cat != null && cat.isNotEmpty) {
                            categories.add(cat);
                          }
                        }
                      }

                      if (!categories.contains(selectedCategory)) {
                        selectedCategory = "All Categories";
                      }

                      return DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: InputDecoration(
                          labelText: "Filter Category",
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: categories.map((cat) {
                          return DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedCategory = val;
                            });
                          }
                        },
                      );
                    },
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('Inventory')
                          .where('userId', isEqualTo: user?.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text("No items available."));
                        }

                        final docs = snapshot.data!.docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final itemName = (data['itemName'] ?? '').toString().toLowerCase();
                          final barcode = (data['barcode'] ?? '').toString().toLowerCase();
                          final category = data['category'] ?? 'Others';

                          if (selectedCategory != "All Categories" && category != selectedCategory) {
                            return false;
                          }

                          if (searchQuery.isNotEmpty) {
                            return itemName.contains(searchQuery) || barcode.contains(searchQuery);
                          }
                          return true;
                        }).toList();

                        if (docs.isEmpty) {
                          return const Center(child: Text("No matching items found."));
                        }

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final docId = doc.id;
                            final itemName = data['itemName'] ?? 'Unknown Item';
                            final price = (data['price'] as num?)?.toDouble() ?? 0.0;
                            final stock = (data['stock'] as num?)?.toInt() ?? 0;
                            final piecesPerPack = (data['piecesPerPack'] as num?)?.toInt() ?? 1;
                            bool hasPackOption = piecesPerPack > 1;

                            bool isSelected = tempSelections.containsKey(docId);
                            int qty = isSelected ? tempSelections[docId]!['qty'] : 1;
                            bool isPackMode = isSelected ? tempSelections[docId]!['isPack'] : false;

                            double displayPrice = isPackMode ? (price * piecesPerPack) : price;
                            int maxLimit = isPackMode ? (stock ~/ piecesPerPack) : stock;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        ),
                                        Text("Stock: $stock", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text("₱${displayPrice.toStringAsFixed(2)} ${isPackMode ? '(Pack)' : '(Piece)'}",
                                      style: TextStyle(color: navyBlue, fontWeight: FontWeight.w600, fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: hasPackOption
                                              ? ChoiceChip(
                                                  label: Text(
                                                    isPackMode ? "Pack ($piecesPerPack pcs)" : "Piece",
                                                    style: const TextStyle(fontSize: 10),
                                                  ),
                                                  selected: isPackMode,
                                                  selectedColor: Colors.teal.shade100,
                                                  onSelected: (val) {
                                                    setModalState(() {
                                                      if (isSelected) {
                                                        tempSelections[docId]!['isPack'] = val;
                                                      } else {
                                                        tempSelections[docId] = {'qty': 1, 'isPack': val};
                                                      }
                                                    });
                                                  },
                                                )
                                              : const Text("Piece only", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isSelected) ...[
                                              IconButton(
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                icon: const Icon(Icons.remove, size: 16),
                                                onPressed: () {
                                                  setModalState(() {
                                                    if (qty > 1) {
                                                      tempSelections[docId]!['qty'] = qty - 1;
                                                    } else {
                                                      tempSelections.remove(docId);
                                                    }
                                                  });
                                                },
                                              ),
                                              GestureDetector(
                                                onTap: () => _showEditQuantityDialog(setModalState, docId, qty, maxLimit, tempSelections),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: navyBlue.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: navyBlue.withValues(alpha: 0.3)),
                                                  ),
                                                  child: Text(
                                                    "$qty",
                                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: navyBlue),
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                icon: const Icon(Icons.add, size: 16),
                                                onPressed: () {
                                                  setModalState(() {
                                                    if (qty < maxLimit) {
                                                      tempSelections[docId]!['qty'] = qty + 1;
                                                    } else {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text("Cannot exceed available stock!")),
                                                      );
                                                    }
                                                  });
                                                },
                                              ),
                                            ],
                                            Checkbox(
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              activeColor: navyBlue,
                                              value: isSelected,
                                              onChanged: (bool? value) {
                                                setModalState(() {
                                                  if (value == true) {
                                                    tempSelections[docId] = {'qty': 1, 'isPack': false};
                                                  } else {
                                                    tempSelections.remove(docId);
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: navyBlue),
                onPressed: () async {
                  if (tempSelections.isEmpty) {
                    Navigator.pop(context);
                    return;
                  }

                  for (var entry in tempSelections.entries) {
                    final docRef = await FirebaseFirestore.instance.collection('Inventory').doc(entry.key).get();
                    if (docRef.exists) {
                      final data = docRef.data() as Map<String, dynamic>;
                      _addItemToCart(
                        id: entry.key,
                        name: data['itemName'] ?? 'Unknown',
                        piecePrice: (data['price'] as num?)?.toDouble() ?? 0.0,
                        pieceCost: (data['cost'] as num?)?.toDouble() ?? 0.0,
                        stock: (data['stock'] as num?)?.toInt() ?? 0,
                        quantityToAdd: entry.value['qty'],
                        piecesPerPack: (data['piecesPerPack'] as num?)?.toInt() ?? 1,
                        isSellingAsPack: entry.value['isPack'],
                      );
                    }
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Selected items added to cart!"), backgroundColor: Colors.green),
                    );
                  }
                },
                child: const Text("Select & Add", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── UPGRADED: handles both barcode scans AND AI vision results ──
  void _openCameraScanner() async {
    final scanResult = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (scanResult == null || scanResult.trim().isEmpty || !mounted) return;

    final firestore = FirebaseFirestore.instance;

    // ── Step 1: Try barcode match (exact, global) ──────────────
    var querySnapshot = await firestore
    .collection('Inventory')
    .where('userId', isEqualTo: user?.uid)
    .where('barcode', isEqualTo: scanResult)
    .limit(1)
    .get();

    if (querySnapshot.docs.isNotEmpty) {
      final doc = querySnapshot.docs.first;
      final data = doc.data();
      _addItemToCart(
        id: doc.id,
        name: data['itemName'] ?? 'Unknown Item',
        piecePrice: (data['price'] as num?)?.toDouble() ?? 0.0,
        pieceCost: (data['cost'] as num?)?.toDouble() ?? 0.0,
        stock: (data['stock'] as num?)?.toInt() ?? 0,
        quantityToAdd: 1,
        piecesPerPack: (data['piecesPerPack'] as num?)?.toInt() ?? 1,
        isSellingAsPack: false,
      );
      _showSnackBar("Auto-filled: ${data['itemName']}");
      return;
    }

    // ── Step 2: Fetch user's inventory for fuzzy name match ────
    // (handles AI vision results like "Marlboro Red Softpack" → "Marlboro Red")
    final allDocsSnap = await firestore
        .collection('Inventory')
        .where('userId', isEqualTo: user?.uid)
        .get();

    if (allDocsSnap.docs.isEmpty) {
      _handleUnknownScan(scanResult);
      return;
    }

    final allItems = allDocsSnap.docs
        .map((doc) => <String, dynamic>{'_docId': doc.id, ...doc.data()})
        .toList();

    final matched = _fuzzyMatchItem(scanResult, allItems);

    if (matched != null) {
      _addItemToCart(
        id: matched['_docId'] as String,
        name: matched['itemName'] ?? 'Unknown Item',
        piecePrice: (matched['price'] as num?)?.toDouble() ?? 0.0,
        pieceCost: (matched['cost'] as num?)?.toDouble() ?? 0.0,
        stock: (matched['stock'] as num?)?.toInt() ?? 0,
        quantityToAdd: 1,
        piecesPerPack: (matched['piecesPerPack'] as num?)?.toInt() ?? 1,
        isSellingAsPack: false,
      );
      _showSnackBar("Auto-filled: ${matched['itemName']}");
      return;
    }

    // ── Step 3: Nothing matched — prompt user ──────────────────
    _handleUnknownScan(scanResult);
  }

  /// Fuzzy match: exact → prefix → contains → word overlap.
  /// Returns the best matching inventory item or null.
  Map<String, dynamic>? _fuzzyMatchItem(
    String scanResult,
    List<Map<String, dynamic>> items,
  ) {
    final query = scanResult.trim().toLowerCase();
    String nameOf(Map<String, dynamic> item) =>
        (item['itemName'] as String? ?? '').toLowerCase();

    // 1. Exact
    for (final item in items) {
      if (nameOf(item) == query) return item;
    }
    // 2. Prefix (either direction)
    for (final item in items) {
      final n = nameOf(item);
      if (n.startsWith(query) || query.startsWith(n)) return item;
    }
    // 3. Contains (either direction)
    for (final item in items) {
      final n = nameOf(item);
      if (n.contains(query) || query.contains(n)) return item;
    }
    // 4. Word overlap — at least 1 significant word (≥3 chars)
    final queryWords = query
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
    if (queryWords.isEmpty) return null;

    Map<String, dynamic>? best;
    int bestScore = 0;
    for (final item in items) {
      final nameWords = nameOf(item)
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 3)
          .toSet();
      final overlap = queryWords.intersection(nameWords).length;
      if (overlap > bestScore) {
        bestScore = overlap;
        best = item;
      }
    }
    return bestScore >= 1 ? best : null;
  }

  /// Called when scan result doesn't match anything in inventory.
  void _handleUnknownScan(String scanResult) {
    final bool isNumericBarcode = RegExp(r'^\d+$').hasMatch(scanResult);
    if (isNumericBarcode) {
      _promptForUnknownBarcodeName(scanResult);
    } else {
      // AI returned a name we don't have — offer to add it as a new item
      _verifyAndNavigateToAddItemWithData({
        'itemName': scanResult,
        'barcode': '',
      });
    }
  }

  void _promptForUnknownBarcodeName(String scannedBarcode) {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "New Barcode Detected",
            style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Barcode: $scannedBarcode", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 12),
              const Text("Enter the name for this item:"),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "e.g., Safeguard Soap 135g",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: navyBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                String enteredName = nameController.text.trim();
                Navigator.pop(context);
                _verifyAndNavigateToAddItemWithData({
                  'barcode': scannedBarcode,
                  'itemName': enteredName.isNotEmpty ? enteredName : 'New Item',
                });
              },
              child: const Text("Continue", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showReceiptOverview() {
    if (_cartItems.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text("Receipt Overview", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(height: 30),
            Expanded(
              child: ListView.builder(
                itemCount: _cartItems.length,
                itemBuilder: (context, i) {
                  final item = _cartItems[i];
                  bool isPack = item['isSellingAsPack'] ?? false;
                  int pieces = item['piecesPerPack'] ?? 1;
                  double basePrice = item['price'] ?? 0.0;
                  double linePrice = isPack ? (basePrice * pieces * item['quantity']) : (basePrice * item['quantity']);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${item['quantity']}x ${item['name']} ${isPack ? '(Pack)' : '(Piece)'}"),
                        Text("₱${linePrice.toStringAsFixed(2)}"),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Payable", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text("₱${_totalAmount.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: navyBlue)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _processCheckout();
                },
                style: ElevatedButton.styleFrom(backgroundColor: navyBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: const Text("CONFIRM AND PAY", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Back to Cart", style: TextStyle(color: Colors.grey))),
          ],
        ),
      ),
    );
  }

  void _processCheckout() async {
    if (_cartItems.isEmpty || user == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final WriteBatch batch = firestore.batch();
      double totalProfit = 0.0;

      for (var item in _cartItems) {
        DocumentReference invRef = firestore.collection('Inventory').doc(item['id']);
        DocumentSnapshot doc = await invRef.get();

        if (!doc.exists) throw "Item '${item['name']}' not found.";

        int currentStock = (doc['stock'] as num).toInt();
        int currentTotalSold = (doc.data() as Map<String, dynamic>).containsKey('totalSold')
            ? (doc['totalSold'] as num).toInt()
            : 0;

        int requestedQty = (item['quantity'] as num).toInt();
        bool isPack = item['isSellingAsPack'] ?? false;
        int piecesPerPack = item['piecesPerPack'] ?? 1;

        int unitsToSubtract = isPack ? (requestedQty * piecesPerPack) : requestedQty;
        int newStock = currentStock - unitsToSubtract;
        int newTotalSold = currentTotalSold + unitsToSubtract;

        double piecePrice = (item['price'] as num).toDouble();
        double pieceCost = (item['cost'] as num).toDouble();

        double itemProfit = isPack
            ? ((piecePrice * piecesPerPack) - (pieceCost * piecesPerPack)) * requestedQty
            : (piecePrice - pieceCost) * requestedQty;

        totalProfit += itemProfit;

        int estimatedTotalVolume = currentStock + currentTotalSold;
        double percentageSold = estimatedTotalVolume > 0 ? (newTotalSold / estimatedTotalVolume) : 0.0;

        String newStatus = "In Stock";
        if (newStock <= 0) {
          newStatus = "Out of Stock";
        } else if (percentageSold >= 0.80 || newStock <= 5) {
          newStatus = "Critical";
        } else if (percentageSold >= 0.60 || newStock <= 10) {
          newStatus = "Low Stock";
        }

        batch.update(invRef, {
          'stock': newStock < 0 ? 0 : newStock,
          'totalSold': newTotalSold,
          'status': newStatus,
        });
      }

      final cleanCartItems = _cartItems.map((item) => {
        'id': item['id'],
        'name': "${item['name']} ${item['isSellingAsPack'] == true ? '(Pack)' : '(Piece)'}",
        'price': item['isSellingAsPack'] == true ? (item['price'] * item['piecesPerPack']) : item['price'],
        'cost': item['isSellingAsPack'] == true ? (item['cost'] * item['piecesPerPack']) : item['cost'],
        'quantity': item['quantity'],
      }).toList();

      DocumentReference transRef = firestore.collection('transactions').doc();
      batch.set(transRef, {
        'userId': user!.uid,
        'items': cleanCartItems,
        'totalAmount': _totalAmount,
        'profit': totalProfit,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // --- DAILY METRICS AGGREGATION ---
      String todayDateKey = DateTime.now().toIso8601String().substring(0, 10);
      DocumentReference dailyRef = firestore
          .collection('Users')
          .doc(user!.uid)
          .collection('DailyMetrics')
          .doc(todayDateKey);

      batch.set(dailyRef, {
        'totalSales': FieldValue.increment(_totalAmount),
        'totalProfit': FieldValue.increment(totalProfit),
        'transactionCount': FieldValue.increment(1),
        'date': todayDateKey,
      }, SetOptions(merge: true));

      await batch.commit();

      navigator.pop();
      setState(() {
        _cartItems.clear();
        _totalAmount = 0.0;
      });

      messenger.showSnackBar(const SnackBar(content: Text("Checkout Successful!"), backgroundColor: Colors.green));
    } catch (e) {
      if (navigator.canPop()) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18191A) : Colors.grey[100],
      appBar: AppBar(
        title: const Text("Counter", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildSearchTriggerBar(isDark),
          Expanded(
            child: _cartItems.isEmpty
                ? const Center(child: Text("No items in cart"))
                : ListView.builder(
              itemCount: _cartItems.length,
              itemBuilder: (context, index) => _buildCartItem(index, isDark),
            ),
          ),
          _buildCheckoutSection(isDark),
        ],
      ),
    );
  }

  Widget _buildSearchTriggerBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: InkWell(
        onTap: _openMultiSelectSearchModal,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF242526) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.search, color: Colors.grey),
              SizedBox(width: 12),
              Text("Search items to select...", style: TextStyle(color: Colors.grey, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartItem(int index, bool isDark) {
    final item = _cartItems[index];
    bool isPack = item['isSellingAsPack'] ?? false;
    int pieces = item['piecesPerPack'] ?? 1;
    double basePrice = item['price'] ?? 0.0;
    double displayPrice = isPack ? (basePrice * pieces) : basePrice;
    bool hasPackOption = pieces > 1;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      color: isDark ? const Color(0xFF242526) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text("${item['name']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Text("₱${displayPrice.toStringAsFixed(2)} each", style: TextStyle(color: navyBlue, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (hasPackOption)
                  ChoiceChip(
                    label: Text(isPack ? "Selling: Pack ($pieces pcs)" : "Selling: Piece"),
                    selected: isPack,
                    selectedColor: Colors.teal.shade100,
                    onSelected: (bool selected) {
                      setState(() {
                        item['isSellingAsPack'] = selected;
                        item['quantity'] = 1;
                        _calculateTotal();
                      });
                    },
                  )
                else
                  const Text("Sold by Piece only", style: TextStyle(fontSize: 12, color: Colors.grey)),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 22),
                      onPressed: () => setState(() {
                        if (item['quantity'] > 1) {
                          item['quantity']--;
                        } else {
                          _cartItems.removeAt(index);
                        }
                        _calculateTotal();
                      }),
                    ),
                    Text("${item['quantity']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 22),
                      onPressed: () => setState(() {
                        int maxLimit = isPack ? (item['maxStock'] ~/ pieces) : item['maxStock'];
                        if (item['quantity'] < maxLimit) {
                          item['quantity']++;
                          _calculateTotal();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot exceed available stock!")));
                        }
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openCameraScanner,
              icon: const Icon(Icons.camera_alt),
              label: const Text("SCAN ITEM (BARCODE / AI VISION)"),
              style: OutlinedButton.styleFrom(
                foregroundColor: navyBlue,
                side: BorderSide(color: navyBlue),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Payable:", style: TextStyle(fontSize: 18)),
              Text("₱${_totalAmount.toStringAsFixed(2)}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: navyBlue)),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _cartItems.isEmpty ? null : _showReceiptOverview,
              style: ElevatedButton.styleFrom(
                backgroundColor: navyBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("REVIEW RECEIPT"),
            ),
          ),
        ],
      ),
    );
  }
}