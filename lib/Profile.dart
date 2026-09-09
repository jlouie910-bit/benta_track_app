import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'Profile_Settings.dart';
import 'store_settings.dart';
import 'terms_conditions.dart';
import 'help_support_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser;

  Future<void> _showLogoutDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("Confirm Logout"),
          content: const Text("Are you sure you want to log out of your account?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseAuth.instance.signOut();
              },
              child: const Text(
                "Logout",
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color navyBlue = Color(0xFF1E3A5F);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18191A) : Colors.grey[100],
      body: SingleChildScrollView(
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: navyBlue,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(40),
                      bottomRight: Radius.circular(40),
                    ),
                  ),
                  child: const SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(top: 25),
                      child: Text(
                        "My Profile",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 150,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF18191A) : Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
                      child: Icon(
                          Icons.person,
                          size: 65,
                          color: isDark ? Colors.white70 : navyBlue
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 85),

            StreamBuilder<DocumentSnapshot>(
              // FIXED: Changed collection from 'users' to 'Users'
              stream: FirebaseFirestore.instance.collection('Users').doc(user?.uid).snapshots(),
              builder: (context, snapshot) {
                String displayName = user?.email ?? "Store Owner";
                if (snapshot.hasData && snapshot.data!.exists) {
                  var data = snapshot.data!.data() as Map<String, dynamic>?;
                  if (data != null && data.containsKey('storeName')) {
                    displayName = data['storeName'] ?? displayName;
                  }
                }

                return Column(
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : navyBlue
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        "Store Owner",
                        style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontSize: 15,
                            letterSpacing: 0.5
                        )
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 35),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader("Preferences", isDark),
                  _buildProfileOption(
                    isDark: isDark,
                    icon: Icons.dark_mode,
                    title: "Dark Mode",
                    iconColor: Colors.cyan,
                    trailing: Switch(
                      value: isDark,
                      onChanged: (bool value) {
                        themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                      },
                      activeThumbColor: Colors.cyanAccent,
                    ),
                  ),

                  const SizedBox(height: 10),

                  _buildSectionHeader("Account & Store", isDark),
                  _buildProfileOption(
                    isDark: isDark,
                    icon: Icons.person_outline,
                    title: "Profile Settings",
                    iconColor: Colors.orange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ProfileSettingsScreen()),
                      );
                    },
                  ),
                  _buildProfileOption(
                    isDark: isDark,
                    icon: Icons.storefront,
                    title: "Store Settings",
                    iconColor: navyBlue,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const StoreSettingsScreen()),
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  _buildSectionHeader("Support & Legal", isDark),
                  _buildProfileOption(
                    isDark: isDark,
                    icon: Icons.gavel_outlined,
                    title: "Legal Policies",
                    iconColor: Colors.blueGrey,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const TermsConditionsScreen()),
                      );
                    },
                  ),
                  _buildProfileOption(
                    isDark: isDark,
                    icon: Icons.help_outline,
                    title: "Help & Support",
                    iconColor: Colors.teal,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const HelpSupportScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showLogoutDialog,
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent, width: 1.8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white38 : Colors.black38,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildProfileOption({
    required bool isDark,
    required IconData icon,
    required String title,
    required Color iconColor,
    Widget? trailing,
    VoidCallback? onTap
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          if(!isDark) BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
            title,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 16
            )
        ),
        trailing: trailing ?? Icon(Icons.arrow_forward_ios, size: 14, color: isDark ? Colors.white24 : Colors.black26),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
      ),
    );
  }
}