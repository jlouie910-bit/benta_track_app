import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'navigation.dart';

class WelcomeSetupScreen extends StatefulWidget {
  const WelcomeSetupScreen({super.key});

  @override
  State<WelcomeSetupScreen> createState() => _WelcomeSetupScreenState();
}

class _WelcomeSetupScreenState extends State<WelcomeSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _storeNameController = TextEditingController();
  String _selectedCategory = 'Retail';
  bool _isLoading = false;

  final Color navyBlue = const Color(0xFF1E3A5F);
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
    super.dispose();
  }

  Future<void> _completeSetup() async {
    final user = FirebaseAuth.instance.currentUser;

    if (_formKey.currentState!.validate() && user != null) {
      setState(() => _isLoading = true);

      try {
        final storeName = _storeNameController.text.trim();

        // 1. Update Firebase Auth Display Name
        await user.updateDisplayName(storeName);
        await user.reload();

        // 2. Save store information to Firestore 'Users' collection with explicit write confirmation
        await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
          'storeName': storeName,
          'category': _selectedCategory,
          'email': user.email ?? '',
          'ownerName': storeName,
          'setupComplete': true,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;

        // 3. Clear navigation stack and go directly to MainNavigation
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
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18191A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Welcome! 👋",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Let's set up your business profile.",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),

                Text(
                  "Store Name",
                  style: TextStyle(
                    color: tealAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextFormField(
                  controller: _storeNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Enter your shop name", 
                    hintStyle: const TextStyle(color: Colors.white24),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: tealAccent),
                    ),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? "Please enter a name"
                          : null,
                ),

                const SizedBox(height: 30),

                Text(
                  "Type of Store",
                  style: TextStyle(
                    color: tealAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Theme(
                  data: Theme.of(context).copyWith(
                    canvasColor: const Color(0xFF242526),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white),
                    dropdownColor: const Color(0xFF242526),
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

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _completeSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tealAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "FINISH SETUP",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}