import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

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

  /// SHA256 hash
  String hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate temp password
  String generateTempPassword() {
    const chars = "abcdefghijklmnopqrstuvwxyz1234567890";
    Random rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  /// Login function
  Future<void> loginUser() async {
    String stationNameInput = stationController.text.trim().toUpperCase();
    String passwordInput = passwordController.text.trim();

    if (stationNameInput.isEmpty || passwordInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter station name and password")),
      );
      return;
    }

    /// 🔴 HARDCODED ADMIN LOGIN
    if (stationNameInput == "ADMIN" && passwordInput == "#Megabrain100") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Admin Login Successful")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AdminDashboard(isAdmin: true),
        ),
      );
      return;
    }

    try {
      String hashedPassword = hashPassword(passwordInput);

      var query = await FirebaseFirestore.instance
          .collection('stations')
          .where('station_name', isEqualTo: stationNameInput)
          .where('password', isEqualTo: hashedPassword)
          .get();

      if (query.docs.isEmpty) {
        throw Exception("Invalid station name or password");
      }

      var userData = query.docs.first.data();

      String role = (userData["role"] ?? "station").toString().toLowerCase();

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Login Successful")));

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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Failed: $e")),
      );
    }
  }

  /// Forgot password
  Future<void> forgotPassword() async {
    TextEditingController resetController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Reset Password"),
          content: TextField(
            controller: resetController,
            decoration: const InputDecoration(
              labelText: "Enter Station Name",
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text("Reset"),
              onPressed: () async {
                try {
                  String stationName =
                  resetController.text.trim().toUpperCase();

                  var query = await FirebaseFirestore.instance
                      .collection('stations')
                      .where('station_name', isEqualTo: stationName)
                      .get();

                  if (query.docs.isEmpty) {
                    throw Exception("Station not found");
                  }

                  String tempPassword = generateTempPassword();
                  String hashedTempPassword = hashPassword(tempPassword);

                  await FirebaseFirestore.instance
                      .collection('stations')
                      .doc(query.docs.first.id)
                      .update({"password": hashedTempPassword});

                  Navigator.pop(context);

                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Temporary Password"),
                      content: Text(
                        "Your temporary password is:\n\n$tempPassword\n\nPlease login and change it.",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      actions: [
                        TextButton(
                          child: const Text("OK"),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e")),
                  );
                }
              },
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
                padding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              onPressed: loginUser,
              child: const Text("LOGIN"),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: forgotPassword,
              child: const Text("Forgot Password?"),
            ),
            const SizedBox(height: 10),
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
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}