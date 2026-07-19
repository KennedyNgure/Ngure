import 'package:flutter/material.dart';
import 'report_fire_screen.dart';
import 'registration_screen.dart';
import 'faq_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Soft background color
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FAQScreen(isAdmin: false)),
              ),
              icon: const Icon(Icons.help_outline, color: Colors.red),
              label: const Text(
                "FAQs",
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // --- APP LOGO / ILLUSTRATION ---
              const Icon(
                Icons.local_fire_department_rounded,
                size: 100,
                color: Colors.red,
              ),
              const SizedBox(height: 10),
              const Text(
                "Fire Alert System",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Choose your role to continue",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 50),

              // --- REPORTER ROLE CARD ---
              _buildRoleCard(
                context,
                title: "Report an Emergency",
                subtitle: "I want to report a fire incident instantly",
                icon: Icons.notification_important_rounded,
                color: Colors.blue[700]!,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportFireScreen()),
                ),
              ),

              const SizedBox(height: 20),

              // --- OFFICER ROLE CARD ---
              _buildRoleCard(
                context,
                title: "Fire Station Officer",
                subtitle: "Official login for responders and stations",
                icon: Icons.admin_panel_settings_rounded,
                color: Colors.red[700]!,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegistrationScreen()),
                ),
              ),

              const SizedBox(height: 40),
              const Divider(),
              const SizedBox(height: 20),
              const Text(
                "For emergencies, always dial 999 first.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper widget to build professional interactive cards
  Widget _buildRoleCard(
      BuildContext context, {
        required String title,
        required String subtitle,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            // Icon Background
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 35),
            ),
            const SizedBox(width: 20),
            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}