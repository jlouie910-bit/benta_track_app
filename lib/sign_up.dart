import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'terms_conditions.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final AuthService _authService = AuthService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _otpErrorMessage;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // State for the checkbox
  bool _hasAcceptedTerms = false;

  final Color navyBlue = const Color(0xFF1E3A5F);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isPasswordStrong(String password) {
    // Minimum 8 characters, at least 1 uppercase letter, at least 1 number
    final hasMinLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));

    return hasMinLength && hasUppercase && hasDigit;
  }

  void _showOtpPopup({required String email, required String password}) {
    final TextEditingController otpController = TextEditingController();
    _otpErrorMessage = null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setPopupState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 30,
            right: 30,
          ),
          decoration: BoxDecoration(
            color: navyBlue,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Verify Your Account",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Enter the 6-digit code sent to your email",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),

              if (_otpErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    _otpErrorMessage!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                ),

              const SizedBox(height: 30),

              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 20,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: "",
                  hintText: "000000",
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    letterSpacing: 20,
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.cyanAccent, width: 2),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 3),
                  ),
                ),
                onChanged: (value) {
                  setPopupState(() {
                    _otpErrorMessage = null;
                  });
                },
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (otpController.text.length < 6) {
                      setPopupState(() =>
                          _otpErrorMessage = "Please enter all 6 digits.");
                      return;
                    }

                    if (_authService.verifyOtp(otpController.text)) {
                      try {
                        // 1. Authenticate with Firebase
                        dynamic result = await _authService.signUpWithEmail(email, password);
                        
                        // Extract User credential safely
                        User? user;
                        if (result is UserCredential) {
                          user = result.user;
                        } else if (result is User) {
                          user = result;
                        } else {
                          user = FirebaseAuth.instance.currentUser;
                        }

                        // 2. Write initial profile record in 'Users' collection
                        if (user != null) {
                          await FirebaseFirestore.instance
                              .collection('Users')
                              .doc(user.uid)
                              .set({
                            'email': email,
                            'setupComplete': false, // Triggers WelcomeSetupScreen
                            'createdAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        }

                        if (mounted) {
                          // Unfocus and trigger password manager save prompt
                          FocusScope.of(context).unfocus();
                          TextInput.finishAutofillContext();

                          Navigator.of(context).pop(); // Close bottom sheet
                          Navigator.of(context).pop(); // Exit SignUpScreen
                          _showSnackBar("Verified and Registered Successfully!", Colors.green);
                        }
                      } catch (e) {
                        setPopupState(() => _otpErrorMessage = e.toString());
                      }
                    } else {
                      setPopupState(() =>
                          _otpErrorMessage = "Invalid code. Try again.");
                    }
                  },
                  child: Text(
                    "VERIFY NOW",
                    style: TextStyle(
                        color: navyBlue, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignUp() async {
    if (!_hasAcceptedTerms) {
      _showSnackBar(
          "Please accept the Terms & Conditions to continue.", Colors.redAccent);
      return;
    }

    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar("Please fill in all fields.", Colors.redAccent);
      return;
    }

    // Secure password validation check
    if (!_isPasswordStrong(_passwordController.text)) {
      _showSnackBar(
        "Password must contain at least 8 characters long 1 uppercase letter, 1 lowercase letter, and 1 number.",
        Colors.redAccent,
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackBar("Passwords do not match!", Colors.redAccent);
      return;
    }

    setState(() => _isLoading = true);

    try {
      bool isSent =
          await _authService.sendOtpToEmail(_emailController.text.trim());

      if (isSent) {
        if (mounted) {
          _showOtpPopup(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
        }
      } else {
        _showSnackBar("Failed to send verification email.", Colors.redAccent);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(e.toString(), Colors.redAccent);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Center(
                child: Text("Create Account",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 35),

              // AUTOFILL GROUP FOR REGISTRATION CREDENTIALS
              AutofillGroup(
                child: Column(
                  children: [
                    _buildField(
                      _emailController,
                      "Email",
                      Icons.email,
                      false,
                      autofillHints: const [AutofillHints.email, AutofillHints.newUsername],
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),
                    _buildField(
                      _passwordController,
                      "Password",
                      Icons.lock,
                      true,
                      isObscured: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    const SizedBox(height: 8),
                    // Helpful indicator text for password requirements
                    const Text(
                      "create a strong password",
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 15),
                    _buildField(
                      _confirmPasswordController,
                      "Confirm Password",
                      Icons.lock_outline,
                      true,
                      isObscured: _obscureConfirmPassword,
                      autofillHints: const [AutofillHints.newPassword],
                      onToggle: () => setState(
                          () => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Theme(
                data: ThemeData(unselectedWidgetColor: Colors.white70),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _hasAcceptedTerms,
                  activeColor: Colors.cyanAccent,
                  checkColor: navyBlue,
                  onChanged: (value) =>
                      setState(() => _hasAcceptedTerms = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const TermsConditionsScreen()),
                      );
                    },
                    child: RichText(
                      text: const TextSpan(
                        text: "I accept the ",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                        children: [
                          TextSpan(
                            text: "Terms and Conditions",
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _hasAcceptedTerms ? Colors.white : Colors.white24,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: _isLoading ? null : _handleSignUp,
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: navyBlue, strokeWidth: 2),
                        )
                      : Text("SIGN UP",
                          style: TextStyle(
                              color: navyBlue, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Already have an account? ",
                      style: TextStyle(color: Colors.white70)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      "Login",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String hint,
    IconData icon,
    bool isPass, {
    bool isObscured = false,
    VoidCallback? onToggle,
    Iterable<String>? autofillHints,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPass ? isObscured : false,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.cyanAccent, width: 2)),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(
                  isObscured ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                ),
                onPressed: onToggle,
              )
            : null,
      ),
    );
  }
}