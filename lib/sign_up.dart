import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'package:flutter/services.dart';
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
            top: 20, left: 30, right: 30,
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
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
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
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (otpController.text.length < 6) {
                      setPopupState(() => _otpErrorMessage = "Please enter all 6 digits.");
                      return;
                    }

                    if (_authService.verifyOtp(otpController.text)) {
                      try {
                        await _authService.signUpWithEmail(email, password);

                        if (mounted) {
                          Navigator.of(context).pop();
                          _showSnackBar("Verified and Registered Successfully!", Colors.green);
                        }
                      } catch (e) {
                        setPopupState(() => _otpErrorMessage = e.toString());
                      }
                    } else {
                      setPopupState(() => _otpErrorMessage = "Invalid code. Try again.");
                    }
                  },
                  child: Text(
                    "VERIFY NOW",
                    style: TextStyle(color: navyBlue, fontWeight: FontWeight.bold),
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
    // Constraint: Validates checkbox status before proceeding
    if (!_hasAcceptedTerms) {
      _showSnackBar("Please accept the Terms & Conditions to continue.", Colors.redAccent);
      return;
    }

    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar("Please fill in all fields.", Colors.redAccent);
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackBar("Passwords do not match!", Colors.redAccent);
      return;
    }

    setState(() => _isLoading = true);

    try {
      bool isSent = await _authService.sendOtpToEmail(_emailController.text.trim());

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
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          children: [
            const SizedBox(height: 40),
            const Text("Create Account",
                style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            _buildField(_emailController, "Email", Icons.email, false),
            const SizedBox(height: 20),
            _buildField(
              _passwordController,
              "Password",
              Icons.lock,
              true,
              isObscured: _obscurePassword,
              onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            const SizedBox(height: 20),
            _buildField(
              _confirmPasswordController,
              "Confirm Password",
              Icons.lock_outline,
              true,
              isObscured: _obscureConfirmPassword,
              onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),

            const SizedBox(height: 20),

            // UI Enhancement: Highlighted and Underlined Terms Link
            Theme(
              data: ThemeData(unselectedWidgetColor: Colors.white70),
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _hasAcceptedTerms,
                activeColor: Colors.cyanAccent,
                checkColor: navyBlue,
                onChanged: (value) => setState(() => _hasAcceptedTerms = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const TermsConditionsScreen()),
                    );
                  },
                  child: RichText(
                    text: TextSpan(
                      text: "I accept the ",
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                  backgroundColor: _hasAcceptedTerms ? Colors.white : Colors.white24,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _isLoading ? null : _handleSignUp,
                child: _isLoading
                    ? CircularProgressIndicator(color: navyBlue)
                    : Text("SIGN UP", style: TextStyle(color: navyBlue, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Already have an account? ", style: TextStyle(color: Colors.white70)),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    "Login",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
      TextEditingController controller,
      String hint,
      IconData icon,
      bool isPass,
      {bool isObscured = false, VoidCallback? onToggle}
      ) {
    return TextField(
      controller: controller,
      obscureText: isPass ? isObscured : false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
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