import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Required for database check
import 'auth_service.dart';
import 'WelcomeSetupScreen.dart';
import 'navigation.dart'; // Ensure you import your main navigation or dashboard

class OTPScreen extends StatefulWidget {
  final String email;
  final String password;

  const OTPScreen({
    super.key,
    required this.email,
    required this.password,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _otpController = TextEditingController();

  final Color fbDarkBg = const Color(0xFF18191A);
  final Color navyBlue = const Color(0xFF1E3A5F);

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleVerifyAndSignUp() async {
    if (_isLoading) return;

    if (_otpController.text.length < 6) {
      setState(() => _errorMessage = "Please enter the full 6-digit code.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Verify the OTP local logic
      bool isValid = _authService.verifyOtp(_otpController.text);

      if (isValid) {
        // 2. Perform the actual Firebase Sign Up
        final userCredential = await _authService.signUpWithEmail(widget.email, widget.password);
        final String uid = userCredential.user!.uid;

        // 3. Check Firestore to see if this UID already has a setup profile
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();

        if (mounted) {
          _showSnackBar("Verification successful!", Colors.green);

          // 4. Conditional Navigation
          if (!userDoc.exists) {
            // NEW USER: No document found, go to Setup
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const WelcomeSetupScreen()),
                  (route) => false,
            );
          } else {
            // RETURNING USER: Document exists, skip setup
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainNavigation()),
                  (route) => false,
            );
          }
        }
      } else {
        setState(() => _errorMessage = "Invalid OTP code. Please try again.");
      }
    } catch (e) {
      setState(() => _errorMessage = "Error: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? fbDarkBg : const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.mark_email_read_outlined, size: 80, color: Colors.cyanAccent),
            const SizedBox(height: 30),
            const Text(
                "Verification",
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 10),
            Text(
                "Sent to ${widget.email}",
                style: const TextStyle(color: Colors.white70)
            ),
            const SizedBox(height: 40),

            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              autofocus: true,
              onChanged: (value) {
                if (value.length == 6) _handleVerifyAndSignUp();
              },
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 20
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: "",
                hintText: "000000",
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.1),
                    letterSpacing: 20
                ),
                enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)
                ),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.cyanAccent, width: 3)
                ),
              ),
            ),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)
                ),
              ),

            const SizedBox(height: 50),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isLoading ? null : _handleVerifyAndSignUp,
                child: _isLoading
                    ? CircularProgressIndicator(color: navyBlue)
                    : Text(
                    "VERIFY & SIGN UP",
                    style: TextStyle(color: navyBlue, fontWeight: FontWeight.bold)
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}