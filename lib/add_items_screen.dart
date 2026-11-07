import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Camera.dart'; // Ensure this points to your camera scanner file
import 'barcode_directory_service.dart';

class AddItemScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final String? documentId;

  const AddItemScreen({super.key, this.initialData, this.documentId});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _packCostController = TextEditingController(); 
  final TextEditingController _unitCostController = TextEditingController(); 
  final TextEditingController _piecesPerPackController = TextEditingController(text: '20'); 
  final TextEditingController _sellingPriceController = TextEditingController();
  final TextEditingController _customCategoryController = TextEditingController();

  // Authentic Filipino Sari-Sari Store Categories including "Others"
  final List<String> _categories = [
    'Canned Goods & Staples',
    'Snacks & Treats',
    'Beverages & Drinks',
    'Condiments & Sauces',
    'Personal Care & Hygiene',
    'Household & Cleaning Supplies',
    'Cigarettes & Tobacco',
    'Others',
  ];

  String _selectedCategory = 'Canned Goods & Staples';
  bool _isTingiMode = true; 
  String? _imagePath;
  bool _isLoading = false;

  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color tealAccent = const Color(0xFF4FD1C5);
  final Color fbCardBg = const Color(0xFF242526);

  // Helper to give smart product examples based on selected category
  String _getCategoryHint() {
    switch (_selectedCategory) {
      case 'Canned Goods & Staples':
        return "e.g., Lucky Me Pancit Canton, Argentina Corned Beef";
      case 'Snacks & Treats':
        return "e.g., Piattos Cheese, Nova, Chippy, Cloud 9";
      case 'Beverages & Drinks':
        return "e.g., Coca-Cola 8oz, Cobra Energy Drink, Wilkins Water";
      case 'Condiments & Sauces':
        return "e.g., Datu Puti Soy Sauce, Silver Swan Vinegar";
      case 'Personal Care & Hygiene':
        return "e.g., Rejoice Shampoo Sachet, Safeguard Soap";
      case 'Household & Cleaning Supplies':
        return "e.g., Surf Powder, Joy Dishwashing Liquid";
      case 'Cigarettes & Tobacco':
        return "e.g., Marlboro Red (Per Stick), Mighty Green";
      default:
        return "e.g., Custom Product Name";
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final data = widget.initialData!;
      
      _itemNameController.text = data['itemName'] ?? ''; 
      _barcodeController.text = data['barcode'] ?? '';
      
      int pieces = (data['piecesPerPack'] ?? 1).toInt();
      _isTingiMode = pieces > 1;

      int rawStock = (data['stock'] ?? 0).toInt();
      if (_isTingiMode && pieces > 0) {
        _stockController.text = (rawStock ~/ pieces).toString();
      } else {
        _stockController.text = rawStock.toString();
      }

      _piecesPerPackController.text = pieces.toString();
      _sellingPriceController.text = (data['price'] ?? '').toString();
      
      String loadedCategory = data['category'] ?? 'Canned Goods & Staples';
      if (_categories.contains(loadedCategory)) {
        _selectedCategory = loadedCategory;
      } else {
        _selectedCategory = 'Others';
        _customCategoryController.text = loadedCategory;
      }

      _imagePath = data['imagePath'] ?? data['imageUrl'];

      if (_isTingiMode) {
        // Fallback calculation if totalPackCost wasn't stored explicitly
        double packCostVal = data['totalPackCost'] ?? ((data['cost'] ?? 0.0) * pieces);
        _packCostController.text = packCostVal > 0 ? packCostVal.toString() : '';
      } else {
        double unitCostVal = data['cost'] ?? 0.0;
        _unitCostController.text = unitCostVal > 0 ? unitCostVal.toString() : '';
      }
    }
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    _packCostController.dispose();
    _unitCostController.dispose();
    _piecesPerPackController.dispose();
    _sellingPriceController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _handleCategorySelection(String? category) async {
    if (category == 'Others') {
      String? customVal = await showDialog<String>(
        context: context,
        builder: (context) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? fbCardBg : Colors.white,
            title: Text("Custom Category", style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold)),
            content: TextField(
              controller: _customCategoryController,
              autofocus: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "e.g., Hardware, Pets",
                hintStyle: const TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: tealAccent)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: tealAccent, width: 2)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: tealAccent),
                onPressed: () => Navigator.pop(context, _customCategoryController.text.trim()),
                child: const Text("Save", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );

      if (customVal != null && customVal.isNotEmpty) {
        setState(() {
          _selectedCategory = customVal;
        });
      }
    } else if (category != null) {
      setState(() {
        _selectedCategory = category;
        _customCategoryController.clear();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // SCAN + AUTO-FILL
  // Order of lookup for a scanned barcode:
  //   1. The user's OWN inventory   -> fills everything (name, category, prices)
  //   2. The shared barcodeDirectory -> fills ONLY item name + category
  //   3. Unknown barcode             -> just keeps the barcode
  // ---------------------------------------------------------------------------
  Future<void> _scanAndAutoFill() async {
    // Camera.dart returns a Map: {source: 'barcode', barcode: '...'} or
    // {source: 'ai', itemName, category, imagePath, ...}.
    // (Older versions returned a plain String, so that is still accepted.)
    final scanned = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (scanned == null || !mounted) return;

    // AI photo result: no barcode, so fill what the AI recognised
    if (scanned is Map && scanned['source'] == 'ai') {
      _applyAiResult(Map<String, dynamic>.from(scanned));
      return;
    }

    final String scannedResult =
        (scanned is Map ? (scanned['barcode'] ?? '') : scanned)
            .toString()
            .trim();
    if (scannedResult.isEmpty) return;

    setState(() => _barcodeController.text = scannedResult);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // ── Step 1: Check the user's OWN inventory for this barcode ──
    final ownQuery = await FirebaseFirestore.instance
        .collection('Inventory')
        .where('userId', isEqualTo: user.uid)
        .where('barcode', isEqualTo: scannedResult)
        .limit(1)
        .get();

    if (!mounted) return;

    if (ownQuery.docs.isNotEmpty) {
      // Full auto-fill including price, cost, pieces
      final existingData = ownQuery.docs.first.data();
      _applyExistingItemData(existingData);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Auto-filled from your inventory!"),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    // ── Step 2: Check the shared global barcode directory ─────────
    // Another user may have already catalogued this barcode.
    // We auto-fill ONLY Item Name + Category — the user still enters
    // Stock, Cost, Pieces/Pack and Selling Price themselves.
    final directoryResult = await BarcodeDirectoryService.lookup(scannedResult);

    if (!mounted) return;

    if (directoryResult != null) {
      setState(() {
        _itemNameController.text = directoryResult.itemName;
        final cat = directoryResult.category;
        if (_categories.contains(cat)) {
          _selectedCategory = cat;
          _customCategoryController.clear();
        } else {
          _selectedCategory = 'Others';
          _customCategoryController.text = cat;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Nahanap sa community database: ${directoryResult.itemName}. "
            "I-fill na lang ang Stock, Cost, at Presyo.",
          ),
          backgroundColor: const Color(0xFF1E3A5F),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // ── Step 3: Truly unknown barcode ─────────────────────────────
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Barcode scanned: $scannedResult. I-fill ang detalye ng item."),
        backgroundColor: const Color(0xFF1E3A5F),
      ),
    );
  }

  /// Fills the form from an AI photo scan (name, category, photo).
  void _applyAiResult(Map<String, dynamic> ai) {
    final name = (ai['itemName'] ?? '').toString().trim();
    final cat = (ai['category'] ?? '').toString().trim();
    final path = (ai['imagePath'] ?? '').toString();

    setState(() {
      if (name.isNotEmpty) _itemNameController.text = name;
      if (cat.isNotEmpty) {
        if (_categories.contains(cat)) {
          _selectedCategory = cat;
          _customCategoryController.clear();
        } else {
          _selectedCategory = 'Others';
          _customCategoryController.text = cat;
        }
      }
      if (path.isNotEmpty) _imagePath = path;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(name.isEmpty
            ? "AI scan done. I-fill ang detalye ng item."
            : "AI detected: $name. Pakicheck ang detalye."),
        backgroundColor: const Color(0xFF1E3A5F),
      ),
    );
  }

  /// Applies a full data map from the user's own inventory
  /// (all fields: name, category, price, cost, pieces).
  void _applyExistingItemData(Map<String, dynamic> data) {
    setState(() {
      _itemNameController.text = data['itemName'] ?? '';
      final cat = data['category'] ?? _selectedCategory;
      if (_categories.contains(cat)) {
        _selectedCategory = cat;
      } else {
        _selectedCategory = 'Others';
        _customCategoryController.text = cat;
      }
      _sellingPriceController.text = (data['price'] ?? '').toString();

      final int pieces = (data['piecesPerPack'] ?? 1).toInt();
      _isTingiMode = pieces > 1;
      _piecesPerPackController.text = pieces.toString();

      if (_isTingiMode) {
        _packCostController.text = (data['totalPackCost'] ?? '').toString();
      } else {
        _unitCostController.text = (data['cost'] ?? '').toString();
      }
    });
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      String normalize(String input) {
        return input.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      }

      final itemName = _itemNameController.text.trim();
      final normalizedInputName = normalize(itemName);
      final barcode = _barcodeController.text.trim();
      
      final finalCategory = (_selectedCategory == 'Others' && _customCategoryController.text.isNotEmpty)
          ? _customCategoryController.text.trim()
          : _selectedCategory;

      if (widget.documentId == null) {
        QuerySnapshot duplicateCheckQuery = await FirebaseFirestore.instance
            .collection('Inventory')
            .where('userId', isEqualTo: user.uid)
            .get();

        bool isDuplicate = duplicateCheckQuery.docs.any((doc) {
          var data = doc.data() as Map<String, dynamic>;
          String existingName = (data['itemName'] ?? '').toString();
          String normalizedExistingName = normalize(existingName);
          String existingBarcode = (data['barcode'] ?? '').toString().trim();

          bool nameMatch = normalizedExistingName.isNotEmpty && normalizedExistingName == normalizedInputName;
          bool barcodeMatch = barcode.isNotEmpty && existingBarcode == barcode;

          return nameMatch || barcodeMatch;
        });

        if (isDuplicate) {
          if (!mounted) return;
          
          bool? confirmAdd = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              final bool isDark = Theme.of(context).brightness == Brightness.dark;
              return AlertDialog(
                backgroundColor: isDark ? fbCardBg : Colors.white,
                title: Text(
                  "Item Already Exists",
                  style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold),
                ),
                content: Text(
                  "An item with a similar name ('$itemName')${barcode.isNotEmpty ? " or barcode '$barcode'" : ""} is already in your inventory. Are you sure you want to add it again?",
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: tealAccent),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Add Anyway", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          );

          if (confirmAdd != true) {
            setState(() => _isLoading = false);
            return; 
          }
        }
      }

      final int inputStock = int.parse(_stockController.text.trim());
      final int piecesPerPack = _isTingiMode ? int.parse(_piecesPerPackController.text.trim()) : 1;
      
      final int totalPiecesStock = _isTingiMode ? (inputStock * piecesPerPack) : inputStock;

      double inputCost = 0.0;
      double unitCost = 0.0;
      double totalPackCostStored = 0.0;

      if (_isTingiMode) {
        inputCost = double.parse(_packCostController.text.trim());
        unitCost = piecesPerPack > 0 ? (inputCost / piecesPerPack) : inputCost;
        totalPackCostStored = inputCost;
      } else {
        unitCost = double.parse(_unitCostController.text.trim());
        totalPackCostStored = 0.0;
      }

      final double sellingPrice = double.parse(_sellingPriceController.text.trim());

      String status = 'In Stock';
      if (totalPiecesStock <= 0) {
        status = 'Critical';
      } else if (totalPiecesStock <= 5) {
        status = 'Low Stock';
      }

      final itemData = {
        'userId': user.uid,
        'itemName': itemName,
        'barcode': barcode,
        'stock': totalPiecesStock, 
        'cost': unitCost, // Saved properly as a double
        'totalPackCost': totalPackCostStored, 
        'piecesPerPack': piecesPerPack,
        'price': sellingPrice, 
        'category': finalCategory,
        'status': status,
        'imagePath': _imagePath ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.documentId != null) {
        await FirebaseFirestore.instance
            .collection('Inventory')
            .doc(widget.documentId)
            .update(itemData);
      } else {
        itemData['createdAt'] = FieldValue.serverTimestamp();
        itemData['totalSold'] = 0;
        await FirebaseFirestore.instance.collection('Inventory').add(itemData);
      }

      // ── Contribute to shared barcode directory ───────────────────
      // Silently share the barcode→name mapping so other users
      // benefit when they scan the same product.
      // Only contributes if a real barcode was entered (not empty,
      // not an AI-returned product name string).
      if (barcode.isNotEmpty) {
        BarcodeDirectoryService.contribute(
          barcode: barcode,
          itemName: itemName,
          category: finalCategory,
        );
        // Clear cache so a re-scan of this barcode returns fresh data.
        BarcodeDirectoryService.clearCache(barcode);
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving item: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    double previewPackCost = double.tryParse(_packCostController.text) ?? 0.0;
    int previewPieces = int.tryParse(_piecesPerPackController.text) ?? 1;
    double liveUnitCost = (_isTingiMode && previewPieces > 0) ? (previewPackCost / previewPieces) : 0.0;

    int inputStockVal = int.tryParse(_stockController.text) ?? 0;
    int computedTotalPieces = _isTingiMode ? (inputStockVal * previewPieces) : inputStockVal;

    String dropdownValue = _categories.contains(_selectedCategory) ? _selectedCategory : 'Others';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18191A) : navyBlue,
      appBar: AppBar(
        title: Text(
          widget.documentId == null ? "Add Inventory Item" : "Edit Inventory Item",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: navyBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          color: isDark ? fbCardBg : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.documentId == null) ...[
                  OutlinedButton.icon(
                    onPressed: _scanAndAutoFill,
                    icon: Icon(Icons.qr_code_scanner, color: navyBlue),
                    label: Text("Auto-Fill with Barcode / AI Camera Scan", style: TextStyle(color: navyBlue, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(color: navyBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // --- BARCODE / SKU ---
                const Text("Barcode / SKU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _barcodeController,
                  decoration: _inputDecoration("Scan or type barcode"),
                ),
                const SizedBox(height: 16),

                // --- CATEGORY DROPDOWN ---
                const Text("Category", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: dropdownValue,
                  decoration: _inputDecoration(""),
                  items: _categories.map((cat) {
                    return DropdownMenuItem(
                      value: cat, 
                      child: Text(cat == 'Others' && !_categories.contains(_selectedCategory) 
                          ? "Others ($_selectedCategory)" 
                          : cat),
                    );
                  }).toList(),
                  onChanged: (val) => _handleCategorySelection(val),
                ),
                const SizedBox(height: 16),

                // --- ITEM NAME ---
                const Text("Item Name", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _itemNameController,
                  decoration: _inputDecoration(_getCategoryHint()),
                  validator: (val) => val == null || val.isEmpty ? "Please enter item name" : null,
                ),
                const SizedBox(height: 16),

                // --- TINGI TOGGLE ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: SwitchListTile(
                    title: const Text("Bought in Pack, Sold by Piece (Tingi)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text("Enable if bought in bulk packs and sold individually", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    value: _isTingiMode,
                    activeColor: tealAccent,
                    onChanged: (val) => setState(() => _isTingiMode = val),
                  ),
                ),
                const SizedBox(height: 16),

                // --- DYNAMIC STOCK LABEL & INPUT ---
                Text(
                  _isTingiMode ? "Stock (Packs / Boxes)" : "Stock (Pcs)",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _stockController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration(_isTingiMode ? "e.g., 5 packs" : "e.g., 100 pcs"),
                  validator: (val) => val == null || val.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 6),
                if (_isTingiMode && inputStockVal > 0 && previewPieces > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      "Total Individual Pieces: $computedTotalPieces pcs ($inputStockVal packs × $previewPieces pcs)",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                const SizedBox(height: 16),

                // --- COST INPUTS ---
                if (_isTingiMode) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Total Pack/Box Cost (₱)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _packCostController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onChanged: (_) => setState(() {}),
                              decoration: _inputDecoration("e.g., 180"),
                              validator: (val) => _isTingiMode && (val == null || val.isEmpty || double.parse(val) <= 0) ? "Required (> 0)" : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Pieces / Pack", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _piecesPerPackController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (_) => setState(() {}),
                              decoration: _inputDecoration("e.g., 20"),
                              validator: (val) => _isTingiMode && (val == null || val.isEmpty || int.parse(val) <= 0) ? "Invalid" : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (previewPackCost > 0 && previewPieces > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        "Computed Cost: ₱${liveUnitCost.toStringAsFixed(2)} per piece",
                        style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 16),
                ] else ...[
                  const Text("Capital Cost per Piece (₱)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _unitCostController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    decoration: _inputDecoration("e.g., 9.00"),
                    validator: (val) => !_isTingiMode && (val == null || val.isEmpty || double.parse(val) <= 0) ? "Required (> 0)" : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // --- SELLING PRICE ---
                const Text("Selling Price per Piece (₱)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _sellingPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  decoration: _inputDecoration("e.g., 13"),
                  validator: (val) => val == null || val.isEmpty ? "Please enter selling price" : null,
                ),
                const SizedBox(height: 32),

                // --- SAVE BUTTON ---
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tealAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _saveItem,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text(
                            "SAVE ITEM",
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
      filled: true,
      fillColor: Colors.grey.withValues(alpha: 0.1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: tealAccent, width: 1.5)),
    );
  }
}