import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'welcomesetupscreen.dart'; // Adjust path as needed
import 'navigation.dart';           // Adjust path as needed
import 'login.dart';          // Your login/Gmail sign-in screen

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // 1. Connection loading state
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF18191A),
            body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
          );
        }

        // 2. User is NOT logged in -> Go to Login
        if (!authSnapshot.hasData || authSnapshot.data == null) {
          return const LoginScreen(); 
        }

        final user = authSnapshot.data!;

        // 3. User IS logged in -> Stream their Firestore user document
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF18191A),
                body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
              );
            }

            // Check if document exists and setup is finished
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
              final bool isSetupComplete = userData?['setupComplete'] ?? false;

              if (isSetupComplete) {
                return const MainNavigation();
              }
            }

            // Setup is incomplete or document missing -> Show Welcome Setup Screen
            return const WelcomeSetupScreen();
          },
        );
      },
    );
  }
}