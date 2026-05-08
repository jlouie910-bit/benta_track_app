import 'package:flutter/material.dart';
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

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _costController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;

  String _selectedCategory = 'Food Products & Staples';
  bool _isLoading = false;

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
    _nameController = TextEditingController(text: widget.initialData?['itemName'] ?? '');
    _costController = TextEditingController(text: widget.initialData?['cost']?.toString() ?? '');
    _priceController = TextEditingController(text: widget.initialData?['price']?.toString() ?? '');
    _stockController = TextEditingController();

    if (widget.initialData != null && widget.initialData!.containsKey('category')) {
      _selectedCategory = widget.initialData!['category'];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      final double cost = double.parse(_costController.text);
      final double price = double.parse(_priceController.text);
      final int newAddedStock = int.parse(_stockController.text);

      if (widget.documentId != null) {
        // RESTOCK
        int existingStock = (widget.initialData?['stock'] ?? 0).toInt();
        int updatedTotalStock = existingStock + newAddedStock;

        await FirebaseFirestore.instance
            .collection('inventory')
            .doc(widget.documentId)
            .update({
          'itemName': _nameController.text.trim(),
          'category': _selectedCategory,
          'cost': cost,
          'price': price,
          'stock': updatedTotalStock,
          'status': updatedTotalStock <= 0 ? "Out of Stock" : (updatedTotalStock <= 5 ? "Critical" : "In Stock"),
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // NEW ITEM
        await FirebaseFirestore.instance.collection('inventory').add({
          'userId': user?.uid,
          'itemName': _nameController.text.trim(),
          'category': _selectedCategory,
          'cost': cost,
          'price': price,
          'stock': newAddedStock,
          'status': newAddedStock <= 5 ? "Critical" : "In Stock",
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.documentId != null ? "Restocked Successfully!" : "Item Added!")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18191A) : const Color(0xFFF0FAFC),
      appBar: AppBar(
        title: Text(widget.documentId != null ? "Restock Item" : "Add New Item"),
        backgroundColor: const Color(0xFF1E3A5F),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildTextField(_nameController, "Item Name", Icons.shopping_basket, isDark),
              const SizedBox(height: 15),
              _buildCategoryDropdown(isDark),
              const SizedBox(height: 15),
              _buildTextField(_costController, "Cost Price (Capital)", Icons.payments, isDark, isNumber: true),
              const SizedBox(height: 15),
              _buildTextField(_priceController, "Selling Price (Benta)", Icons.sell, isDark, isNumber: true),
              const SizedBox(height: 15),
              _buildTextField(_stockController, widget.documentId != null ? "Quantity to Add" : "Initial Stock", Icons.inventory, isDark, isNumber: true),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveItem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4FD1C5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(widget.documentId != null ? "UPDATE INVENTORY" : "SAVE TO INVENTORY",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, bool isDark, {bool isNumber = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF4FD1C5)),
        filled: true,
        fillColor: isDark ? const Color(0xFF242526) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (value) => value!.isEmpty ? "Required" : null,
    );
  }

  Widget _buildCategoryDropdown(bool isDark) {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      dropdownColor: isDark ? const Color(0xFF242526) : Colors.white,
      items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black)))).toList(),
      onChanged: (val) => setState(() => _selectedCategory = val!),
      decoration: InputDecoration(
        labelText: "Category",
        filled: true,
        fillColor: isDark ? const Color(0xFF242526) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}