import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'auth_service.dart';
import 'Navigation.dart';
import 'sign_up.dart';
import 'forgot_password.dart';
import 'terms_conditions.dart';
import 'WelcomeSetupScreen.dart';
import 'phone_auth_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();

  final AuthService _authService = AuthService();

  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color mintGreen = const Color(0xFF6EE7B7);

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _hasAcceptedTerms = false;

  // true = mobile number tab is shown first. Set to false to default to email.
  bool _usePhone = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  void _handleForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
    );
  }

  // ---------------- EMAIL LOGIN ----------------
   Future<void> _handleLogin() async {
    if (!_hasAcceptedTerms) {
      _showErrorSnackBar("Please accept the Terms and Conditions to continue.");
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showErrorSnackBar("Please fill in all fields.");
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final userCredential = await _authService.login(email, password);

      if (userCredential != null && userCredential.user != null && mounted) {
        // NEW: add this account's email to the lookup index
        final u = userCredential.user!;
        final mail = u.email?.toLowerCase();
        if (mail != null) {
          try {
            await FirebaseFirestore.instance
                .collection('EmailIndex')
                .doc(mail)
                .set({'uid': u.uid});
          } catch (_) {
            // already indexed or offline; safe to ignore
          }
        }

        TextInput.finishAutofillContext();
        await _checkSetupAndNavigate(userCredential.user!.uid);
      } else if (mounted) {
        _showErrorSnackBar("Invalid email or password.");
      }
    } on FirebaseAuthException catch (e) {
      // ...keep your existing catch blocks and finally exactly as they are
      if (!mounted) return;

      String errorMessage = "Login failed. Please try again.";
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        errorMessage = "Incorrect email or password.";
      } else if (e.code == 'invalid-email') {
        errorMessage = "Please enter a valid email address.";
      } else if (e.code == 'user-disabled') {
        errorMessage = "This account has been disabled.";
      }
      _showErrorSnackBar(errorMessage);
    } catch (e) {
      if (mounted) _showErrorSnackBar("An unexpected error occurred.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- PHONE LOGIN ----------------
  Future<void> _handlePhoneLogin() async {
    if (!_hasAcceptedTerms) {
      _showErrorSnackBar("Please accept the Terms and Conditions to continue.");
      return;
    }

    final phone = PhoneAuthHelper.normalizePhNumber(_mobileController.text);
    if (phone == null) {
      _showErrorSnackBar("Enter a valid mobile number, e.g. 917 123 4567.");
      return;
    }

    FocusScope.of(context).unfocus();

    // Sends the SMS, shows the OTP sheet, returns the signed-in user
    final credential = await PhoneAuthHelper.verifyWithSheet(context, phone);
    final user = credential?.user;
    if (user == null || !mounted) return;

    setState(() => _isLoading = true);
    await _checkSetupAndNavigate(user.uid, phone: phone);
  }

  // ---------------- GOOGLE LOGIN ----------------
  Future<void> _handleGoogleSignIn() async {
    if (!_hasAcceptedTerms) {
      _showErrorSnackBar("Please accept the Terms and Conditions to continue.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithGoogle();
      if (userCredential != null && userCredential.user != null && mounted) {
        await _checkSetupAndNavigate(userCredential.user!.uid);
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar("Google Sign-In failed: $e");
      }
    }
  }

  Future<void> _checkSetupAndNavigate(String uid, {String? phone}) async {
    try {
      final userRef = FirebaseFirestore.instance.collection('Users').doc(uid);
      final userDoc = await userRef.get();
      bool setupComplete = false;

      if (userDoc.exists) {
        setupComplete = userDoc.data()?['setupComplete'] ?? false;
      } else if (phone != null) {
        // First time this number signs in: create the profile record
        await userRef.set({
          'phone': phone,
          'setupComplete': false,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              setupComplete ? const MainNavigation() : const WelcomeSetupScreen(),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar("Error verifying profile status.");
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _navigateToSignUp() {
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => const SignUpScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: navyBlue,
        body: Stack(
          children: [
            Positioned(
              top: -100,
              right: -100,
              child: CircleAvatar(
                radius: 150,
                backgroundColor: mintGreen.withValues(alpha: 0.05),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 30),
                    Hero(
                      tag: 'app_logo',
                      child: Image.asset(
                        'assets/benta_track_logo.png',
                        height: 110,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "BentaTrack",
                      style: TextStyle(
                        fontSize: 32,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      "Inventory Management for Filipino Sari-Sari Stores",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: mintGreen.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 35),

                    _buildLoginModeToggle(),
                    const SizedBox(height: 25),

                    if (_usePhone) ...[
                      _buildPhoneField(),
                      const SizedBox(height: 10),
                    ] else ...[
                      AutofillGroup(
                        child: Column(
                          children: [
                            _buildInputField(
                              "Email",
                              Icons.email_outlined,
                              "Enter your email",
                              _emailController,
                              false,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [
                                AutofillHints.email,
                                AutofillHints.username
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildInputField(
                              "Password",
                              Icons.lock_outline,
                              "Enter your password",
                              _passwordController,
                              true,
                              autofillHints: const [AutofillHints.password],
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _handleForgotPassword,
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                                color: mintGreen, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    _buildTermsCheckbox(),

                    const SizedBox(height: 25),
                    _buildLoginButton(),

                    const SizedBox(height: 25),
                    _buildSignUpOption(),

                    const SizedBox(height: 35),
                    _buildSocialLoginSection(),

                    const SizedBox(height: 30),
                    const Text(
                      "Made for Filipino sari-sari stores",
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "© ${DateTime.now().year} BentaTrack. All rights reserved.",
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white30, fontSize: 10),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginModeToggle() {
    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? mintGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
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
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Mobile Number",
            style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          controller: _mobileController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_outlined, color: mintGreen, size: 20),
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
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            hintText: "917 123 4567",
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: mintGreen),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text("We'll text you a 6-digit code.",
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }

  Widget _buildInputField(
    String label,
    IconData icon,
    String hint,
    TextEditingController controller,
    bool isPassword, {
    TextInputType keyboardType = TextInputType.text,
    Iterable<String>? autofillHints,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          obscureText: isPassword ? _obscurePassword : false,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: mintGreen, size: 20),
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: mintGreen),
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.white70,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildTermsCheckbox() {
    return Theme(
      data: ThemeData(unselectedWidgetColor: Colors.white70),
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: GestureDetector(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const TermsConditionsScreen())),
          child: RichText(
            text: TextSpan(
              text: "I accept the ",
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              children: [
                TextSpan(
                  text: "Terms & Conditions",
                  style: TextStyle(
                      color: mintGreen, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        value: _hasAcceptedTerms,
        activeColor: mintGreen,
        checkColor: navyBlue,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (bool? value) =>
            setState(() => _hasAcceptedTerms = value ?? false),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _hasAcceptedTerms ? mintGreen : Colors.grey.shade800,
          foregroundColor: navyBlue,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
        ),
        onPressed: _isLoading
            ? null
            : (_usePhone ? _handlePhoneLogin : _handleLogin),
        child: _isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: navyBlue, strokeWidth: 2))
            : Text(_usePhone ? "Send Code" : "Login",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSignUpOption() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Don't have an account? ",
            style: TextStyle(color: Colors.white70)),
        GestureDetector(
          onTap: _navigateToSignUp,
          child: Text("Sign Up",
              style:
                  TextStyle(color: mintGreen, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSocialLoginSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.1))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Text("Or continue with",
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.1))),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _socialIconButton(
                const FaIcon(FontAwesomeIcons.google,
                    color: Colors.white, size: 22),
                _handleGoogleSignIn),
          ],
        ),
      ],
    );
  }

  Widget _socialIconButton(Widget icon, VoidCallback onTap) {
    return InkWell(
      onTap: _isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 55,
        width: 140,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Center(child: icon),
      ),
    );
  }
}