import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController stationController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  bool isVerified = false;
  bool isLoading = false;

  /// Modern Input Decoration
  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.red),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  /// Step 1: Verify user against Firestore metadata
  Future<void> verifyUser() async {
    String station = stationController.text.trim().toUpperCase();
    String phone = phoneController.text.trim();
    String email = emailController.text.trim();

    if (station.isEmpty || phone.isEmpty || email.isEmpty) {
      _showSnackBar("Please fill all verification fields", Colors.orange);
      return;
    }

    setState(() => isLoading = true);

    try {
      // Searching for the station in Firestore
      var query = await FirebaseFirestore.instance
          .collection('stations')
          .where('station_name', isEqualTo: station)
          .where('email', isEqualTo: email)
      // Note: Ensure your 'phone' field exists in Firestore 'stations' collection
          .get();

      if (query.docs.isNotEmpty) {
        setState(() {
          isVerified = true;
          isLoading = false;
        });
        _showSnackBar("Identity Verified! Check your email to reset password.", Colors.green);

        // Auto-trigger password reset once verified
        resetPassword();
      } else {
        setState(() => isLoading = false);
        _showSnackBar("No matching record found. Please check details.", Colors.red);
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar("Error: $e", Colors.red);
    }
  }

  /// Step 2: Trigger Firebase Password Reset Email
  Future<void> resetPassword() async {
    String email = emailController.text.trim();

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Reset Link Sent"),
          content: Text("A password reset link has been sent to $email. Please check your inbox or spam folder."),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back to Login
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Back to Login", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      );
    } catch (e) {
      _showSnackBar("Error sending email: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Account Recovery"),
        backgroundColor: Colors.red,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.lock_reset, size: 80, color: Colors.white),
                  const SizedBox(height: 10),
                  const Text(
                    "Forgot Password?",
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isVerified
                        ? "Identity verified successfully"
                        : "Enter your station details to verify your identity",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Step Indicator
                  Row(
                    children: [
                      _buildStepCircle("1", "Verify", !isVerified),
                      Expanded(child: Divider(color: isVerified ? Colors.green : Colors.grey)),
                      _buildStepCircle("2", "Reset", isVerified),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Verification Card
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TextField(
                            controller: stationController,
                            readOnly: isVerified,
                            decoration: _buildInputDecoration("Station Name", Icons.local_fire_department),
                            textCapitalization: TextCapitalization.characters,
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: phoneController,
                            readOnly: isVerified,
                            keyboardType: TextInputType.phone,
                            decoration: _buildInputDecoration("Phone Number", Icons.phone),
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: emailController,
                            readOnly: isVerified,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _buildInputDecoration("Email Address", Icons.email),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : (isVerified ? resetPassword : verifyUser),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isVerified ? Colors.green : Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 5,
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                        isVerified ? "RESEND RESET LINK" : "VERIFY IDENTITY",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Back to Login", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCircle(String step, String label, bool isActive) {
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: isActive ? Colors.red : (isVerified ? Colors.green : Colors.grey[300]),
          child: Text(
            step,
            style: TextStyle(color: isActive || isVerified ? Colors.white : Colors.black54, fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}