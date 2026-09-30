import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      _stockController.text = (data['stock'] ?? '').toString();
      
      _packCostController.text = (data['totalPackCost'] ?? data['cost'] ?? '').toString();
      _piecesPerPackController.text = (data['piecesPerPack'] ?? 20).toString();
      _sellingPriceController.text = (data['price'] ?? '').toString();
      _selectedCategory = data['category'] ?? 'Food Products & Staples';
      _imagePath = data['imagePath'] ?? data['imageUrl'];
      _isTingiMode = data['piecesPerPack'] != null && (data['piecesPerPack'] as num) > 1;
    }
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    _packCostController.dispose();
    _piecesPerPackController.dispose();
    _sellingPriceController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final itemName = _itemNameController.text.trim();
      final barcode = _barcodeController.text.trim();
      final int stock = int.parse(_stockController.text.trim());
      
      final double inputCost = double.parse(_packCostController.text.trim());
      final int piecesPerPack = _isTingiMode ? int.parse(_piecesPerPackController.text.trim()) : 1;
      
      // Fixed calculation: True individual piece cost derived from whole pack cost divided by pieces per pack
      final double unitCost = (_isTingiMode && piecesPerPack > 0) ? (inputCost / piecesPerPack) : inputCost;
      final double sellingPrice = double.parse(_sellingPriceController.text.trim());

      String status = 'In Stock';
      if (stock <= 0) {
        status = 'Critical';
      } else if (stock <= 5) {
        status = 'Low Stock';
      }

      final itemData = {
        'userId': user.uid,
        'itemName': itemName,
        'barcode': barcode,
        'stock': stock,
        'cost': unitCost, 
        'totalPackCost': _isTingiMode ? inputCost : 0.0, 
        'piecesPerPack': piecesPerPack,
        'price': sellingPrice, // Selling price per piece
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
                const Text("Item Name", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _itemNameController,
                  decoration: _inputDecoration("e.g., Marlboro Red (Per Stick)"),
                  validator: (val) => val == null || val.isEmpty ? "Please enter item name" : null,
                ),
                const SizedBox(height: 16),

                const Text("Category", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: _inputDecoration(""),
                  items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val!),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Initial Stock (Pcs)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _stockController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: _inputDecoration("e.g., 100"),
                            validator: (val) => val == null || val.isEmpty ? "Required" : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Barcode / SKU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _barcodeController,
                            decoration: _inputDecoration("Scan or type"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

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

                if (_isTingiMode) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Capital Cost per Whole Pack (₱)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _packCostController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              decoration: _inputDecoration("e.g., 180"),
                              validator: (val) => val == null || val.isEmpty ? "Required" : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Pieces per Pack", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _piecesPerPackController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: _inputDecoration("e.g., 20"),
                              validator: (val) => _isTingiMode && (val == null || val.isEmpty || int.parse(val) <= 0) ? "Invalid" : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  const Text("Capital Cost per Piece (₱)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _packCostController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    decoration: _inputDecoration("e.g., 9.00"),
                    validator: (val) => val == null || val.isEmpty ? "Required" : null,
                  ),
                  const SizedBox(height: 16),
                ],

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