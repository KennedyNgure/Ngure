import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'registration_screen.dart';

class FireReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future submitReport({
    required String fireType,
    required String fireSize,
    required int peopleTrapped,
    required String evacuationStatus,
    required double lat,
    required double lon,
    String? name,
    String? phone,
  }) async {
    await _firestore.collection("reports").add({
      "fireType": fireType,
      "fireSize": fireSize,
      "peopleTrapped": peopleTrapped,
      "evacuationStatus": evacuationStatus,
      "latitude": lat,
      "longitude": lon,
      "reporterName": name,
      "reporterPhone": phone,
      "status": "pending",
      "timestamp": FieldValue.serverTimestamp(),
    });
  }
}

class ReportFireScreen extends StatefulWidget {
  const ReportFireScreen({super.key});

  @override
  State<ReportFireScreen> createState() => _ReportFireScreenState();
}

class _ReportFireScreenState extends State<ReportFireScreen> {

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController peopleController = TextEditingController();

  final FireReportService service = FireReportService();

  String? selectedFireType;
  String? selectedFireSize;
  String? evacuationStatus;


  bool isLoading = false;

  final List<String> fireTypes = [
    "House/building fire",
    "Forest or bush fire",
    "Vehicle fire",
    "Electrical fire",
    "Industrial fire",
  ];

  final List<String> fireSizes = [
    "Small",
    "Medium",
    "Large",
  ];

  final List<String> evacuationOptions = [
    "Evacuated",
    "Evacuation in progress",
    "People still inside",
  ];

  /// GET LOCATION
  Future<Position> getLocation() async {

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception("Location services are disabled.");
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception("Location permission permanently denied.");
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// REPORT FIRE
  Future<void> reportFire() async {

    if (selectedFireType == null ||
        selectedFireSize == null ||
        evacuationStatus == null) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fire details")),
      );
      return;
    }

    try {

      setState(() {
        isLoading = true;
      });

      Position position = await getLocation();

      await service.submitReport(
        fireType: selectedFireType!,
        fireSize: selectedFireSize!,
        peopleTrapped: int.tryParse(peopleController.text) ?? 0,
        evacuationStatus: evacuationStatus!,
        lat: position.latitude,
        lon: position.longitude,
        name: nameController.text.isEmpty ? null : nameController.text.trim(),
        phone: phoneController.text.isEmpty ? null : phoneController.text.trim(),
      );

      setState(() {
        isLoading = false;
      });

      nameController.clear();
      phoneController.clear();
      peopleController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🚨 Fire Report Sent Successfully"),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error sending report: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Fire"),
        backgroundColor: Colors.red,
        actions: [
          TextButton(
            child: const Text("Safety Tips",
                style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SafetyTipsScreen()),
              );
            },
          ),
          TextButton(
            child: const Text("Emmergency Contacts",
                style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const EmergencyContactsScreen()),
              );
            },
          ),
          TextButton(
            child: const Text("Stations Registration",
                style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => RegistrationScreen()),
              );
            },
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            children: [

              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Full Name (optional)",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Phone Number (optional)",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 15),

              DropdownButtonFormField<String>(
                value: selectedFireType,
                decoration: const InputDecoration(
                  labelText: "Type of Fire 🔥",
                  border: OutlineInputBorder(),
                ),
                items: fireTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedFireType = value;
                  });
                },
              ),

              const SizedBox(height: 15),

              DropdownButtonFormField<String>(
                value: selectedFireSize,
                decoration: const InputDecoration(
                  labelText: "Size of Fire",
                  border: OutlineInputBorder(),
                ),
                items: fireSizes.map((size) {
                  return DropdownMenuItem(
                    value: size,
                    child: Text(size),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedFireSize = value;
                  });
                },
              ),

              const SizedBox(height: 15),

              TextField(
                controller: peopleController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Number of people trapped or injured",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                value: evacuationStatus,
                decoration: const InputDecoration(
                  labelText: "Evacuation Status",
                  border: OutlineInputBorder(),
                ),
                items: evacuationOptions.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(status),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    evacuationStatus = value;
                  });
                },
              ),

              const SizedBox(height: 30),

              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 20,
                  ),
                ),
                onPressed: reportFire,
                child: const Text(
                  "🚨 REPORT FIRE",
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SafetyTipsScreen extends StatelessWidget {
  const SafetyTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Safety Tips"),
        backgroundColor: Colors.orange,
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [

          ListTile(
            leading: Icon(Icons.warning, color: Colors.red),
            title: Text("Stay calm and evacuate immediately."),
          ),

          ListTile(
            leading: Icon(Icons.warning, color: Colors.red),
            title: Text("Do not use elevators during a fire."),
          ),

          ListTile(
            leading: Icon(Icons.warning, color: Colors.red),
            title: Text("Cover nose and mouth with cloth to avoid smoke."),
          ),

          ListTile(
            leading: Icon(Icons.warning, color: Colors.red),
            title: Text("Stay low to the ground when escaping smoke."),
          ),

          ListTile(
            leading: Icon(Icons.warning, color: Colors.red),
            title: Text("Call emergency services immediately."),
          ),
        ],
      ),
    );
  }
}

class EmergencyContactsScreen extends StatelessWidget {
  const EmergencyContactsScreen({super.key});

  Future<void> callNumber(String number) async {

    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: number,
    );

    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Contacts"),
        backgroundColor: Colors.blue,
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          ListTile(
            leading: const Icon(Icons.local_fire_department, color: Colors.red),
            title: const Text("Fire Department"),
            subtitle: const Text("Tap to call 999"),
            trailing: const Icon(Icons.call),
            onTap: () => callNumber("999"),
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.local_police, color: Colors.blue),
            title: const Text("Police"),
            subtitle: const Text("Tap to call 999"),
            trailing: const Icon(Icons.call),
            onTap: () => callNumber("999"),
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.local_hospital, color: Colors.green),
            title: const Text("Ambulance"),
            subtitle: const Text("Tap to call 999"),
            trailing: const Icon(Icons.call),
            onTap: () => callNumber("999"),
          ),
        ],
      ),
    );
  }
}