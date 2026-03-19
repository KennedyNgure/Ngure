import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisteredStationsScreen extends StatefulWidget {
  const RegisteredStationsScreen({super.key});

  @override
  State<RegisteredStationsScreen> createState() =>
      _RegisteredStationsScreenState();
}

class _RegisteredStationsScreenState
    extends State<RegisteredStationsScreen> {

  String searchQuery = "";

  /// DELETE STATION
  Future<void> deleteStation(BuildContext context, String stationName) async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection("stations")
          .where("station_name", isEqualTo: stationName)
          .get();

      for (var doc in snapshot.docs) {
        await FirebaseFirestore.instance
            .collection("stations")
            .doc(doc.id)
            .delete();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Station deleted successfully"),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting station: $e")),
      );
    }
  }

  /// CONFIRM DELETE
  void confirmDelete(BuildContext context, String stationName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Station"),
          content: Text(
            "Are you sure you want to delete $stationName?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(context);
                deleteStation(context, stationName);
              },
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );
  }

  /// 🔍 SEARCH FILTER FUNCTION
  bool matchesSearch(Map<String, dynamic> station) {
    final query = searchQuery.toLowerCase();

    final name = (station["station_name"] ?? "").toLowerCase();
    final ward = (station["ward"] ?? "").toLowerCase();
    final subcounty = (station["subcounty"] ?? "").toLowerCase();
    final county = (station["county"] ?? "").toLowerCase();

    return name.contains(query) ||
        ward.contains(query) ||
        subcounty.contains(query) ||
        county.contains(query) ||
        "$ward $subcounty".contains(query) ||
        "$ward $subcounty $county".contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Registered Stations"),
        backgroundColor: Colors.red,
      ),
      body: Column(
        children: [

          /// 🔍 SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText:
                "Search by name, ward, subcounty, county...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.trim();
                });
              },
            ),
          ),

          /// 📋 STATIONS LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("stations")
                  .snapshots(),
              builder: (context, snapshot) {

                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                var stations = snapshot.data!.docs;

                /// 🔍 APPLY SEARCH FILTER
                var filteredStations = stations.where((doc) {
                  var station =
                  doc.data() as Map<String, dynamic>;
                  return matchesSearch(station);
                }).toList();

                if (filteredStations.isEmpty) {
                  return const Center(
                    child: Text("No matching stations found"),
                  );
                }

                return ListView.builder(
                  itemCount: filteredStations.length,
                  itemBuilder: (context, index) {

                    var station =
                    filteredStations[index].data()
                    as Map<String, dynamic>;

                    String name =
                        station["station_name"] ?? "Unknown";
                    String phone = station["phone"] ?? "No phone";
                    String email = station["email"] ?? "No email";

                    String ward = station["ward"] ?? "Unknown";
                    String subcounty =
                        station["subcounty"] ?? "Unknown";
                    String county = station["county"] ?? "Unknown";

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [

                            /// STATION NAME
                            Row(
                              children: [
                                const Icon(Icons.fire_truck,
                                    color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight:
                                      FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            /// CONTACT INFO
                            Row(
                              children: [
                                const Icon(Icons.phone, size: 18),
                                const SizedBox(width: 8),
                                Text(phone),
                              ],
                            ),

                            const SizedBox(height: 6),

                            Row(
                              children: [
                                const Icon(Icons.email, size: 18),
                                const SizedBox(width: 8),
                                Text(email),
                              ],
                            ),

                            const SizedBox(height: 10),

                            /// 📍 LOCATION DETAILS
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 18,
                                    color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Ward: $ward",
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 4),

                            Text("Subcounty: $subcounty"),
                            Text("County: $county"),

                            const SizedBox(height: 15),

                            /// DELETE BUTTON
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                onPressed: () {
                                  confirmDelete(context, name);
                                },
                                icon: const Icon(Icons.delete),
                                label:
                                const Text("Delete Station"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}