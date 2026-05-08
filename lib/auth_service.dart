import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  String? _generatedOtp;
  // --- 1. OTP & REGISTRATION
  Future<bool> sendOtpToEmail(String email) async {
    _generatedOtp = (Random().nextInt(900000) + 100000).toString();
    debugPrint("BentaTrack OTP: $_generatedOtp");

    const String serviceId = 'service_9gpj742';
    const String templateId = 'template_qpl591f';
    const String publicKey = '8BCOOVKPLH8lHdPJZ';

    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'origin': 'http://localhost',
        },
        body: json.encode({
          'service_id': serviceId,
          'template_id': templateId,
          'user_id': publicKey,
          'template_params': {
            'email': email,
            'passcode': _generatedOtp,
            'time': '15 minutes',
          },
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("✅ OTP Sent Successfully!");
        return true;
      } else {
        debugPrint("❌ EmailJS Error: ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("❌ Network Error: $e");
      return false;
    }
  }

  bool verifyOtp(String userInput) {
    if (_generatedOtp == null) return false;
    return _generatedOtp == userInput;
  }

  Future<UserCredential> signUpWithEmail(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw 'This email is already registered.';
      } else if (e.code == 'weak-password') {
        throw 'The password provided is too weak.';
      }
      rethrow;
    }
  }

  //  LOGIN & SOCIAL

  Future<UserCredential?> login(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      debugPrint("Login Error: $e");
      return null;
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      return null;
    }
  }

  Future<UserCredential?> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
        return await _auth.signInWithCredential(credential);
      }
      return null;
    } catch (e) {
      debugPrint("Facebook Error: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}