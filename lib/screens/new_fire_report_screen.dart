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

  String? fireType;
  String? fireSize;
  String? evacuationStatus;

  final List<String> fireTypes = [
    'Station Fire',
  ];

  final List<String> fireSizes = [
    "Small",
    "Medium",
    "Large",
  ];

  final List<String> evacuationStatuses = [
    "Evacuated",
    "Evacuation in progress",
    "People still inside",
  ];

  /// 🔥 SUBMIT REPORT
  void _submitReport() async {
    if (_formKey.currentState!.validate()) {
      try {
        /// 🔍 QUERY STATION BY NAME
        final querySnapshot = await FirebaseFirestore.instance
            .collection("stations")
            .where("station_name", isEqualTo: widget.stationName)
            .limit(1)
            .get();

        if (querySnapshot.docs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Station not found in database"),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        /// 📍 GET STATION DATA
        final stationData = querySnapshot.docs.first.data();

        final String ward = stationData["ward"] ?? "";
        final String subcounty = stationData["subcounty"] ?? "";
        final String county = stationData["county"] ?? "";
        final String phoneNumber = stationData["phone"] ?? ""; // <-- fetch phone

        /// 🔥 SAVE REPORT WITH LOCATION
        await FirebaseFirestore.instance.collection("reports").add({

          /// 📍 AUTO LOCATION FROM MATCHED STATION
          "ward": ward,
          "subcounty": subcounty,
          "county": county,

          /// 🚒 STATION INFO
          "reporterName": widget.stationName,
          "reporterPhone": phoneNumber, // <-- new field
          "locationType": "station",
          "isStationOnFire": true,

          /// 🔥 FIRE DETAILS
          "fireType": fireType ?? "Station Fire",
          "fireSize": fireSize,
          "evacuationStatus": evacuationStatus,

          /// 🆕 STATUS FIELD
          "status": "pending",

          /// ⏱ TIME
          "timestamp": DateTime.now(),

          /// OPTIONAL
          "latitude": null,
          "longitude": null,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🚨 Fire reported with station location"),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context);

      } catch (e) {
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

              /// 🔥 FIRE TYPE
              DropdownButtonFormField<String>(
                value: fireType,
                hint: const Text("Select Fire Type"),
                items: fireTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    fireType = value;
                  });
                },
                validator: (value) =>
                value == null ? "Select fire type" : null,
              ),

              const SizedBox(height: 15),

              /// 🔥 FIRE SIZE
              DropdownButtonFormField<String>(
                value: fireSize,
                hint: const Text("Select Fire Size"),
                items: fireSizes.map((size) {
                  return DropdownMenuItem(
                    value: size,
                    child: Text(size),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    fireSize = value;
                  });
                },
                validator: (value) =>
                value == null ? "Select fire size" : null,
              ),

              const SizedBox(height: 15),

              /// 🚨 EVACUATION STATUS
              DropdownButtonFormField<String>(
                value: evacuationStatus,
                hint: const Text("Evacuation Status"),
                items: evacuationStatuses.map((status) {
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
                validator: (value) =>
                value == null ? "Select evacuation status" : null,
              ),

              const SizedBox(height: 25),

              /// 🚀 SUBMIT BUTTON
              ElevatedButton(
                onPressed: _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
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