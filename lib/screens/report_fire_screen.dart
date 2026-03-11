import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'registration_screen.dart';

class FireReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future submitReport({
    required String description,
    required String imageUrl,
    required double lat,
    required double lon,
    String? name,
    String? phone,
  }) async {
    await _firestore.collection("reports").add({
      "description": description,
      "imageUrl": imageUrl,
      "latitude": lat,
      "longitude": lon,
      "reporterName": name,
      "reporterPhone": phone,
      "status": "pending",
      "timestamp": Timestamp.now(),
    });
  }
}

class ReportFireScreen extends StatefulWidget {
  const ReportFireScreen({super.key});

  @override
  State<ReportFireScreen> createState() => _ReportFireScreenState();
}

class _ReportFireScreenState extends State<ReportFireScreen> {
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  final FireReportService service = FireReportService();
  final ImagePicker picker = ImagePicker();

  Uint8List? _imageBytes;
  bool isLoading = false;

  /// PICK IMAGE
  Future pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();

      setState(() {
        _imageBytes = bytes;
      });
    }
  }

  /// UPLOAD IMAGE TO FIREBASE STORAGE
  Future<String> uploadImage(Uint8List imageBytes) async {
    try {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();

      final ref = FirebaseStorage.instance
          .ref()
          .child("fire_images")
          .child("$fileName.jpg");

      UploadTask uploadTask = ref.putData(
        imageBytes,
        SettableMetadata(contentType: "image/jpeg"),
      );

      TaskSnapshot snapshot = await uploadTask;

      String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      throw Exception("Image upload failed: $e");
    }
  }

  /// GET USER LOCATION
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
      throw Exception("Location permissions permanently denied.");
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// REPORT FIRE
  Future<void> reportFire() async {
    try {
      setState(() {
        isLoading = true;
      });

      Position position = await getLocation();

      double latitude = position.latitude;
      double longitude = position.longitude;

      String imageUrl = "";

      if (_imageBytes != null) {
        imageUrl = await uploadImage(_imageBytes!);
      }

      await service.submitReport(
        description: descriptionController.text,
        imageUrl: imageUrl,
        lat: latitude,
        lon: longitude,
        name: nameController.text.isEmpty ? null : nameController.text,
        phone: phoneController.text.isEmpty ? null : phoneController.text,
      );

      setState(() {
        isLoading = false;
        _imageBytes = null;
      });

      descriptionController.clear();
      nameController.clear();
      phoneController.clear();

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
            child: const Text("Contacts",
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
            child: const Text("Register",
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
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: "Describe the fire",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              _imageBytes != null
                  ? Image.memory(_imageBytes!, height: 150)
                  : const Text("No image selected"),

              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: pickImage,
                child: const Text("📷 Upload Photo"),
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
    final Uri phoneUri = Uri(scheme: 'tel', path: number);

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