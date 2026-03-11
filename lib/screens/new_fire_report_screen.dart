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
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  void _submitReport() async {
    if (_formKey.currentState!.validate()) {
      await FirebaseFirestore.instance.collection("reports").add({
        "description": _descriptionController.text,
        "latitude": double.tryParse(_latitudeController.text),
        "longitude": double.tryParse(_longitudeController.text),
        "nearest_station": widget.stationName ?? "",
        "timestamp": DateTime.now(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fire report submitted successfully")),
      );
      Navigator.pop(context); // go back to dashboard
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Fire Report"), backgroundColor: Colors.red),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: "Description"),
                validator: (value) => value!.isEmpty ? "Enter description" : null,
              ),
              TextFormField(
                controller: _latitudeController,
                decoration: const InputDecoration(labelText: "Latitude"),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? "Enter latitude" : null,
              ),
              TextFormField(
                controller: _longitudeController,
                decoration: const InputDecoration(labelText: "Longitude"),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? "Enter longitude" : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submitReport,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("Submit Report"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}