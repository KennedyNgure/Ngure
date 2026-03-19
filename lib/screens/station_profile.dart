import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final TextEditingController unitsController = TextEditingController();

  final TextEditingController wardController = TextEditingController();
  final TextEditingController subcountyController = TextEditingController();
  final TextEditingController countyController = TextEditingController();

  final TextEditingController fcmController = TextEditingController();

  bool passwordVisible = false;

  /// HASH PASSWORD
  String hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 🔥 FORWARD GEOCODING (ward → lat/lon)
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
      fcmController.text = data["fcm_token"] ?? "";

      wardController.text = data["ward"] ?? "";
      subcountyController.text = data["subcounty"] ?? "";
      countyController.text = data["county"] ?? "";

    } catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading station: $e")),
      );
    }
  }

  /// UPDATE STATION
  Future updateStation() async {

    try {

      // 🔥 Convert ward → coordinates
      final coords = await getCoordinatesFromAddress(
        wardController.text.trim(),
        subcountyController.text.trim(),
        countyController.text.trim(),
      );

      Map<String, dynamic> updateData = {

        "email": emailController.text.trim(),
        "phone": phoneController.text.trim(),
        "available_units": int.tryParse(unitsController.text) ?? 0,

        "ward": wardController.text.trim(),
        "subcounty": subcountyController.text.trim(),
        "county": countyController.text.trim(),

        "latitude": coords["lat"],
        "longitude": coords["lon"],

        "fcm_token": fcmController.text.trim(),
      };

      if (passwordController.text.isNotEmpty) {
        updateData["password"] =
            hashPassword(passwordController.text.trim());
      }

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

      await FirebaseFirestore.instance
          .collection("stations")
          .doc(docId)
          .update(updateData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Station updated with location"),
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
                  icon: Icon(passwordVisible
                      ? Icons.visibility
                      : Icons.visibility_off),
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

            /// 🔥 NEW FIELDS
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
              child: const Text("UPDATE DETAILS"),
            ),
          ],
        ),
      ),
    );
  }
}