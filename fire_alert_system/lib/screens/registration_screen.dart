import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'role_selection_screen.dart';
import 'login_screen.dart';
import 'terms_and_conditions_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController stationNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _isAccepted = false;
  bool _isLoading = false;

  /// 🛠️ CUSTOM INPUT DECORATION
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

  /// 🔐 REGISTRATION LOGIC
  Future<void> registerStation() async {
    String stationName = stationNameController.text.trim().toUpperCase();
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    String confirmPassword = confirmPasswordController.text.trim();

    if (stationName.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showSnackBar("Please fill all fields", Colors.orange);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match", Colors.red);
      return;
    }

    if (!_isAccepted) {
      _showSnackBar("You must agree to the Terms and Conditions", Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if station name exists
      var stationCheck = await FirebaseFirestore.instance
          .collection('stations')
          .where('station_name', isEqualTo: stationName)
          .get();

      if (stationCheck.docs.isNotEmpty) {
        throw Exception("Station name already exists");
      }

      // Create Auth User
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Store Metadata
      await FirebaseFirestore.instance.collection('stations').add({
        'station_name': stationName,
        'email': email,
        'role': 'station',
        'status': 'unverified', // Default status for admin to check later
        'uid': userCredential.user!.uid,
        'created_at': Timestamp.now(),
      });

      if (!mounted) return;
      _showSnackBar("Station Registered Successfully", Colors.green);

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? "Registration failed", Colors.red);
    } catch (e) {
      _showSnackBar(e.toString(), Colors.red);
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- PROFESSIONAL HEADER ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
              decoration: const BoxDecoration(
                color: Colors.red,
                gradient: LinearGradient(
                  colors: [Colors.red, Color(0xFFB71C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RoleSelectionScreen())),
                      ),
                    ],
                  ),
                  const Icon(Icons.app_registration_rounded, size: 70, color: Colors.white),
                  const SizedBox(height: 10),
                  const Text(
                    "New Station",
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "Create an official responder account",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --- FORM CARD ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TextField(
                            controller: stationNameController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _buildInputDecoration("Official Station Name", Icons.business),
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _buildInputDecoration("Email Address", Icons.email_outlined),
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: passwordController,
                            obscureText: !_passwordVisible,
                            decoration: _buildInputDecoration(
                              "Password",
                              Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: confirmPasswordController,
                            obscureText: !_confirmPasswordVisible,
                            decoration: _buildInputDecoration(
                              "Confirm Password",
                              Icons.lock_reset,
                              suffix: IconButton(
                                icon: Icon(_confirmPasswordVisible ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _confirmPasswordVisible = !_confirmPasswordVisible),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  // --- TERMS SECTION ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _isAccepted,
                          activeColor: Colors.red,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (val) => setState(() => _isAccepted = val ?? false),
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              text: "I agree to the ",
                              style: const TextStyle(color: Colors.black54, fontSize: 13),
                              children: [
                                TextSpan(
                                  text: "Terms and Conditions",
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen(isAdmin: false))),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // --- SUBMIT BUTTON ---
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : registerStation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 5,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                        "REGISTER STATION",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: const Text(
                      "Already have an account? Login",
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
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