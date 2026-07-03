import 'package:flutter/material.dart';
import 'report_fire_screen.dart';
import 'registration_screen.dart';
import 'faq_screen.dart'; // ✅ ADD THIS

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Alert App"),
        actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FAQScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.help_outline, color: Colors.red),
              label: const Text(
                "FAQs",
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
      ),

      // ✅ ADD BODY BACK
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const Text(
              "Who are you?",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 40),

            // 🚨 Reporter Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
                backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ReportFireScreen(),
                  ),
                );
              },
              child: const Text("Reporter 🚨"),
            ),

            const SizedBox(height: 20),

            // 🚒 Fire Station Officer Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
                backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RegistrationScreen(),
                  ),
                );
              },
              child: const Text("Fire Station Officer 🚒"),
            ),
          ],
        ),
      ),
    );
  }
}