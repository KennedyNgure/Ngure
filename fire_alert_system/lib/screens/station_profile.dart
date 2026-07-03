import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class StationProfile extends StatefulWidget {
  final String stationName;

  const StationProfile({super.key, required this.stationName});

  @override
  State<StationProfile> createState() => _StationProfileState();
}

class _StationProfileState extends State<StationProfile> {
  final TextEditingController stationNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final TextEditingController wardController = TextEditingController();
  final TextEditingController subcountyController = TextEditingController();
  final TextEditingController countyController = TextEditingController();

  bool passwordVisible = false;

  /// HASH PASSWORD (kept for reference, NOT used for Firebase Auth anymore)
  String hashPassword(String password) {
    var bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// 🌍 Forward Geocoding
  Future<Map<String, double>> getCoordinatesFromAddress(
      String ward, String subcounty, String county) async {
    final query = "$ward, $subcounty, $county, Kenya";

    final url = Uri.parse(
      "https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1",
    );

    final response = await http.get(url, headers: {
      'User-Agent': 'fire_app',
    });

    final data = json.decode(response.body);

    if (data.isEmpty) {
      throw Exception("Location not found. Check ward/subcounty/county.");
    }

    return {
      "lat": double.parse(data[0]["lat"]),
      "lon": double.parse(data[0]["lon"]),
    };
  }

  /// Load Station
  Future loadStation() async {
    try {
      var query = await FirebaseFirestore.instance
          .collection("stations")
          .where("station_name", isEqualTo: widget.stationName)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Station not found")),
        );
        return;
      }

      var data = query.docs.first.data();

      setState(() {
        stationNameController.text = data["station_name"] ?? "";
        emailController.text = data["email"] ?? "";
        phoneController.text = data["phone"] ?? "";

        wardController.text = data["ward"] ?? "";
        subcountyController.text = data["subcounty"] ?? "";
        countyController.text = data["county"] ?? "";
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading station: $e")),
      );
    }
  }

  /// 🔐 Update Firebase Auth Password
  Future<void> updateAuthPassword(String newPassword) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception("No authenticated user found");
      }

      await user.updatePassword(newPassword);
    } catch (e) {
      throw Exception("Password update failed: $e");
    }
  }

  /// Update Station
  Future updateStation() async {
    try {
      final coords = await getCoordinatesFromAddress(
        wardController.text.trim(),
        subcountyController.text.trim(),
        countyController.text.trim(),
      );

      Map<String, dynamic> updateData = {
        "email": emailController.text.trim(),
        "phone": phoneController.text.trim(),
        "ward": wardController.text.trim(),
        "subcounty": subcountyController.text.trim(),
        "county": countyController.text.trim(),
        "latitude": coords["lat"],
        "longitude": coords["lon"],
      };

      var query = await FirebaseFirestore.instance
          .collection("stations")
          .where("station_name", isEqualTo: widget.stationName)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Station not found")),
        );
        return;
      }

      String docId = query.docs.first.id;

      // 🔥 Update Firestore
      await FirebaseFirestore.instance
          .collection("stations")
          .doc(docId)
          .update(updateData);

      // 🔐 Update Firebase Auth password
      if (passwordController.text.isNotEmpty) {
        await updateAuthPassword(passwordController.text.trim());
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Station updated successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    loadStation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Station Profile"),
        backgroundColor: Colors.red,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: stationNameController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "Station Name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: "Email",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: "Phone",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: passwordController,
              obscureText: !passwordVisible,
              decoration: InputDecoration(
                labelText: "New Password (optional)",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      passwordVisible = !passwordVisible;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: wardController,
              decoration: const InputDecoration(
                labelText: "Ward",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: subcountyController,
              decoration: const InputDecoration(
                labelText: "Subcounty",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: countyController,
              decoration: const InputDecoration(
                labelText: "County",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              onPressed: updateStation,
              child: const Text("UPDATE DETAILS"),
            ),
          ],
        ),
      ),
    );
  }
}