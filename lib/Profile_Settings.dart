import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _storeNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _storedMpin;
  String _initialStoreName = "";

  bool _obscurePassword = true;

  static const Color navyBlue = Color(0xFF1E3A5F);
  static const Color darkBg = Color(0xFF18191A);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() async {
    _emailController.text = user?.email ?? "";
    if (user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (!userDoc.exists) {
        userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(user!.uid)
            .get();
      }

      if (userDoc.exists && mounted) {
        final data = userDoc.data() as Map<String, dynamic>?;
        setState(() {
          _initialStoreName = data?['storeName'] ?? data?['store_name'] ?? "";
          _storeNameController.text = _initialStoreName;
          _storedMpin = data?['mpin'] ?? data?['pin'] ?? data?['securityMpin'];
        });
      }
    } catch (e) {
      debugPrint("Error loading user data: $e");
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : navyBlue),
    );
  }

  Future<bool> _verifyMpin() async {
    try {
      DocumentSnapshot freshDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      
      if (!freshDoc.exists) {
        freshDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(user!.uid)
            .get();
      }

      if (freshDoc.exists) {
        final data = freshDoc.data() as Map<String, dynamic>?;
        _storedMpin = data?['mpin'] ?? data?['pin'] ?? data?['securityMpin'];
      }
    } catch (e) {
      debugPrint("Error refreshing MPIN: $e");
    }

    if (_storedMpin == null || _storedMpin!.isEmpty) {
      _showSnackBar("MPIN not found in database. Please set up your MPIN in Store Settings first.", isError: true);
      return false;
    }

    final TextEditingController mpinInputController = TextEditingController();
    bool isVerified = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Security MPIN Required",
              style: TextStyle(color: isDark ? Colors.white : navyBlue, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter your 4-digit MPIN to authorize your password change:"),
              const SizedBox(height: 15),
              TextField(
                controller: mpinInputController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(fontSize: 24, letterSpacing: 10, color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  counterText: "",
                  filled: true,
                  fillColor: isDark ? Colors.black26 : Colors.grey[200],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: navyBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                if (mpinInputController.text.trim() == _storedMpin!.trim()) {
                  isVerified = true;
                  Navigator.pop(context);
                } else {
                  _showSnackBar("Incorrect MPIN", isError: true);
                }
              },
              child: const Text("Verify", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    return isVerified;
  }

  Future<String?> _showPasswordPrompt() async {
    String? password;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
          title: const Text("Security Re-login"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter your CURRENT account password to finalize the password change."),
              const SizedBox(height: 15),
              TextField(
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: "Current Password",
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => password = value,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: navyBlue),
              onPressed: () => Navigator.pop(context, password),
              child: const Text("Submit", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleUpdate() async {
    if (!_formKey.currentState!.validate()) return;

    bool isChangingPassword = _passwordController.text.isNotEmpty;
    bool isChangingStoreName = _storeNameController.text.trim() != _initialStoreName.trim();

    if (!isChangingPassword && !isChangingStoreName) {
      _showSnackBar("No changes detected.");
      return;
    }

    // Only require MPIN verification if changing the password
    if (isChangingPassword) {
      bool mpinVerified = await _verifyMpin();
      if (!mpinVerified) return;

      if (_passwordController.text != _confirmPasswordController.text) {
        _showSnackBar("New passwords do not match!", isError: true);
        return;
      }

      String? currentPassword = await _showPasswordPrompt();
      if (currentPassword == null || currentPassword.isEmpty) {
        return;
      }

      setState(() => _isLoading = true);

      try {
        AuthCredential credential = EmailAuthProvider.credential(
          email: user!.email!,
          password: currentPassword,
        );
        await user!.reauthenticateWithCredential(credential);
        await user?.updatePassword(_passwordController.text.trim());
      } on FirebaseAuthException catch (e) {
        setState(() => _isLoading = false);
        if (e.code == 'wrong-password') {
          _showSnackBar("Incorrect current password.", isError: true);
        } else {
          _showSnackBar(e.message ?? "An authentication error occurred", isError: true);
        }
        return;
      }
    } else {
      setState(() => _isLoading = true);
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user?.uid).set({
        'storeName': _storeNameController.text.trim(),
      }, SetOptions(merge: true));

      setState(() {
        _initialStoreName = _storeNameController.text.trim();
      });

      if (mounted) {
        _showSnackBar("Profile updated successfully.");
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar("Update failed: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    String creationDate = user?.metadata.creationTime != null
        ? DateFormat('MMMM dd, yyyy').format(user!.metadata.creationTime!)
        : "Unknown";

    return Scaffold(
      backgroundColor: isDark ? darkBg : Colors.grey[100],
      appBar: AppBar(
        title: const Text("Profile Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: navyBlue))
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel("Store Name", isDark),
                            _buildTextField(_storeNameController, Icons.storefront, isDark),
                            const SizedBox(height: 20),
                            _buildLabel("Email Address (Not Editable)", isDark),
                            _buildTextField(_emailController, Icons.email_outlined, isDark, isReadOnly: true),
                            const SizedBox(height: 20),
                            _buildLabel("New Password (Optional)", isDark),
                            _buildTextField(_passwordController, Icons.lock_outline, isDark, isPassword: true),
                            const SizedBox(height: 20),
                            _buildLabel("Confirm New Password", isDark),
                            _buildTextField(_confirmPasswordController, Icons.lock_reset, isDark, isPassword: true),
                            const SizedBox(height: 30),
                            Center(
                              child: Text("Account created: $creationDate",
                                  style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _handleUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: navyBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: const Text("Save Changes",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, bottom: 8),
      child: Text(text,
          style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black54)),
    );
  }

  Widget _buildTextField(TextEditingController controller, IconData icon, bool isDark, {bool isPassword = false, bool isReadOnly = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      readOnly: isReadOnly,
      style: TextStyle(color: isReadOnly ? (isDark ? Colors.white38 : Colors.black38) : (isDark ? Colors.white : Colors.black)),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: navyBlue),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
        filled: true,
        fillColor: isDark ? const Color(0xFF242526) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: isReadOnly ? BorderSide.none : const BorderSide(color: navyBlue, width: 2),
        ),
      ),
    );
  }
}