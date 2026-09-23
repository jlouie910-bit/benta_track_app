import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'camera.dart';

class AddItemScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final String? documentId;

  const AddItemScreen({super.key, this.initialData, this.documentId});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _costController;
  late TextEditingController _stockController;
  late TextEditingController _barcodeController;
  
  // TINGI SYSTEM CONTROLLERS
  late TextEditingController _piecesPerPackController;
  late TextEditingController _packsController;

  String _selectedCategory = 'Food Products & Staples';
  String? _capturedImagePath;
  bool _isUploading = false;
  bool _isPackItem = false; // Toggle for Tingi / Sold by Pack

  final List<String> _categories = [
    'Food Products & Staples',
    'Snacks & Treats',
    'Beverages',
    'Personal Care & Hygiene',
    'Household & Cleaning Supplies',
  ];

  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color tealAccent = const Color(0xFF4FD1C5);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialData?['itemName'] ?? '');
    _priceController = TextEditingController(text: widget.initialData?['price']?.toString() ?? '');
    _costController = TextEditingController(text: widget.initialData?['cost']?.toString() ?? '');
    _stockController = TextEditingController(text: widget.initialData?['stock']?.toString() ?? '');
    _barcodeController = TextEditingController(text: widget.initialData?['barcode'] ?? '');
    
    _isPackItem = widget.initialData?['isPackItem'] ?? false;
    _piecesPerPackController = TextEditingController(text: widget.initialData?['piecesPerPack']?.toString() ?? '1');
    _packsController = TextEditingController(text: widget.initialData?['packs']?.toString() ?? '0');

    _capturedImagePath = widget.initialData?['imagePath'] ?? widget.initialData?['imageUrl'];

    if (widget.initialData?['category'] != null && _categories.contains(widget.initialData?['category'])) {
      _selectedCategory = widget.initialData!['category'];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockController.dispose();
    _barcodeController.dispose();
    _piecesPerPackController.dispose();
    _packsController.dispose();
    super.dispose();
  }

  void _scanBarcodeFromCamera() async {
    final scannedResult = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (scannedResult != null && scannedResult is String) {
      setState(() {
        _barcodeController.text = scannedResult;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Barcode Scanned: $scannedResult"), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _pickItemImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera, 
      imageQuality: 70,
    );

    if (image != null) {
      setState(() {
        _capturedImagePath = image.path;
      });
    }
  }

  Future<String?> _uploadImageToStorage(String imagePath) async {
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }

    try {
      File file = File(imagePath);
      if (!file.existsSync()) return null;

      String fileName = 'inventory_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference ref = FirebaseStorage.instance.ref().child('inventory_images/$fileName');

      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;

      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint("Error uploading image: $e");
      return null;
    }
  }

  void _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isUploading = true;
    });

    final double price = double.parse(_priceController.text);
    final double cost = double.parse(_costController.text);
    
    int finalStock = 0;
    int packsCount = 0;
    int piecesPerPackCount = 1;

    if (_isPackItem) {
      packsCount = int.parse(_packsController.text);
      piecesPerPackCount = int.parse(_piecesPerPackController.text);
      finalStock = packsCount * piecesPerPackCount; 
    } else {
      finalStock = int.parse(_stockController.text);
    }

    String status = 'In Stock';
    if (finalStock <= 0) {
      status = 'Critical';
    } else if (finalStock <= 5) {
      status = 'Critical';
    } else if (finalStock <= 10) {
      status = 'Low Stock';
    }

    final String finalBarcode = _barcodeController.text.trim().isEmpty
        ? 'BT-${DateTime.now().millisecondsSinceEpoch}'
        : _barcodeController.text.trim();

    try {
      String? imageUrl;
      if (_capturedImagePath != null) {
        imageUrl = await _uploadImageToStorage(_capturedImagePath!);
      }

      final firestore = FirebaseFirestore.instance;
      final itemData = {
        'userId': user.uid,
        'itemName': _nameController.text.trim(),
        'category': _selectedCategory,
        'price': price,
        'cost': cost,
        'stock': finalStock,
        'isPackItem': _isPackItem,
        'piecesPerPack': piecesPerPackCount,
        'packs': packsCount,
        'barcode': finalBarcode,
        'status': status,
        'imagePath': imageUrl ?? _capturedImagePath,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (widget.documentId != null) {
        await firestore.collection('Inventory').doc(widget.documentId).update(itemData);
      } else {
        await firestore.collection('Inventory').add(itemData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Item saved successfully!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving item: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentId != null ? "Edit Item" : "Add New Item",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- PRODUCT IMAGE PICKER WIDGET ---
              Center(
                child: GestureDetector(
                  onTap: _pickItemImage,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF242526) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: tealAccent, width: 2),
                    ),
                    child: _capturedImagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: _capturedImagePath!.startsWith('http://') || _capturedImagePath!.startsWith('https://')
                                ? Image.network(_capturedImagePath!, fit: BoxFit.cover)
                                : Image.file(File(_capturedImagePath!), fit: BoxFit.cover),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt, color: tealAccent, size: 32),
                              const SizedBox(height: 6),
                              const Text(
                                "Add Photo", 
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Item Name",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Please enter item name' : null,
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      decoration: InputDecoration(
                        labelText: "Barcode (Optional)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _scanBarcodeFromCamera,
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                    label: const Text("Scan", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navyBlue,
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: InputDecoration(
                  labelText: "Category",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: _categories.map((category) {
                  return DropdownMenuItem(value: category, child: Text(category));
                }).toList(),
                onChanged: (value) => setState(() => _selectedCategory = value!),
              ),
              const SizedBox(height: 16),

              // --- TINGI / PACK TOGGLE SWITCH ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: tealAccent, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SwitchListTile(
                  title: const Text("Bought in Pack, Sold by Piece (Tingi)", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("Enable if bought in bulk packs/boxes and sold individually (e.g. Cigarettes, Cotton Buds)", style: TextStyle(fontSize: 11)),
                  value: _isPackItem,
                  activeThumbColor: tealAccent,
                  onChanged: (bool value) {
                    setState(() {
                      _isPackItem = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),

              // DYNAMIC FIELDS DEPENDING ON TINGI TOGGLE
              if (_isPackItem) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _packsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "Packs / Boxes in Stock",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (value) => _isPackItem && (value == null || int.tryParse(value) == null) ? 'Enter packs' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _piecesPerPackController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "Pieces per Pack",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (value) => _isPackItem && (value == null || int.tryParse(value) == null) ? 'Enter count' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ] else ...[
                TextFormField(
                  controller: _stockController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Stock Quantity (Pieces)",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (value) => !_isPackItem && (value == null || int.tryParse(value) == null) ? 'Please enter valid stock' : null,
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: "Selling Price per Piece (₱)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) => value == null || double.tryParse(value) == null ? 'Please enter a valid price' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _isPackItem ? "Capital Cost per Whole Pack (₱)" : "Capital Cost (₱)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) => value == null || double.tryParse(value) == null ? 'Please enter a valid cost' : null,
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _isUploading ? null : _saveItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: navyBlue,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isUploading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        widget.documentId != null ? "UPDATE ITEM" : "SAVE ITEM",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}