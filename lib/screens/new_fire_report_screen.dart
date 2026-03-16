import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NewFireReportScreen extends StatefulWidget {
  final String? stationName;

  const NewFireReportScreen({super.key, this.stationName});

  @override
  State<NewFireReportScreen> createState() => _NewFireReportScreenState();
}

class _NewFireReportScreenState extends State<NewFireReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  String? fireType;
  String? fireSize;
  String? evacuationStatus;

  final List<String> fireTypes = [
    "Electrical Fire",
    "Forest Fire",
    "Building Fire",
    "Vehicle Fire",
    "Gas Fire",
    "Other"
  ];

  final List<String> fireSizes = [
    "Small",
    "Medium",
    "Large",
    "Out of Control"
  ];

  final List<String> evacuationStatuses = [
    "Not Required",
    "In Progress",
    "Completed",
    "Unknown"
  ];

  void _submitReport() async {
    if (_formKey.currentState!.validate()) {
      await FirebaseFirestore.instance.collection("reports").add({
        "latitude": double.tryParse(_latitudeController.text),
        "longitude": double.tryParse(_longitudeController.text),
        "fire_type": fireType,
        "fire_size": fireSize,
        "evacuation_status": evacuationStatus,
        "nearest_station": widget.stationName ?? "",
        "timestamp": DateTime.now(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fire report submitted successfully")),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Fire Report"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _latitudeController,
                decoration: const InputDecoration(labelText: "Latitude"),
                keyboardType: TextInputType.number,
                validator: (value) =>
                value!.isEmpty ? "Enter latitude" : null,
              ),

              TextFormField(
                controller: _longitudeController,
                decoration: const InputDecoration(labelText: "Longitude"),
                keyboardType: TextInputType.number,
                validator: (value) =>
                value!.isEmpty ? "Enter longitude" : null,
              ),

              const SizedBox(height: 15),

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

              ElevatedButton(
                onPressed: _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text("Submit Report"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}