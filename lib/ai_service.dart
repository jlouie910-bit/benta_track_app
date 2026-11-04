import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  // Insight cache: same data -> same answer, no new request.
  static final Map<String, ({String text, DateTime at})> _insightCache = {};
  static const Duration _insightTtl = Duration(hours: 6);

  // ---------------------------------------------------------------------------
  // FIELD NAMES - edit these to match your Firestore documents.
  // The first key found in a document wins.
  // ---------------------------------------------------------------------------
  static const _dateKeys = ['date', 'timestamp', 'createdAt', 'time', 'soldAt'];
  static const _revenueKeys = [
    'total', 'totalAmount', 'amount', 'totalSales', 'sales', 'revenue'
  ];
  static const _profitKeys = ['profit', 'totalProfit', 'tubo'];
  static const _nameKeys = ['itemName', 'name', 'productName', 'item', 'product'];
  static const _qtyKeys = ['quantity', 'qty', 'quantitySold', 'count'];
  static const _stockKeys = ['stock', 'quantity', 'qty', 'currentStock', 'inStock'];
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
      _blockedUntil =
          DateTime.now().add(Duration(minutes: daily ? 30 : 1));
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
  static String _errorString(Object e) => e is AIException
      ? 'Error:${e.kind}|${e.detail}'
      : 'Error:OTHER|$e';

  /// Turns an "Error:KIND|detail" reply into a message for the store owner.
  static String friendlyError(String reply) {
    final m = RegExp(r'^Error:\s*([A-Z]+)').firstMatch(reply);
    switch (m?.group(1)) {
      case 'QUOTA':
        return 'Naubos na muna ang free limit ng AI. Subukan ulit mamaya.';
      case 'KEY':
        return 'May problema sa API key ng AI. Pakicheck ang settings.';
      case 'NET':
        return 'Walang internet. Pakicheck ang connection mo at subukan ulit.';
      case 'TIMEOUT':
        return 'Natagalan ang sagot ng AI. Subukan ulit.';
      case 'SERVER':
        return 'Busy ang AI ngayon. Subukan ulit sa ilang sandali.';
      default:
        return 'Pasensya na, may problema sa AI. Subukan ulit mamaya.';
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
      .trim();

  // ---------------------------------------------------------------------------
  // Market-data (web search) trigger
  // ---------------------------------------------------------------------------
  static final RegExp _marketRe = RegExp(
    r'\b(puregold|sm|s&r|landers|wholesale|supplier|palengke|divisoria|presyo|'
    r'magkano|price|srp|murang|mura|bilihan|bulk|promo|market|trend|tumaas|bumaba|'
    r'saan\s+bumili|saan\s+kumuha)\b',
    caseSensitive: false,
  );

  // Names of places/sources: clearly about outside prices.
  static final RegExp _explicitMarketRe = RegExp(
    r'\b(puregold|sm|s&r|landers|wholesale|supplier|palengke|divisoria|bilihan|'
    r'saan\s+bumili|saan\s+kumuha|saan\s+pa)\b',
    caseSensitive: false,
  );

  // Questions about the store's own numbers.
  static final RegExp _ownDataRe = RegExp(
    r'\b(tubo|profit|benta|sales|kita|stock|stocks|inventory|best\s*seller|'
    r'matumal|restock|i-restock|natitira|ubos)\b',
    caseSensitive: false,
  );

  // "nito", "yan", "sa kanila" -> refers to the previous message.
  static final RegExp _pronounRe = RegExp(
    r'\b(nito|niyan|niyon|yan|iyan|iyon|yun|dito|diyan|kanila|din|pa)\b',
    caseSensitive: false,
  );

  static bool _needsMarketData(String q, List<Map<String, String>> history) {
    final explicit = _explicitMarketRe.hasMatch(q);
    final market = _marketRe.hasMatch(q);
    final own = _ownDataRe.hasMatch(q);

    // "Magkano ang tubo ko?" matches 'magkano' but is about the store's data.
    if (market && !(own && !explicit)) return true;

    // Follow-up like "Saan pa mura bumili nito?" after a price question.
    if (_pronounRe.hasMatch(q) && !own) {
      for (final h in history.reversed) {
        if (h['role'] == 'user') {
          return _marketRe.hasMatch(h['content'] ?? '') &&
              !_ownDataRe.hasMatch(h['content'] ?? '');
        }
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Store summary: numbers are computed here, the model only explains them.
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
      if (v is String) {
        final d = DateTime.tryParse(v);
        if (d != null) return d.isUtc ? d.toLocal() : d;
      }
    }
    return null;
  }

  static double _r(double v) => (v * 100).round() / 100;

  static Map<String, dynamic> _accJson(_Acc a) => {
        'sales': _r(a.sales),
        'profit': _r(a.profit),
        'transactions': a.count,
      };

  static Map<String, dynamic> _buildSummary(List<Map<String, dynamic>> data) {
    final txs = data.where((d) => d['type'] == 'transaction').toList();
    final inv = data.where((d) => d['type'] == 'inventory').toList();

    if (txs.isEmpty && inv.isEmpty) {
      return {'note': 'Walang nakitang transactions o inventory data.'};
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final start7 = todayStart.subtract(const Duration(days: 6));
    final start14 = todayStart.subtract(const Duration(days: 13));
    final start30 = todayStart.subtract(const Duration(days: 29));

    final today = _Acc(), week = _Acc(), month = _Acc();
    final units = <String, double>{};
    final salesBy = <String, double>{};
    final display = <String, String>{};
    final lastSold = <String, DateTime>{};
    DateTime? oldest;

    for (final t in txs) {
      final date = _dateOf(t);
      if (date == null) continue;
      if (oldest == null || date.isBefore(oldest)) oldest = date;

      // A transaction is either one sale line or has an 'items' list.
      final lines = t['items'] is List
          ? (t['items'] as List).whereType<Map>().toList()
          : <Map>[t];

      double lineRevSum = 0, lineProfitSum = 0;
      final lineData = <({String? name, double qty, double rev})>[];

      for (final l in lines) {
        final qty = _numOf(l, _qtyKeys) ?? 1;
        final price = _numOf(l, _priceKeys);
        final cost = _numOf(l, _costKeys);
        final rev = _numOf(l, _revenueKeys) ?? (price != null ? price * qty : 0.0);
        final profit = _numOf(l, _profitKeys) ??
            ((price != null && cost != null) ? (price - cost) * qty : 0.0);
        lineRevSum += rev;
        lineProfitSum += profit;
        lineData.add((name: _strOf(l, _nameKeys), qty: qty, rev: rev));
      }

      final revenue = _numOf(t, _revenueKeys) ?? lineRevSum;
      final profit = _numOf(t, _profitKeys) ?? lineProfitSum;

      void add(_Acc a) {
        a.sales += revenue;
        a.profit += profit;
        a.count++;
      }

      if (!date.isBefore(todayStart)) add(today);
      if (!date.isBefore(start7)) add(week);
      if (!date.isBefore(start30)) add(month);

      for (final l in lineData) {
        final name = l.name;
        if (name == null) continue;
        final k = name.toLowerCase();
        display.putIfAbsent(k, () => name);
        final prev = lastSold[k];
        if (prev == null || date.isAfter(prev)) lastSold[k] = date;
        if (!date.isBefore(start30)) {
          units[k] = (units[k] ?? 0) + l.qty;
          salesBy[k] = (salesBy[k] ?? 0) + l.rev;
        }
      }
    }

    final top = units.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topSellers = [
      for (final e in top.take(5))
        {
          'name': display[e.key],
          'unitsSold': _r(e.value),
          'sales': _r(salesBy[e.key] ?? 0),
        }
    ];

    final lowStock = <Map<String, dynamic>>[];
    final slow = <Map<String, dynamic>>[];
    final invList = <Map<String, dynamic>>[];

    for (final i in inv) {
      final name = _strOf(i, _nameKeys);
      if (name == null) continue;
      final stock = _numOf(i, _stockKeys);
      final reorder = _numOf(i, _reorderKeys) ?? 5;
      final sold = lastSold[name.toLowerCase()];

      if (invList.length < 80) {
        invList.add({
          'name': name,
          'stock': stock,
          'price': _numOf(i, _priceKeys),
          'cost': _numOf(i, _costKeys),
        });
      }
      if (stock != null && stock <= reorder) {
        lowStock.add({'name': name, 'stock': stock, 'reorderLevel': reorder});
      }
      if ((stock ?? 0) > 0 && (sold == null || sold.isBefore(start14))) {
        slow.add({
          'name': name,
          'stock': stock,
          'lastSold': sold?.toIso8601String().substring(0, 10) ?? 'walang record',
        });
      }
    }
    lowStock.sort((a, b) => (a['stock'] as double).compareTo(b['stock'] as double));

    return {
      'today': _accJson(today),
      'last7Days': _accJson(week),
      'last30Days': _accJson(month),
      'topSellers30Days': topSellers,
      'lowStock': lowStock.take(10).toList(),
      'slowMovers14Days': slow.take(10).toList(),
      'transactionRecordsLoaded': txs.length,
      'transactionHistoryDays':
          oldest == null ? 0 : now.difference(oldest).inDays + 1,
      'inventoryItemCount': inv.length,
      'inventory': invList,
    };
  }

  // ---------------------------------------------------------------------------
  // Shared rules appended to every system prompt
  // ---------------------------------------------------------------------------
  static const String _rules =
      "RULES: Answer ONLY what was asked, in Taglish, short and direct. "
      "Never invent prices, stock numbers, or sales figures. "
      "For the store's own data, use ONLY the provided summary and use its numbers as they are; never recompute them. "
      "For market prices (Puregold, S&R, Landers, wholesalers, palengke), use web search results only, "
      "give a price range in PHP, and say the price may differ per branch or date. "
      "If you cannot find a reliable price, say 'Hindi ako sigurado sa presyo, pakicheck sa tindahan.' "
      "If a question has nothing to do with retail, business, money, or the store, politely say you can only help with store and business topics. "
      "Do NOT use asterisks, bold, bullet points, or any markdown. Plain text paragraphs only.";

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
      return text == null ? null : {'rawResult': text};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Business insight (dashboard / analytics)
  // ---------------------------------------------------------------------------
  static String _peso(num v) {
    final s = v.round().toString();
    return 'P${s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';
  }

  static String _names(List items, {int take = 2}) => items
      .take(take)
      .map((e) => (e is Map ? e['name'] : e).toString())
      .join(' at ');

  /// Insight built from the numbers alone, used when the AI is unavailable.
  static String _localInsight(Map<String, dynamic> s) {
    if (s.containsKey('note')) {
      return 'Wala pang sapat na data. Magdagdag muna ng benta at paninda para magkaroon ng insight.';
    }
    final low = (s['lowStock'] as List?) ?? const [];
    final slow = (s['slowMovers14Days'] as List?) ?? const [];
    final top = (s['topSellers30Days'] as List?) ?? const [];
    final month = s['last30Days'] as Map?;

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
    const sysInstruct =
        "You are the BentaTrack Business Analyst for Filipino sari-sari stores. "
        "You receive a pre-computed summary of sales, profit, top sellers, low stock and slow movers. "
        "Give exactly 2 sentences of practical advice about what to restock, "
        "what is selling slowly, or how to improve profit. "
        "$_rules";

    try {
      final data = <Map<String, dynamic>>[
        for (final t in transactions) {'type': 'transaction', ...t},
        for (final i in inventory) {'type': 'inventory', ...i},
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
  /// [businessData] is a mixed list; each item has 'type': 'transaction' or 'inventory'.
  /// Returns plain text, or a string starting with "Error:" on failure
  /// (pass it to [friendlyError] for display).
  static Future<String> getAIResponse({
    required String userPrompt,
    required List<Map<String, dynamic>> businessData,
    List<Map<String, String>> history = const [],
  }) async {
    const sysInstruct =
        "You are BentaTrack AI, an assistant for sari-sari store owners in the Philippines. "
        "You know retailing, markup, profit computation, and where to buy stock cheaply "
        "(Puregold, S&R, Landers, local wholesalers, palengke, Divisoria). "
        "You receive a pre-computed STORE SUMMARY (today, last 7 days, last 30 days, top sellers, low stock, slow movers, inventory list). "
        "Slow movers and top sellers only cover the transaction history available (see transactionHistoryDays); mention that if the history is short. "
        "Do not show raw JSON or step-by-step filtering. "
        "Start with the direct answer (the number or the fact) in the first sentence. "
        "Keep it to 2-4 short sentences unless the owner asks for details. "
        "Use the peso sign and plain numbers like P1,250. "
        "If store data is empty or missing what is needed, say what is missing instead of guessing. "
        "Remember earlier messages in this chat when the owner says 'yan', 'iyon', 'nito', or 'sa kanila'. "
        "$_rules";

    try {
      final useSearch = _needsMarketData(userPrompt, history);
      final summary = jsonEncode(_buildSummary(businessData),
          toEncodable: (o) => o.toString());
      final prompt = "STORE SUMMARY (already computed, use as is): $summary\n"
          "TODAY: ${DateTime.now().toIso8601String().substring(0, 10)}\n"
          "QUESTION: $userPrompt";

      final text = await _generate(
        systemInstruction: sysInstruct,
        parts: [
          {'text': prompt}
        ],
        useSearch: useSearch,
        history: history,
      );
      return text == null ? "Pasensya na, subukan muli." : _clean(text);
    } catch (e) {
      return _errorString(e);
    }
  }
}