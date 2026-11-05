import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ai_service.dart';

const Color _navy = Color(0xFF1E3A5F);
const Color _mint = Color(0xFF6EE7B7);

class _ChatMessage {
  final String role; // 'user' or 'ai'
  // For error bubbles this is the raw "Error:KIND|..." text. It is turned into
  // a friendly message when drawn, so it follows the selected language.
  final String content;
  final bool isError;
  const _ChatMessage(this.role, this.content, {this.isError = false});
}

class AIChatWidget extends StatefulWidget {
  const AIChatWidget({super.key});

  @override
  State<AIChatWidget> createState() => _AIChatWidgetState();
}

class _AIChatWidgetState extends State<AIChatWidget> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  // 'tl' = Taglish, 'en' = English. Static, so the choice is kept when the
  // chat is closed and opened again (until the app is restarted).
  static String _savedLang = 'tl';
  String _lang = _savedLang;
  bool get _en => _lang == 'en';
  String _t(String tl, String en) => _en ? en : tl;

  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;

  // Used to ignore a late reply after the chat was cleared.
  int _requestId = 0;

  // Store data cache: avoids hitting Firestore on every message.
  List<Map<String, dynamic>>? _cachedData;
  DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(seconds: 60);

  // Names must match Firestore exactly (case-sensitive) and Analytics.dart.
  static const String _transactionsCollection = 'transactions';
  static const String _inventoryCollection = 'Inventory';
  static const String _dateField = 'timestamp';

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Texts (Tagalog / English)
  // ---------------------------------------------------------------------------
  String get _welcome => _t(
        'Kumusta! Ako ang BentaTrack assistant mo. Tanungin mo ako tungkol sa benta, tubo, stocks, o presyo ng paninda sa Puregold at wholesale.',
        "Hi! I'm your BentaTrack assistant. Ask me about your sales, profit, stocks, or product prices at Puregold and wholesale.",
      );

  List<String> get _starterSuggestions => _en
      ? const [
          'How much is my profit today?',
          'What is my best seller?',
          'What should I restock?',
          'How much is Lucky Me Pancit Canton at Puregold?',
          'Where can I buy soft drinks cheaply for my store?',
          'Which products are slow-moving?',
        ]
      : const [
          'Magkano ang tubo ko ngayon?',
          'Ano ang best seller ko?',
          'Ano ang dapat kong i-restock?',
          'Magkano ang Lucky Me Pancit Canton sa Puregold?',
          'Saan mura bumili ng softdrinks na paninda?',
          'Anong paninda ang matumal?',
        ];

  // ---------------------------------------------------------------------------
  // Follow-up suggestions based on the last question
  // ---------------------------------------------------------------------------
  static final RegExp _ownRe = RegExp(
      r'tubo|tutubuin|profit|benta|sales|kita|earn|income|revenue|stock|best\s*seller|matumal|slow|restock|inventory',
      caseSensitive: false);
  static final RegExp _marketRe = RegExp(
      r'puregold|presyo|price|magkano|how\s+much|wholesale|murang|mura|saan|cheap|where',
      caseSensitive: false);

  List<String> _followUpsFor(String lastUser) {
    final own = _ownRe.hasMatch(lastUser);
    final market = _marketRe.hasMatch(lastUser);

    // "Magkano ang tubo ko?" is about the store, not about market prices.
    if (market && !own) {
      return _en
          ? const [
              'How much will I earn if I sell this?',
              'Where else is it cheaper?',
              'What should I restock?',
            ]
          : const [
              'Magkano ang tubo ko kung ibenta ko ito?',
              'Saan pa mura bumili nito?',
              'Ano ang dapat i-restock ko?',
            ];
    }
    if (own) {
      return _en
          ? const [
              'What is my best seller?',
              'Which products are slow-moving?',
              'How can I increase my profit?',
            ]
          : const [
              'Ano ang best seller ko?',
              'Anong paninda ang matumal?',
              'Paano ko madadagdagan ang tubo ko?',
            ];
    }
    return _en
        ? const [
            'How much is my profit today?',
            'What should I restock?',
            'Give me tips to grow my sales',
          ]
        : const [
            'Magkano ang tubo ko ngayon?',
            'Ano ang dapat kong i-restock?',
            'Magbigay ng tips para lumaki ang benta',
          ];
  }

  // ---------------------------------------------------------------------------
  // Firestore helpers
  // ---------------------------------------------------------------------------
  dynamic _sanitize(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), _sanitize(val)));
    if (v is List) return v.map(_sanitize).toList();
    return v;
  }

  List<Map<String, dynamic>> _docsToMaps(QuerySnapshot<Map<String, dynamic>> snap) {
    return snap.docs
        .map((d) => Map<String, dynamic>.from(_sanitize(d.data()) as Map))
        .toList();
  }

  /// Recent transactions of this user, newest first. Same query shape as the
  /// Analytics screen (userId + timestamp, ordered by timestamp), so it uses
  /// the index that already exists. Covers the previous month too, because
  /// the AI compares "this month" with "last month".
  Future<List<Map<String, dynamic>>> _fetchTransactions(String uid) async {
    final base = FirebaseFirestore.instance
        .collection(_transactionsCollection)
        .where('userId', isEqualTo: uid);

    final now = DateTime.now();
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);
    final thirtyFiveDaysAgo = DateTime(now.year, now.month, now.day - 35);
    final from =
        prevMonthStart.isBefore(thirtyFiveDaysAgo) ? prevMonthStart : thirtyFiveDaysAgo;

    try {
      final snap = await base
          .where(_dateField, isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .orderBy(_dateField, descending: true)
          .limit(600)
          .get();
      return _docsToMaps(snap);
    } catch (e) {
      debugPrint('Ordered transactions query failed (missing index?): $e');
    }

    try {
      final snap = await base.limit(300).get();
      return _docsToMaps(snap);
    } catch (e) {
      debugPrint('Transactions query failed: $e');
      return []; // a missing collection should never break the chat
    }
  }

  Future<List<Map<String, dynamic>>> _fetchInventory(String uid) async {
    Future<List<Map<String, dynamic>>> read(String collection) async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(collection)
            .where('userId', isEqualTo: uid)
            .limit(400)
            .get();
        return _docsToMaps(snap);
      } catch (e) {
        debugPrint('Query on $collection failed: $e');
        return [];
      }
    }

    final items = await read(_inventoryCollection);
    if (items.isNotEmpty) return items;
    // Safety net in case an older build wrote to a lower-case collection.
    return read(_inventoryCollection.toLowerCase());
  }

  Future<List<Map<String, dynamic>>> _loadStoreData({bool force = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final cached = _cachedData;
    final at = _cachedAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheTtl) {
      return cached;
    }

    final results = await Future.wait([
      _fetchTransactions(uid),
      _fetchInventory(uid),
    ]);

    final data = [
      for (final t in results[0]) {...t, 'type': 'transaction'},
      for (final i in results[1]) {...i, 'type': 'inventory'},
    ];

    _cachedData = data;
    _cachedAt = DateTime.now();
    return data;
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------
  List<Map<String, String>> _buildHistory() {
    // Skip errors, and skip a user message whose reply failed, so the model
    // never sees two user turns in a row.
    final turns = <_ChatMessage>[];
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.isError) continue;
      if (m.role == 'user' &&
          i + 1 < _messages.length &&
          _messages[i + 1].isError) {
        continue;
      }
      turns.add(m);
    }

    final recent = turns.length > 8 ? turns.sublist(turns.length - 8) : turns;
    // Gemini requires the first turn to be from the user.
    int start = 0;
    while (start < recent.length && recent[start].role == 'ai') {
      start++;
    }
    return [
      for (final m in recent.sublist(start)) {'role': m.role, 'content': m.content}
    ];
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _isLoading) return;

    final history = _buildHistory();
    final myRequest = ++_requestId;
    final lang = _lang; // the reply follows the language chosen when asking

    setState(() {
      _messages.add(_ChatMessage('user', text));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    String reply;
    try {
      final data = await _loadStoreData();
      reply = await AIService.getAIResponse(
        userPrompt: text,
        businessData: data,
        history: history,
        language: lang,
      );
    } catch (e) {
      debugPrint('Chat send failed: $e');
      reply = 'Error:NET|$e';
    }

    // The chat was closed or cleared while waiting.
    if (!mounted || myRequest != _requestId) return;

    final failed = reply.startsWith('Error:');
    if (failed) debugPrint(reply); // full reason shows in the Debug Console

    setState(() {
      _messages.add(_ChatMessage('ai', reply, isError: failed));
      _isLoading = false;
    });
    _scrollToBottom();
  }

  /// Removes the failed exchange and asks the same question again.
  void _retry() {
    if (_isLoading || _messages.length < 2) return;
    final last = _messages.last;
    if (!last.isError) return;

    String? question;
    for (var i = _messages.length - 2; i >= 0; i--) {
      if (_messages[i].role == 'user') {
        question = _messages[i].content;
        _messages.removeRange(i, _messages.length);
        break;
      }
    }
    if (question == null) return;
    setState(() {});
    _send(question);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    _requestId++; // ignore any reply still on its way
    _cachedData = null; // "new chat" also refreshes the store data
    _cachedAt = null;
    setState(() {
      _messages.clear();
      _isLoading = false;
    });
  }

  void _setLanguage(String code) {
    if (code == _lang) return;
    setState(() {
      _lang = code;
      _savedLang = code;
    });
  }

  // ---------------------------------------------------------------------------
  // UI pieces
  // ---------------------------------------------------------------------------
  Widget _languageRow() {
    Widget pill(String code, String label) {
      final selected = _lang == code;
      return GestureDetector(
        onTap: () => _setLanguage(code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? _navy : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _navy,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.translate, size: 16, color: Colors.black45),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _t('Wika ng sagot', 'Reply language'),
              style: const TextStyle(color: Colors.black54, fontSize: 12.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FA),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [pill('tl', 'Tagalog'), pill('en', 'English')],
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(color: _navy, fontSize: 13)),
      backgroundColor: const Color(0xFFEAF1FA),
      side: BorderSide(color: _navy.withValues(alpha: 0.15)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () => _send(text),
    );
  }

  Widget _retryChip() {
    return ActionChip(
      avatar: const Icon(Icons.refresh, size: 16, color: _navy),
      label: Text(_t('Subukan ulit', 'Try again'),
          style: const TextStyle(color: _navy, fontSize: 13)),
      backgroundColor: const Color(0xFFEAF1FA),
      side: BorderSide(color: _navy.withValues(alpha: 0.15)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: _retry,
    );
  }

  Widget _bubble(_ChatMessage m) {
    final isAi = m.role == 'ai';
    final shown =
        m.isError ? AIService.friendlyError(m.content, language: _lang) : m.content;

    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: shown));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(_t('Na-copy ang sagot', 'Copied')),
                duration: const Duration(seconds: 1)),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isAi
                ? (m.isError ? const Color(0xFFFDECEC) : Colors.grey[200])
                : _navy,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isAi ? 4 : 16),
              bottomRight: Radius.circular(isAi ? 16 : 4),
            ),
          ),
          child: Text(
            shown,
            style: TextStyle(
                color: isAi ? Colors.black87 : Colors.white,
                fontSize: 14.5,
                height: 1.35),
          ),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _navy),
            ),
            const SizedBox(width: 10),
            Text(_t('Nag-iisip...', 'Thinking...'),
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _welcomeView() {
    return ListView(
      controller: _scroll,
      children: [
        _bubble(_ChatMessage('ai', _welcome)),
        const SizedBox(height: 12),
        Text(_t('Subukan mong itanong:', 'Try asking:'),
            style: const TextStyle(
                color: Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in _starterSuggestions) _suggestionChip(s)],
        ),
      ],
    );
  }

  Widget _conversationView() {
    final last = _messages.isNotEmpty ? _messages.last : null;
    final lastIsAi = last != null && last.role == 'ai';
    final lastIsError = last != null && last.isError;

    String lastUser = '';
    for (final m in _messages.reversed) {
      if (m.role == 'user') {
        lastUser = m.content;
        break;
      }
    }

    return ListView(
      controller: _scroll,
      children: [
        for (final m in _messages) _bubble(m),
        if (_isLoading) _typingBubble(),
        if (!_isLoading && lastIsAi) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: lastIsError
                ? [_retryChip()]
                : [for (final s in _followUpsFor(lastUser)) _suggestionChip(s)],
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: height * 0.78,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: _navy,
                  child: Icon(Icons.auto_awesome, color: _mint, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('BentaTrack AI Assistant',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: _navy)),
                ),
                if (_messages.isNotEmpty)
                  IconButton(
                    tooltip: _t('Bagong chat', 'New chat'),
                    onPressed: _clearChat,
                    icon: const Icon(Icons.refresh, color: Colors.black54),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            _languageRow(),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: _messages.isEmpty ? _welcomeView() : _conversationView(),
            ),
            const SizedBox(height: 8),
            TextField(
              style: const TextStyle(color: Colors.black),
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: _t('Magtanong tungkol sa tubo, stocks, presyo...',
                    'Ask about profit, stocks, prices...'),
                hintStyle: const TextStyle(color: Colors.black54),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                suffixIcon: IconButton(
                  onPressed: _isLoading ? null : () => _send(),
                  icon: Icon(Icons.send,
                      color: _isLoading ? Colors.grey : _navy),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onSubmitted: (_) => _send(),
            ),
          ],
        ),
      ),
    );
  }
}