import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login.dart';
import 'navigation.dart';
import 'WelcomeSetupScreen.dart';

// Global notifier to manage the theme state across the app
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Load the saved theme before running the app
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  runApp(const BentaTrackApp());
}

class BentaTrackApp extends StatefulWidget {
  const BentaTrackApp({super.key});

  @override
  State<BentaTrackApp> createState() => _BentaTrackAppState();
}

class _BentaTrackAppState extends State<BentaTrackApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'BentaTrack',

          // Light Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: const Color(0xFF1E3A5F),
            scaffoldBackgroundColor: Colors.grey[100],
          ),

          // Dark Theme (Facebook Style)
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF18191A),
            cardColor: const Color(0xFF242526),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1E3A5F),
              brightness: Brightness.dark,
              surface: const Color(0xFF242526),
            ),
            cardTheme: const CardThemeData(
              color: Color(0xFF242526),
              elevation: 0,
            ),
          ),

          themeMode: currentMode,

          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, authSnapshot) {
              // 1. Check if Firebase is still checking authentication status
              if (authSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // 2. If the user is logged in, check if they have a profile
              if (authSnapshot.hasData && authSnapshot.data != null) {
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(authSnapshot.data!.uid)
                      .get(),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState == ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }

                    // 3. If document does NOT exist, they are a first-time user
                    if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                      return const WelcomeSetupScreen();
                    }

                    // 4. If document exists, they have finished setup
                    return const MainNavigation();
                  },
                );
              }

              // 5. If no user is logged in, go to Login
              return const LoginScreen();
            },
          ),
        );
      },
    );
  }
}