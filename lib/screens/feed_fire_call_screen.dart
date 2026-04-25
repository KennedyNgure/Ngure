// lib/screens/feed_fire_call_screen.dart
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

  String description = '';
  String reporterName = '';
  String reporterPhone = '';
  String ward = '';
  String subCounty = '';
  String county = '';

  Future<void> markAsHandled() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    await FirebaseFirestore.instance.collection("reports").add({
      "description": description,
      "reporterName": reporterName,
      "reporterPhone": reporterPhone,
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

  Future<void> assignToStation() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final stationsSnapshot =
    await FirebaseFirestore.instance.collection("stations").get();

    if (!mounted) return;

    final String currentStation = widget.stationName;

    /// 🔥 STRICT FILTER: role == station AND status == verified
    List<Map<String, dynamic>> stations =
    stationsSnapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).where((station) {
      final role =
      (station['role'] ?? '').toString().trim().toLowerCase();
      final status =
      (station['status'] ?? '').toString().trim().toLowerCase();
      final name = (station['station_name'] ?? '').toString();

      return ((role == 'station' && status == 'verified') ||
          name == currentStation);
    }).toList();

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (context) {
        TextEditingController searchController = TextEditingController();

        ValueNotifier<List<Map<String, dynamic>>> filteredStations =
        ValueNotifier(stations);

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              /// 🔍 SEARCH
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText:
                    "Search station by name, phone, ward, county",
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (query) {
                    String q = query.toLowerCase();

                    filteredStations.value = stations.where((station) {
                      return (station['station_name']
                          ?.toLowerCase()
                          .contains(q) ??
                          false) ||
                          (station['phone']?.toLowerCase().contains(q) ??
                              false) ||
                          (station['ward']?.toLowerCase().contains(q) ??
                              false) ||
                          (station['county']?.toLowerCase().contains(q) ??
                              false);
                    }).toList();
                  },
                ),
              ),

              /// 📋 LIST
              SizedBox(
                height: 400,
                child: ValueListenableBuilder<
                    List<Map<String, dynamic>>>(
                  valueListenable: filteredStations,
                  builder: (context, list, _) {
                    if (list.isEmpty) {
                      return const Center(
                        child: Text("No verified stations found"),
                      );
                    }

                    return ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final station = list[index];

                        String selectedStation =
                            station['station_name'] ?? '';

                        String displayName =
                        selectedStation == currentStation
                            ? "You ($selectedStation)"
                            : selectedStation;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                            selectedStation == currentStation
                                ? Colors.blue
                                : Colors.red,
                            child: const Icon(
                              Icons.local_fire_department,
                              color: Colors.white,
                            ),
                          ),
                          title: SelectableText(displayName),
                          subtitle: SelectableText(
                            "${station['ward'] ?? ''}, ${station['subCounty'] ?? ''}, ${station['county'] ?? ''}",
                          ),

                          onTap: () async {
                            List<String> stationsNames = [
                              currentStation,
                              selectedStation
                            ];

                            stationsNames.sort();

                            String chatId =
                                "${stationsNames[0]}_${stationsNames[1]}";

                            String messageText = """
🚒 FIRE ALERT DETAILS
Reporter: $reporterName
Phone: ${reporterPhone.isEmpty ? 'N/A' : reporterPhone}

Description: $description

Location:
Ward: $ward
Subcounty: $subCounty
County: $county

Please respond immediately.
""";

                            final chatRef = FirebaseFirestore.instance
                                .collection("interstation_chats")
                                .doc(chatId);

                            final messageRef =
                            chatRef.collection("messages").doc();

                            await messageRef.set({
                              "sender": currentStation,
                              "text": messageText,
                              "timestamp":
                              FieldValue.serverTimestamp(),
                            });

                            await chatRef.set({
                              "participants": stationsNames,
                              "lastMessage": messageText,
                              "lastTimestamp":
                              FieldValue.serverTimestamp(),
                              "unread_$selectedStation":
                              FieldValue.increment(1),
                              "unread_$currentStation": 0,
                            }, SetOptions(merge: true));

                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    "Fire report sent to $displayName"),
                              ),
                            );

                            Navigator.pop(context);
                            Navigator.pop(context);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Feed Fire Call"),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                decoration:
                const InputDecoration(labelText: "Reporter Name"),
                onSaved: (v) => reporterName = v!.trim(),
              ),
              TextFormField(
                decoration:
                const InputDecoration(labelText: "Reporter Phone"),
                onSaved: (v) => reporterPhone = v!.trim(),
              ),
              TextFormField(
                maxLines: 5,
                decoration:
                const InputDecoration(labelText: "Fire Description"),
                onSaved: (v) => description = v!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: "Ward"),
                onSaved: (v) => ward = v!.trim(),
              ),
              TextFormField(
                decoration:
                const InputDecoration(labelText: "Subcounty"),
                onSaved: (v) => subCounty = v!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: "County"),
                onSaved: (v) => county = v!.trim(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: markAsHandled,
                      style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.green),
                      child: const Text("Mark as Handled"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: assignToStation,
                      style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.blue),
                      child: const Text("Assign Station"),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}