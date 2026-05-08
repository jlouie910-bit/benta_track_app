import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Add this for date formatting

class NewSalesScreen extends StatefulWidget {
  const NewSalesScreen({super.key});

  @override
  State<NewSalesScreen> createState() => _NewSalesScreenState();
}

class _NewSalesScreenState extends State<NewSalesScreen> {
  final Color navyBlue = const Color(0xFF1E3A5F);
  final User? user = FirebaseAuth.instance.currentUser;
  final SearchController _searchController = SearchController();

  final List<Map<String, dynamic>> _cartItems = [];
  double _totalAmount = 0.0;

  void _calculateTotal() {
    double total = 0;
    for (var item in _cartItems) {
      total += (item['price'] * item['quantity']);
    }
    setState(() => _totalAmount = total);
  }

  void _addItemToCart(String id, String name, double price, double cost, int stock) {
    if (stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Item out of stock!"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      int index = _cartItems.indexWhere((item) => item['id'] == id);
      if (index != -1) {
        if (_cartItems[index]['quantity'] < stock) {
          _cartItems[index]['quantity'] += 1;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Cannot exceed available stock!")),
          );
        }
      } else {
        _cartItems.add({
          'id': id,
          'name': name,
          'price': price,
          'cost': cost,
          'quantity': 1,
          'maxStock': stock
        });
      }
      _calculateTotal();
    });
  }

  // --- NEW: RECEIPT OVERVIEW DIALOG ---
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${item['quantity']}x ${item['name']}"),
                        Text("₱${(item['price'] * item['quantity']).toStringAsFixed(2)}"),
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
        DocumentReference invRef = firestore.collection('inventory').doc(item['id']);
        DocumentSnapshot doc = await invRef.get();

        if (!doc.exists) throw "Item '${item['name']}' not found.";

        int currentStock = (doc['stock'] as num).toInt();
        int requestedQty = (item['quantity'] as num).toInt();
        int newStock = currentStock - requestedQty;

        double itemPrice = (item['price'] as num).toDouble();
        double itemCost = (item['cost'] as num).toDouble();
        totalProfit += (itemPrice - itemCost) * requestedQty;

        String newStatus = "In Stock";
        if (newStock <= 0) newStatus = "Out of Stock";
        else if (newStock <= 5) newStatus = "Critical";
        else if (newStock <= 10) newStatus = "Low Stock";

        batch.update(invRef, {'stock': newStock < 0 ? 0 : newStock, 'status': newStatus});
      }

      DocumentReference transRef = firestore.collection('transactions').doc();
      batch.set(transRef, {
        'userId': user!.uid,
        'items': _cartItems,
        'totalAmount': _totalAmount,
        'profit': totalProfit,
        'timestamp': FieldValue.serverTimestamp(),
      });

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
          _buildSearchBar(isDark),
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

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SearchAnchor(
        searchController: _searchController,
        builder: (context, controller) => SearchBar(
          controller: controller,
          onTap: () => controller.openView(),
          leading: const Icon(Icons.search),
          hintText: "Search items to sell...",
          backgroundColor: WidgetStatePropertyAll(isDark ? const Color(0xFF242526) : Colors.white),
        ),
        suggestionsBuilder: (context, controller) async {
          final snapshot = await FirebaseFirestore.instance.collection('inventory').where('userId', isEqualTo: user?.uid).get();
          return snapshot.docs
              .where((doc) => doc['itemName'].toString().toLowerCase().contains(controller.text.toLowerCase()))
              .map((doc) => ListTile(
            title: Text(doc['itemName']),
            subtitle: Text("Price: ₱${doc['price']} | Stock: ${doc['stock']}"),
            trailing: const Icon(Icons.add_shopping_cart, color: Colors.blue),
            onTap: () {
              _addItemToCart(doc.id, doc['itemName'], (doc['price'] as num).toDouble(), (doc['cost'] as num).toDouble(), (doc['stock'] as num).toInt());
              controller.closeView(null);
            },
          ))
              .toList();
        },
      ),
    );
  }

  Widget _buildCartItem(int index, bool isDark) {
    final item = _cartItems[index];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      color: isDark ? const Color(0xFF242526) : Colors.white,
      child: ListTile(
        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("₱${item['price']} each"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                onPressed: () => setState(() {
                  if (item['quantity'] > 1) item['quantity']--;
                  else _cartItems.removeAt(index);
                  _calculateTotal();
                })),
            Text("${item['quantity']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                onPressed: () => setState(() {
                  if (item['quantity'] < item['maxStock']) {
                    item['quantity']++;
                    _calculateTotal();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot exceed available stock!")));
                  }
                })),
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
              onPressed: _cartItems.isEmpty ? null : _showReceiptOverview, // UPDATED TO SHOW OVERVIEW
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