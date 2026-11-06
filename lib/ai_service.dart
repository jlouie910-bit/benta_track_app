import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http; // pubspec.yaml: http: ^1.2.0

/// Typed failure so the UI can show a helpful message instead of a generic one.
/// kind: KEY | QUOTA | NET | TIMEOUT | SERVER | OTHER
class AIException implements Exception {
  final String kind;
  final String detail;
  const AIException(this.kind, this.detail);
  @override
  String toString() => '$kind: $detail';
}

class _Acc {
  double sales = 0;
  double profit = 0;
  int count = 0;
}

/// One inventory item, with its recent sales already attached.
class _Item {
  final String name;
  final double stock, price, cost, sold7, sold30, reorder;
  final DateTime? lastSold;
  final double? daysLeft;
  const _Item({
    required this.name,
    required this.stock,
    required this.price,
    required this.cost,
    required this.sold7,
    required this.sold30,
    required this.reorder,
    required this.lastSold,
    required this.daysLeft,
  });
  double get capitalTied => cost * stock;
}

/// What the owner is really asking. Decides which data the AI sees.
enum _Intent {
  market,
  valuation,
  itemInfo,
  restock,
  slow,
  bestSeller,
  profit,
  tips,
  general
}

class AIService {
  static String get _apiKey => dotenv.env['VISION_API_KEY'] ?? '';
  static String get _backupKey => dotenv.env['BACKUP_API_KEY'] ?? '';

  // Check https://ai.google.dev/gemini-api/docs/models for the latest model name.
  // Free-tier quotas are counted per model, so if the first one is used up
  // the next one is tried automatically.
  static const List<String> _models = ['gemini-2.5-flash', 'gemini-2.5-flash-lite'];

  // After every model returns 429 we stop calling Gemini for a while
  // instead of failing the same way on every tap.
  static DateTime? _blockedUntil;

  // Same data + same question -> same answer, no new request.
  static final Map<String, ({String text, DateTime at})> _insightCache = {};
  static const Duration _insightTtl = Duration(hours: 6);
  static final Map<String, ({String text, DateTime at})> _chatCache = {};
  static const Duration _chatTtl = Duration(minutes: 10);

  // ---------------------------------------------------------------------------
  // FIELD NAMES - taken from Analytics.dart. The first key found wins.
  // ---------------------------------------------------------------------------
  static const _dateKeys = ['timestamp', 'date', 'createdAt', 'time', 'soldAt'];
  static const _revenueKeys = [
    'totalAmount', 'total', 'amount', 'totalSales', 'sales', 'revenue'
  ];
  static const _profitKeys = ['profit', 'totalProfit', 'tubo'];
  static const _nameKeys = ['itemName', 'name', 'productName', 'item', 'product'];
  static const _qtyKeys = ['quantity', 'qty', 'quantitySold', 'count'];
  static const _stockKeys = ['stock', 'currentStock', 'inStock', 'quantity', 'qty'];
  static const _reorderKeys = [
    'reorderLevel', 'minStock', 'lowStockThreshold', 'minimumStock'
  ];
  static const _priceKeys = ['price', 'sellingPrice', 'retailPrice'];
  static const _costKeys = ['cost', 'costPrice', 'capital', 'unitCost'];

