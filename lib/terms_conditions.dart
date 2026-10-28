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
                    fontSize: 13,
                    color: isDark ? Colors.white70 : navyBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ...sections,
        ],
      ),
    );
  }

  List<Widget> _termsOfService(bool isDark) {
    return [
      _sectionTitle("Acceptance of Terms"),
      _sectionText(
        "By accessing, registering, or using BentaTrack, you agree to be legally bound by these Terms of Service. If you disagree with any portion of these terms, you must immediately discontinue use of the mobile application.",
        isDark,
      ),
      _sectionTitle("Scope of Service"),
      _sectionText(
        "BentaTrack provides a cloud-integrated inventory and sales management platform tailored for micro and small enterprises (MSEs) in the Philippines. We reserve the right to modify, suspend, or terminate features or service availability at any time for system maintenance, security updates, or functional upgrades.",
        isDark,
      ),
      _sectionTitle("User Accounts & Security"),
      _sectionText(
        "You are entirely responsible for maintaining the strict confidentiality of your account credentials, password, and 4-digit security MPIN. BentaTrack shall not be held liable for any loss, unauthorized modifications, or damages arising from your failure to safeguard your account information.",
        isDark,
      ),
      _sectionTitle("Acceptable Use Policy"),
      _sectionText(
        "Users are strictly prohibited from reverse-engineering the application architecture, attempting unauthorized database breaches, uploading malicious code, or utilizing the platform for fraudulent or unlawful commercial transactions.",
        isDark,
      ),
      _sectionTitle("Limitation of Liability"),
      _sectionText(
        "The application is provided on an 'as is' and 'as available' basis without warranties of any kind, whether express or implied. BentaTrack does not guarantee uninterrupted operational availability or complete error-free data synchronization under unstable network conditions.",
        isDark,
      ),
    ];
  }

  List<Widget> _privacyPolicy(bool isDark) {
    return [
      _sectionTitle("Information We Collect"),
      _sectionText(
        "To provide effective inventory processing and authentication services, we collect account registration data including your store name, business email address, and encrypted security parameters (such as your MPIN). Inventory records and product metrics entered are securely stored under your account identifier.",
        isDark,
      ),
      _sectionTitle("Utilization of Data"),
      _sectionText(
        "Collected information is utilized exclusively for generating business analytics, tracking stock performance, and operating core application features. We do not sell, trade, or transfer your proprietary business records or personal identifiers to unauthorized third parties.",
        isDark,
      ),
      _sectionTitle("Cloud Storage & Data Security"),
      _sectionText(
        "We implement industry-standard encryption protocols and secure cloud databases (Firebase) to protect your records. Sensitive account configurations and verification checks are further secured using localized PIN protection.",
        isDark,
      ),
      _sectionTitle("Compliance with Privacy Laws"),
      _sectionText(
        "Our data processing practices adhere to standard data privacy principles, respecting user confidentiality, data minimization, and secure account management rights.",
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
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Acknowledge & Close",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: navyBlue,
          fontSize: 15,
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
        fontSize: 13.5,
        height: 1.6,
        fontWeight: FontWeight.normal,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
    );
  }
}