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

  // Basic details
  String description = '';
  String reporterName = '';
  String reporterPhone = '';
  String ward = '';
  String subCounty = '';
  String county = '';

  /// 🔥 MARK AS HANDLED
  Future<void> markAsHandled() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    try {
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to mark as handled: $e")),
      );
    }
  }

  /// 🚒 ASSIGN TO STATION (INTER-STATION CHAT)
  Future<void> assignToStation() async {
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();

    final stationsSnapshot =
    await FirebaseFirestore.instance.collection("stations").get();

    if (!mounted) return;

    final String currentStation = widget.stationName;

    List<Map<String, dynamic>> stations = stationsSnapshot.docs
        .map((doc) => doc.data()..['id'] = doc.id)
        .toList();

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
              /// 🔍 SEARCH BAR
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: "Search station by name, phone, ward, county",
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (query) {
                    String q = query.toLowerCase();

                    filteredStations.value = stations.where((station) {
                      return (station['station_name']
                          ?.toLowerCase()
                          .contains(q) ??
                          false) ||
                          (station['phone']
                              ?.toLowerCase()
                              .contains(q) ??
                              false) ||
                          (station['ward']
                              ?.toLowerCase()
                              .contains(q) ??
                              false) ||
                          (station['county']
                              ?.toLowerCase()
                              .contains(q) ??
                              false);
                    }).toList();
                  },
                ),
              ),

              /// 📋 STATIONS LIST
              SizedBox(
                height: 400,
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: filteredStations,
                  builder: (context, list, _) {
                    if (list.isEmpty) {
                      return const Center(
                        child: Text("No stations found"),
                      );
                    }

                    return ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final station = list[index];

                        String selectedStation =
                            station['station_name'] ?? '';

                        /// ✅ DISPLAY NAME (YOU LABEL)
                        String displayName = selectedStation == currentStation
                            ? "You ($selectedStation)"
                            : selectedStation;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: selectedStation == currentStation
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

                          /// 🚀 SEND MESSAGE
                          onTap: () async {
                            List<String> stationsNames = [
                              currentStation,
                              selectedStation
                            ];

                            stationsNames.sort();

                            String chatId =
                                "${stationsNames[0]}_${stationsNames[1]}";

                            String messageText = """🚒 FIRE ALERT DETAILS
Reporter: $reporterName
Phone: ${reporterPhone.isEmpty ? 'N/A' : reporterPhone}

Description:
$description

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

                            /// 📩 SAVE MESSAGE
                            await messageRef.set({
                              "sender": currentStation,
                              "text": messageText,
                              "timestamp": FieldValue.serverTimestamp(),
                            });

                            /// 🔄 UPDATE CHAT META
                            await chatRef.set({
                              "participants": stationsNames,
                              "lastMessage": messageText,
                              "lastTimestamp":
                              FieldValue.serverTimestamp(),
                              "unread_${selectedStation}":
                              FieldValue.increment(1),
                              "unread_${currentStation}": 0,
                            }, SetOptions(merge: true));

                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: SelectableText(
                                    "Fire report sent to $displayName"),
                              ),
                            );

                            Navigator.pop(context); // close bottom sheet
                            Navigator.pop(context); // exit screen
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

  /// 🧱 UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SelectableText("Feed Fire Call"),
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
                  labelText: "Reporter Phone",
                ),
                keyboardType: TextInputType.phone,
                validator: (value) =>
                value == null || value.isEmpty ? "Required" : null,
                onSaved: (value) => reporterPhone = value!.trim(),
              ),

              const SizedBox(height: 12),

              /// Fire Description
              TextFormField(
                initialValue: description,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: "📝 Fire Description",
                  hintText:
                  "Describe the fire:\n• What is burning? (e.g., house, car, forest, electrical wires)\n• How intense is it? (small, spreading, out of control)\n• Are people trapped or injured?",
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                value == null || value.isEmpty ? "Describe the fire" : null,
                onSaved: (value) => description = value!.trim(),
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
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: markAsHandled,
                      child: const SelectableText("Mark as Handled"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.grey[200]),
                      onPressed: assignToStation,
                      child: const SelectableText("Assign Station"),
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