import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FireReportsScreen extends StatefulWidget {
  const FireReportsScreen({super.key});

  @override
  State<FireReportsScreen> createState() => _FireReportsScreenState();
}

class _FireReportsScreenState extends State<FireReportsScreen> {
  final TextEditingController searchController = TextEditingController();
  String searchTimestamp = "";

  Future<void> deleteReportsByTimestamp() async {
    if (searchTimestamp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter timestamp first")),
      );
      return;
    }

    try {
      QuerySnapshot snapshot =
      await FirebaseFirestore.instance.collection("reports").get();

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;

        if (data["timestamp"] != null) {
          String time = data["timestamp"].toDate().toString();

          if (time.contains(searchTimestamp)) {
            await FirebaseFirestore.instance
                .collection("reports")
                .doc(doc.id)
                .delete();
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Reports deleted successfully"),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting reports: $e")),
      );
    }
  }

  void confirmDelete() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Reports"),
          content:
          const Text("Delete all reports with this timestamp?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style:
              ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(context);
                deleteReportsByTimestamp();
              },
              child: const Text("Delete"),
            )
          ],
        );
      },
    );
  }

  bool matchesSearch(Map<String, dynamic> report) {
    if (searchTimestamp.isEmpty) return true;

    if (report["timestamp"] == null) return false;

    String time = report["timestamp"].toDate().toString();

    return time.contains(searchTimestamp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Reports"),
        backgroundColor: Colors.red,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: "Search by timestamp...",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchTimestamp = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 18),
                  ),
                  onPressed: confirmDelete,
                  icon: const Icon(Icons.delete),
                  label: const Text("Delete"),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("reports")
                  .orderBy("timestamp", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                var reports = snapshot.data!.docs;

                var filteredReports = reports.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  return matchesSearch(data);
                }).toList();

                if (filteredReports.isEmpty) {
                  return const Center(
                    child: Text("No reports found"),
                  );
                }

                return ListView.builder(
                  itemCount: filteredReports.length,
                  itemBuilder: (context, index) {
                    var report = filteredReports[index].data()
                    as Map<String, dynamic>;

                    String description =
                        report["description"] ?? "Fire Incident";
                    String latitude =
                        report["latitude"]?.toString() ?? "Unknown";
                    String longitude =
                        report["longitude"]?.toString() ?? "Unknown";
                    String station =
                        report["nearest_station"] ?? "Unknown";

                    String time = report["timestamp"] != null
                        ? report["timestamp"].toDate().toString()
                        : "No timestamp";

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                    Icons.local_fire_department,
                                    color: Colors.red),
                                const SizedBox(width: 8),
                                Text(
                                  description,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text("Latitude: $latitude"),
                            Text("Longitude: $longitude"),
                            const SizedBox(height: 5),
                            Text("Station: $station"),
                            const SizedBox(height: 5),
                            Text(
                              "Timestamp: $time",
                              style: const TextStyle(
                                  color: Colors.grey),
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