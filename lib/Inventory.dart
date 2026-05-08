import 'package:flutter/material.dart';
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

    Query query = FirebaseFirestore.instance
        .collection('inventory')
        .where('userId', isEqualTo: user.uid);

    if (_selectedStatusTab != 'All Items') {
      query = query.where('status', isEqualTo: _selectedStatusTab);
    }

    if (_selectedCategory != 'All Categories') {
      query = query.where('category', isEqualTo: _selectedCategory);
    }

    return query.orderBy('timestamp', descending: true).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? fbDarkBg : const Color(0xFFF0FAFC),
      appBar: AppBar(
        title: const Text("Inventory Stocks",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                      backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.1),
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
              boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
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
              onChanged: (newValue) => setState(() => _selectedCategory = newValue!),
            ),
          ),

          // 3. INVENTORY LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getInventoryStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text("No items found", style: TextStyle(color: isDark ? fbTextGrey : Colors.grey)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;

                    double price = (data['price'] ?? 0.0).toDouble();
                    double cost = (data['cost'] ?? 0.0).toDouble();
                    double margin = price - cost;
                    int currentStock = (data['stock'] ?? 0).toInt();
                    bool isOutOfStock = currentStock <= 0;

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
                              leading: _buildStatusIcon(isOutOfStock ? 'Critical' : (data['status'] ?? 'In Stock')),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(data['itemName'] ?? 'Product',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                                  ),
                                  if (isOutOfStock)
                                    const Text("OUT OF STOCK", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Stock: $currentStock | ${data['category'] ?? 'General'}", style: TextStyle(color: isDark ? fbTextGrey : Colors.black54)),
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

                          // BUTTON SECTION
                          Padding(
                            padding: const EdgeInsets.only(right: 12, bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: isOutOfStock ? [
                                      BoxShadow(
                                        color: Colors.redAccent.withOpacity(0.7),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                    ] : [],
                                  ),
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => AddItemScreen(
                                            initialData: data,
                                            documentId: doc.id,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.add_business, size: 16, color: Colors.white),
                                    label: const Text("RESTOCK", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isOutOfStock ? Colors.redAccent : tealAccent,
                                      elevation: isOutOfStock ? 0 : 2, // Use standard elevation for normal buttons
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddItemScreen())),
        label: const Text("Add New", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: tealAccent,
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    Color color = status == 'Critical' ? Colors.red : (status == 'Low Stock' ? Colors.orange : Colors.green);
    return CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(Icons.inventory_2, color: color, size: 20));
  }
}