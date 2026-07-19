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
  final TextEditingController fireDescriptionController = TextEditingController();
  bool _isLoading = false;

  /// 🛠️ CUSTOM INPUT DECORATION
  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      alignLabelWithHint: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  /// 🔥 SUBMIT REPORT
  void _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 🔍 FETCH STATION METADATA
      final querySnapshot = await FirebaseFirestore.instance
          .collection("stations")
          .where("station_name", isEqualTo: widget.stationName)
          .limit(1)
          .get();

      if (!mounted) return;

      if (querySnapshot.docs.isEmpty) {
        _showSnackBar("Station metadata not found", Colors.red);
        setState(() => _isLoading = false);
        return;
      }

      final stationData = querySnapshot.docs.first.data();

      /// 🔥 SAVE REPORT TO FIRESTORE
      await FirebaseFirestore.instance.collection("reports").add({
        "ward": stationData["ward"] ?? "Unknown",
        "subcounty": stationData["subcounty"] ?? "Unknown",
        "county": stationData["county"] ?? "Unknown",
        "reporterName": widget.stationName,
        "reporterPhone": stationData["phone"] ?? "Unknown",
        "locationType": "station",
        "isStationOnFire": true,
        "description": fireDescriptionController.text.trim(),
        "status": "pending",
        "timestamp": FieldValue.serverTimestamp(),
        "latitude": null,
        "longitude": null,
      });

      if (!mounted) return;

      _showSnackBar("🚨 STATION FIRE ALERT DISPATCHED", Colors.green);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    fireDescriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Station Emergency", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : SingleChildScrollView(
        child: Column(
          children: [
            // --- WARNING HEADER ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: const [
                  Icon(Icons.warning_amber_rounded, size: 60, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    "IMMEDIATE DANGER",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    "Reporting a fire at your own station",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- STATION INFO CARD ---
                    const Text(
                      "EMERGENCY BRIEF",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.red.shade200),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.red.shade50,
                            child: const Icon(Icons.business, color: Colors.red),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.stationName,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const Text("Location data will be auto-attached",
                                    style: TextStyle(fontSize: 12, color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

                    // --- FIRE DESCRIPTION ---
                    const Text(
                      "INCIDENT DESCRIPTION",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: fireDescriptionController,
                      maxLines: 6,
                      decoration: _buildInputDecoration(
                        "Describe the fire details...\n\n"
                            "• What exactly is burning?\n"
                            "• Are chemicals or fuels involved?\n"
                            "• Is everyone evacuated?",
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Description is required for response units";
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 30),

                    // --- ACTION BUTTON ---
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton.icon(
                        onPressed: _submitReport,
                        icon: const Icon(Icons.flash_on, color: Colors.white),
                        label: const Text(
                          "DISPATCH EMERGENCY ALERT",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel and Go Back", style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}