import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'navigation.dart';

class WelcomeSetupScreen extends StatefulWidget {
  const WelcomeSetupScreen({super.key});

  @override
  State<WelcomeSetupScreen> createState() => _WelcomeSetupScreenState();
}

class _WelcomeSetupScreenState extends State<WelcomeSetupScreen> {
  int _currentStep = 1; // 1: Store Details, 2: MPIN Setup
  final _formKeyStep1 = GlobalKey<FormState>();
  final _formKeyStep2 = GlobalKey<FormState>();

  final TextEditingController _storeNameController = TextEditingController();
  final TextEditingController _mpinController = TextEditingController();
  final TextEditingController _confirmMpinController = TextEditingController();

  String _selectedCategory = 'Retail';
  bool _isLoading = false;

  final Color tealAccent = const Color(0xFF4FD1C5);

  final List<String> _categories = [
    'Retail',
    'Food & Beverage',
    'Services',
    'Clothing',
    'Others'
  ];

  @override
  void dispose() {
    _storeNameController.dispose();
    _mpinController.dispose();
    _confirmMpinController.dispose();
    super.dispose();
  }

  void _proceedToMpinStep() {
    if (_formKeyStep1.currentState!.validate()) {
      setState(() {
        _currentStep = 2;
      });
    }
  }

  Future<void> _completeSetup() async {
    if (!_formKeyStep2.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final storeName = _storeNameController.text.trim();
      final mpin = _mpinController.text.trim();

      // 1. Update Firebase Auth Display Name
      await user.updateDisplayName(storeName);
      await user.reload();

      // 2. Save store information and security MPIN to Firestore 'Users' collection
      await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
        'storeName': storeName,
        'category': _selectedCategory,
        'email': user.email ?? '',
        'ownerName': storeName,
        'mpin': mpin,
        'setupComplete': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      // 3. Go straight to the main app dashboard smoothly
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainNavigation()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error saving profile: $e"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18191A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: _currentStep == 1 ? _buildStep1() : _buildStep2(),
          ),
        ),
      ),
    );
  }

  // --- STEP 1: STORE NAME & CATEGORY ---
  Widget _buildStep1() {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tealAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.storefront_rounded, color: tealAccent, size: 36),
          ),
          const SizedBox(height: 24),
          const Text(
            "Welcome aboard! 👋",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Step 1 of 2: Let's configure your business profile.",
            style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 36),
          const Text(
            "Store Name",
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _storeNameController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: "e.g., Aling Nena's Sari-Sari Store",
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
              filled: true,
              fillColor: const Color(0xFF242526),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tealAccent, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.redAccent, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
              ),
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty)
                    ? "Please enter your store name"
                    : null,
          ),
          const SizedBox(height: 24),
          const Text(
            "Type of Business",
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF242526),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                isExpanded: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                dropdownColor: const Color(0xFF242526),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: tealAccent),
                items: _categories.map((String category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setState(() => _selectedCategory = newValue);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _proceedToMpinStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "NEXT STEP",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 2: SECURE MPIN SETUP ---
  Widget _buildStep2() {
    return Form(
      key: _formKeyStep2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _currentStep = 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_rounded, color: tealAccent, size: 16),
                const SizedBox(width: 4),
                Text(
                  "Back to Store Info",
                  style: TextStyle(color: tealAccent, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tealAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.lock_rounded, color: tealAccent, size: 36),
          ),
          const SizedBox(height: 24),
          const Text(
            "Secure Your Store 🔒",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Step 2 of 2: Create a 4-digit security MPIN to protect your sensitive inventory actions.",
            style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 36),
          const Text(
            "4-Digit MPIN",
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _mpinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: "",
              hintText: "••••",
              hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 8),
              filled: true,
              fillColor: const Color(0xFF242526),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tealAccent, width: 1.5),
              ),
            ),
            validator: (val) {
              if (val == null || val.length != 4 || int.tryParse(val) == null) {
                return "Must be exactly 4 digits";
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          const Text(
            "Confirm MPIN",
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _confirmMpinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: "",
              hintText: "••••",
              hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 8),
              filled: true,
              fillColor: const Color(0xFF242526),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tealAccent, width: 1.5),
              ),
            ),
            validator: (val) {
              if (val != _mpinController.text) {
                return "MPINs do not match";
              }
              return null;
            },
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _completeSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      "COMPLETE SETUP",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.8,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}