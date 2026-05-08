import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'ai_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color mintGreen = const Color(0xFF6EE7B7);
  String selectedFilter = "This Week";
  String aiInsight = "Sinusuri ang iyong data...";
  bool isAnalyzing = true;

  @override
  void initState() {
    super.initState();
    _generateAIInsight();
  }

  Future<void> _generateAIInsight() async {
    setState(() => isAnalyzing = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final transSnapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(15)
          .get();

      final invSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('userId', isEqualTo: uid)
          .get();

      final transactions = transSnapshot.docs.map((doc) => doc.data()).toList();
      final inventory = invSnapshot.docs.map((doc) => doc.data()).toList();

      String insight = await AIService.getBusinessInsight(
        transactions: transactions,
        inventory: inventory,
      );

      if (mounted) {
        setState(() {
          aiInsight = insight;
          isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          aiInsight = "Hindi ma-analyze ang data sa ngayon. Subukan muli mamaya.";
          isAnalyzing = false;
        });
      }
    }
  }

  DateTime _getStartDate() {
    DateTime now = DateTime.now();
    if (selectedFilter == "This Week") {
      int daysToSubtract = now.weekday - 1;
      return DateTime(now.year, now.month, now.day).subtract(Duration(days: daysToSubtract));
    } else if (selectedFilter == "This Month") {
      return DateTime(now.year, now.month, 1);
    } else {
      return DateTime(now.year, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    final DateTime startDate = _getStartDate();

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Analytics & Reports", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildFilterToggle(isDark),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('transactions')
                  .where('userId', isEqualTo: uid)
                  .where('timestamp', isGreaterThanOrEqualTo: startDate)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                double totalBenta = 0;
                double totalTubo = 0;
                int transactionCount = 0;
                Map<String, double> bentaData = {'Mon': 0, 'Tue': 0, 'Wed': 0, 'Thu': 0, 'Fri': 0, 'Sat': 0, 'Sun': 0};
                Map<String, double> tuboData = {'Mon': 0, 'Tue': 0, 'Wed': 0, 'Thu': 0, 'Fri': 0, 'Sat': 0, 'Sun': 0};

                if (snapshot.hasData) {
                  transactionCount = snapshot.data!.docs.length;
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    double benta = (data['totalAmount'] ?? 0).toDouble();
                    double tubo = (data['profit'] ?? 0).toDouble();
                    totalBenta += benta;
                    totalTubo += tubo;
                    if (data['timestamp'] != null) {
                      DateTime date = (data['timestamp'] as Timestamp).toDate();
                      String dayName = DateFormat('EEE').format(date);
                      if (bentaData.containsKey(dayName)) {
                        bentaData[dayName] = bentaData[dayName]! + benta;
                        tuboData[dayName] = tuboData[dayName]! + tubo;
                      }
                    }
                  }
                }

                double avgSale = transactionCount > 0 ? totalBenta / transactionCount : 0;
                double avgProfit = transactionCount > 0 ? totalTubo / transactionCount : 0;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAIInsightCard(isDark),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _buildStatCard("Total Benta", "₱${totalBenta.toStringAsFixed(2)}", navyBlue, Icons.payments, true),
                          const SizedBox(width: 12),
                          _buildStatCard("Total Tubo", "₱${totalTubo.toStringAsFixed(2)}", mintGreen, Icons.trending_up, false),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildMiniCard("Transactions", "$transactionCount", Icons.calendar_today, isDark),
                          const SizedBox(width: 12),
                          _buildMiniCard("Avg. Sale", "₱${avgSale.toStringAsFixed(2)}", Icons.assessment_outlined, isDark),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildHeader("Revenue Trend (Benta)", isDark),
                      _buildBarChart(bentaData, isDark),
                      const SizedBox(height: 24),
                      _buildHeader("Profit Trend (Tubo)", isDark),
                      _buildProfitLineChart(tuboData, isDark),
                      const SizedBox(height: 24),
                      _buildHeader("Business Summary", isDark),
                      _buildSummaryRow("Total Transactions", "$transactionCount", isDark),
                      _buildSummaryRow("Avg. Profit per Sale", "₱${avgProfit.toStringAsFixed(2)}", isDark),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIInsightCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mintGreen.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: mintGreen, size: 20),
              const SizedBox(width: 8),
              Text("AI Business Insight", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : navyBlue)),
            ],
          ),
          const SizedBox(height: 10),
          isAnalyzing
              ? const LinearProgressIndicator(minHeight: 2, color: Color(0xFF6EE7B7), backgroundColor: Colors.transparent)
              : Text(aiInsight, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon, bool isNavy) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isNavy ? Colors.white70 : Colors.black54, size: 20),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: isNavy ? Colors.white70 : Colors.black54, fontSize: 11)),
            FittedBox(child: Text(value, style: TextStyle(color: isNavy ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniCard(String title, String value, IconData icon, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                  Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart(Map<String, double> data, bool isDark) {
    List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(10, 20, 15, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[100]!),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(days[value.toInt() % 7], style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ),
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)))),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: isDark ? Colors.white10 : Colors.black12, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: data[days[i]]!, color: navyBlue, width: 16, borderRadius: BorderRadius.circular(4))])),
        ),
      ),
    );
  }

  Widget _buildProfitLineChart(Map<String, double> data, bool isDark) {
    List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[100]!),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) => Text(days[value.toInt() % 7], style: const TextStyle(color: Colors.grey, fontSize: 10)))),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10)))),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(7, (i) => FlSpot(i.toDouble(), data[days[i]]!)),
              color: mintGreen,
              isCurved: true,
              barWidth: 3,
              belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [mintGreen.withValues(alpha: 0.3), mintGreen.withValues(alpha: 0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToggle(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: ["This Week", "This Month", "This Year"].map((filter) {
          bool isSelected = selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(filter, style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.grey : Colors.black87))),
              selected: isSelected,
              onSelected: (val) { if (val) setState(() { selectedFilter = filter; _generateAIInsight(); }); },
              selectedColor: navyBlue,
              backgroundColor: isDark ? Colors.black : Colors.grey[200],
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader(String text, bool isDark) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)));

  Widget _buildSummaryRow(String label, String value, bool isDark) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1A1A) : Colors.white, borderRadius: BorderRadius.circular(15)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: isDark ? Colors.grey : Colors.black54)), Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))]),
  );
}