import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ListahanScreen extends StatelessWidget {
  const ListahanScreen({super.key});

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
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  leading: const CircleAvatar(
                    backgroundColor: navyBlue,
                    child: Icon(Icons.receipt_long, color: Colors.white),
                  ),
                  title: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "${dt.month}/${dt.day}/${dt.year} | ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}",
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Total Sales
                      Text(
                        "₱${totalBenta.toStringAsFixed(2)}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      // Calculated Profit
                      Text(
                        "+₱${transactionProfit.toStringAsFixed(2)} profit",
                        style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            }
            ,
          );
        },
      ),
    );
  }
}