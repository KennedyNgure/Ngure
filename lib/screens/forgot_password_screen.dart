import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {

  final TextEditingController emailController = TextEditingController();

  Future resetPassword() async {

    try {

      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: emailController.text.trim(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset link sent to your email"),
        ),
      );

      Navigator.pop(context);

    } catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
        ),
      );

    }

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("Forgot Password"),
        backgroundColor: Colors.red,
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(

          mainAxisAlignment: MainAxisAlignment.center,

          children: [

            const Text(
              "Enter your email to reset your password",
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "Email",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
              ),

              onPressed: resetPassword,

              child: const Text(
                "Reset Password",
                style: TextStyle(fontSize: 18),
              ),
            ),

          ],
        ),
      ),
    );
  }
}