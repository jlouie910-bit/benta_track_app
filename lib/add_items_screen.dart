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

  String _selectedCategory = 'Food Products & Staples';
  String? _capturedImagePath;
  bool _isUploading = false;

  final List<String> _categories = [
    'Food Products & Staples',
    'Snacks & Treats',
    'Beverages',
    'Personal Care & Hygiene',
    'Household & Cleaning Supplies',
  ];

  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color tealAccent = const Color(0xFF4FD1C5); // Fixed: Defined here

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialData?['itemName'] ?? '');
    _priceController = TextEditingController(text: widget.initialData?['price']?.toString() ?? '');
    _costController = TextEditingController(text: widget.initialData?['cost']?.toString() ?? '');
    _stockController = TextEditingController(text: widget.initialData?['stock']?.toString() ?? '');
    _barcodeController = TextEditingController(text: widget.initialData?['barcode'] ?? '');
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
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);

    if (image != null) {
      setState(() {
        _capturedImagePath = image.path;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Item photo attached for AI Vision!"), backgroundColor: Colors.green),
        );
      }
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
      debugPrint("Error uploading image to Firebase Storage: $e");
      return null;
    }
  }

  void _showCatalogPickerModal() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 15),
            const Text("Select Existing Item", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text("Pick an item to populate fields automatically", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const Divider(height: 25),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('Inventory')
                    .where('userId', isEqualTo: user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("No existing inventory items found."));
                  }

                  final docs = snapshot.data!.docs;

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final itemName = data['itemName'] ?? 'Unnamed';
                      final stock = data['stock'] ?? 0;
                      final price = data['price'] ?? 0;
                      final category = data['category'] ?? 'Food Products & Staples';
                      final cost = data['cost'] ?? 0;
                      final barcode = data['barcode'] ?? '';
                      final image = data['imagePath'] ?? data['imageUrl'];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Stock: $stock | Price: ₱$price"),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: navyBlue, foregroundColor: Colors.white),
                            onPressed: () {
                              setState(() {
                                _nameController.text = itemName;
                                _priceController.text = price.toString();
                                _costController.text = cost.toString();
                                _stockController.text = stock.toString();
                                _barcodeController.text = barcode;
                                if (_categories.contains(category)) {
                                  _selectedCategory = category;
                                }
                                if (image != null) {
                                  _capturedImagePath = image;
                                }
                              });
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Loaded details for: $itemName"), backgroundColor: Colors.teal),
                              );
                            },
                            child: const Text("Select"),
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
    );
  }

  void _deleteItem() async {
    if (widget.documentId == null) return;

    bool? confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Item"),
        content: const Text("Are you sure you want to permanently remove this item from your inventory and Firebase?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      try {
        await FirebaseFirestore.instance.collection('Inventory').doc(widget.documentId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Item deleted successfully!"), backgroundColor: Colors.red),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error deleting item: $e"), backgroundColor: Colors.red),
          );
        }
      }
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
    final int stock = int.parse(_stockController.text);

    String status = 'In Stock';
    if (stock <= 0) {
      status = 'Critical';
    } else if (stock <= 5) {
      status = 'Critical';
    } else if (stock <= 10) {
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

      if (widget.documentId != null) {
        await firestore.collection('Inventory').doc(widget.documentId).update({
          'itemName': _nameController.text.trim(),
          'category': _selectedCategory,
          'price': price,
          'cost': cost,
          'stock': stock,
          'barcode': finalBarcode,
          'status': status,
          'imagePath': imageUrl ?? _capturedImagePath,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Item updated successfully!"), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
      } else {
        await firestore.collection('Inventory').add({
          'userId': user.uid,
          'itemName': _nameController.text.trim(),
          'category': _selectedCategory,
          'price': price,
          'cost': cost,
          'stock': stock,
          'barcode': finalBarcode,
          'status': status,
          'imagePath': imageUrl ?? _capturedImagePath,
          'timestamp': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Item added successfully!"), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentId != null ? "Edit / Restock Item" : "Add New Item",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (widget.documentId != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _deleteItem,
              tooltip: "Delete Item",
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.documentId == null) ...[
                ElevatedButton.icon(
                  onPressed: _showCatalogPickerModal,
                  icon: const Icon(Icons.list_alt, color: Colors.white),
                  label: const Text("Select Existing Item from Catalog", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tealAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),
              ],

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
                        labelText: "Barcode (Optional / Auto-generated)",
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
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: "Selling Price (₱)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) => value == null || double.tryParse(value) == null ? 'Please enter a valid price' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: "Capital / Cost (₱)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) => value == null || double.tryParse(value) == null ? 'Please enter a valid cost' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stockController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Stock Quantity",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) => value == null || int.tryParse(value) == null ? 'Please enter a valid quantity' : null,
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.camera_alt, color: Colors.blueGrey),
                        SizedBox(width: 8),
                        Text("Item Photo for AI Vision (Optional)", style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_capturedImagePath != null)
                      Container(
                        height: 120,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: _capturedImagePath!.startsWith('http')
                                ? NetworkImage(_capturedImagePath!) as ImageProvider
                                : FileImage(File(_capturedImagePath!)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _pickItemImage,
                      icon: const Icon(Icons.add_a_photo),
                      label: Text(_capturedImagePath == null ? "Take Photo of Item" : "Retake Photo"),
                      style: OutlinedButton.styleFrom(foregroundColor: navyBlue),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isUploading ? null : _saveItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: navyBlue,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isUploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
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