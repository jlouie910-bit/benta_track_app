import 'package:flutter/material.dart';
import 'Dashboard.dart';
import 'Listahan.dart';
import 'Inventory.dart';
import 'Analytics.dart';
import 'Profile.dart';
import 'NewSalesScreen.dart';
import 'ai_chat_widget.dart';

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
                  color: const Color(0xFF1E3A5F).withOpacity(0.9), // Navy Blue
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
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