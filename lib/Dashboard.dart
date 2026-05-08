import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final Color navyBlue = const Color(0xFF1E3A5F);
  DateTime _selectedDate = DateTime.now();

  Stream<int> _getLowStockCount() {
    if (user == null) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('inventory')
        .where('userId', isEqualTo: user?.uid)
        .where('status', whereIn: ['Low Stock', 'Critical'])
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: navyBlue),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    DateTime startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    DateTime endOfDay = startOfDay.add(const Duration(days: 1));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18191A) : Colors.grey[100],
      appBar: AppBar(
        title: const Text("Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
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

          double totalBenta = 0;
          double totalTubo = 0;
          int transactionCount = 0;
          List<QueryDocumentSnapshot> filteredDocs = [];

          for (var doc in snapshot.data?.docs ?? []) {
            var data = doc.data() as Map<String, dynamic>;
            DateTime txDate = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

            if (txDate.isAfter(startOfDay) && txDate.isBefore(endOfDay)) {
              totalBenta += (data['totalAmount'] ?? 0.0);
              transactionCount++;
              filteredDocs.add(doc);

              List items = data['items'] ?? [];
              for (var item in items) {
                double price = (item['price'] ?? 0.0).toDouble();
                double cost = (item['cost'] ?? 0.0).toDouble();
                int qty = (item['quantity'] ?? 0).toInt();
                totalTubo += (price - cost) * qty;
              }
            }
          }

          double avgSale = transactionCount > 0 ? (totalBenta / transactionCount) : 0.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        _selectedDate.day == DateTime.now().day ? "Today's Summary" : "Daily Summary",
                        style: const TextStyle(color: Colors.grey),
                      ),
                      Text(DateFormat('MMMM d, yyyy').format(_selectedDate),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 25),

                GestureDetector(
                  onTap: () => _selectDate(context),
                  child: _buildSummaryCard(
                    title: "Total Benta (Sales)",
                    value: "₱${totalBenta.toStringAsFixed(2)}",
                    icon: Icons.calendar_month_outlined,
                    isDark: isDark,
                  ),
                ),

                const SizedBox(height: 15),

                _buildSummaryCard(
                  title: "Total Tubo (Profit)",
                  value: "₱${totalTubo.toStringAsFixed(2)}",
                  icon: Icons.trending_up,
                  isDark: isDark,
                  isProfit: true,
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSmallStat(transactionCount.toString(), "Transactions", isDark),
                    _buildSmallStat("₱${avgSale.toStringAsFixed(0)}", "Avg. Sale", isDark),

                    StreamBuilder<int>(
                      stream: _getLowStockCount(),
                      builder: (context, lowStockSnapshot) {
                        int count = lowStockSnapshot.data ?? 0;
                        return _buildSmallStat(
                          count.toString(),
                          "Low Stock",
                          isDark,
                          valueColor: count > 0 ? Colors.redAccent : null,
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 30),
                const Text("Transactions for this Day", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                filteredDocs.isEmpty
                    ? const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: Text("No transactions on this date", style: TextStyle(color: Colors.grey))),
                )
                    : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    var data = filteredDocs[index].data() as Map<String, dynamic>;
                    List items = data['items'] ?? [];
                    String displayName = items.isNotEmpty ? items[0]['name'] : "Transaction";
                    if (items.length > 1) displayName += " +${items.length - 1} more";

                    DateTime dt = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

                    return _buildTransactionItem(context, displayName, dt, (data['totalAmount'] ?? 0.0).toDouble());
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({required String title, required String value, required IconData icon, required bool isDark, bool isProfit = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: isProfit ? Colors.green : navyBlue, size: 30),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(value, style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isProfit ? Colors.green : (isDark ? Colors.white : navyBlue)
              )),
            ],
          ),
          const Spacer(),
          if (!isProfit) const Icon(Icons.edit_calendar, color: Colors.grey, size: 20),
        ],
      ),
    );
  }

  Widget _buildSmallStat(String value, String label, bool isDark, {Color? valueColor}) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor ?? (isDark ? Colors.white : Colors.black)
          )),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(BuildContext context, String name, DateTime date, double price) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black)),
              Text(DateFormat('hh:mm a').format(date), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          Text("₱${price.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}