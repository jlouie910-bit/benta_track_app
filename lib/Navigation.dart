import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Dashboard.dart';
import 'Listahan.dart';
import 'Inventory.dart';
import 'Analytics.dart';
import 'Profile.dart';
import 'NewSalesScreen.dart';
import 'ai_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  static int _selectedIndex = 0;

  Offset _fabPosition = const Offset(20, 100);

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ListahanScreen(),
    const NewSalesScreen(),
    const InventoryScreen(),
    const AnalyticsScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _snapToEdges() {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double centerX = screenWidth / 2;

    setState(() {
      double newX = (_fabPosition.dx + 27.5) < centerX ? 15 : screenWidth - 70;
      double newY = _fabPosition.dy.clamp(50.0, screenHeight - 180.0);

      _fabPosition = Offset(newX, newY);
    });
  }

  void _showAIChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AIChatWidget(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),

          // ASSISTIVE TOUCH AI BUTTON
          Positioned(
            left: _fabPosition.dx,
            top: _fabPosition.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _fabPosition += details.delta;
                });
              },
              onPanEnd: (details) {
                _snapToEdges();
              },
              onTap: () => _showAIChat(context),
              child: Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withValues(alpha: 0.9), // Navy Blue
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFF1E3A5F),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.point_of_sale_rounded), label: 'Counter'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), label: 'Inventory'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Analytics'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

// --- AI CHAT INTERFACE ---

class AIChatWidget extends StatefulWidget {
  const AIChatWidget({super.key});

  @override
  State<AIChatWidget> createState() => _AIChatWidgetState();
}

class _AIChatWidgetState extends State<AIChatWidget> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [
    {"role": "ai", "content": "Kumusta! I'm your BentaTrack assistant. Ask me about your benta, tubo, or stocks!"}
  ];
  bool _isLoading = false;

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty) return;

    String userText = _controller.text;
    setState(() {
      _messages.add({"role": "user", "content": userText});
      _isLoading = true;
    });
    _controller.clear();

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final snapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: uid)
          .limit(10)
          .get();

      List<Map<String, dynamic>> contextData = snapshot.docs.map((doc) => doc.data()).toList();
      String aiResponse = await AIService.getAIResponse(userText, contextData);

      setState(() {
        _messages.add({"role": "ai", "content": aiResponse});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({"role": "ai", "content": "Pasensya na, check your connection and try again."});
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("BentaTrack AI Assistant",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E3A5F))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                bool isAi = _messages[index]['role'] == 'ai';
                return Align(
                  alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                    decoration: BoxDecoration(
                      color: isAi ? Colors.grey[200] : const Color(0xFF1E3A5F),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      _messages[index]['content']!,
                      style: TextStyle(color: isAi ? Colors.black87 : Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator(color: Color(0xFF6EE7B7))),
          const SizedBox(height: 10),
          TextField(
            style: const TextStyle(color: Colors.black),
            controller: _controller,
            decoration: InputDecoration(
              hintText: "Ask about your profit...",
              hintStyle: const TextStyle(color: Colors.black54),
              suffixIcon: IconButton(onPressed: _sendMessage, icon: const Icon(Icons.send, color: Color(0xFF1E3A5F))),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
              filled: true,
              fillColor: Colors.grey[100],
            ),
            onSubmitted: (_) => _sendMessage(),
          ),
        ],
      ),
    );
  }
}