  // ---------------------------------------------------------------------------
  // Core request helper (REST API, supports Google Search grounding)
  // ---------------------------------------------------------------------------
  static Future<String?> _generateOn({
    required String model,
    required String systemInstruction,
    required List<Map<String, dynamic>> parts,
    bool useSearch = false,
    bool jsonOutput = false,
    double temperature = 0.3,
    int? maxOutputTokens,
    List<Map<String, String>> history = const [],
  }) async {
    final keys = <String>[
      if (_apiKey.isNotEmpty) _apiKey,
      if (_backupKey.isNotEmpty) _backupKey,
    ];
    if (keys.isEmpty) {
      throw const AIException('KEY', 'API key is missing from .env file');
    }

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction}
        ]
      },
      'contents': [
        for (final h in history)
          {
            'role': h['role'] == 'ai' ? 'model' : 'user',
            'parts': [
              {'text': h['content'] ?? ''}
            ]
          },
        {'role': 'user', 'parts': parts}
      ],
      // Search grounding = real, current web results (Puregold, S&R, etc.)
      if (useSearch)
        'tools': [
          {'google_search': {}}
        ],
      'generationConfig': {
        'temperature': temperature,
        // 2.5 Flash "thinks" by default: slow and uses quota. Not needed here.
        'thinkingConfig': {'thinkingBudget': 0},
        if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
        // JSON mode cannot be combined with search
        if (jsonOutput && !useSearch) 'responseMimeType': 'application/json',
      },
    });

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');

    AIException? lastError;

    for (final key in keys) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'x-goog-api-key': key,
                },
                body: body,
              )
              .timeout(const Duration(seconds: 45));

          if (res.statusCode == 200) return _parse(res.body);

          final status = res.statusCode;
          final detail = 'HTTP $status: ${res.body}';

          if (status == 429) {
            lastError = AIException('QUOTA', detail);
          } else if (status >= 500) {
            lastError = AIException('SERVER', detail);
          } else if (status == 401 ||
              status == 403 ||
              (status == 400 && res.body.contains('API key'))) {
            lastError = AIException('KEY', detail);
          } else {
            // Bad request etc. - a different key or a retry will not help.
            throw AIException('OTHER', detail);
          }

          // One short retry on the same key for temporary problems.
          // A per-day quota will not recover in 2 seconds, so do not wait for it.
          final dailyLimit = status == 429 && res.body.contains('PerDay');
          final transient = (status == 429 && !dailyLimit) || status >= 500;
          if (transient && attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          break; // go to the backup key
        } on AIException {
          rethrow;
        } on TimeoutException {
          lastError = const AIException('TIMEOUT', 'Request timed out');
          break; // try the backup key, no second wait on the same one
        } on SocketException catch (e) {
          // No internet: the backup key will not help.
          throw AIException('NET', e.toString());
        } on http.ClientException catch (e) {
          throw AIException('NET', e.toString());
        } catch (e) {
          throw AIException('OTHER', e.toString());
        }
      }
    }
    throw lastError ?? const AIException('OTHER', 'Unknown error');
  }

  /// Tries each model in [_models]; moves to the next one only on quota/server errors.
  static Future<String?> _generate({
    required String systemInstruction,
    required List<Map<String, dynamic>> parts,
    bool useSearch = false,
    bool jsonOutput = false,
    double temperature = 0.3,
    int? maxOutputTokens,
    List<Map<String, String>> history = const [],
  }) async {
    final blocked = _blockedUntil;
    if (blocked != null && DateTime.now().isBefore(blocked)) {
      throw const AIException('QUOTA', 'Skipped: quota cooldown active');
    }

    AIException? last;
    for (final model in _models) {
      try {
        return await _generateOn(
          model: model,
          systemInstruction: systemInstruction,
          parts: parts,
          useSearch: useSearch,
          jsonOutput: jsonOutput,
          temperature: temperature,
          maxOutputTokens: maxOutputTokens,
          history: history,
        );
      } on AIException catch (e) {
        last = e;
        // Bad key, no internet, bad request: another model will not fix it.
        if (e.kind != 'QUOTA' && e.kind != 'SERVER') rethrow;
        debugPrint('$model failed (${e.kind}), trying next model');
      }
    }

    if (last != null && last.kind == 'QUOTA') {
      final daily = last.detail.contains('PerDay');
      _blockedUntil = DateTime.now().add(Duration(minutes: daily ? 30 : 1));
    }
    throw last ?? const AIException('OTHER', 'Unknown error');
  }

  static String? _parse(String raw) {
    final data = jsonDecode(raw);
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      debugPrint('Gemini returned no candidates: ${data['promptFeedback']}');
      return null;
    }
    final partsOut = candidates[0]['content']?['parts'] as List? ?? [];
    final text = partsOut
        .map((p) => (p['text'] ?? '').toString())
        .where((t) => t.isNotEmpty)
        .join('');
    return text.isEmpty ? null : text;
  }

  // ---------------------------------------------------------------------------
  // Error helpers (used by the chat widget)
  // ---------------------------------------------------------------------------
  static String _errorString(Object e) =>
      e is AIException ? 'Error:${e.kind}|${e.detail}' : 'Error:OTHER|$e';

  /// Turns an "Error:KIND|detail" reply into a message for the store owner.
  static String friendlyError(String reply, {String language = 'tl'}) {
    final en = language == 'en';
    final m = RegExp(r'^Error:\s*([A-Z]+)').firstMatch(reply);
    switch (m?.group(1)) {
      case 'QUOTA':
        return en
            ? "The AI's free limit has been reached for now. Please try again later."
            : 'Naubos na muna ang free limit ng AI. Subukan ulit mamaya.';
      case 'KEY':
        return en
            ? "There's a problem with the AI API key. Please check the settings."
            : 'May problema sa API key ng AI. Pakicheck ang settings.';
      case 'NET':
        return en
            ? 'No internet connection. Please check your connection and try again.'
            : 'Walang internet. Pakicheck ang connection mo at subukan ulit.';
      case 'TIMEOUT':
        return en
            ? 'The AI took too long to reply. Please try again.'
            : 'Natagalan ang sagot ng AI. Subukan ulit.';
      case 'SERVER':
        return en
            ? 'The AI is busy right now. Please try again in a moment.'
            : 'Busy ang AI ngayon. Subukan ulit sa ilang sandali.';
      default:
        return en
            ? 'Sorry, something went wrong with the AI. Please try again later.'
            : 'Pasensya na, may problema sa AI. Subukan ulit mamaya.';
    }
  }

  // ---------------------------------------------------------------------------
  // Text helpers
  // ---------------------------------------------------------------------------

  /// Removes markdown symbols the model sometimes adds anyway.
  static String _clean(String text) => text
      .replaceAll(RegExp(r'\*+'), '')
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ñ ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static double _r(double v) => (v * 100).round() / 100;
  static double _r1(double v) => (v * 10).round() / 10;
  static String _ymd(DateTime d) => d.toIso8601String().substring(0, 10);

  /// "P1,250" or "P1,250.50".
  static String _peso(num v) {
    final neg = v < 0;
    final a = v.abs().toDouble();
    final whole = a == a.roundToDouble();
    final s = whole ? a.round().toString() : a.toStringAsFixed(2);
    final parts = s.split('.');
    parts[0] = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '${neg ? '-' : ''}P${parts.join('.')}';
  }

  /// "12" or "12.5".
  static String _num(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble() ? d.round().toString() : d.toStringAsFixed(1);
  }

  // ---------------------------------------------------------------------------
  // Question analysis: market lookup? follow-up? which period? which intent?
  // ---------------------------------------------------------------------------
  static final RegExp _marketRe = RegExp(
    r'\b(puregold|sm|s&r|landers|wholesale|supplier|palengke|divisoria|presyo|'
    r'magkano|price|srp|murang|mura|bilihan|bulk|promo|market|trend|tumaas|bumaba|'
    r'how\s+much|cheapest|cheaper|cheap|discount|supermarket|'
    r'where\s+(else\s+)?(to|can\s+i)\s+buy|saan\s+bumili|saan\s+kumuha)\b',
    caseSensitive: false,
  );

  // Names of places/sources: clearly about outside prices.
  static final RegExp _explicitMarketRe = RegExp(
    r'\b(puregold|sm|s&r|landers|wholesale|supplier|palengke|divisoria|bilihan|'
    r'saan\s+bumili|saan\s+kumuha|saan\s+pa|where\s+(else\s+)?(to|can\s+i)\s+buy)\b',
    caseSensitive: false,
  );

  // Questions about the store's own numbers.
  static final RegExp _ownDataRe = RegExp(
    r'\b(tubo|tutubuin|profit|benta|sales|kita|kinita|income|earn|earned|revenue|'
    r'stock|stocks|inventory|best\s*seller|matumal|slow|restock|i-restock|'
    r'natitira|ubos|left|remaining|sold|nabenta|capital|margin)\b',
    caseSensitive: false,
  );

  // Words that point back to the previous question.
  static final RegExp _followUpRe = RegExp(
    r'\b(nito|niyan|niyon|nyan|nun|yan|iyan|iyon|yun|ito|dito|diyan|doon|kanila|'
    r'it|them|saan\s+pa|ano\s+pa|alin\s+pa|where\s+else|what\s+else|bakit|why|how\s+come|'
    r'this\s+(one|item|product)|that\s+(one|item|product))\b',
    caseSensitive: false,
  );

  static final RegExp _valuationRe = RegExp(
    r'(mabenta\s+lahat|mabebenta\s+lahat|maibenta\s+lahat|ibenta\s+lahat|benta\s+lahat|'
    r'lahat\s+ng\s+(stock|paninda|inventory|items?)|kapital|puhunan|inventory\s+value|'
    r'halaga\s+ng\s+(stock|inventory|paninda)|projected|sell\s+(all|everything)|'
    r'sold\s+out|total\s+value|capital)',
    caseSensitive: false,
  );
  static final RegExp _restockRe = RegExp(
    r'(restock|re-stock|bilhin|kulang|paubos|\bubos\b|maubos|running\s+low|low\s+stock|'
    r'out\s+of\s+stock|reorder|what\s+(should|do)\s+i\s+(buy|order)|ano\s+ang\s+bibilhin|anong\s+bibilhin)',
    caseSensitive: false,
  );
  static final RegExp _slowRe = RegExp(
    r'(matumal|\bslow\b|hindi\s+nabebenta|di\s+nabebenta|walang\s+bumibili|tengga|'
    r'dead\s+stock|not\s+selling|hindi\s+gumagalaw)',
    caseSensitive: false,
  );
  static final RegExp _bestRe = RegExp(
    r'(best\s*seller|pinakamabenta|pinaka-?mabenta|pinakamabili|top\s+(item|product|seller|selling)|'
    r'most\s+(sold|popular)|popular|mabenta|mabili|bumebenta|hot\s+item)',
    caseSensitive: false,
  );
  static final RegExp _profitRe = RegExp(
    r'(tubo|tutubuin|kita|kinita|profit|benta|nabenta|sales|income|revenue|earn|gross|margin)',
    caseSensitive: false,
  );
  static final RegExp _tipsRe = RegExp(
    r'(tips|payo|paano|how\s+(can|do|to|should)|advice|suggest|palaguin|lumaki|palakihin|'
    r'increase|improve|dagdagan|grow|strategy)',
    caseSensitive: false,
  );

  static bool _needsMarketData(String q, List<Map<String, String>> history) {
    final explicit = _explicitMarketRe.hasMatch(q);
    final market = _marketRe.hasMatch(q);
    final own = _ownDataRe.hasMatch(q);

    // "Magkano ang tubo ko?" matches 'magkano' but is about the store's data.
    if (market && !(own && !explicit)) return true;

    // Follow-up like "Saan pa mura bumili nito?" after a price question.
    if (_followUpRe.hasMatch(q) && !own) {
      final prev = _previousUserQuestion(history);
      if (prev != null) {
        return _marketRe.hasMatch(prev) && !_ownDataRe.hasMatch(prev);
      }
    }
    return false;
  }

  static String? _previousUserQuestion(List<Map<String, String>> history) {
    for (final h in history.reversed) {
      if (h['role'] == 'user') return h['content'];
    }
    return null;
  }

  static bool _isFollowUp(String q, String? prev) =>
      prev != null && prev.trim().isNotEmpty && _followUpRe.hasMatch(q);

  /// Keeps only the last [n] messages (and makes sure the first one is from the user).
  static List<Map<String, String>> _trimHistory(List<Map<String, String>> h, int n) {
    final recent = h.length > n ? h.sublist(h.length - n) : h;
    var start = 0;
    while (start < recent.length && recent[start]['role'] == 'ai') {
      start++;
    }
    return recent.sublist(start);
  }

  static String? _detectPeriod(String q) {
    final s = q.toLowerCase();
    bool has(String p) => RegExp(p).hasMatch(s);
    if (has(r'kahapon|yesterday')) return 'yesterday';
    if (has(r'nakaraang\s+linggo|last\s+week|noong\s+isang\s+linggo')) return 'lastWeek';
    if (has(r'nakaraang\s+buwan|last\s+month|noong\s+isang\s+buwan')) return 'lastMonth';
    if (has(r'\b(7|pitong)\s*(days?|araw)')) return 'last7Days';
    if (has(r'\b(30|tatlumpung)\s*(days?|araw)')) return 'last30Days';
    if (has(r'ngayong\s+linggo|this\s+week|\blinggo\b|\bweek\b')) return 'thisWeek';
    if (has(r'ngayong\s+buwan|this\s+month|\bbuwan\b|\bmonth\b')) return 'thisMonth';
    if (has(r'\bngayon\b|ngayong\s+araw|today')) return 'today';
    return null;
  }

  static _Intent _detectIntent(String q, bool market, bool hasItems) {
    if (market) return _Intent.market;
    if (_valuationRe.hasMatch(q)) return _Intent.valuation;
    if (hasItems) return _Intent.itemInfo;
    if (_restockRe.hasMatch(q)) return _Intent.restock;
    if (_slowRe.hasMatch(q)) return _Intent.slow;
    if (_bestRe.hasMatch(q)) return _Intent.bestSeller;
    if (_tipsRe.hasMatch(q)) return _Intent.tips;
    if (_profitRe.hasMatch(q)) return _Intent.profit;
    return _Intent.general;
  }

  // ---------------------------------------------------------------------------
  // Matching products named in the question against the inventory
  // ---------------------------------------------------------------------------
  static const Set<String> _stop = {
    'ano', 'ang', 'ng', 'sa', 'ko', 'mo', 'ba', 'na', 'ay', 'at', 'pa', 'ilan',
    'magkano', 'presyo', 'price', 'how', 'much', 'many', 'what', 'the', 'my',
    'are', 'have', 'kung', 'mga', 'po', 'yung', 'yong', 'nito', 'ito', 'best',
    'seller', 'tubo', 'benta', 'profit', 'sales', 'item', 'items', 'paninda',
    'lahat', 'ngayon', 'today', 'this', 'week', 'month', 'natitira', 'left',
    'sold', 'nabenta', 'saan', 'mura', 'bumili', 'where', 'buy', 'cheap',
    'stock', 'stocks', 'inventory', 'ibenta', 'kita', 'earn', 'with', 'for',
    'and', 'can', 'you', 'tell', 'show', 'give', 'bakit', 'why', 'ilang',
  };

  static Iterable<String> _tokens(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9ñ]+'))
      .where((t) => t.length >= 3 && !_stop.contains(t));

  static List<_Item> _matchItems(String q, List<_Item> items) {
    final qt = _tokens(q).toSet();
    if (qt.isEmpty) return const [];
    final scored = <({_Item item, double score})>[];
    for (final it in items) {
      final nt = _tokens(it.name).toList();
      if (nt.isEmpty) continue;
      final hit = nt.where(qt.contains).toList();
      if (hit.isEmpty) continue;
      // A single shared word must be a real word (4+ letters), e.g. "marlboro".
      if (hit.length == 1 && nt.length > 1 && hit.first.length < 4) continue;
      scored.add((item: it, score: hit.length + hit.length / nt.length));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final s in scored.take(5)) s.item];
  }

  // ---------------------------------------------------------------------------
  // Store summary: numbers are computed here, the model only explains them.
  // Mirrors the rules in Analytics.dart so chat and dashboard always agree.
  // ---------------------------------------------------------------------------
  static double? _numOf(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final n = double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
        if (n != null) return n;
      }
    }
    return null;
  }

  static String? _strOf(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static DateTime? _dateOf(Map m) {
    for (final k in _dateKeys) {
      final v = m[k];
      DateTime? d;
      if (v is Timestamp) {
        d = v.toDate();
      } else if (v is DateTime) {
        d = v;
      } else if (v is String) {
        d = DateTime.tryParse(v);
      } else if (v is num) {
        d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
      }
      if (d != null) return d.isUtc ? d.toLocal() : d;
    }
    return null;
  }

  /// Same cost-per-piece logic as the Analytics screen.
  static double _costPerPiece(Map i, double stock, double price) {
    final pieces = (_numOf(i, ['piecesPerPack']) ?? 1).toInt();
    final packCost = _numOf(i, ['totalPackCost']) ?? 0;
    final stored = _numOf(i, _costKeys) ?? 0;
    if (pieces > 1 && packCost > 0) return packCost / pieces;
    if (packCost > 0 && stock > 0 && stored > price * 2) {
      return packCost / (pieces > 0 ? pieces : 1);
    }
    return stored;
  }

  static Map<String, dynamic> _accJson(_Acc a) => {
        'sales': _r(a.sales),
        'profit': _r(a.profit),
        'transactions': a.count,
        'profitMarginPct': a.sales > 0 ? _r(a.profit / a.sales * 100) : 0,
      };

  static Map<String, dynamic> _itemJson(_Item i) => {
        'name': i.name,
        'stock': _r(i.stock),
        'sellingPrice': _r(i.price),
        'costPerPiece': _r(i.cost),
        'profitPerPiece': _r(i.price - i.cost),
        'soldLast7Days': _r(i.sold7),
        'soldLast30Days': _r(i.sold30),
        'lastSold': i.lastSold == null ? 'none in recent records' : _ymd(i.lastSold!),
        if (i.daysLeft != null) 'daysOfStockLeft': _r1(i.daysLeft!),
      };

  static Map<String, dynamic> _buildSummary(
    List<Map<String, dynamic>> data, {
    String question = '',
  }) {
    final txs = data.where((d) => d['type'] == 'transaction').toList();
    final inv = data.where((d) => d['type'] == 'inventory').toList();

    if (txs.isEmpty && inv.isEmpty) {
      return {'note': 'No transactions or inventory records were found for this store.'};
    }

    final now = DateTime.now();
    DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);
    final todayStart = day(0);
    final weekStart = day(-(now.weekday - 1)); // weeks start on Monday, like Analytics
    final monthStart = DateTime(now.year, now.month, 1);
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastWeekStart = DateTime(weekStart.year, weekStart.month, weekStart.day - 7);
    final start7 = day(-6);
    final start14 = day(-13);
    final start30 = day(-29);

    final periods = <String, ({DateTime from, DateTime? to, _Acc acc})>{
      'today': (from: todayStart, to: null, acc: _Acc()),
      'yesterday': (from: day(-1), to: todayStart, acc: _Acc()),
      'thisWeek': (from: weekStart, to: null, acc: _Acc()),
      'lastWeek': (from: lastWeekStart, to: weekStart, acc: _Acc()),
      'last7Days': (from: start7, to: null, acc: _Acc()),
      'thisMonth': (from: monthStart, to: null, acc: _Acc()),
      'lastMonth': (from: prevMonthStart, to: monthStart, acc: _Acc()),
      'last30Days': (from: start30, to: null, acc: _Acc()),
    };

    final units30 = <String, double>{};
    final units7 = <String, double>{};
    final sales30 = <String, double>{};
    final profit30 = <String, double>{};
    final display = <String, String>{};
    final lastSold = <String, DateTime>{};
    final weekdaySales = List<double>.filled(7, 0.0);
    DateTime? oldest;

    for (final t in txs) {
      final date = _dateOf(t);
      if (date == null) continue;
      if (oldest == null || date.isBefore(oldest)) oldest = date;

      final rawItems = t['items'];
      final lines = rawItems is List ? rawItems.whereType<Map>().toList() : <Map>[];

      double lineRev = 0, lineProfit = 0;
      final lineInfo = <({String? name, double qty, double rev, double profit})>[];
      for (final l in lines) {
        final qty = _numOf(l, _qtyKeys) ?? 1;
        final price = _numOf(l, _priceKeys);
        final cost = _numOf(l, _costKeys) ?? 0;
        final rev = price != null ? price * qty : (_numOf(l, _revenueKeys) ?? 0);
        final profit = ((price ?? 0) - cost) * qty;
        lineRev += rev;
        lineProfit += profit;
        lineInfo.add((name: _strOf(l, _nameKeys), qty: qty, rev: rev, profit: profit));
      }

      final revenue = _numOf(t, _revenueKeys) ?? lineRev;
      // Analytics: with an items list profit = sum((price - cost) * qty), else the 'profit' field.
      final profit = rawItems is List ? lineProfit : (_numOf(t, _profitKeys) ?? 0);

      for (final p in periods.values) {
        final to = p.to;
        if (!date.isBefore(p.from) && (to == null || date.isBefore(to))) {
          p.acc.sales += revenue;
          p.acc.profit += profit;
          p.acc.count++;
        }
      }

      if (!date.isBefore(start30)) weekdaySales[date.weekday - 1] += revenue;

      for (final l in lineInfo) {
        final name = l.name;
        if (name == null) continue;
        final k = name.toLowerCase();
        display.putIfAbsent(k, () => name);
        final prev = lastSold[k];
        if (prev == null || date.isAfter(prev)) lastSold[k] = date;
        if (!date.isBefore(start30)) {
          units30[k] = (units30[k] ?? 0) + l.qty;
          sales30[k] = (sales30[k] ?? 0) + l.rev;
          profit30[k] = (profit30[k] ?? 0) + l.profit;
        }
        if (!date.isBefore(start7)) units7[k] = (units7[k] ?? 0) + l.qty;
      }
    }

    final histDays = oldest == null
        ? 0
        : math.max(
            1,
            todayStart
                    .difference(DateTime(oldest.year, oldest.month, oldest.day))
                    .inDays +
                1);
    final windowDays = math.max(1, math.min(30, histDays));

    // ---- inventory ----
    final items = <_Item>[];
    double capital = 0, projected = 0;
    int outOfStock = 0;
    for (final i in inv) {
      final name = _strOf(i, _nameKeys);
      if (name == null) continue;
      final stock = _numOf(i, _stockKeys) ?? 0;
      final price = _numOf(i, _priceKeys) ?? 0;
      final cost = _costPerPiece(i, stock, price);
      final k = name.toLowerCase();
      final s30 = units30[k] ?? 0;
      final avgDaily = s30 / windowDays;
      items.add(_Item(
        name: name,
        stock: stock,
        price: price,
        cost: cost,
        sold7: units7[k] ?? 0,
        sold30: s30,
        reorder: _numOf(i, _reorderKeys) ?? 5, // same limit as Analytics (5)
        lastSold: lastSold[k],
        daysLeft: avgDaily > 0 ? stock / avgDaily : null,
      ));
      capital += cost * stock;
      projected += price * stock;
      if (stock <= 0) outOfStock++;
    }

    final top = units30.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topSellers = [
      for (final e in top.take(5))
        {
          'name': display[e.key],
          'unitsSold': _r(e.value),
          'sales': _r(sales30[e.key] ?? 0),
          'profit': _r(profit30[e.key] ?? 0),
        }
    ];
    final topP = profit30.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topProfit = [
      for (final e in topP.take(3))
        {
          'name': display[e.key],
          'profit': _r(e.value),
          'unitsSold': _r(units30[e.key] ?? 0),
        }
    ];

    final lowStock = items.where((i) => i.stock <= i.reorder).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    final restock = items
        .where((i) =>
            i.sold30 > 0 &&
            (i.stock <= i.reorder || (i.daysLeft != null && i.daysLeft! <= 7)))
        .toList()
      ..sort((a, b) {
        final c = (a.daysLeft ?? 9999).compareTo(b.daysLeft ?? 9999);
        return c != 0 ? c : a.stock.compareTo(b.stock);
      });

    final slow = items
        .where((i) => i.stock > 0 && (i.lastSold == null || i.lastSold!.isBefore(start14)))
        .toList()
      ..sort((a, b) => b.capitalTied.compareTo(a.capitalTied));

    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    final maxDay = weekdaySales.reduce(math.max);
    final busiest = maxDay > 0
        ? {'day': dayNames[weekdaySales.indexOf(maxDay)], 'sales': _r(maxDay)}
        : null;

    final matched = question.trim().isEmpty ? <_Item>[] : _matchItems(question, items);

    return {
      'salesByPeriod': {
        for (final e in periods.entries) e.key: _accJson(e.value.acc),
      },
      if (busiest != null) 'busiestWeekday30Days': busiest,
      'topSellers30Days': topSellers,
      'topProfitItems30Days': topProfit,
      'restockPriority': [
        for (final i in restock.take(8))
          {
            'name': i.name,
            'stock': _r(i.stock),
            'soldLast30Days': _r(i.sold30),
            'daysOfStockLeft': i.daysLeft == null ? null : _r1(i.daysLeft!),
          }
      ],
      'lowStock': [
        for (final i in lowStock.take(10))
          {'name': i.name, 'stock': _r(i.stock), 'soldLast30Days': _r(i.sold30)}
      ],
      'slowMovers': [
        for (final i in slow.take(10))
          {
            'name': i.name,
            'stock': _r(i.stock),
            'capitalTied': _r(i.capitalTied),
            'lastSold': i.lastSold == null ? 'none in recent records' : _ymd(i.lastSold!),
          }
      ],
      'inventoryValuation': {
        'capital': _r(capital),
        'projectedSales': _r(projected),
        'projectedProfit': _r(projected - capital),
        'projectedMarginPct': projected > 0 ? _r((projected - capital) / projected * 100) : 0,
        'itemCount': items.length,
        'outOfStockCount': outOfStock,
      },
      if (matched.isNotEmpty) 'mentionedItems': [for (final i in matched) _itemJson(i)],
      'inventoryList': [
        for (final i in items.take(60)) '${i.name}: ${_num(i.stock)} pcs @ ${_peso(i.price)}'
      ],
      'meta': {
        'today': _ymd(now),
        'transactionRecordsLoaded': txs.length,
        'transactionHistoryDays': histDays,
        'inventoryItemCount': items.length,
      },
    };
  }

  /// Only the part of the summary that answers this kind of question.
  static Map<String, dynamic> _focus(Map<String, dynamic> s, _Intent intent) {
    if (s.containsKey('note')) return s;
    Map<String, dynamic> pick(List<String> keys) =>
        {for (final k in keys) if (s.containsKey(k)) k: s[k]};
    final meta = {'meta': s['meta']};

    switch (intent) {
      case _Intent.market:
        return pick(['mentionedItems']);
      case _Intent.profit:
        return {...meta, ...pick(['salesByPeriod', 'busiestWeekday30Days'])};
      case _Intent.bestSeller:
        return {...meta, ...pick(['topSellers30Days', 'topProfitItems30Days'])};
      case _Intent.restock:
        return {...meta, ...pick(['restockPriority', 'lowStock'])};
      case _Intent.slow:
        return {...meta, ...pick(['slowMovers'])};
      case _Intent.valuation:
        return {...meta, ...pick(['inventoryValuation'])};
      case _Intent.itemInfo:
        return {...meta, ...pick(['mentionedItems', 'salesByPeriod'])};
      case _Intent.tips:
      case _Intent.general:
        return s;
    }
  }

  static String _guide(_Intent intent, String? period) {
    switch (intent) {
      case _Intent.profit:
        return period != null
            ? "The owner asks about sales or profit. Use salesByPeriod.$period only. Give the sales and the profit in the first sentence. Do not list items."
            : "The owner asks about sales or profit but gave no period. Use salesByPeriod.today; if today has no sales, say so and give salesByPeriod.thisWeek instead. Do not list items.";
      case _Intent.bestSeller:
        return "Name the top 1-3 items from topSellers30Days with the units sold in the last 30 days. Only mention profit if the owner asked.";
      case _Intent.restock:
        return "Use restockPriority: name the top 3-5 items with the stock left and about how many days it will last (daysOfStockLeft). If restockPriority is empty, say the stocks are fine and mention lowStock items if there are any.";
      case _Intent.slow:
        return "Use slowMovers: name the top 3 with the stock left and the money tied up (capitalTied). These had no sales in the last 14 days of the recorded history. End with one short action (promo, bundle, or a smaller reorder).";
      case _Intent.valuation:
        return "Use inventoryValuation. First sentence: the projectedProfit if all current stock is sold at the current prices. Then briefly the capital and the projectedSales.";
      case _Intent.itemInfo:
        return "Answer only about the products in mentionedItems (stock, sellingPrice, costPerPiece, profitPerPiece, units sold, daysOfStockLeft). If several match, give the 1-3 most relevant. Do not talk about other products.";
      case _Intent.market:
        return "Use web search. Answer only for the exact product and store the owner asked about, in at most 3 short sentences: the price range in PHP and, if asked where to buy cheaper, at most 3 places with prices. If the product is in mentionedItems, add one sentence comparing the market price with the owner's selling price or cost. Do not add unrelated products.";
      case _Intent.tips:
        return "Give 2-3 concrete tips based on the store data, naming real items (top sellers, slow movers, low stock) from the summary.";
      case _Intent.general:
        return "Answer the question directly using only the relevant part of the summary.";
    }
  }

  // ---------------------------------------------------------------------------
  // Shared rules appended to every system prompt
  // ---------------------------------------------------------------------------
  static String _rulesFor(String lang) {
    final en = lang == 'en';
    final style = en ? 'in simple, clear English' : 'in Taglish';
    final notSure = en
        ? "I'm not sure about the price, please check the store."
        : 'Hindi ako sigurado sa presyo, pakicheck sa tindahan.';
    return "RULES: Answer ONLY what was asked, $style, short and direct. "
        "Always reply in that language, even if the question is written in another language. "
        "Never invent prices, stock numbers, or sales figures. "
        "For the store's own data, use ONLY the provided summary and use its numbers as they are; never recompute them. "
        "For market prices (Puregold, S&R, Landers, wholesalers, palengke), use web search results only, "
        "give a price range in PHP, and say the price may differ per branch or date. "
        "If you cannot find a reliable price, say '$notSure' "
        "If a question has nothing to do with retail, business, money, or the store, politely say you can only help with store and business topics. "
        "Do NOT use asterisks, bold, bullet points, or any markdown. Plain text paragraphs only.";
  }

  static String _chatSystem(String lang) =>
      "You are BentaTrack AI, an assistant for sari-sari store owners in the Philippines. "
      "You know retailing, markup, profit computation, and where to buy stock cheaply "
      "(Puregold, S&R, Landers, local wholesalers, palengke, Divisoria). "
      "You receive a pre-computed STORE SUMMARY, today's date, an ANSWER GUIDE and the owner's QUESTION. "
      "Follow the ANSWER GUIDE: it says which part of the summary answers this question. "
      "Use ONLY the facts that answer the question and leave out everything else, even if it is in the summary. "
      "When the owner names a product, talk about that product only. "
      "If that product is not in the store data, say you can't find it in their inventory instead of using other numbers. "
      "Do not show raw JSON, field names or step-by-step filtering. "
      "Start with the direct answer (the number or the fact) in the first sentence. "
      "Keep it to 2-3 short sentences unless the owner asks for details or a list (then at most 5 short lines). "
      "Use the peso sign and plain numbers like P1,250. "
      "If store data is empty or missing what is needed, say what is missing instead of guessing. "
      "The transaction history may be short (see meta.transactionHistoryDays); mention that only when it affects the answer (slow movers, best sellers, days of stock left). "
      "Earlier messages are only context: words like 'yan', 'iyon', 'nito', 'it', 'that' refer to the PREVIOUS QUESTION, never to older topics. "
      "${_rulesFor(lang)}";

  // ---------------------------------------------------------------------------
  // 1. Vision: identify an item from a photo
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>?> detectItemFromImage(File imageFile) async {
  const sysInstruct =
      "You are an inventory scanner for a sari-sari store in the Philippines. "
      "Look at the image and return ONLY a JSON object with keys: "
      "itemName (specific product name and brand as printed on the package), "
      "category (one of: Food Products & Staples, Snacks & Treats, Beverages, Personal Care & Hygiene, Household & Cleaning Supplies), "
      "estimatedPrice (typical Philippine retail price in PHP as a numeric string, or empty string if unknown). "
      "Do not guess a brand you cannot read.";

  try {
    final bytes = await imageFile.readAsBytes();
    final text = await _generate(
      systemInstruction: sysInstruct,
      parts: [
        {'text': 'Identify this retail item and extract product details.'},
        {
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(bytes),
          }
        },
      ],
      jsonOutput: true,
      temperature: 0.1,
    );
    if (text == null) return null;

    // Strip ```json fences in case the model adds them
    final cleaned = text.replaceAll(RegExp(r'```json|```'), '').trim();
    var decoded = jsonDecode(cleaned);
    if (decoded is List && decoded.isNotEmpty) decoded = decoded.first;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  } on AIException catch (e) {
    debugPrint('Vision failed: $e');
    return {'error': e.kind};
  } catch (e) {
    debugPrint('Vision failed: $e');
    return {'error': 'OTHER'};
  }
}

  // ---------------------------------------------------------------------------
  // 2. Business insight (dashboard / analytics)
  // ---------------------------------------------------------------------------
  static String _names(List items, {int take = 2}) => items
      .take(take)
      .map((e) => (e is Map ? e['name'] : e).toString())
      .join(' at ');

  /// Insight built from the numbers alone, used when the AI is unavailable.
  static String _localInsight(Map<String, dynamic> s) {
    if (s.containsKey('note')) {
      return 'Wala pang sapat na data. Magdagdag muna ng benta at paninda para magkaroon ng insight.';
    }
    final restock = (s['restockPriority'] as List?) ?? const [];
    final low = restock.isNotEmpty ? restock : ((s['lowStock'] as List?) ?? const []);
    final slow = (s['slowMovers'] as List?) ?? const [];
    final top = (s['topSellers30Days'] as List?) ?? const [];
    final byPeriod = s['salesByPeriod'] as Map?;
    final month = byPeriod == null ? null : byPeriod['last30Days'] as Map?;

    final first = low.isNotEmpty
        ? 'Paubos na ang ${_names(low)}, mag-restock na bago maubusan.'
        : top.isNotEmpty
            ? 'Best seller mo ang ${_names(top, take: 1)}, siguraduhing laging may stock nito.'
            : 'Walang paninda na paubos na sa ngayon.';

    final second = slow.isNotEmpty
        ? 'Matumal ang ${_names(slow)} sa nakaraang 14 araw, subukang i-promo o bawasan ang order.'
        : (month != null && ((month['profit'] as num?) ?? 0) > 0)
            ? 'Tubo mo sa nakaraang 30 araw ay ${_peso(month['profit'] as num)}.'
            : 'Ituloy ang pag-record ng benta para mas tumpak ang insight.';

    return '$first $second';
  }

  /// Never returns an "Error:" string: if the AI fails, a local insight is shown.
  static Future<String> getBusinessInsight({
    required List<Map<String, dynamic>> transactions,
    required List<Map<String, dynamic>> inventory,
  }) async {
    final sysInstruct =
        "You are the BentaTrack Business Analyst for Filipino sari-sari stores. "
        "You receive a pre-computed summary of sales, profit, top sellers, restock priority and slow movers. "
        "Only the most recent transactions were loaded (see meta.transactionRecordsLoaded), so do not present the totals as full-period totals; focus on advice. "
        "Give exactly 2 sentences of practical advice about what to restock, "
        "what is selling slowly, or how to improve profit. "
        "${_rulesFor('tl')}";

    try {
      final data = <Map<String, dynamic>>[
        for (final t in transactions) {...t, 'type': 'transaction'},
        for (final i in inventory) {...i, 'type': 'inventory'},
      ];
      final summary = _buildSummary(data);
      final summaryJson = jsonEncode(summary, toEncodable: (o) => o.toString());
      final cacheKey = summaryJson.hashCode.toString();

      // Same data as last time -> reuse the answer instead of spending a request.
      final cached = _insightCache[cacheKey];
      if (cached != null && DateTime.now().difference(cached.at) < _insightTtl) {
        return cached.text;
      }

      try {
        final text = await _generate(
          systemInstruction: sysInstruct,
          parts: [
            {'text': "STORE SUMMARY: $summaryJson\nGive the insight now."}
          ],
          maxOutputTokens: 300,
        );
        if (text != null) {
          final clean = _clean(text);
          _insightCache[cacheKey] = (text: clean, at: DateTime.now());
          return clean;
        }
      } catch (e) {
        debugPrint('Insight AI failed, using local insight: $e');
      }
      return _localInsight(summary);
    } catch (e) {
      debugPrint('Insight failed: $e');
      return 'Hindi makuha ang insight sa ngayon.';
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Chat assistant (store data + live market prices)
  // ---------------------------------------------------------------------------

  static String _periodLabel(String key, bool en) {
    const tl = {
      'today': 'ngayong araw',
      'yesterday': 'kahapon',
      'thisWeek': 'ngayong linggo',
      'lastWeek': 'noong nakaraang linggo',
      'last7Days': 'sa nakaraang 7 araw',
      'thisMonth': 'ngayong buwan',
      'lastMonth': 'noong nakaraang buwan',
      'last30Days': 'sa nakaraang 30 araw',
    };
    const eng = {
      'today': 'today',
      'yesterday': 'yesterday',
      'thisWeek': 'this week',
      'lastWeek': 'last week',
      'last7Days': 'in the last 7 days',
      'thisMonth': 'this month',
      'lastMonth': 'last month',
      'last30Days': 'in the last 30 days',
    };
    return (en ? eng : tl)[key] ?? key;
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Answer built from the numbers alone. Used when the AI cannot be reached
  /// (quota, no internet, ...) so common store questions still get an answer.
  static String? _localAnswer({
    required _Intent intent,
    required Map<String, dynamic> s,
    required bool en,
    String? period,
  }) {
    if (s.containsKey('note')) return null;

    try {
      switch (intent) {
        case _Intent.profit:
          {
            final by = s['salesByPeriod'] as Map;
            String line(String key) {
              final b = by[key] as Map;
              final label = _periodLabel(key, en);
              if ((b['transactions'] as num) == 0) {
                return en
                    ? 'No sales recorded $label.'
                    : 'Walang naitalang benta $label.';
              }
              return en
                  ? '${_cap(label)}, you sold ${_peso(b['sales'] as num)} with a profit of ${_peso(b['profit'] as num)} (${b['transactions']} transactions).'
                  : '${_cap(label)}, nakabenta ka ng ${_peso(b['sales'] as num)} at tubo mo ay ${_peso(b['profit'] as num)} (${b['transactions']} transaksyon).';
            }

            final key = period ?? 'today';
            var out = line(key);
            if (period == null && ((by['today'] as Map)['transactions'] as num) == 0) {
              out = '$out ${line('thisWeek')}';
            }
            return out;
          }

        case _Intent.bestSeller:
          {
            final top = (s['topSellers30Days'] as List).take(3).toList();
            if (top.isEmpty) {
              return en
                  ? "There isn't enough sales data yet to tell your best seller."
                  : 'Wala pang sapat na datos ng benta para malaman ang best seller mo.';
            }
            final list = top
                .map((e) => '${(e as Map)['name']} (${_num(e['unitsSold'] as num)} pcs)')
                .join(', ');
            return en
                ? 'Your best sellers in the last 30 days: $list.'
                : 'Best seller mo sa nakaraang 30 araw: $list.';
          }

        case _Intent.restock:
          {
            String pcs(Map e) => (e['stock'] as num) <= 0
                ? (en ? 'out of stock' : 'ubos na')
                : (en ? '${_num(e['stock'] as num)} left' : '${_num(e['stock'] as num)} na lang');
            final pri = (s['restockPriority'] as List).take(5).toList();
            if (pri.isNotEmpty) {
              final list = pri.map((e) => '${(e as Map)['name']} (${pcs(e)})').join(', ');
              return en ? 'Restock soon: $list.' : 'Mag-restock na ng: $list.';
            }
            final low = (s['lowStock'] as List).take(5).toList();
            if (low.isNotEmpty) {
              final list = low.map((e) => '${(e as Map)['name']} (${pcs(e)})').join(', ');
              return en ? 'Running low: $list.' : 'Paubos na ang: $list.';
            }
            return en
                ? 'Your stock levels look fine, nothing is running low.'
                : 'Maayos pa ang stocks mo, walang paubos na paninda.';
          }

        case _Intent.slow:
          {
            final slow = (s['slowMovers'] as List).take(3).toList();
            if (slow.isEmpty) {
              return en
                  ? 'No slow-moving items right now.'
                  : 'Walang matumal na paninda sa ngayon.';
            }
            final list = slow
                .map((e) => '${(e as Map)['name']} (${_num(e['stock'] as num)} pcs)')
                .join(', ');
            return en
                ? 'Slow movers: $list. No sales in the last 14 days.'
                : 'Matumal ang: $list. Walang benta nito sa nakaraang 14 araw.';
          }

        case _Intent.valuation:
          {
            final v = s['inventoryValuation'] as Map;
            if ((v['itemCount'] as num) == 0) {
              return en
                  ? 'There are no items in your inventory yet.'
                  : 'Wala pang paninda sa inventory mo.';
            }
            final profit = _peso(v['projectedProfit'] as num);
            final sales = _peso(v['projectedSales'] as num);
            final capital = _peso(v['capital'] as num);
            return en
                ? "If you sell all your current stock, you'd earn about $profit in profit (sales $sales, capital $capital)."
                : 'Kung mabenta lahat ng stock mo, tutubo ka ng mga $profit (benta $sales, puhunan $capital).';
          }

        case _Intent.itemInfo:
          {
            final list = (s['mentionedItems'] as List?)?.take(3).toList() ?? const [];
            if (list.isEmpty) return null;
            return list.map((e) {
              final m = e as Map;
              final name = m['name'];
              final stock = _num(m['stock'] as num);
              final price = _peso(m['sellingPrice'] as num);
              final cost = _peso(m['costPerPiece'] as num);
              final ppp = _peso(m['profitPerPiece'] as num);
              final s7 = _num(m['soldLast7Days'] as num);
              final s30 = _num(m['soldLast30Days'] as num);
              return en
                  ? '$name: $stock in stock, sells at $price (cost $cost), $ppp profit each. Sold $s7 in 7 days, $s30 in 30 days.'
                  : '$name: $stock pcs ang stock, presyo $price (puhunan $cost), $ppp ang tubo bawat isa. Nabenta: $s7 sa 7 araw, $s30 sa 30 araw.';
            }).join(' ');
          }

        case _Intent.market:
        case _Intent.tips:
        case _Intent.general:
          return null;
      }
    } catch (e) {
      debugPrint('Local answer failed: $e');
      return null;
    }
  }

  /// [businessData] is a mixed list; each item has 'type': 'transaction' or 'inventory'.
  /// [language] is 'tl' (Taglish) or 'en' (English).
  /// Returns plain text, or a string starting with "Error:" on failure
  /// (pass it to [friendlyError] for display).
  static Future<String> getAIResponse({
    required String userPrompt,
    required List<Map<String, dynamic>> businessData,
    List<Map<String, String>> history = const [],
    String language = 'tl',
  }) async {
    final lang = language == 'en' ? 'en' : 'tl';
    final en = lang == 'en';
    final q = userPrompt.trim();

    final period = _detectPeriod(q);
    final prevQ = _previousUserQuestion(history);
    // "nito/yan/it" -> look at the previous question too, unless the owner
    // clearly changed topic by naming a period ("... ngayong linggo").
    final followUp = _isFollowUp(q, prevQ) && period == null;
    final matchText = followUp ? '$prevQ $q' : q;

    Map<String, dynamic> summary;
    try {
      summary = _buildSummary(businessData, question: matchText);
    } catch (e, st) {
      debugPrint('Store summary failed: $e\n$st');
      summary = {'note': 'The store data could not be read.'};
    }

    final market = _needsMarketData(q, history);
    final hasItems = (summary['mentionedItems'] as List?)?.isNotEmpty ?? false;
    final intent = _detectIntent(q, market, hasItems);

    try {
      final focused = _focus(summary, intent);
      final summaryJson = jsonEncode(focused, toEncodable: (o) => o.toString());
      final today = DateTime.now();

      // Same question + same data -> reuse the answer (not for follow-ups or web prices).
      final cacheKey = '$lang|${_ymd(today)}|${_norm(q)}|${summaryJson.hashCode}';
      final cacheable = !followUp && !market;
      if (cacheable) {
        final hit = _chatCache[cacheKey];
        if (hit != null && DateTime.now().difference(hit.at) < _chatTtl) return hit.text;
      }

      const weekdays = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ];
      final prompt = [
        if (focused.isNotEmpty)
          'STORE SUMMARY (already computed, use as is): $summaryJson',
        'TODAY: ${_ymd(today)} (${weekdays[today.weekday - 1]})',
        'REPLY LANGUAGE: ${en ? 'English' : 'Taglish'}',
        'ANSWER GUIDE: ${_guide(intent, period)}',
        if (followUp)
          'PREVIOUS QUESTION (this is what words like nito/yan/iyon/it/that refer to; ignore older topics): $prevQ',
        'QUESTION: $q',
      ].join('\n');

      // Web-search answers ramble when old topics are in the history, so keep
      // only the previous exchange for those.
      final trimmed = _trimHistory(history, market ? 2 : 6);

      final text = await _generate(
        systemInstruction: _chatSystem(lang),
        parts: [
          {'text': prompt}
        ],
        useSearch: market,
        history: trimmed,
        temperature: 0.2,
        maxOutputTokens: 700,
      );

      if (text == null) {
        return _localAnswer(intent: intent, s: summary, en: en, period: period) ??
            (en ? 'Sorry, please try again.' : 'Pasensya na, subukan muli.');
      }

      final clean = _clean(text);
      if (cacheable) _chatCache[cacheKey] = (text: clean, at: DateTime.now());
      return clean;
    } catch (e) {
      debugPrint('Chat AI failed: $e');
      // The AI is unreachable (quota, internet...): answer from the store's own numbers.
      final local = _localAnswer(intent: intent, s: summary, en: en, period: period);
      if (local != null) return local;
      return _errorString(e);
    }
  }
}