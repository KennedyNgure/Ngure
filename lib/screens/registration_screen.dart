import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'station_dashboard.dart';
import 'login_screen.dart';

class RegistrationScreen extends StatefulWidget {
  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {

  final TextEditingController stationNameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  // 🔐 HASH PASSWORD FUNCTION
  String hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future registerStation() async {

    String stationName = stationNameController.text.trim();
    String password = passwordController.text.trim();
    String confirmPassword = confirmPasswordController.text.trim();

    if (stationName.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    try {

      // Check if station already exists
      var stationCheck = await FirebaseFirestore.instance
          .collection('stations')
          .where('station_name', isEqualTo: stationName)
          .get();

      if (stationCheck.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Station name already exists")),
        );
        return;
      }

      // 🔐 HASH PASSWORD BEFORE SAVING
      String hashedPassword = hashPassword(password);

      await FirebaseFirestore.instance.collection('stations').add({
        'station_name': stationName,
        'password': hashedPassword,
        'created_at': Timestamp.now(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Station Registered Successfully")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LoginScreen(),
        ),
      );

    } catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );

    }

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: Text("Station Registration"),
        backgroundColor: Colors.red,
      ),

      body: Padding(
        padding: EdgeInsets.all(20),

        child: Column(

          children: [

            TextField(
              controller: stationNameController,
              decoration: InputDecoration(
                labelText: "Station Name",
                border: OutlineInputBorder(),
              ),
            ),

            SizedBox(height: 20),

            // PASSWORD FIELD
            TextField(
              controller: passwordController,
              obscureText: !_passwordVisible,
              decoration: InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
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

            SizedBox(height: 20),

            // CONFIRM PASSWORD FIELD
            TextField(
              controller: confirmPasswordController,
              obscureText: !_confirmPasswordVisible,
              decoration: InputDecoration(
                labelText: "Confirm Password",
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _confirmPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _confirmPasswordVisible = !_confirmPasswordVisible;
                    });
                  },
                ),
              ),
            ),

            SizedBox(height: 30),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),

              onPressed: registerStation,

              child: Text("REGISTER STATION"),
            ),

            SizedBox(height: 20),

            TextButton(

              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => LoginScreen()),
                );
              },

              child: Text(
                "Already have an account? Login",
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                ),
              ),
            )

          ],
        ),
      ),
    );
  }
}