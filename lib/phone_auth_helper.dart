import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PhoneAuthHelper {
  /// Accepts 9171234567, 09171234567, 639171234567, +63 917 123 4567.
  /// Returns +639171234567, or null if the number is invalid.
  static String? normalizePhNumber(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('63')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length != 10 || !digits.startsWith('9')) return null;
    return '+63$digits';
  }

  /// +639171234567 -> +63 917 *** 4567
  static String formatMasked(String e164) {
    final d = e164.substring(3);
    return '+63 ${d.substring(0, 3)} *** ${d.substring(6)}';
  }

  /// Sends the SMS code, shows the OTP sheet, and returns the signed-in
  /// UserCredential. Returns null if the user closes the sheet.
  static Future<UserCredential?> verifyWithSheet(
      BuildContext context, String phone) {
    return showModalBottomSheet<UserCredential>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhoneOtpSheet(phone: phone),
    );
  }
}

class _PhoneOtpSheet extends StatefulWidget {
  final String phone;
  const _PhoneOtpSheet({required this.phone});

  @override
  State<_PhoneOtpSheet> createState() => _PhoneOtpSheetState();
}

class _PhoneOtpSheetState extends State<_PhoneOtpSheet> {
  static const Color navyBlue = Color(0xFF1E3A5F);
  static const Color mintGreen = Color(0xFF6EE7B7);
  static const int _resendSeconds = 60;

  final TextEditingController _otpController = TextEditingController();
  Timer? _timer;

  String? _verificationId;
  int? _resendToken;
  bool _sending = true;
  bool _verifying = false;
  String? _error;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return "That mobile number isn't valid.";
      case 'too-many-requests':
        return "Too many attempts. Please try again later.";
      case 'quota-exceeded':
        return "SMS limit reached. Please try again later.";
      case 'invalid-verification-code':
        return "Wrong code. Please check and try again.";
      case 'session-expired':
        return "The code expired. Tap Resend to get a new one.";
      case 'network-request-failed':
        return "No internet connection. Please try again.";
      case 'captcha-check-failed':
        return "Verification check failed. Please try again.";
      default:
        return "Something went wrong. Please try again.";
    }
  }

  Future<void> _sendCode({bool isResend = false}) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    if (isResend) _otpController.clear();

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: isResend ? _resendToken : null,
        // Android may read the SMS automatically and skip typing the code.
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signIn(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() {
            _sending = false;
            _error = _friendlyError(e);
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _sending = false;
          });
          _startTimer();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = "Could not send the code. Please try again.";
      });
    }
  }

  Future<void> _signIn(PhoneAuthCredential credential) async {
    if (!mounted || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) Navigator.of(context).pop(result);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = _friendlyError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = "Something went wrong. Please try again.";
      });
    }
  }

  void _verify() {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      setState(() => _error = "Please enter all 6 digits.");
      return;
    }
    if (_verificationId == null) {
      setState(() => _error = "Please request a new code.");
      return;
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: code,
    );
    _signIn(credential);
  }

  @override
  Widget build(BuildContext context) {
    final masked = PhoneAuthHelper.formatMasked(widget.phone);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 12,
        left: 30,
        right: 30,
      ),
      decoration: const BoxDecoration(
        color: navyBlue,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Verify Your Number",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              _sending
                  ? "Sending a code to $masked..."
                  : "Enter the 6-digit code we texted to\n$masked",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 25),
            if (_sending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: CircularProgressIndicator(color: mintGreen),
              )
            else if (_verificationId != null) ...[
              TextField(
                controller: _otpController,
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
                    color: Colors.white.withValues(alpha: 0.2),
                    letterSpacing: 20,
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: mintGreen, width: 2),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 3),
                  ),
                ),
                onChanged: (value) {
                  if (_error != null) setState(() => _error = null);
                  // Verify automatically once all 6 digits are typed
                  if (value.length == 6) _verify();
                },
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mintGreen,
                    foregroundColor: navyBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: _verifying ? null : _verify,
                  child: _verifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: navyBlue, strokeWidth: 2),
                        )
                      : const Text("VERIFY",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              _secondsLeft > 0
                  ? Text(
                      "Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}",
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                    )
                  : TextButton(
                      onPressed:
                          _verifying ? null : () => _sendCode(isResend: true),
                      child: const Text("Resend code",
                          style: TextStyle(
                              color: mintGreen, fontWeight: FontWeight.w600)),
                    ),
            ] else
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: mintGreen),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: () => _sendCode(),
                  child: const Text("Try again",
                      style: TextStyle(color: mintGreen)),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}