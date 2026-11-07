import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'phone_auth_helper.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _existingMpin;

  // Theme Constants based on BentaTrack UI
  static const Color navyBlue = Color(0xFF1E3A5F);
  static const Color darkCard = Color(0xFF242526);
  static const Color darkBg = Color(0xFF18191A);

  @override
  void initState() {
    super.initState();
    _fetchCurrentSettings();
  }

  Future<void> _fetchCurrentSettings() async {
    setState(() => _isLoading = true);
    try {
      // FIXED: Changed 'users' to 'Users' to match WelcomeSetupScreen
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user?.uid)
          .get();

      if (doc.exists) {
        setState(() {
          _existingMpin = doc.get('mpin');
        });
      }
    } catch (e) {
      debugPrint("Error fetching settings: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // FORGOT MPIN
  // ---------------------------------------------------------------------------

  /// Step 1: explain, then verify the owner (email code or SMS code),
  /// Step 2: let them set a brand-new MPIN.
  Future<void> _startForgotMpin() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      _showError("You're signed out. Please log in again.");
      return;
    }

    final email = u.email;
    final phone = u.phoneNumber;
    final hasEmail = email != null && email.isNotEmpty;
    final hasPhone = phone != null && phone.isNotEmpty;

    if (!hasEmail && !hasPhone) {
      _showError("No email or mobile number on this account to verify.");
      return;
    }

    final target = hasEmail ? _maskEmail(email) : PhoneAuthHelper.formatMasked(phone!);
    final via = hasEmail ? "email" : "mobile number";

    // Confirmation dialog
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Forgot MPIN?",
            style: TextStyle(
                color: isDark ? Colors.white : navyBlue,
                fontWeight: FontWeight.bold),
          ),
          content: Text(
            "To confirm it's really you, we'll send a 6-digit code to your $via ($target). After that you can set a new MPIN.",
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("Cancel",
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: navyBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Send Code",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (proceed != true || !mounted) return;

    // Verify identity
    final bool verified =
        hasEmail ? await _verifyByEmailOtp(email) : await _verifyByPhone(u, phone!);

    if (!verified || !mounted) return;

    // Let them pick a new MPIN
    _showResetMpinDialog();
  }

  /// Sends a 6-digit code to the account's email and asks for it.
  Future<bool> _verifyByEmailOtp(String email) async {
    setState(() => _isLoading = true);
    bool sent = false;
    try {
      sent = await _authService
          .sendOtpToEmail(email)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint("Forgot MPIN: could not send OTP: $e");
    }
    if (mounted) setState(() => _isLoading = false);

    if (!sent) {
      _showError(
          "Couldn't send the verification code. Check your connection and try again.");
      return false;
    }
    if (!mounted) return false;

    final otpController = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: isDark ? darkCard : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              "Enter Verification Code",
              style: TextStyle(
                  color: isDark ? Colors.white : navyBlue,
                  fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "We sent a 6-digit code to ${_maskEmail(email)}.",
                  style:
                      TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: "000000",
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.grey[200],
                    errorText: error,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) {
                    if (error != null) setDialogState(() => error = null);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text("Cancel",
                    style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: navyBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (otpController.text.length < 6) {
                    setDialogState(() => error = "Enter all 6 digits.");
                    return;
                  }
                  if (_authService.verifyOtp(otpController.text)) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDialogState(() => error = "Invalid code. Try again.");
                  }
                },
                child: const Text("Verify",
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );

    return ok == true;
  }

  /// For phone-only accounts: re-verifies the same number by SMS.
  Future<bool> _verifyByPhone(User u, String phone) async {
    final credential = await PhoneAuthHelper.verifyWithSheet(context, phone);
    final verifiedUser = credential?.user;
    return verifiedUser != null && verifiedUser.uid == u.uid;
  }

  /// After verification: set a new MPIN (no current MPIN needed).
  void _showResetMpinDialog() {
    final newMpinController = TextEditingController();
    final confirmMpinController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Set New MPIN",
            style: TextStyle(
                color: isDark ? Colors.white : navyBlue,
                fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogField(
                  controller: newMpinController,
                  label: "New 4-Digit MPIN",
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildDialogField(
                  controller: confirmMpinController,
                  label: "Confirm New MPIN",
                  isDark: isDark,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel",
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: navyBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (newMpinController.text.length != 4) {
                  _showError("MPIN must be exactly 4 digits.");
                  return;
                }
                if (newMpinController.text != confirmMpinController.text) {
                  _showError("New MPINs do not match.");
                  return;
                }
                await _updateMpinInFirebase(newMpinController.text);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    if (name.length <= 2) return '${name[0]}***@${parts[1]}';
    return '${name.substring(0, 2)}***@${parts[1]}';
  }

  // ---------------------------------------------------------------------------
  // MPIN DIALOG (FOR SETUP AND CHANGE)
  // ---------------------------------------------------------------------------
  void _showMpinDialog() {
    final TextEditingController oldMpinController = TextEditingController();
    final TextEditingController newMpinController = TextEditingController();
    final TextEditingController confirmMpinController = TextEditingController();
    final bool isChanging = _existingMpin != null && _existingMpin!.isNotEmpty;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isChanging ? "Change MPIN" : "Setup MPIN",
            style: TextStyle(
                color: isDark ? Colors.white : navyBlue,
                fontWeight: FontWeight.bold
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isChanging) ...[
                  _buildDialogField(
                    controller: oldMpinController,
                    label: "Current MPIN",
                    isDark: isDark,
                  ),
                  // NEW: Forgot MPIN link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context); // close this dialog
                        _startForgotMpin();
                      },
                      child: const Text(
                        "Forgot MPIN?",
                        style: TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Divider(color: Colors.white10),
                  ),
                ],
                _buildDialogField(
                  controller: newMpinController,
                  label: "New 4-Digit MPIN",
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildDialogField(
                  controller: confirmMpinController,
                  label: "Confirm New MPIN",
                  isDark: isDark,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: navyBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (isChanging && oldMpinController.text != _existingMpin) {
                  _showError("The current MPIN you entered is incorrect.");
                  return;
                }
                if (isChanging && newMpinController.text == _existingMpin) {
                  _showError("New MPIN cannot be the same as your current one.");
                  return;
                }
                if (newMpinController.text.length != 4) {
                  _showError("MPIN must be exactly 4 digits.");
                  return;
                }
                if (newMpinController.text != confirmMpinController.text) {
                  _showError("New MPINs do not match.");
                  return;
                }

                await _updateMpinInFirebase(newMpinController.text);
                if (mounted) Navigator.pop(context);
              },
              child: const Text("Confirm", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // --- DELETE ACCOUNT LOGIC ---
  Future<void> _deleteAccount() async {
    if (_existingMpin == null || _existingMpin!.isEmpty) {
      _showError("Please set an MPIN first.");
      return;
    }

    final TextEditingController authController = TextEditingController();
    bool verified = false;
    bool forgot = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("Confirm Deletion",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("This action is permanent. Enter your MPIN to confirm:"),
              const SizedBox(height: 15),
              TextField(
                controller: authController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  filled: true,
                  fillColor: isDark ? Colors.black26 : Colors.grey[200],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none
                  ),
                  counterText: "",
                ),
              ),
              // NEW: Forgot MPIN link
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    forgot = true;
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "Forgot MPIN?",
                    style: TextStyle(
                        color: Colors.blueAccent, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                if (authController.text == _existingMpin) {
                  verified = true;
                  Navigator.pop(context);
                } else {
                  _showError("Incorrect MPIN");
                }
              },
              child: const Text("Delete Permanently", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    // They tapped "Forgot MPIN?" instead: run the reset flow, don't delete
    if (forgot) {
      if (mounted) _startForgotMpin();
      return;
    }

    if (!verified) return;

    setState(() => _isLoading = true);
    try {
      // FIXED: Changed 'users' to 'Users'
      await FirebaseFirestore.instance.collection('Users').doc(user?.uid).delete();
      await user?.delete();

      if (mounted) {
        _showSuccess("Account successfully deleted.");
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _showError("Security Timeout: Please log out and back in to delete your account.");
      } else {
        _showError("Error: ${e.message}");
      }
    } catch (e) {
      _showError("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- HELPER UI METHODS ---
  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required bool isDark,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        counterText: "",
        labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
        filled: true,
        fillColor: isDark ? Colors.black26 : Colors.grey[200],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Future<void> _updateMpinInFirebase(String newMpin) async {
    setState(() => _isLoading = true);
    try {
      // FIXED: Changed 'users' to 'Users'
      await FirebaseFirestore.instance.collection('Users').doc(user?.uid).set({
        'mpin': newMpin,
      }, SetOptions(merge: true));

      setState(() => _existingMpin = newMpin);
      _showSuccess("Security MPIN updated!");
    } catch (e) {
      _showError("Update failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? darkBg : Colors.grey[100],
      appBar: AppBar(
        title: const Text("Store Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: navyBlue))
          : ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        children: [
          _buildSectionHeader("Security & Privacy", isDark),
          _buildSettingCard(
            isDark: isDark,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (_existingMpin != null && _existingMpin!.isNotEmpty ? Colors.green : Colors.orange).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  (_existingMpin != null && _existingMpin!.isNotEmpty) ? Icons.shield_rounded : Icons.add_moderator_rounded,
                  color: (_existingMpin != null && _existingMpin!.isNotEmpty) ? Colors.green : Colors.orange,
                ),
              ),
              title: Text(
                (_existingMpin != null && _existingMpin!.isNotEmpty) ? "Change Security MPIN" : "Setup Security MPIN",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : navyBlue,
                ),
              ),
              subtitle: Text(
                (_existingMpin != null && _existingMpin!.isNotEmpty) ? "Active Protection" : "Protect crucial actions",
                style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              ),
              trailing: Icon(Icons.arrow_forward_ios, size: 14, color: isDark ? Colors.white24 : Colors.black26),
              onTap: _showMpinDialog,
            ),
          ),
          const SizedBox(height: 30),
          _buildSectionHeader("Account Actions", isDark),
          _buildSettingCard(
            isDark: isDark,
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              ),
              title: const Text("Delete Store Account",
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              subtitle: const Text("This action cannot be undone"),
              onTap: _deleteAccount,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white24 : Colors.black26,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingCard({required Widget child, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}