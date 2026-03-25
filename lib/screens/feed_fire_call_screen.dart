// feed_fire_call_screen.dart
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

  // Basic details
  String reporterName = '';
  String reporterPhone = '';
  String ward = '';
  String subCounty = '';
  String county = '';

  // Dropdown selections
  String? fireType;
  String? fireSize;
  String? evacuationStatus;

  // Options
  final List<String> fireTypes = [
    'Forest/Bush Fire',
    'House/Building Fire',
    'Vehicle Fire',
    'Electrical Fire',
    'Industrial'
  ];

  final List<String> fireSizes = ['Small', 'Medium', 'Large'];

  final List<String> evacuationOptions = [
    "Evacuated",
    "Evacuation in progress",
    "People still inside",
  ];

  /// 🔥 MARK AS HANDLED
  Future<void> markAsHandled() async {
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();

    await FirebaseFirestore.instance.collection("reports").add({
      "reporterName": reporterName,
      "reporterPhone": reporterPhone,
      "fireType": fireType ?? 'Unknown',
      "fireSize": fireSize ?? 'Unknown',
      "evacuationStatus": evacuationStatus ?? 'Unknown',
      "ward": ward,
      "subcounty": subCounty,
      "county": county,
      "handledBy": widget.stationName,
      "status": "handled",
      "timestamp": FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Fire report saved as handled")),
    );

    Navigator.pop(context);
  }

  /// 🚒 ASSIGN TO STATION (INTER-STATION CHAT)
  /// 🚒 ASSIGN TO STATION (INTER-STATION CHAT)
  Future<void> assignToStation() async {
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();

    final stationsSnapshot =
    await FirebaseFirestore.instance.collection("stations").get();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: stationsSnapshot.docs.map((doc) {
            final station = doc.data();
            String selectedStation = station["station_name"];

            return ListTile(
              title: Text(selectedStation),
              subtitle: Text(
                "${station["ward"] ?? ''}, ${station["subCounty"] ?? ''}, ${station["county"] ?? ''}",
              ),
              onTap: () async {
                String currentStation = widget.stationName;

                /// 🔥 CREATE CONSISTENT CHAT ID
                List<String> stations = [currentStation, selectedStation];
                stations.sort();
                String chatId = "${stations[0]}_${stations[1]}";
                /// 🔥 BUILD FIRE MESSAGE
                String messageText = """
🚒 FIRE ALERT DETAILS

Reporter: $reporterName
Phone: ${reporterPhone.isEmpty ? 'N/A' : reporterPhone}

Type: ${fireType ?? 'Unknown'}
Size: ${fireSize ?? 'Unknown'}
Evacuation: ${evacuationStatus ?? 'Unknown'}

Location:
Ward: $ward
Subcounty: $subCounty
County: $county

Please respond immediately.
""";

                final chatRef = FirebaseFirestore.instance
                    .collection("interstation_chats")
                    .doc(chatId);

                final messageRef = chatRef.collection("messages").doc();

                /// 🔥 SAVE MESSAGE
                await messageRef.set({
                  "sender": currentStation,
                  "text": messageText,
                  "timestamp": FieldValue.serverTimestamp(),
                });

                /// 🔥 UPDATE CHAT METADATA
                await chatRef.set({
                  "participants": [stations[0], stations[1]],
                  "lastMessage": messageText,
                  "lastTimestamp": FieldValue.serverTimestamp(),
                  "unread_${selectedStation}": FieldValue.increment(1),
                  "unread_${currentStation}": 0,
                }, SetOptions(merge: true));

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Fire report sent to $selectedStation"),
                  ),
                );

                Navigator.pop(context); // close bottom sheet
                Navigator.pop(context); // exit screen
              },
            );
          }).toList(),
        );
      },
    );
  }

  /// 🧱 UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Feed Fire Call"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              /// Reporter Name
              TextFormField(
                decoration: const InputDecoration(labelText: "Reporter Name"),
                validator: (value) => value!.isEmpty ? "Required" : null,
                onSaved: (value) => reporterName = value!.trim(),
              ),

              /// Reporter Phone
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Reporter Phone (optional)",
                ),
                keyboardType: TextInputType.phone,
                onSaved: (value) => reporterPhone = value?.trim() ?? '',
              ),

              const SizedBox(height: 12),

              /// Fire Type
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Type of Fire"),
                value: fireType,
                items: fireTypes
                    .map((type) =>
                    DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                validator: (value) => value == null ? "Select fire type" : null,
                onChanged: (value) => setState(() => fireType = value),
              ),

              const SizedBox(height: 12),

              /// Fire Size
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Size of Fire"),
                value: fireSize,
                items: fireSizes
                    .map((size) =>
                    DropdownMenuItem(value: size, child: Text(size)))
                    .toList(),
                validator: (value) => value == null ? "Select fire size" : null,
                onChanged: (value) => setState(() => fireSize = value),
              ),

              const SizedBox(height: 12),

              /// Evacuation Status
              DropdownButtonFormField<String>(
                decoration:
                const InputDecoration(labelText: "Evacuation Status"),
                value: evacuationStatus,
                items: evacuationOptions
                    .map((status) =>
                    DropdownMenuItem(value: status, child: Text(status)))
                    .toList(),
                validator: (value) =>
                value == null ? "Select evacuation status" : null,
                onChanged: (value) =>
                    setState(() => evacuationStatus = value),
              ),

              const SizedBox(height: 12),

              /// Location Fields
              TextFormField(
                decoration: const InputDecoration(labelText: "Ward"),
                onSaved: (value) => ward = value!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: "Subcounty"),
                onSaved: (value) => subCounty = value!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: "County"),
                onSaved: (value) => county = value!.trim(),
              ),

              const SizedBox(height: 20),

              /// Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      onPressed: markAsHandled,
                      child: const Text("Mark as Handled"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200]),
                      onPressed: assignToStation,
                      child: const Text("Assign Station"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}