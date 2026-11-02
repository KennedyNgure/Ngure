import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'registration_screen.dart';
import 'station_dashboard.dart';
import 'admin_dashboard.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController stationController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _passwordVisible = false;
  bool _isLoading = false;

  InputDecoration _buildInputDecoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.red),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 15),
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

  Future<void> loginUser() async {
    String stationNameInput = stationController.text.trim().toUpperCase();
    String passwordInput = passwordController.text.trim();

    if (stationNameInput.isEmpty || passwordInput.isEmpty) {
      _showSnackBar("Please enter both station name and password", Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check Station existence first
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('stations')
          .where('station_name', isEqualTo: stationNameInput)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showSnackBar("No station found with that name", Colors.red);
        setState(() => _isLoading = false);
        return;
      }

      Map<String, dynamic> userData = query.docs.first.data() as Map<String, dynamic>;
      String email = (userData["email"] ?? "").toString().trim();
      String role = (userData["role"] ?? "station").toString().toLowerCase();

      // Attempt Auth
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: passwordInput,
      );

      if (!mounted) return;

      if (role == "admin") {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard(isAdmin: true)));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => StationDashboard(stationName: stationNameInput)));
      }

    } on FirebaseAuthException catch (e) {
      // Distinguish specific password errors
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showSnackBar("Incorrect password. Please try again.", Colors.red);
      } else {
        _showSnackBar(e.message ?? "Authentication failed", Colors.red);
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    stationController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 20),
              decoration: const BoxDecoration(
                color: Colors.red,
                gradient: LinearGradient(
                  colors: [Colors.red, Color(0xFFB71C1C)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(50), bottomRight: Radius.circular(50)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.local_fire_department, size: 100, color: Colors.white),
                  const SizedBox(height: 10),
                  const Text("FIRE ALERT SYSTEM", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const Text("Station Login Portal", style: TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: [
                  TextField(
                    controller: stationController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _buildInputDecoration("Station Name", Icons.account_balance),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: passwordController,
                    obscureText: !_passwordVisible,
                    decoration: _buildInputDecoration(
                      "Password",
                      Icons.lock,
                      suffix: IconButton(
                        icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                      child: const Text("Forgot Password?", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : loginUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 5,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("LOGIN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Not registered? "),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen())),
                        child: const Text("Register New Station", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}