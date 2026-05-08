import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'navigation.dart';// Ensure this filename matches your dashboard file exactly

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

  final List<String> _categories = [
    'Retail',
    'Food & Beverage',
    'Services',
    'Clothing',
    'Others'
  ];

  // Inside WelcomeSetupScreen.dart

  void _completeSetup() async {
    final user = FirebaseAuth.instance.currentUser;

    if (_formKey.currentState!.validate() && user != null) {
      setState(() => _isLoading = true);

      try {
        // 1. Create the user document in Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'storeName': _storeNameController.text,
          'category': _selectedCategory,
          'setupComplete': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          // 2. Navigate to MainNavigation (the shell with the bottom bar)
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainNavigation()),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          // This captures the 'permission-denied' error you saw
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error saving profile: $e")),
          );
        }
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
                    style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 10),
                const Text(
                    "Let's set up your business profile.",
                    style: TextStyle(color: Colors.white70, fontSize: 16)
                ),
                const SizedBox(height: 40),

                const Text("Store Name", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                TextFormField(
                  controller: _storeNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Enter your shop name",
                    hintStyle: TextStyle(color: Colors.white24),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                  ),
                  validator: (value) => value!.isEmpty ? "Please enter a name" : null,
                ),

                const SizedBox(height: 30),

                const Text("Type of Store", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                Theme(
                  data: Theme.of(context).copyWith(canvasColor: const Color(0xFF242526)),
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white),
                    items: _categories.map((String category) {
                      return DropdownMenuItem(value: category, child: Text(category));
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() => _selectedCategory = newValue!);
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
                      backgroundColor: Colors.cyanAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                    )
                        : const Text("FINISH SETUP", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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