import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'Navigation.dart';
import 'sign_up.dart';
import 'forgot_password.dart';
import 'terms_conditions.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  final Color navyBlue = const Color(0xFF1e3a5f);
  final Color mintGreen = const Color(0xFF6ee7b7);
  final Color glassWhite = Colors.white.withOpacity(0.1);

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _hasAcceptedTerms = false;

  void _handleForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
    );
  }

  Future<void> _handleLogin() async {
    if (!_hasAcceptedTerms) {
      _showErrorSnackBar("Please accept the Terms and Conditions to continue.");
      return;
    }

    if (_phoneController.text.isEmpty || _passwordController.text.isEmpty) {
      _showErrorSnackBar("Please fill in all fields.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _phoneController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        _navigateToDashboard();
      }
    } on FirebaseAuthException catch (e) {
      String message = "Login failed.";
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        message = "No account found or incorrect credentials.";
      } else if (e.code == 'wrong-password') {
        message = "Incorrect password. Please try again.";
      }

      if (mounted) _showErrorSnackBar(message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUpScreen()));
  }

  void _navigateToDashboard() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainNavigation()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navyBlue,
      body: Stack(
        children: [
          // Background decorative element
          Positioned(
            top: -100,
            right: -100,
            child: CircleAvatar(radius: 150, backgroundColor: mintGreen.withOpacity(0.05)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30.0),
              child: Column(
                children: [
                  const SizedBox(height: 50),

                  // NEW: Modern Logo implementation (Replaced BT Box)
                  Hero(
                    tag: 'app_logo',
                    child: Image.asset(
                      'assets/benta_track_logo.png', height: 120,
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
                    "Inventory Management for MSE Businesses",
                    style: TextStyle(
                      color: mintGreen.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 50),

                  _buildInputField("Email", Icons.email_outlined, "Enter your email", _phoneController, false),
                  const SizedBox(height: 20),
                  _buildInputField("Password", Icons.lock_outline, "Enter your password", _passwordController, true),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _handleForgotPassword,
                      child: Text("Forgot Password?", style: TextStyle(color: mintGreen, fontWeight: FontWeight.w600)),
                    ),
                  ),

                  const SizedBox(height: 10),
                  _buildTermsCheckbox(),

                  const SizedBox(height: 25),
                  _buildLoginButton(),

                  const SizedBox(height: 25),
                  _buildSignUpOption(),

                  const SizedBox(height: 40),
                  _buildSocialLoginSection(),

                  const SizedBox(height: 40),
                  const Text("Made for Filipino MSMEs", style: TextStyle(color: Colors.white30, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(String label, IconData icon, String hint, TextEditingController controller, bool isPassword) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          obscureText: isPassword ? _obscurePassword : false,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: mintGreen, size: 20),
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: mintGreen),
            ),
            suffixIcon: isPassword
                ? IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TermsConditionsScreen())),
          child: RichText(
            text: TextSpan(
              text: "I accept the ",
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              children: [
                TextSpan(
                  text: "Terms & Conditions",
                  style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        value: _hasAcceptedTerms,
        activeColor: mintGreen,
        checkColor: navyBlue,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (bool? value) => setState(() => _hasAcceptedTerms = value ?? false),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
        ),
        onPressed: _isLoading ? null : _handleLogin,
        child: _isLoading
            ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: navyBlue, strokeWidth: 2))
            : const Text("Login", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSignUpOption() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Don't have an account? ", style: TextStyle(color: Colors.white70)),
        GestureDetector(
          onTap: _navigateToSignUp,
          child: Text("Sign Up", style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSocialLoginSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Text("Or continue with", style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
          ],
        ),
        const SizedBox(height: 25),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _socialIconButton(const FaIcon(FontAwesomeIcons.google, color: Colors.white, size: 22), () {}),
            const SizedBox(width: 20),
            _socialIconButton(const FaIcon(FontAwesomeIcons.facebook, color: Color(0xFF1877F2), size: 22), () {}),
          ],
        ),
      ],
    );
  }

  Widget _socialIconButton(Widget icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 55,
        width: 80,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Center(child: icon),
      ),
    );
  }
}