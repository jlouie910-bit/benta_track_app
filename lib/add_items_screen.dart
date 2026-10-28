import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Camera.dart'; // Ensure this points to your camera scanner file

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

  String _selectedCategory = 'Food Products & Staples';
  bool _isTingiMode = true; 
  String? _imagePath;
  bool _isLoading = false;

  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color tealAccent = const Color(0xFF4FD1C5);
  final Color fbCardBg = const Color(0xFF242526);

  final List<String> _categories = [
    'Food Products & Staples',
    'Snacks & Treats',
    'Beverages',
    'Personal Care & Hygiene',
    'Household & Cleaning Supplies',
  ];

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
      _selectedCategory = data['category'] ?? 'Food Products & Staples';
      _imagePath = data['imagePath'] ?? data['imageUrl'];

      if (_isTingiMode) {
        _packCostController.text = (data['totalPackCost'] ?? (data['cost'] * pieces)).toString();
      } else {
        _unitCostController.text = (data['cost'] ?? '').toString();
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
    super.dispose();
  }

  Future<void> _scanAndAutoFill() async {
    final scannedResult = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (scannedResult != null && scannedResult is String && mounted) {
      setState(() {
        _barcodeController.text = scannedResult;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final query = await FirebaseFirestore.instance
            .collection('Inventory')
            .where('userId', isEqualTo: user.uid)
            .where('barcode', isEqualTo: scannedResult)
            .get();

        if (query.docs.isNotEmpty) {
          final existingData = query.docs.first.data();
          setState(() {
            _itemNameController.text = existingData['itemName'] ?? '';
            _selectedCategory = existingData['category'] ?? _selectedCategory;
            _sellingPriceController.text = (existingData['price'] ?? '').toString();
            
            int pieces = (existingData['piecesPerPack'] ?? 1).toInt();
            _isTingiMode = pieces > 1;
            _piecesPerPackController.text = pieces.toString();
            
            if (_isTingiMode) {
              _packCostController.text = (existingData['totalPackCost'] ?? '').toString();
            } else {
              _unitCostController.text = (existingData['cost'] ?? '').toString();
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Existing item details auto-filled from barcode!"), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Barcode scanned: $scannedResult. Fill in the remaining details."), backgroundColor: navyBlue),
          );
        }
      }
    }
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
        'cost': unitCost, 
        'totalPackCost': totalPackCostStored, 
        'piecesPerPack': piecesPerPack,
        'price': sellingPrice, 
        'category': _selectedCategory,
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
        actions: [
          if (widget.documentId == null)
            IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              tooltip: "Scan Barcode / AI Vision",
              onPressed: _scanAndAutoFill,
            ),
        ],
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

                // --- ITEM NAME ---
                const Text("Item Name", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _itemNameController,
                  decoration: _inputDecoration("e.g., Marlboro Red (Per Stick)"),
                  validator: (val) => val == null || val.isEmpty ? "Please enter item name" : null,
                ),
                const SizedBox(height: 16),

                // --- BARCODE / SKU ---
                const Text("Barcode / SKU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _barcodeController,
                  decoration: _inputDecoration("Scan or type barcode"),
                ),
                const SizedBox(height: 16),

                // --- CATEGORY ---
                const Text("Category", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: _inputDecoration(""),
                  items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val!),
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
                              validator: (val) => _isTingiMode && (val == null || val.isEmpty) ? "Required" : null,
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
                    validator: (val) => !_isTingiMode && (val == null || val.isEmpty) ? "Required" : null,
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