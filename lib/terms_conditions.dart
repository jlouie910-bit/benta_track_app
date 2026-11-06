import 'package:flutter/material.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  static const Color navyBlue = Color(0xFF1E3A5F);
  static const Color lightBg = Color(0xFFF5F5F5);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF18191A) : lightBg,
        appBar: AppBar(
          title: const Text(
            "Legal & Compliance",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: navyBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          bottom: TabBar(
            indicatorColor: Colors.cyanAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: const [
              Tab(text: "Terms of Service"),
              Tab(text: "Privacy Policy"),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  _legalTabContent(_termsOfService(isDark), isDark),
                  _legalTabContent(_privacyPolicy(isDark), isDark),
                ],
              ),
            ),
            _bottomActionArea(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _legalTabContent(List<Widget> sections, bool isDark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Effective Date Info Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: navyBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: navyBlue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: navyBlue, size: 20),
                const SizedBox(width: 10),
                Text(
                  "Effective Date: October 2026",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : navyBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Plain-Language Summary Box
          _plainLanguageSummaryCard(isDark),
          const SizedBox(height: 10),
          ...sections,
        ],
      ),
    );
  }

  Widget _plainLanguageSummaryCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bolt_rounded, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                "TL;DR — Quick Summary",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: navyBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryBullet("Your data is yours. We don’t sell it to anyone."),
          _summaryBullet("Keep your store password and 4-digit MPIN private."),
          _summaryBullet("Don’t try to hack or misuse the app."),
          _summaryBullet("Keep your own backup copies of critical store records."),
        ],
      ),
    );
  }

  Widget _summaryBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(fontWeight: FontWeight.bold, color: navyBlue)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _termsOfService(bool isDark) {
    return [
      _sectionTitle("Acceptance of Terms"),
      _sectionText(
        "By using BentaTrack, you agree to follow these rules. If you do not agree, please stop using the app immediately.",
        isDark,
      ),
      _sectionTitle("Scope of Service"),
      _sectionText(
        "BentaTrack is built to help sari-sari store owners in the Philippines manage their inventory and sales easily. We may update or improve features from time to time for security and maintenance.",
        isDark,
      ),
      _sectionTitle("User Accounts & Security"),
      _sectionText(
        "You are responsible for keeping your login details, password, and 4-digit MPIN secure. BentaTrack is not liable for any losses if someone else accesses your account due to shared credentials.",
        isDark,
      ),
      _sectionTitle("Acceptable Use Policy"),
      _sectionText(
        "Please use the app honestly. Do not attempt to reverse-engineer the code, breach our database security, upload harmful files, or use the platform for illegal transactions.",
        isDark,
      ),
      _sectionTitle("Limitation of Liability"),
      _sectionText(
        "The app is provided 'as is'. While we do our best to keep your records synced, we cannot guarantee zero downtime if your mobile network connection drops suddenly.",
        isDark,
      ),
    ];
  }

  List<Widget> _privacyPolicy(bool isDark) {
    return [
      _sectionTitle("Information We Collect"),
      _sectionText(
        "To run your store management smoothly, we collect basic details like your store name, business email, encrypted security credentials (MPIN), and your inventory records.",
        isDark,
      ),
      _sectionTitle("Customer Records & Utang Tracking"),
      _sectionText(
        "If you record customer names, phone numbers, or credit balances (utang) inside the app, this data remains strictly under your account. We treat your customers' personal information with utmost confidentiality and secure it just like your own business records.",
        isDark,
      ),
      _sectionTitle("How We Use Your Data"),
      _sectionText(
        "Your data is used solely to generate your store analytics and keep your inventory synced across devices. We never sell, trade, or share your proprietary business metrics with third parties.",
        isDark,
      ),
      _sectionTitle("Cloud Storage & Security"),
      _sectionText(
        "Your records are protected using industry-standard cloud encryption (Firebase) and localized PIN authentication on your device.",
        isDark,
      ),
      _sectionTitle("Compliance with Philippine Law (RA 10173)"),
      _sectionText(
        "We fully comply with the Data Privacy Act of 2012 (Republic Act No. 10173) in the Philippines. You have full rights to access, correct, or request deletion of your store data at any time.\n\nFor privacy questions or data deletion requests, contact our support team at: support@bentatrack.com",
        isDark,
      ),
    ];
  }

  Widget _bottomActionArea(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 25),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: navyBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              // Passing `true` back allows the parent screen to automatically check the consent box
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                "Acknowledge & Close",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'BentaTrack',
              applicationVersion: '1.0.0',
            ),
            child: const Text(
              "View Third-Party Open Source Notices",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: navyBlue,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _sectionText(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        height: 1.6,
        fontWeight: FontWeight.normal,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
    );
  }
}