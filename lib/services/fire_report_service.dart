import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class FireReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future submitReport(
      String description,
      String severity,
      double lat,
      double lon,
      ) async {
    await _firestore.collection("reports").add({
      "description": description,
      "severity": severity,
      "latitude": lat,
      "longitude": lon,
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
  final FireReportService service = FireReportService();

  Future<void> reportFire() async {
    try {
      // Get GPS Location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      double latitude = position.latitude;
      double longitude = position.longitude;

      // Send report to Firestore
      await service.submitReport(
        "Fire spotted near building",
        "High",
        latitude,
        longitude,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🔥 Fire Report Sent Successfully")),
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
        title: const Text("Report Fire"),
        backgroundColor: Colors.red,
      ),
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          ),
          onPressed: reportFire,
          child: const Text(
            "🚨 REPORT FIRE",
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}