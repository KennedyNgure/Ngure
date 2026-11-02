import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FeedFireCallScreen extends StatefulWidget {
  final String stationName;

  const FeedFireCallScreen({super.key, required this.stationName});

  @override
  State<FeedFireCallScreen> createState() => _FeedFireCallScreenState();
}

class _FeedFireCallScreenState extends State<FeedFireCallScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form values
  String description = '';
  String reporterName = '';
  String reporterPhone = '';

  // Location Selection State
  String? selectedCounty;
  String? selectedSubCounty;
  String? selectedWard;

  bool _isSaving = false;

  // --- KENYA LOCATION DATA STRUCTURE ---
  // Note: You can expand this map with all 47 counties.
  final Map<String, Map<String, List<String>>> kenyaData = {
    "Nairobi": {
      "Westlands": ["Parklands", "Kitisuru", "Kangemi", "Mountain View"],
      "Dagoretti North": ["Kileleshwa", "Kawangware", "Gatina"],
      "Kasarani": ["Clay City", "Mwiki", "Kasarani", "Njiru"],
      "Lang'ata": ["Karen", "South C", "Mugumo-ini"],
    },
    "Mombasa": {
      "Nyali": ["Frere Town", "Ziwa La Ng'ombe", "Mkomani"],
      "Mvita": ["Majengo", "Railway", "Tononoka"],
      "Likoni": ["Mtongwe", "Shika Adabu", "Bofu"],
    },
    "Kiambu": {
      "Thika Town": ["Township", "Kamenu", "Hospital"],
      "Ruiru": ["Biashara", "Gatongora", "Kahawa Sukari"],
      "Kikuyu": ["Kikuyu", "Sigona", "Kinoo"],
    },
    "Nakuru": {
      "Nakuru East": ["Biashara", "Kivumbini", "Flamingo"],
      "Naivasha": ["Hells Gate", "Lake View", "Mai Mahiu"],
    },
    "Kisumu": {
      "Kisumu Central": ["Market", "Milimani", "Kondele"],
      "Kisumu East": ["Manyatta B", "Nyalenda A", "Kolwa East"],
    }
  };

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.red),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  /// Mark as Handled Logic
  Future<void> markAsHandled() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedCounty == null || selectedSubCounty == null || selectedWard == null) {
      _showSnackBar("Please select all location details", Colors.orange);
      return;
    }
    _formKey.currentState!.save();

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection("reports").add({
        "description": description,
        "reporterName": reporterName,
        "reporterPhone": reporterPhone,
        "ward": selectedWard,
        "subcounty": selectedSubCounty,
        "county": selectedCounty,
        "handledBy": widget.stationName,
        "status": "handled",
        "timestamp": FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnackBar("Incident logged and marked as handled", Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar("Error: $e", Colors.red);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  /// Assign to Station Logic
  Future<void> assignToStation() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedCounty == null || selectedSubCounty == null || selectedWard == null) {
      _showSnackBar("Please select all location details", Colors.orange);
      return;
    }
    _formKey.currentState!.save();

    final stationsSnapshot = await FirebaseFirestore.instance.collection("stations").get();
    final String currentStation = widget.stationName;

    List<Map<String, dynamic>> verifiedStations = stationsSnapshot.docs
        .map((doc) => {...doc.data(), 'id': doc.id})
        .where((s) => (s['role'] == 'station' && s['status'] == 'verified') || s['station_name'] == currentStation)
        .toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, controller) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 20),
                  const Text("Assign Fire Station", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Search stations...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        verifiedStations = stationsSnapshot.docs
                            .map((doc) => {...doc.data(), 'id': doc.id})
                            .where((s) => ((s['role'] == 'station' && s['status'] == 'verified') || s['station_name'] == currentStation))
                            .where((s) => s['station_name'].toString().toLowerCase().contains(val.toLowerCase()))
                            .toList();
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: verifiedStations.length,
                      itemBuilder: (context, index) {
                        final station = verifiedStations[index];
                        final name = station['station_name'] ?? 'Unknown';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.fire_truck, color: Colors.white, size: 20)),
                            title: Text(name == currentStation ? "You ($name)" : name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("${station['ward'] ?? ''}, ${station['county'] ?? ''}"),
                            trailing: const Icon(Icons.send_rounded, color: Colors.blue),
                            onTap: () => _finalizeAssignment(name, currentStation),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _finalizeAssignment(String targetStation, String currentStation) async {
    String chatId = currentStation.compareTo(targetStation) < 0
        ? "${currentStation}_$targetStation"
        : "${targetStation}_$currentStation";

    String messageText = "🚒 *NEW FIRE ALERT*\n\nReporter: $reporterName\nPhone: $reporterPhone\n\nDesc: $description\n\nLocation: $selectedWard, $selectedSubCounty, $selectedCounty";

    await FirebaseFirestore.instance.collection("interstation_chats").doc(chatId).collection("messages").add({
      "sender": currentStation,
      "text": messageText,
      "timestamp": FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection("interstation_chats").doc(chatId).set({
      "participants": [currentStation, targetStation],
      "lastMessage": messageText,
      "lastTimestamp": FieldValue.serverTimestamp(),
      "unread_$targetStation": FieldValue.increment(1),
    }, SetOptions(merge: true));

    if (mounted) {
      Navigator.pop(context);
      Navigator.pop(context);
      _showSnackBar("Alert sent to $targetStation", Colors.blue);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Log Fire Incident", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.red,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("Reporter Information"),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        decoration: _buildInputDecoration("Reporter Name", Icons.person),
                        validator: (v) => v!.isEmpty ? "Required" : null,
                        onSaved: (v) => reporterName = v!.trim(),
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        keyboardType: TextInputType.phone,
                        decoration: _buildInputDecoration("Phone Number", Icons.phone),
                        validator: (v) {
                          if (v!.isEmpty) return "Required";
                          if (v.length < 10) return "Enter valid phone number";
                          return null;
                        },
                        onSaved: (v) => reporterPhone = v!.trim(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle("Incident Details"),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextFormField(
                    maxLines: 4,
                    decoration: _buildInputDecoration("Brief Description of Fire", Icons.description),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                    onSaved: (v) => description = v!.trim(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle("Location Details"),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // COUNTY DROPDOWN
                      DropdownButtonFormField<String>(
                        value: selectedCounty,
                        decoration: _buildInputDecoration("Select County", Icons.explore),
                        items: kenyaData.keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedCounty = val;
                            selectedSubCounty = null;
                            selectedWard = null;
                          });
                        },
                        validator: (v) => v == null ? "Required" : null,
                      ),
                      const SizedBox(height: 15),

                      // SUBCOUNTY DROPDOWN
                      DropdownButtonFormField<String>(
                        value: selectedSubCounty,
                        decoration: _buildInputDecoration("Select Sub-County", Icons.location_city),
                        items: selectedCounty == null
                            ? []
                            : kenyaData[selectedCounty]!.keys.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedSubCounty = val;
                            selectedWard = null;
                          });
                        },
                        validator: (v) => v == null ? "Required" : null,
                      ),
                      const SizedBox(height: 15),

                      // WARD DROPDOWN
                      DropdownButtonFormField<String>(
                        value: selectedWard,
                        decoration: _buildInputDecoration("Select Ward", Icons.map),
                        items: (selectedCounty == null || selectedSubCounty == null)
                            ? []
                            : kenyaData[selectedCounty]![selectedSubCounty]!.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                        onChanged: (val) => setState(() => selectedWard = val),
                        validator: (v) => v == null ? "Required" : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: markAsHandled,
                      icon: const Icon(Icons.check_circle),
                      label: const Text("HANDLED BY US"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: assignToStation,
                      icon: const Icon(Icons.share_location),
                      label: const Text("FORWARD ALERT"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1.1),
      ),
    );
  }
}