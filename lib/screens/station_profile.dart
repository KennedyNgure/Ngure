import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class StationProfile extends StatefulWidget {

  final String stationName;

  StationProfile({super.key, required this.stationName});

  @override
  State<StationProfile> createState() => _StationProfileState();
}

class _StationProfileState extends State<StationProfile> {

  final TextEditingController stationNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController unitsController = TextEditingController();
  final TextEditingController latitudeController = TextEditingController();
  final TextEditingController longitudeController = TextEditingController();
  final TextEditingController fcmController = TextEditingController();

  bool passwordVisible = false;

  /// HASH PASSWORD
  String hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// LOAD STATION DATA
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

      stationNameController.text = data["station_name"] ?? "";
      emailController.text = data["email"] ?? "";
      phoneController.text = data["phone"] ?? "";
      unitsController.text = data["available_units"].toString();
      latitudeController.text = data["latitude"].toString();
      longitudeController.text = data["longitude"].toString();
      fcmController.text = data["fcm_token"] ?? "";

    } catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading station: $e")),
      );

    }

  }

  /// UPDATE STATION
  Future updateStation() async {

    try {

      Map<String, dynamic> updateData = {

        "email": emailController.text.trim(),
        "phone": phoneController.text.trim(),
        "available_units": int.tryParse(unitsController.text) ?? 0,
        "latitude": double.tryParse(latitudeController.text) ?? 0,
        "longitude": double.tryParse(longitudeController.text) ?? 0,
        "fcm_token": fcmController.text.trim(),

      };

      if (passwordController.text.isNotEmpty) {
        updateData["password"] =
            hashPassword(passwordController.text.trim());
      }

      /// FIND DOCUMENT BY station_name
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

      /// UPDATE DOCUMENT
      await FirebaseFirestore.instance
          .collection("stations")
          .doc(docId)
          .update(updateData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Station details updated successfully"),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
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

            /// STATION NAME (READ ONLY)
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
              controller: unitsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Available Units",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: latitudeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Latitude",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: longitudeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Longitude",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: fcmController,
              decoration: const InputDecoration(
                labelText: "FCM Token",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 30),

            ElevatedButton(

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(
                    horizontal: 40, vertical: 15),
              ),

              onPressed: updateStation,

              child: const Text(
                "UPDATE DETAILS",
                style: TextStyle(fontSize: 16),
              ),
            ),

          ],
        ),
      ),
    );
  }
}