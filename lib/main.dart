import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'login.dart';
import 'navigation.dart';
import 'WelcomeSetupScreen.dart';

// Global notifier to manage theme state across the app
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment configuration
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp();

  // Load theme preference
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  runApp(const BentaTrackApp());
}

class BentaTrackApp extends StatelessWidget {
  const BentaTrackApp({super.key});

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

          // Dark Theme
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
              // 1. Waiting for Auth State
              if (authSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // 2. User is Authenticated
              if (authSnapshot.hasData && authSnapshot.data != null) {
                final user = authSnapshot.data!;

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('Users') // Ensure casing matches Firestore rules
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, userSnapshot) {
                    // Check for errors (e.g., permission-denied)
                    if (userSnapshot.hasError) {
                      debugPrint("Firestore Stream Error: ${userSnapshot.error}");
                      return Scaffold(
                        body: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Text(
                              "Database Error: ${userSnapshot.error}\n\nPlease check your Firestore security rules or collection name.",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ),
                      );
                    }

                    // Show loader while fetching initial user metadata
                    if (userSnapshot.connectionState == ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }

                    // Check if setup is complete in Firestore
                    if (userSnapshot.hasData && userSnapshot.data!.exists) {
                      final userData =
                          userSnapshot.data!.data() as Map<String, dynamic>?;
                      final bool isSetupComplete =
                          userData?['setupComplete'] ?? false;

                      if (isSetupComplete) {
                        return const MainNavigation();
                      }
                    }

                    // Show setup screen if setup is incomplete or document missing
                    return const WelcomeSetupScreen();
                  },
                );
              }

              // 3. Unauthenticated -> Go to Login
              return const LoginScreen();
            },
          ),
        );
      },
    );
  }
}