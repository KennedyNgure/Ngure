import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'registration_screen.dart';
import 'station_dashboard.dart';
import 'admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController stationController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _passwordVisible = false;

  /// 🔐 LOGIN FUNCTION
  Future<void> loginUser() async {
    // 🧼 Normalize input (VERY IMPORTANT FIX)
    String stationNameInput = stationController.text
        .trim()
        .toUpperCase();

    String passwordInput = passwordController.text.trim();

    print("RAW INPUT: '${stationController.text}'");
    print("NORMALIZED INPUT: '$stationNameInput'");

    if (stationNameInput.isEmpty || passwordInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter station name and password")),
      );
      return;
    }

    try {
      // 🔍 Get station from Firestore
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('stations')
          .where(
        'station_name',
        isEqualTo: stationNameInput,
      )
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        throw Exception("Station not found");
      }

      var userData = query.docs.first.data() as Map<String, dynamic>;

      String email = (userData["email"] ?? "").toString().trim();
      String role = (userData["role"] ?? "station").toString().toLowerCase();

      print("EMAIL FOUND: $email");
      print("ROLE FOUND: $role");

      if (email.isEmpty) {
        throw Exception("No email found for this station");
      }

      // 🔐 Firebase Authentication login
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: passwordInput,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login Successful")),
      );

      // 🚀 Role-based navigation
      if (role == "admin") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AdminDashboard(isAdmin: true),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                StationDashboard(stationName: stationNameInput),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Auth Error: ${e.message}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Failed: $e")),
      );
    }
  }

  /// 📧 FORGOT PASSWORD
  Future<void> forgotPassword() async {
    TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Reset Password"),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: "Enter your email",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(
                    email: emailController.text.trim(),
                  );

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Reset email sent")),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e")),
                  );
                }
              },
              child: const Text("Send Link"),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Station Login"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: stationController,
              decoration: const InputDecoration(
                labelText: "Station Name",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: passwordController,
              obscureText: !_passwordVisible,
              decoration: InputDecoration(
                labelText: "Password",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _passwordVisible = !_passwordVisible;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
              ),
              onPressed: loginUser,
              child: const Text("LOGIN"),
            ),

            const SizedBox(height: 10),

            TextButton(
              onPressed: forgotPassword,
              child: const Text("Forgot Password?"),
            ),

            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RegistrationScreen(),
                  ),
                );
              },
              child: const Text(
                "Register New Station",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}