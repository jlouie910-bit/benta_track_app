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
  
  // Test variable for subscription tier popup preview ('Basic' or 'Premium')
  String _currentSubscriptionTier = 'Basic'; 

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

  // --- PREMIUM SUBSCRIPTION POPUP DIALOG FOR TESTING ---
  void _showSubscriptionModal() {
    showDialog(
      context: context,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        const Color navyBlue = Color(0xFF1E3A5F);
        const Color tealAccent = Color(0xFF4FD1C5);

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF242526) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.workspace_premium, color: _currentSubscriptionTier == 'Premium' ? Colors.amber : navyBlue),
                const SizedBox(width: 10),
                const Text("Subscription Plan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Current Tier: $_currentSubscriptionTier",
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: _currentSubscriptionTier == 'Premium' ? Colors.amber.shade700 : tealAccent,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Select a tier for testing features & restrictions:",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 15),

                // BASIC TIER CARD
                GestureDetector(
                  onTap: () {
                    setDialogState(() => _currentSubscriptionTier = 'Basic');
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _currentSubscriptionTier == 'Basic' ? tealAccent.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _currentSubscriptionTier == 'Basic' ? tealAccent : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Basic Plan (Free)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        SizedBox(height: 4),
                        Text(
                          "• AI Chats: 10/day limit\n• Analytics: Unlimited use\n• Barcode/AI Scanner: 10 uses/day\n• Counter Checkout: 10 transactions/day",
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // PREMIUM TIER CARD
                GestureDetector(
                  onTap: () {
                    setDialogState(() => _currentSubscriptionTier = 'Premium');
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _currentSubscriptionTier == 'Premium' ? Colors.amber.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _currentSubscriptionTier == 'Premium' ? Colors.amber : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Premium Plan (Pro)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        SizedBox(height: 4),
                        Text(
                          "• AI Chats: Unlimited 🚀\n• Analytics: Unlimited use\n• Barcode/AI Scanner: Unlimited use\n• Counter Checkout: Unlimited use",
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: navyBlue),
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Subscription updated to $_currentSubscriptionTier (Test Mode)"), backgroundColor: Colors.green),
                  );
                },
                child: const Text("Save Tier", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
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
              stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
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

                  // --- SUBSCRIPTION SECTION ---
                  _buildSectionHeader("Subscription", isDark),
                  _buildProfileOption(
                    isDark: isDark,
                    icon: Icons.workspace_premium,
                    title: "Subscription Plan",
                    iconColor: Colors.amber,
                    trailing: Text(
                      _currentSubscriptionTier,
                      style: TextStyle(
                        color: _currentSubscriptionTier == 'Premium' ? Colors.amber.shade700 : Colors.teal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: _showSubscriptionModal,
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