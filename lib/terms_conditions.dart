import 'package:flutter/material.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  // Re-established Navy Blue Palette
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
          title: const Text("Legal Information",
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: navyBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorWeight: 3,
            tabs: [
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
                  _legalTabContent(_termsOfService(), isDark),
                  _legalTabContent(_privacyPolicy(), isDark),
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }

  List<Widget> _termsOfService() {
    return [
      _sectionTitle("1. Agreement to Terms"),
      _sectionText("By accessing the application, you agree to be bound by these Terms of Service. This platform is designed for micro-enterprises in the Philippines to facilitate inventory and sales management."),
      _sectionTitle("2. Service Description"),
      _sectionText("We provide an Inventory Tracking Mobile Application. We reserve the right to modify or discontinue features to improve system performance."),
      _sectionTitle("3. User Conduct"),
      _sectionText("Users are prohibited from attempting to reverse-engineer application models or using the platform for fraudulent business transactions."),
      _sectionTitle("4. Disclaimer of Warranties"),
      _sectionText("The service is provided 'as is' without warranties of any kind."),
    ];
  }

  List<Widget> _privacyPolicy() {
    return [
      _sectionTitle("1. Data Collection"),
      _sectionText("We collect your store name and email used for inventory processing. Inputted items are used solely for identification."),
      _sectionTitle("2. Use of Data"),
      _sectionText("Data is utilized for business analytics and records. We do not sell or share business data with unauthorized third parties."),
      _sectionTitle("3. Storage & Security"),
      _sectionText("We utilize cloud-based encrypted storage. Sensitive actions are protected by your 4-digit security MPIN."),
      _sectionTitle("4. Third-Party Services"),
      _sectionText("By using this app, you adhere to standard cloud provider policies regarding authentication and database management."),
    ];
  }

  Widget _bottomActionArea(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: navyBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text("Accept & Continue",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'BentaTrack',
              applicationVersion: '1.0.0',
            ),
            child: const Text("View Third-Party Notices",
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: navyBlue,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _sectionText(String text) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 14,
          height: 1.6,
          fontWeight: FontWeight.w400
      ),
    );
  }
}