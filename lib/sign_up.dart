import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'terms_conditions.dart';
import 'WelcomeSetupScreen.dart';
import 'phone_auth_helper.dart';

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
  final _mobileController = TextEditingController();

  bool _isLoading = false;
  String? _otpErrorMessage;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // State for the checkbox
  bool _hasAcceptedTerms = false;

  // true = sign up with mobile number, false = email
  bool _usePhone = true;

  final Color navyBlue = const Color(0xFF1E3A5F);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  bool _isPasswordStrong(String password) {
    final hasMinLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));

    return hasMinLength && hasUppercase && hasDigit;
  }

  // ---------------------------------------------------------------------------
  // DUPLICATE ACCOUNT HANDLING
  // ---------------------------------------------------------------------------

  /// Checks the 'EmailIndex' collection (document ID = lowercase email).
  /// Only a single email can be looked up at a time and no other user data
  /// is exposed.
  Future<bool> _emailAlreadyExists(String email) async {
    final doc = await FirebaseFirestore.instance
        .collection('EmailIndex')
        .doc(email.toLowerCase())
        .get();
    return doc.exists;
  }

  /// Warning popup shown when the email / number is already registered.
  void _showAccountExistsDialog(String identifier, {bool isPhone = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: navyBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Account Already Exists",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          isPhone
              ? "The mobile number $identifier is already registered. Would you like to log in instead or use a different number?"
              : "The email $identifier is already registered. Would you like to log in instead or use a different email?",
          style: const TextStyle(color: Colors.white70),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // close dialog
              if (isPhone) {
                _mobileController.clear();
              } else {
                _emailController.clear();
              }
            },
            child: Text(
              isPhone ? "Use Different Number" : "Use Different Email",
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop(); // close dialog
              Navigator.of(context).pop(); // back to login screen
            },
            child: Text(
              "Go to Login",
              style: TextStyle(color: navyBlue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EMAIL OTP SHEET
  // ---------------------------------------------------------------------------

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
                        dynamic result =
                            await _authService.signUpWithEmail(email, password);

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
                            // Stored lowercase so the duplicate check matches
                            'email': email.toLowerCase(),
                            'setupComplete': false, // Triggers WelcomeSetupScreen
                            'createdAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                          // 3. Register the email in the lookup index
                          await FirebaseFirestore.instance
                              .collection('EmailIndex')
                              .doc(email.toLowerCase())
                              .set({'uid': user.uid});
                        }

                        if (mounted) {
                          // Unfocus and trigger password manager save prompt
                          FocusScope.of(context).unfocus();
                          TextInput.finishAutofillContext();

                          Navigator.of(context).pop(); // Close bottom sheet
                          Navigator.of(context).pop(); // Exit SignUpScreen
                          _showSnackBar("Verified and Registered Successfully!",
                              Colors.green);
                        }
                      } on FirebaseAuthException catch (e) {
                        if (e.code == 'email-already-in-use') {
                          // Safety net: account exists in Auth even if the
                          // Firestore check didn't catch it
                          if (mounted) {
                            Navigator.of(context).pop(); // close the OTP sheet
                            _showAccountExistsDialog(email);
                          }
                        } else {
                          setPopupState(
                              () => _otpErrorMessage = e.message ?? e.toString());
                        }
                      } catch (e) {
                        // Fallback in case AuthService wraps the exception
                        if (e.toString().contains('email-already-in-use')) {
                          if (mounted) {
                            Navigator.of(context).pop();
                            _showAccountExistsDialog(email);
                          }
                        } else {
                          setPopupState(() => _otpErrorMessage = e.toString());
                        }
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

  // ---------------------------------------------------------------------------
  // SIGN UP HANDLERS
  // ---------------------------------------------------------------------------

  Future<void> _handleSignUp() async {
    if (!_hasAcceptedTerms) {
      _showSnackBar(
          "Please accept the Terms & Conditions to continue.", Colors.redAccent);
      return;
    }

    // Mobile number sign-up uses the SMS flow
    if (_usePhone) {
      await _handlePhoneSignUp();
      return;
    }

    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar("Please fill in all fields.", Colors.redAccent);
      return;
    }

    // Secure password validation check
    if (!_isPasswordStrong(_passwordController.text)) {
      _showSnackBar(
        "Password must be at least 8 characters long with 1 uppercase letter and 1 number.",
        Colors.redAccent,
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackBar("Passwords do not match!", Colors.redAccent);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();

      // Duplicate check BEFORE sending the OTP
      final exists = await _emailAlreadyExists(email);
      if (exists) {
        if (mounted) _showAccountExistsDialog(email);
        return; // finally block resets _isLoading
      }

      bool isSent = await _authService.sendOtpToEmail(email);

      if (isSent) {
        if (mounted) {
          _showOtpPopup(
            email: email,
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

  Future<void> _handlePhoneSignUp() async {
    final phone = PhoneAuthHelper.normalizePhNumber(_mobileController.text);
    if (phone == null) {
      _showSnackBar(
          "Enter a valid mobile number, e.g. 917 123 4567.", Colors.redAccent);
      return;
    }

    FocusScope.of(context).unfocus();

    // Sends the SMS, shows the OTP sheet, returns the signed-in user
    final credential = await PhoneAuthHelper.verifyWithSheet(context, phone);
    final user = credential?.user;
    if (user == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final userRef =
          FirebaseFirestore.instance.collection('Users').doc(user.uid);
      final userDoc = await userRef.get();

      if (userDoc.exists) {
        // Phone auth signs existing users in automatically, so this number
        // is already registered. Sign out and warn instead of logging in.
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showAccountExistsDialog("+63 ${_mobileController.text}", isPhone: true);
        return;
      }

      // New user: create the profile record
      await userRef.set({
        'phone': phone,
        'setupComplete': false, // Triggers WelcomeSetupScreen
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeSetupScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar(
            "Error saving your profile. Please try again.", Colors.redAccent);
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

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

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
              const SizedBox(height: 30),

              _buildModeToggle(),
              const SizedBox(height: 30),

              if (_usePhone) ...[
                _buildPhoneField(),
                const SizedBox(height: 8),
                const Text(
                  "We'll text you a 6-digit code to verify your number.",
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ] else
                // AUTOFILL GROUP FOR REGISTRATION CREDENTIALS
                AutofillGroup(
                  child: Column(
                    children: [
                      _buildField(
                        _emailController,
                        "Email",
                        Icons.email,
                        false,
                        autofillHints: const [
                          AutofillHints.email,
                          AutofillHints.newUsername
                        ],
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
                        onToggle: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Create a strong password",
                          style:
                              TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 15),
                      _buildField(
                        _confirmPasswordController,
                        "Confirm Password",
                        Icons.lock_outline,
                        true,
                        isObscured: _obscureConfirmPassword,
                        autofillHints: const [AutofillHints.newPassword],
                        onToggle: () => setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword),
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
                      : Text(_usePhone ? "SEND CODE" : "SIGN UP",
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

  Widget _buildModeToggle() {
    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? Colors.cyanAccent : Colors.transparent,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? navyBlue : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          segment("Mobile Number", _usePhone,
              () => setState(() => _usePhone = true)),
          segment("Email", !_usePhone, () => setState(() => _usePhone = false)),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextField(
      controller: _mobileController,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone, color: Colors.white70),
              const SizedBox(width: 8),
              const Text("+63",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Container(width: 1, height: 22, color: Colors.white24),
            ],
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        hintText: "917 123 4567",
        hintStyle: const TextStyle(color: Colors.white54),
        enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.cyanAccent, width: 2)),
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