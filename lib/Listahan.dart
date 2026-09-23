import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ListahanScreen extends StatelessWidget {
  const ListahanScreen({super.key});

  void _showTransactionDetails(BuildContext context, Map<String, dynamic> data, String dateStr, bool isDark, Color navyBlue) {
    List<dynamic> items = data['items'] ?? [];
    double totalAmount = (data['totalAmount'] ?? 0.0).toDouble();

    // Calculate profit for modal display
    double transactionProfit = 0;
    for (var item in items) {
      double price = (item['price'] ?? 0.0).toDouble();
      double cost = (item['cost'] ?? 0.0).toDouble();
      int qty = (item['quantity'] ?? 0).toInt();
      transactionProfit += (price - cost) * qty;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF242526) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4, 
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Transaction Receipt", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
            const Divider(height: 30),
            const Text("Items Sold:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  var item = items[index];
                  String name = item['name'] ?? 'Unknown Item';
                  int qty = (item['quantity'] ?? 1).toInt();
                  double price = (item['price'] ?? 0.0).toDouble();
                  double subtotal = qty * price;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text("$qty x $name", style: TextStyle(fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black87)),
                        ),
                        Text("₱${subtotal.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Paid", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                Text("₱${totalAmount.toStringAsFixed(2)}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navyBlue)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Estimated Profit", style: TextStyle(fontSize: 14, color: Colors.grey)),
                Text("+₱${transactionProfit.toStringAsFixed(2)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: navyBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("CLOSE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color navyBlue = Color(0xFF1E3A5F);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18191A) : Colors.grey[100],
      appBar: AppBar(
        title: const Text("Transaction History", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('userId', isEqualTo: user?.uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No transactions found", style: TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;

              double totalBenta = (data['totalAmount'] ?? 0.0).toDouble();
              DateTime dt = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
              String dateStr = "${dt.month}/${dt.day}/${dt.year} | ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";

              // 1. CALCULATE PROFIT
              double transactionProfit = 0;
              List items = data['items'] ?? [];

              for (var item in items) {
                double price = (item['price'] ?? 0.0).toDouble();
                double cost = (item['cost'] ?? 0.0).toDouble();
                int qty = (item['quantity'] ?? 0).toInt();

                transactionProfit += (price - cost) * qty;
              }

              String displayName = items.isNotEmpty ? items[0]['name'] : "Transaction";
              if (items.length > 1) {
                displayName = "${items[0]['name']} +${items.length - 1} more";
              }

              return Card(
                elevation: 2,
                color: isDark ? const Color(0xFF242526) : Colors.white,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => _showTransactionDetails(context, data, dateStr, isDark, navyBlue),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: navyBlue,
                          child: Icon(Icons.receipt_long, color: Colors.white),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dateStr,
                                style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "₱${totalBenta.toStringAsFixed(2)}",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "+₱${transactionProfit.toStringAsFixed(2)} profit",
                              style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}