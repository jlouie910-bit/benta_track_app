import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'ai_service.dart';

enum _Granularity { hourly, daily, monthly }

/// One row inside the Low Stock / Slow Mover cards.
class _RowData {
  final String title;
  final String subtitle;
  final String badge;
  final Color color;
  const _RowData(this.title, this.subtitle, this.badge, this.color);
}

/// Everything computed from the transactions of the selected period
/// (plus the previous period of equal length, used for comparison).
class _PeriodStats {
  double sales = 0;
  double profit = 0;
  int count = 0;

  double prevSales = 0;
  double prevProfit = 0;
  int prevCount = 0;

  List<double> trendSales = [];
  List<double> trendProfit = [];
  List<String> labels = [];
  List<String> tipLabels = [];

  List<double> weekdaySales = List<double>.filled(7, 0.0);
  Map<String, int> itemSales = {};

  double get avgSale => count > 0 ? sales / count : 0;
  double get margin => sales > 0 ? (profit / sales) * 100 : 0;
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color mintGreen = const Color(0xFF6EE7B7);

  // Items with this many pieces (or fewer) left are flagged as low stock.
  static const int _lowStockLimit = 5;

  final NumberFormat _pesoFmt = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final NumberFormat _compactFmt = NumberFormat.compact();

  static const List<String> _filters = ["Today", "This Week", "This Month", "This Year", "Custom"];

  String selectedFilter = "This Week";
  late DateTimeRange _range;
  late Stream<QuerySnapshot> _transStream;
  late Stream<QuerySnapshot> _invStream;

  String aiInsight = "Sinusuri ang iyong data...";
  bool isAnalyzing = true;

  // ---------------------------------------------------------------------------
  // Lifecycle & date range handling
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _invStream = FirebaseFirestore.instance
        .collection('Inventory')
        .where('userId', isEqualTo: uid)
        .snapshots();
    _range = _presetRange(selectedFilter);
    _buildTransStream();
    _generateAIInsight();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  DateTimeRange _presetRange(String filter) {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final endToday = _endOfDay(today);

    if (filter == "Today") {
      return DateTimeRange(start: today, end: endToday);
    } else if (filter == "This Week") {
      return DateTimeRange(
        start: DateTime(now.year, now.month, now.day - (now.weekday - 1)),
        end: endToday,
      );
    } else if (filter == "This Month") {
      return DateTimeRange(start: DateTime(now.year, now.month, 1), end: endToday);
    } else {
      return DateTimeRange(start: DateTime(now.year, 1, 1), end: endToday);
    }
  }

  int get _daySpan => _dateOnly(_range.end).difference(_dateOnly(_range.start)).inDays + 1;

  _Granularity get _granularity {
    final span = _daySpan;
    if (span <= 1) return _Granularity.hourly;
    if (span <= 31) return _Granularity.daily;
    return _Granularity.monthly;
  }

  // Slow movers are judged against how long the selected period is.
  int get _slowLimit {
    final span = _daySpan;
    if (span <= 1) return 0;
    if (span <= 7) return 2;
    if (span <= 31) return 5;
    return 10;
  }

  /// One stream covers the current period AND the previous one of equal
  /// length, so we can show "vs previous" without a second query.
  void _buildTransStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final start = _dateOnly(_range.start);
    final prevStart = DateTime(start.year, start.month, start.day - _daySpan);

