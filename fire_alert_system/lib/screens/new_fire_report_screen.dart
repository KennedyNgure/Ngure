import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NewFireReportScreen extends StatefulWidget {
  final String stationName;

  const NewFireReportScreen({super.key, required this.stationName});

  @override
  State<NewFireReportScreen> createState() => _NewFireReportScreenState();
}

class _NewFireReportScreenState extends State<NewFireReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController fireDescriptionController =
  TextEditingController();

  /// 🔥 SUBMIT REPORT
  void _submitReport() async {
    if (_formKey.currentState!.validate()) {
      try {
        // 🔍 GET STATION
        final querySnapshot = await FirebaseFirestore.instance
            .collection("stations")
            .where("station_name", isEqualTo: widget.stationName)
            .limit(1)
            .get();

        if (!mounted) return;

        // ❌ NO STATION FOUND
        if (querySnapshot.docs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Station not found")),
          );
          return;
        }

        /// 📍 GET STATION DATA
        final stationData = querySnapshot.docs.first.data();

        final String ward = stationData["ward"] ?? "";
        final String subcounty = stationData["subcounty"] ?? "";
        final String county = stationData["county"] ?? "";
        final String phoneNumber = stationData["phone"] ?? "";

        /// 🔥 SAVE REPORT
        await FirebaseFirestore.instance.collection("reports").add({
          "ward": ward,
          "subcounty": subcounty,
          "county": county,
          "reporterName": widget.stationName,
          "reporterPhone": phoneNumber,
          "locationType": "station",
          "isStationOnFire": true,
          "description": fireDescriptionController.text.trim(),
          "status": "pending",
          "timestamp": DateTime.now(),
          "latitude": null,
          "longitude": null,
        });

        if (!mounted) return;

        // ✅ SUCCESS MESSAGE
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🚨 Fire reported with station location"),
            backgroundColor: Colors.green,
          ),
        );

        // ✅ GO BACK
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;

        // ❌ ERROR MESSAGE
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    fireDescriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🚨 Station Emergency"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              /// 🚒 STATION DISPLAY
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Station: ${widget.stationName}\n⚠️ Reporting this station is on fire",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 20),

              /// 🔥 FIRE DESCRIPTION
              TextFormField(
                controller: fireDescriptionController,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                  "Describe the fire:\n"
                      "• What is burning? (e.g., house, car, forest, electrical wires)\n"
                      "• How intense is it? (small, spreading, out of control)\n"
                      "• Are people trapped or injured?",
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please describe the fire";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 25),

              /// 🚀 SUBMIT BUTTON
              ElevatedButton(
                onPressed: _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text(
                  "🚨 REPORT STATION FIRE",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}