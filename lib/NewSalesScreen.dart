import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Camera.dart';

class NewSalesScreen extends StatefulWidget {
  const NewSalesScreen({super.key});

  @override
  State<NewSalesScreen> createState() => _NewSalesScreenState();
}

class _NewSalesScreenState extends State<NewSalesScreen> {
  final Color navyBlue = const Color(0xFF1E3A5F);
  final User? user = FirebaseAuth.instance.currentUser;

  // Cart item schema: { id, name, price, cost, quantity, maxStock, isSellingAsPack, piecesPerPack, packPrice }
  final List<Map<String, dynamic>> _cartItems = [];
  double _totalAmount = 0.0;

  void _calculateTotal() {
    double total = 0;
    for (var item in _cartItems) {
      bool asPack = item['isSellingAsPack'] ?? false;
      int pieces = item['piecesPerPack'] ?? 1;
      double effectivePrice = asPack ? (item['price'] * pieces) : item['price'];
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
          // Max out based on stock availability
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

  void _openMultiSelectSearchModal() async {
    if (user == null) return;

    final Map<String, Map<String, dynamic>> tempSelections = {}; // docId -> {qty, isPack}
    String searchQuery = "";

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 15),
              const Text("Search & Select Items", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text("Choose item quantity and selling mode (Piece vs Pack)", style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 15),
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
              const Divider(height: 25),
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
                      return const Center(child: Text("No items available in inventory."));
                    }

                    final docs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final itemName = (data['itemName'] ?? '').toString().toLowerCase();
                      final barcode = (data['barcode'] ?? '').toString().toLowerCase();
                      if (searchQuery.isEmpty) return true;
                      return itemName.contains(searchQuery) || barcode.contains(searchQuery);
                    }).toList();

                    if (docs.isEmpty) {
                      return const Center(child: Text("No matching items found in database."));
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

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                    Text("Stock: $stock pcs", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text("Price: ₱${displayPrice.toStringAsFixed(2)} ${isPackMode ? '(Pack)' : '(Piece)'}", 
                                  style: TextStyle(color: navyBlue, fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (hasPackOption)
                                      ChoiceChip(
                                        label: Text(isPackMode ? "Selling: Pack ($piecesPerPack pcs)" : "Selling: Piece"),
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
                                    else
                                      const Text("Sold by Piece only", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isSelected) ...[
                                          IconButton(
                                            icon: const Icon(Icons.remove, size: 18),
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
                                          Text("$qty", style: const TextStyle(fontWeight: FontWeight.bold)),
                                          IconButton(
                                            icon: const Icon(Icons.add, size: 18),
                                            onPressed: () {
                                              setModalState(() {
                                                int maxLimit = isPackMode ? (stock ~/ piecesPerPack) : stock;
                                                if (qty < maxLimit) {
                                                  tempSelections[docId]!['qty'] = qty + 1;
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                        Checkbox(
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: navyBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCameraScanner() async {
    final scannedResult = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (scannedResult != null && scannedResult is String && mounted) {
      final firestore = FirebaseFirestore.instance;
      
      var querySnapshot = await firestore
          .collection('Inventory')
          .where('userId', isEqualTo: user?.uid)
          .where('barcode', isEqualTo: scannedResult)
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Added piece: ${data['itemName']}"), backgroundColor: Colors.green),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Item not found for barcode: $scannedResult"), backgroundColor: Colors.redAccent),
      );
    }
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
                  double linePrice = isPack ? (item['price'] * pieces * item['quantity']) : (item['price'] * item['quantity']);

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

        // If sold as pack, subtract total individual pieces (qty * piecesPerPack)
        int unitsToSubtract = isPack ? (requestedQty * piecesPerPack) : requestedQty;
        int newStock = currentStock - unitsToSubtract;
        int newTotalSold = currentTotalSold + unitsToSubtract;

        double piecePrice = (item['price'] as num).toDouble();
        double pieceCost = (item['cost'] as num).toDouble();

        // Profit calculation based on actual total pieces sold
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

      await batch.commit();

      navigator.pop();
      setState(() {
        _cartItems.clear();
        _totalAmount = 0.0;
      });

      messenger.showSnackBar(const SnackBar(content: Text("Checkout Successful! Stock & Profit Calculated Correctly."), backgroundColor: Colors.green));
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
    double displayPrice = isPack ? (item['price'] * pieces) : item['price'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      color: isDark ? const Color(0xFF242526) : Colors.white,
      child: ListTile(
        title: Text("${item['name']} ${isPack ? '(Pack)' : '(Piece)'}", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("₱${displayPrice.toStringAsFixed(2)} each"),
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
                  int maxLimit = isPack ? (item['maxStock'] ~/ pieces) : item['maxStock'];
                  if (item['quantity'] < maxLimit) {
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