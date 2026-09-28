import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_items_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _selectedStatusTab = 'All Items';
  String _selectedCategory = 'All Categories';

  // Theme Colors
  final Color fbDarkBg = const Color(0xFF18191A);
  final Color fbCardBg = const Color(0xFF242526);
  final Color fbTextGrey = const Color(0xFFB0B3B8);
  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color tealAccent = const Color(0xFF4FD1C5);

  final List<String> _categories = [
    'All Categories',
    'Food Products & Staples',
    'Snacks & Treats',
    'Beverages',
    'Personal Care & Hygiene',
    'Household & Cleaning Supplies',
  ];

  Stream<QuerySnapshot> _getInventoryStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('Inventory')
        .where('userId', isEqualTo: user.uid)
        .snapshots();
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

  // --- SECURE MPIN VERIFICATION & DELETE ITEM ---
  Future<void> _verifyAndDelete(String docId, String itemName) async {
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
              "Authorize Deletion",
              style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Enter your 4-digit MPIN to delete '$itemName':"),
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
        await FirebaseFirestore.instance.collection('Inventory').doc(docId).delete();
        _showSnackBar("Item deleted successfully", isError: false);
      }
    } catch (e) {
      _showSnackBar("Error deleting item: $e", isError: true);
    }
  }

  // --- SECURE MPIN VERIFICATION & CONTINUOUS ADD MODE ---
  Future<void> _verifyAndAddNew() async {
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

      // Once verified, loop to allow adding multiple items back-to-back without re-entering MPIN
      if (isVerified && mounted) {
        bool addMore = true;
        while (addMore && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddItemScreen()),
          );

          if (!mounted) break;

          // Prompt user after finishing one item
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

    return Scaffold(
      backgroundColor: isDark ? fbDarkBg : navyBlue,
      appBar: AppBar(
        title: const Text("Inventory Stocks", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. STATUS TABS
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: isDark ? fbCardBg : navyBlue,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All Items', 'In Stock', 'Low Stock', 'Critical'].map((tab) {
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

          // 2. CATEGORY DROPDOWN
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
              items: _categories.map((String category) {
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

          // 3. INVENTORY LIST
          Expanded(
            child: Container(
              color: isDark ? fbDarkBg : const Color(0xFFF0FAFC),
              child: StreamBuilder<QuerySnapshot>(
                stream: _getInventoryStream(),
                builder: (context, snapshot) {
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
                      final status = data['status'] ?? 'In Stock';
                      if (status != _selectedStatusTab) {
                        return false;
                      }
                    }

                    return true;
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(child: Text("No items match selected filters", style: TextStyle(color: isDark ? fbTextGrey : Colors.grey)));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(15),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var doc = docs[index];
                      var data = doc.data() as Map<String, dynamic>;

                      double price = (data['price'] as num?)?.toDouble() ?? 0.0;
                      double cost = (data['cost'] as num?)?.toDouble() ?? 0.0;
                      double margin = price - cost;
                      int currentStock = (data['stock'] as num?)?.toInt() ?? 0;
                      bool isOutOfStock = currentStock <= 0;
                      String? imagePath = data['imagePath'] ?? data['imageUrl'];

                      Widget statusIcon = _buildStatusIcon(isOutOfStock ? 'Critical' : (data['status'] ?? 'In Stock'));

                      return Card(
                        color: isDark ? fbCardBg : Colors.white,
                        margin: const EdgeInsets.only(bottom: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: isOutOfStock ? const BorderSide(color: Colors.redAccent, width: 1.5) : BorderSide.none,
                        ),
                        child: Column(
                          children: [
                            Opacity(
                              opacity: isOutOfStock ? 0.4 : 1.0,
                              child: ListTile(
                                leading: _buildProductThumbnail(imagePath, statusIcon),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['itemName'] ?? 'Product',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
                                      ),
                                    ),
                                    if (isOutOfStock)
                                      const Text("OUT OF STOCK", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Stock: $currentStock | ${data['category'] ?? 'General'}", style: TextStyle(color: isDark ? fbTextGrey : Colors.black54)),
                                    Text("Barcode: ${data['barcode'] ?? 'N/A'}", style: TextStyle(color: isDark ? tealAccent : navyBlue, fontSize: 11, fontWeight: FontWeight.w500)),
                                    Text("Capital: ₱${cost.toStringAsFixed(2)}", style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text("₱${price.toStringAsFixed(2)}", style: TextStyle(color: isDark ? tealAccent : navyBlue, fontWeight: FontWeight.bold, fontSize: 16)),
                                    Text("Profit: +₱${margin.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.only(right: 12, bottom: 12, left: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                    onPressed: () => _verifyAndDelete(doc.id, data['itemName'] ?? 'Item'),
                                    tooltip: "Delete Item",
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: isOutOfStock ? [
                                        BoxShadow(
                                          color: Colors.redAccent.withValues(alpha: 0.7),
                                          blurRadius: 12,
                                          spreadRadius: 1,
                                        ),
                                      ] : [],
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: () => _verifyAndRestock(data, doc.id),
                                      icon: const Icon(Icons.add_business, size: 16, color: Colors.white),
                                      label: const Text("RESTOCK", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isOutOfStock ? Colors.redAccent : tealAccent,
                                        elevation: isOutOfStock ? 0 : 2,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _verifyAndAddNew,
        label: const Text("Add New", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: tealAccent,
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    Color color = status == 'Critical' ? Colors.red : (status == 'Low Stock' ? Colors.orange : Colors.green);
    return CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(Icons.inventory_2, color: color, size: 20));
  }
}