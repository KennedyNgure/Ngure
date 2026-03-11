import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisteredStationsScreen extends StatelessWidget {
  const RegisteredStationsScreen({super.key});

  /// Delete station using station_name
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
        SnackBar(
          content: Text("Error deleting station: $e"),
        ),
      );
    }
  }

  /// Confirmation dialog
  void confirmDelete(BuildContext context, String stationName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Station"),
          content: Text(
            "Are you sure you want to delete $stationName? This will permanently remove all station data.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Registered Stations"),
        backgroundColor: Colors.red,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("stations").snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var stations = snapshot.data!.docs;

          if (stations.isEmpty) {
            return const Center(
              child: Text("No registered stations"),
            );
          }

          return ListView.builder(
            itemCount: stations.length,
            itemBuilder: (context, index) {
              var station =
              stations[index].data() as Map<String, dynamic>;

              /// Correct Firestore field names
              String name = station["station_name"] ?? "Unknown";
              String phone = station["phone"] ?? "No phone";
              String email = station["email"] ?? "No email";

              return Card(
                margin:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.fire_truck, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

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

                      const SizedBox(height: 15),

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
                          label: const Text("Delete Station"),
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
    );
  }
}