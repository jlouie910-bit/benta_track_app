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

  static const String _welcome =
      "Kumusta! Ako ang BentaTrack assistant mo. Tanungin mo ako tungkol sa benta, tubo, stocks, o presyo ng paninda sa Puregold at wholesale.";

  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;

  // Used to ignore a late reply after the chat was cleared.
  int _requestId = 0;

  // Store data cache: avoids hitting Firestore on every message.
  List<Map<String, dynamic>>? _cachedData;
  DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(seconds: 60);

  // Collection and field names - change these if yours are different.
  static const String _transactionsCollection = 'transactions';
  static const String _inventoryCollection = 'inventory';
  static const String _dateField = 'date';

  static const List<String> _starterSuggestions = [
    'Magkano ang tubo ko ngayon?',
    'Ano ang best seller ko?',
    'Ano ang dapat kong i-restock?',
    'Magkano ang Lucky Me Pancit Canton sa Puregold?',
    'Saan mura bumili ng softdrinks na paninda?',
    'Anong paninda ang matumal?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Follow-up suggestions based on the last question
  // ---------------------------------------------------------------------------
  List<String> _followUpsFor(String lastUser) {
    final s = lastUser.toLowerCase();
    final own = RegExp(r'tubo|profit|benta|sales|kita|stock|best seller|matumal|restock')
        .hasMatch(s);
    final market = RegExp(r'puregold|presyo|price|magkano|wholesale|murang|mura|saan')
        .hasMatch(s);

    // "Magkano ang tubo ko?" is about the store, not about market prices.
    if (market && !own) {
      return [
        'Magkano ang tubo ko kung ibenta ko ito?',
        'Saan pa mura bumili nito?',
        'Ano ang dapat i-restock ko?',
      ];
    }
    if (own) {
      return [
        'Ano ang best seller ko?',
        'Anong paninda ang matumal?',
        'Paano ko madadagdagan ang tubo ko?',
      ];
    }
    return [
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

  /// Newest [limit] documents of [collection] that belong to [uid].
  /// [newestFirstBy] needs a composite index (userId + that field). Firestore
  /// prints a link in the Debug Console to create it with one click. Until
  /// then (or if the field name is different) it falls back to an unordered query.
  Future<List<Map<String, dynamic>>> _fetch(
    String collection,
    String uid, {
    String? newestFirstBy,
    int limit = 150,
  }) async {
    final base = FirebaseFirestore.instance
        .collection(collection)
        .where('userId', isEqualTo: uid);

    if (newestFirstBy != null) {
      try {
        final snap =
            await base.orderBy(newestFirstBy, descending: true).limit(limit).get();
        // Documents without that field are skipped by orderBy; if nothing
        // came back, try the unordered query below.
        if (snap.docs.isNotEmpty) return _docsToMaps(snap);
      } catch (e) {
        debugPrint('Ordered query on $collection failed (missing index?): $e');
      }
    }

    try {
      final snap = await base.limit(limit).get();
      return _docsToMaps(snap);
    } catch (e) {
      debugPrint('Query on $collection failed: $e');
      return []; // a missing collection should never break the chat
    }
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
      _fetch(_transactionsCollection, uid,
          newestFirstBy: _dateField, limit: 300),
      _fetch(_inventoryCollection, uid, limit: 150),
    ]);

    final data = [
      for (final t in results[0]) {'type': 'transaction', ...t},
      for (final i in results[1]) {'type': 'inventory', ...i},
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
      _messages.add(_ChatMessage(
        'ai',
        failed ? AIService.friendlyError(reply) : reply,
        isError: failed,
      ));
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

  // ---------------------------------------------------------------------------
  // UI pieces
  // ---------------------------------------------------------------------------
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
      label: const Text('Subukan ulit',
          style: TextStyle(color: _navy, fontSize: 13)),
      backgroundColor: const Color(0xFFEAF1FA),
      side: BorderSide(color: _navy.withValues(alpha: 0.15)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: _retry,
    );
  }

  Widget _bubble(_ChatMessage m) {
    final isAi = m.role == 'ai';
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: m.content));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Na-copy ang sagot'),
                duration: Duration(seconds: 1)),
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
            m.content,
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _navy),
            ),
            SizedBox(width: 10),
            Text('Nag-iisip...',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _welcomeView() {
    return ListView(
      controller: _scroll,
      children: [
        _bubble(const _ChatMessage('ai', _welcome)),
        const SizedBox(height: 12),
        const Text('Subukan mong itanong:',
            style: TextStyle(
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
                    tooltip: 'Bagong chat',
                    onPressed: _clearChat,
                    icon: const Icon(Icons.refresh, color: Colors.black54),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
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
                hintText: 'Magtanong tungkol sa tubo, stocks, presyo...',
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