    _transStream = FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(_range.end))
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  void _selectPreset(String filter) {
    if (filter == "Custom") {
      _pickCustomRange();
      return;
    }
    setState(() {
      selectedFilter = filter;
      _range = _presetRange(filter);
      _buildTransStream();
    });
    _generateAIInsight();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: _dateOnly(now),
      initialDateRange: DateTimeRange(
        start: _dateOnly(_range.start),
        end: _dateOnly(_range.end),
      ),
      helpText: 'Select date range',
      saveText: 'Apply',
      builder: (ctx, child) {
        final theme = Theme.of(ctx);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(primary: navyBlue, onPrimary: Colors.white),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) return;

    setState(() {
      selectedFilter = "Custom";
      _range = DateTimeRange(start: _dateOnly(picked.start), end: _endOfDay(picked.end));
      _buildTransStream();
    });
    _generateAIInsight();
  }

  // ---------------------------------------------------------------------------
  // AI insight
  // ---------------------------------------------------------------------------

  Future<void> _generateAIInsight() async {
    setState(() => isAnalyzing = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final transSnapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_range.start))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(_range.end))
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();

      final invSnapshot = await FirebaseFirestore.instance
          .collection('Inventory')
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

  // ---------------------------------------------------------------------------
  // Data crunching
  // ---------------------------------------------------------------------------

  _PeriodStats _computeStats(List<QueryDocumentSnapshot> docs) {
    final s = _PeriodStats();
    final gran = _granularity;
    final span = _daySpan;
    final startDay = _dateOnly(_range.start);
    final prevStart = DateTime(startDay.year, startDay.month, startDay.day - span);
    final multiYear = _range.start.year != _range.end.year;

    int bucketCount;
    if (gran == _Granularity.hourly) {
      bucketCount = 24;
    } else if (gran == _Granularity.daily) {
      bucketCount = span;
    } else {
      bucketCount = (_range.end.year - startDay.year) * 12 + _range.end.month - startDay.month + 1;
    }

    s.trendSales = List<double>.filled(bucketCount, 0.0);
    s.trendProfit = List<double>.filled(bucketCount, 0.0);

    for (int i = 0; i < bucketCount; i++) {
      if (gran == _Granularity.hourly) {
        final h = i % 12 == 0 ? 12 : i % 12;
        s.labels.add('$h${i < 12 ? "a" : "p"}');
        s.tipLabels.add('$h ${i < 12 ? "AM" : "PM"}');
      } else if (gran == _Granularity.daily) {
        final d = DateTime(startDay.year, startDay.month, startDay.day + i);
        s.labels.add(span <= 7 ? DateFormat('EEE').format(d) : DateFormat('d').format(d));
        s.tipLabels.add(DateFormat('EEE, MMM d').format(d));
      } else {
        final m = DateTime(startDay.year, startDay.month + i, 1);
        s.labels.add(DateFormat(multiYear ? 'MMM yy' : 'MMM').format(m));
        s.tipLabels.add(DateFormat('MMMM y').format(m));
      }
    }

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;

      final date = ts.toDate();
      final bool inCurrent = !date.isBefore(_range.start) && !date.isAfter(_range.end);
      final bool inPrev = !date.isBefore(prevStart) && date.isBefore(_range.start);
      if (!inCurrent && !inPrev) continue;

      final double benta = (data['totalAmount'] ?? 0).toDouble();
      double tubo = 0.0;
      final items = data['items'];

      if (items is List) {
        for (final raw in items) {
          if (raw is! Map) continue;
          final String name = (raw['itemName'] ?? raw['name'] ?? 'Unknown').toString();
          final double price = (raw['price'] ?? 0).toDouble();
          final int qty = (raw['quantity'] ?? 1).toInt();
          final double cost = (raw['cost'] ?? 0).toDouble();

          tubo += (price - cost) * qty;
          if (inCurrent) {
            s.itemSales[name] = (s.itemSales[name] ?? 0) + qty;
          }
        }
      } else {
        tubo = (data['profit'] ?? 0).toDouble();
      }

      if (inPrev) {
        s.prevSales += benta;
        s.prevProfit += tubo;
        s.prevCount++;
        continue;
      }

      s.sales += benta;
      s.profit += tubo;
      s.count++;
      s.weekdaySales[date.weekday - 1] += benta;

      int idx;
      if (gran == _Granularity.hourly) {
        idx = date.hour;
      } else if (gran == _Granularity.daily) {
        idx = _dateOnly(date).difference(startDay).inDays;
      } else {
        idx = (date.year - startDay.year) * 12 + date.month - startDay.month;
      }
      if (idx >= 0 && idx < bucketCount) {
        s.trendSales[idx] += benta;
        s.trendProfit[idx] += tubo;
      }
    }

    return s;
  }

  /// Rounds a max value up to a "nice" number so axis labels are clean.
  double _niceMax(double v) {
    if (v <= 0) return 100;
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final norm = v / mag;
    for (final step in [1.0, 2.0, 4.0, 8.0, 10.0]) {
      if (norm <= step) return step * mag;
    }
    return 10 * mag;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Analytics & Reports", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Pick date range',
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickCustomRange,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(isDark),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _transStream,
              builder: (context, transSnap) {
                if (transSnap.hasError) {
                  return _buildError(isDark);
                }
                if (!transSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final stats = _computeStats(transSnap.data!.docs);

                return StreamBuilder<QuerySnapshot>(
                  stream: _invStream,
                  builder: (context, invSnap) {
                    final List<Map<String, dynamic>> items = [];
                    double totalCapital = 0;
                    double potentialRevenue = 0;

                    if (invSnap.hasData) {
                      for (var doc in invSnap.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final String name = (data['itemName'] ?? 'Unknown').toString();
                        final int stock = (data['stock'] ?? 0).toInt();
                        final double pricePerPiece = (data['price'] ?? 0.0).toDouble();

                        items.add({
                          'itemName': name,
                          'stock': stock,
                          'sold': stats.itemSales[name] ?? 0,
                        });

                        double costPerPiece = 0.0;
                        final int piecesPerPack = (data['piecesPerPack'] ?? 1).toInt();
                        final double totalPackCost = (data['totalPackCost'] ?? 0.0).toDouble();
                        final double storedCost = (data['cost'] ?? 0.0).toDouble();

                        if (piecesPerPack > 1 && totalPackCost > 0) {
                          costPerPiece = totalPackCost / piecesPerPack;
                        } else if (totalPackCost > 0 && stock > 0 && storedCost > (pricePerPiece * 2)) {
                          costPerPiece = totalPackCost / (piecesPerPack > 0 ? piecesPerPack : 1);
                        } else {
                          costPerPiece = storedCost;
                        }

                        totalCapital += costPerPiece * stock;
                        potentialRevenue += pricePerPiece * stock;
                      }
                    }

                    final bool hasSales = stats.count > 0;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAIInsightCard(isDark),
                          const SizedBox(height: 20),
                          _buildKpiSection(stats, isDark),
                          const SizedBox(height: 24),
                          if (hasSales) ...[
                            _buildTrendChart(stats, isDark),
                            if (_granularity != _Granularity.hourly) ...[
                              const SizedBox(height: 24),
                              _buildWeekdayChart(stats, isDark),
                            ],
                            const SizedBox(height: 24),
                            _buildTopItems(items, isDark),
                          ] else
                            _buildEmptyState(isDark),
                          const SizedBox(height: 24),
                          _buildLowStockSection(items, isDark),
                          if (hasSales) _buildSlowMoverSection(items, isDark),
                          _buildInventoryValuationCard(totalCapital, potentialRevenue, items.isNotEmpty, isDark),
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
    );
  }

  // ---------------------------------------------------------------------------
  // Filter bar (presets + calendar)
  // ---------------------------------------------------------------------------

  Widget _buildFilterBar(bool isDark) {
    final fmt = DateFormat('MMM d, y');
    final sameDay = _daySpan == 1;
    final rangeText = sameDay
        ? fmt.format(_range.start)
        : '${fmt.format(_range.start)}  –  ${fmt.format(_range.end)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((filter) {
                final bool isSelected = selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    avatar: filter == "Custom"
                        ? Icon(Icons.edit_calendar,
                            size: 16, color: isSelected ? Colors.white : (isDark ? Colors.grey : Colors.black54))
                        : null,
                    label: Text(
                      filter,
                      style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.grey : Colors.black87)),
                    ),
                    selected: isSelected,
                    onSelected: (_) => _selectPreset(filter),
                    selectedColor: navyBlue,
                    backgroundColor: isDark ? Colors.black : Colors.grey[200],
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickCustomRange,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 14, color: isDark ? Colors.white70 : navyBlue),
                  const SizedBox(width: 6),
                  Text(
                    rangeText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : navyBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // KPI cards
  // ---------------------------------------------------------------------------

  Widget _buildKpiSection(_PeriodStats s, bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            _buildStatCard(
              "Total Benta",
              _pesoFmt.format(s.sales),
              navyBlue,
              Icons.payments,
              true,
              _buildDelta(s.sales, s.prevSales, true),
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              "Total Tubo",
              _pesoFmt.format(s.profit),
              mintGreen,
              Icons.trending_up,
              false,
              _buildDelta(s.profit, s.prevProfit, false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildMiniCard("Transactions", "${s.count}", isDark),
            const SizedBox(width: 10),
            _buildMiniCard("Avg. Sale", _pesoFmt.format(s.avgSale), isDark),
            const SizedBox(width: 10),
            _buildMiniCard("Profit Margin", "${s.margin.toStringAsFixed(1)}%", isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildDelta(double current, double previous, bool onNavy) {
    final Color neutral = onNavy ? Colors.white70 : Colors.black54;

    if (previous <= 0) {
      return Text(
        current > 0 ? "New this period" : "No data before",
        style: TextStyle(color: neutral, fontSize: 10),
      );
    }

    final double pct = ((current - previous) / previous) * 100;
    final bool up = pct >= 0;
    final Color color = up
        ? (onNavy ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
        : (onNavy ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            "${pct.abs().toStringAsFixed(1)}% vs prev.",
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon, bool isNavy, Widget footer) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isNavy ? Colors.white70 : Colors.black54, size: 20),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: isNavy ? Colors.white70 : Colors.black54, fontSize: 11)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: isNavy ? Colors.white : Colors.black87,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 6),
            footer,
          ],
        ),
      ),
    );
  }

  Widget _buildMiniCard(String title, String value, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: _cardDecoration(isDark, radius: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Charts
  // ---------------------------------------------------------------------------

  Widget _buildTrendChart(_PeriodStats s, bool isDark) {
    final int n = s.trendSales.length;
    final Color salesColor = isDark ? const Color(0xFF60A5FA) : navyBlue;

    double rawMax = 0;
    int peakIdx = 0;
    for (int i = 0; i < n; i++) {
      rawMax = math.max(rawMax, math.max(s.trendSales[i], s.trendProfit[i]));
      if (s.trendSales[i] > s.trendSales[peakIdx]) peakIdx = i;
    }
    final double maxY = _niceMax(rawMax * 1.1);
    final double interval = maxY / 4;
    final double labelInterval = n <= 8 ? 1.0 : (n / 6).ceilToDouble();

    final String granText = _granularity == _Granularity.hourly
        ? "By hour"
        : (_granularity == _Granularity.daily ? "By day" : "By month");
    final String peakText = s.trendSales[peakIdx] > 0 ? "  •  Highest: ${s.tipLabels[peakIdx]}" : "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader("Sales & Profit Trend", isDark, subtitle: "$granText$peakText"),
        Container(
          height: 300,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
          decoration: _cardDecoration(isDark),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 12),
                child: Row(
                  children: [
                    _legendDot(salesColor, "Benta"),
                    const SizedBox(width: 16),
                    _legendDot(mintGreen, "Tubo"),
                  ],
                ),
              ),
              Expanded(
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: math.max(n - 1, 1).toDouble(),
                    minY: 0,
                    maxY: maxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: interval,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          interval: interval,
                          getTitlesWidget: (value, meta) => Text(
                            value == 0 ? '0' : _compactFmt.format(value),
                            style: const TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: labelInterval,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            final int i = value.toInt();
                            if (value != i.toDouble() || i < 0 || i >= s.labels.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                s.labels[i],
                                style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final bool isSales = spot.barIndex == 0;
                            final int i = spot.x.toInt();
                            final String when = (i >= 0 && i < s.tipLabels.length) ? '${s.tipLabels[i]}\n' : '';
                            return LineTooltipItem(
                              '${isSales ? when : ""}${isSales ? "Benta" : "Tubo"}: ${_pesoFmt.format(spot.y)}',
                              TextStyle(
                                color: isSales ? Colors.white : mintGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    lineBarsData: [
                      _line(s.trendSales, salesColor, area: true, dots: n <= 12),
                      _line(s.trendProfit, mintGreen, area: true, dots: n <= 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  LineChartBarData _line(List<double> values, Color color, {required bool area, required bool dots}) {
    return LineChartBarData(
      spots: List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i])),
      isCurved: true,
      curveSmoothness: 0.25,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: dots,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 3.5,
          color: Colors.white,
          strokeWidth: 2,
          strokeColor: color,
        ),
      ),
      belowBarData: BarAreaData(
        show: area,
        gradient: LinearGradient(
          colors: [color.withOpacity(0.22), color.withOpacity(0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildWeekdayChart(_PeriodStats s, bool isDark) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const fullDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final Color barColor = isDark ? const Color(0xFF60A5FA) : navyBlue;

    final double maxVal = s.weekdaySales.reduce(math.max);
    final int bestIdx = maxVal > 0 ? s.weekdaySales.indexOf(maxVal) : -1;
    final double maxY = _niceMax(maxVal * 1.1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          "Best Selling Days",
          isDark,
          subtitle: bestIdx >= 0 ? "Busiest: ${fullDays[bestIdx]} – stock up before this day" : null,
        ),
        Container(
          height: 220,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          decoration: _cardDecoration(isDark),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: 0,
              maxY: maxY,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final int i = value.toInt();
                      if (i < 0 || i > 6) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          days[i],
                          style: TextStyle(
                            color: i == bestIdx ? (isDark ? mintGreen : navyBlue) : Colors.grey,
                            fontSize: 11,
                            fontWeight: i == bestIdx ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    _pesoFmt.format(rod.toY),
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ),
              barGroups: List.generate(7, (i) {
                final bool isBest = i == bestIdx;
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: s.weekdaySales[i],
                      width: 20,
                      color: isBest ? mintGreen : barColor.withOpacity(0.55),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Items: top sellers, low stock, slow movers
  // ---------------------------------------------------------------------------

  Widget _buildTopItems(List<Map<String, dynamic>> items, bool isDark) {
    final sorted = items.where((i) => (i['sold'] as int) > 0).toList()
      ..sort((a, b) => (b['sold'] as int).compareTo(a['sold'] as int));
    final top = sorted.take(5).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    final int maxSold = top.first['sold'] as int;
    final Color barColor = isDark ? const Color(0xFF60A5FA) : navyBlue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader("Top ${top.length} Best-Selling Items", isDark, subtitle: "Pinakamabenta sa napiling panahon"),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(isDark),
          child: Column(
            children: List.generate(top.length, (index) {
              final item = top[index];
              final String name = item['itemName'] ?? 'Unknown';
              final int sold = item['sold'] as int;

              return Padding(
                padding: EdgeInsets.only(bottom: index == top.length - 1 ? 0 : 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: index == 0 ? mintGreen : navyBlue.withOpacity(0.15),
                      child: Text(
                        "${index + 1}",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: index == 0 ? Colors.black87 : (isDark ? Colors.white : navyBlue),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxSold > 0 ? sold / maxSold : 0,
                              minHeight: 6,
                              backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(index == 0 ? mintGreen : barColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "$sold sold",
                      style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildLowStockSection(List<Map<String, dynamic>> items, bool isDark) {
    final low = items.where((i) => (i['stock'] as int) <= _lowStockLimit).toList()
      ..sort((a, b) => (a['stock'] as int).compareTo(b['stock'] as int));
    if (low.isEmpty) return const SizedBox.shrink();

    final rows = low.take(4).map((item) {
      final int stock = item['stock'] as int;
      return _RowData(
        item['itemName'] ?? 'Unknown',
        "Sold: ${item['sold']} this period",
        stock == 0 ? "Out of stock" : "$stock left",
        stock == 0 ? Colors.red : Colors.orange,
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("Low Stock Alert", isDark, subtitle: "$_lowStockLimit pcs or fewer – mag-restock na!"),
          _buildItemListCard(
            rows,
            low.length,
            isDark,
            Icons.warning_amber_rounded,
            Colors.red,
            () => _showFullItemListModal("Low Stock Items", low, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSlowMoverSection(List<Map<String, dynamic>> items, bool isDark) {
    final limit = _slowLimit;
    final slow = items.where((i) => (i['stock'] as int) > 0 && (i['sold'] as int) <= limit).toList()
      ..sort((a, b) {
        final bySold = (a['sold'] as int).compareTo(b['sold'] as int);
        return bySold != 0 ? bySold : (b['stock'] as int).compareTo(a['stock'] as int);
      });
    if (slow.isEmpty) return const SizedBox.shrink();

    final rows = slow.take(3).map((item) {
      return _RowData(
        item['itemName'] ?? 'Unknown',
        "Stock: ${item['stock']} pcs (naka-tengga)",
        "Sold: ${item['sold']}",
        Colors.orange,
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("Slow-Moving Inventory", isDark, subtitle: "Sold $limit or fewer in this period"),
          _buildItemListCard(
            rows,
            slow.length,
            isDark,
            Icons.hourglass_bottom,
            Colors.orange,
            () => _showFullItemListModal("Slow Movers (≤ $limit Sold)", slow, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildItemListCard(
    List<_RowData> rows,
    int totalCount,
    bool isDark,
    IconData icon,
    Color accent,
    VoidCallback onViewAll,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(icon, color: r.color, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(r.subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: r.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        r.badge,
                        style: TextStyle(color: r.color, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              )),
          if (totalCount > rows.length)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onViewAll,
                child: Text("View all ($totalCount)"),
              ),
            )
          else
            const SizedBox(height: 0),
        ],
      ),
    );
  }

  void _showFullItemListModal(String title, List<Map<String, dynamic>> sortedItems, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : navyBlue),
            ),
            const Divider(height: 25),
            Expanded(
              child: sortedItems.isEmpty
                  ? Center(
                      child: Text(
                        "No items found matching this filter.",
                        style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: sortedItems.length,
                      itemBuilder: (context, index) {
                        final item = sortedItems[index];
                        final itemName = item['itemName'] ?? 'Unknown Item';
                        final soldCount = item['sold'] ?? 0;
                        final stock = item['stock'] ?? 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      itemName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text("Stock remaining: $stock", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "Sold: $soldCount",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inventory valuation
  // ---------------------------------------------------------------------------

  Widget _buildInventoryValuationCard(double totalCapital, double potentialRevenue, bool hasInventory, bool isDark) {
    if (!hasInventory) return const SizedBox.shrink();

    final double potentialProfit = potentialRevenue - totalCapital;
    final double margin = potentialRevenue > 0 ? (potentialProfit / potentialRevenue) * 100 : 0;
    final Color salesColor = isDark ? mintGreen : const Color(0xFF059669);

    Widget row(String label, String value, Color valueColor) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: valueColor)),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader("Inventory Valuation Overview", isDark, subtitle: "Halaga ng lahat ng stock mo ngayon"),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(isDark),
          child: Column(
            children: [
              row("Total Capital Invested", _pesoFmt.format(totalCapital), isDark ? Colors.white : Colors.black87),
              const Divider(height: 20),
              row("Projected Total Sales", _pesoFmt.format(potentialRevenue), salesColor),
              const Divider(height: 20),
              row("Projected Net Profit", "+${_pesoFmt.format(potentialProfit)}", Colors.green),
              const Divider(height: 20),
              row("Projected Margin", "${margin.toStringAsFixed(1)}%", isDark ? Colors.white : Colors.black87),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _buildAIInsightCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mintGreen.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: mintGreen, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "AI Business Insight",
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : navyBlue),
                ),
              ),
              InkWell(
                onTap: isAnalyzing ? null : _generateAIInsight,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.refresh, size: 18, color: isAnalyzing ? Colors.grey.shade400 : Colors.grey),
                ),
              ),
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

  Widget _buildEmptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: _cardDecoration(isDark),
      child: Column(
        children: [
          Icon(Icons.insights, size: 42, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            "No sales in this period",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 6),
          const Text(
            "Try a different date range, or record a sale in the Counter and your trends will show up here.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "Hindi ma-load ang analytics. Check your internet connection and try again.\n\n"
          "If this keeps happening, check the Debug Console – Firestore may need an index (it prints a link).",
          textAlign: TextAlign.center,
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(bool isDark, {double radius = 20}) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
    );
  }

  Widget _buildHeader(String text, bool isDark, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}