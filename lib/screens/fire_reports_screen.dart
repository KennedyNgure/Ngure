import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class FireReportsScreen extends StatefulWidget {
  final String filter; // "today", "week", "all"

  const FireReportsScreen({super.key, required this.filter});

  @override
  State<FireReportsScreen> createState() => _FireReportsScreenState();
}

class _FireReportsScreenState extends State<FireReportsScreen> {
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";

  DateTime getStartOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime getStartOfWeek() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  bool matchesSearch(Map<String, dynamic> report) {
    if (searchQuery.isEmpty) return true;

    String timestamp = report["timestamp"] != null
        ? DateFormat("dd MMM yyyy HH:mm").format(report["timestamp"].toDate())
        : "";
    String station = report["station_name"] ?? "";
    String reporter = report["reporterName"] ?? "";
    String status = report["status"] ?? "";

    return timestamp.toLowerCase().contains(searchQuery.toLowerCase()) ||
        station.toLowerCase().contains(searchQuery.toLowerCase()) ||
        reporter.toLowerCase().contains(searchQuery.toLowerCase()) ||
        status.toLowerCase().contains(searchQuery.toLowerCase());
  }

  Future<void> deleteReport(String docId) async {
    try {
      await FirebaseFirestore.instance.collection("reports").doc(docId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Report deleted successfully"),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting report: $e")),
      );
    }
  }

  void viewReportDetails(Map<String, dynamic> report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Fire Incident Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Fire Type: ${report["fireType"] ?? "Unknown"}"),
              Text("Fire Size: ${report["fireSize"] ?? "Unknown"}"),
              Text("People Trapped: ${report["peopleTrapped"] ?? 0}"),
              Text("Evacuation Status: ${report["evacuationStatus"] ?? "Unknown"}"),
              Text("Reporter Name: ${report["reporterName"] ?? "Unknown"}"),
              Text("Reporter Phone: ${report["reporterPhone"] ?? "Unknown"}"),
              Text("Status: ${report["status"] ?? "Unknown"}"),
              Text("Station: ${report["station_name"] ?? "Unknown"}"),
              Text("Latitude: ${report["latitude"] ?? "Unknown"}"),
              Text("Longitude: ${report["longitude"] ?? "Unknown"}"),
              if (report["timestamp"] != null)
                Text(
                  "Timestamp: ${DateFormat("dd MMM yyyy HH:mm").format(report["timestamp"].toDate())}",
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime startOfToday = getStartOfToday();
    DateTime startOfWeek = getStartOfWeek();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.filter == "today"
              ? "Fires Today"
              : widget.filter == "week"
              ? "Fires This Week"
              : "All Fire Reports",
        ),
        backgroundColor: Colors.red,
      ),
      body: Column(
        children: [
          /// Search bar
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText:
                "Search by timestamp, station, reporter, status...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
          ),

          /// Fire Reports List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("reports")
                  .orderBy("timestamp", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var reports = snapshot.data!.docs;

                var filteredReports = reports.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  if (data["timestamp"] == null) return false;

                  DateTime time = data["timestamp"].toDate();

                  if (widget.filter == "today") {
                    if (!time.isAfter(startOfToday)) return false;
                  } else if (widget.filter == "week") {
                    if (!time.isAfter(startOfWeek)) return false;
                  }

                  return matchesSearch(data);
                }).toList();

                if (filteredReports.isEmpty) {
                  return const Center(child: Text("No reports found"));
                }

                return ListView.builder(
                  itemCount: filteredReports.length,
                  itemBuilder: (context, index) {
                    var doc = filteredReports[index];
                    var report = doc.data() as Map<String, dynamic>;

                    String timestamp = report["timestamp"] != null
                        ? DateFormat("dd MMM yyyy HH:mm")
                        .format(report["timestamp"].toDate())
                        : "No timestamp";
                    String station = report["station_name"] ?? "Unknown";
                    String reporter = report["reporterName"] ?? "Unknown";
                    String status = report["status"] ?? "Unknown";

                    return Card(
                      margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: ListTile(
                        title: Text("Reporter: $reporter"),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Station: $station"),
                            Text("Timestamp: $timestamp"),
                            Text("Status: $status"),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () => viewReportDetails(report),
                              child: const Text("View"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => deleteReport(doc.id),
                              child: const Icon(Icons.delete),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
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