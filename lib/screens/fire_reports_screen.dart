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

  /// 🔍 UPDATED SEARCH FUNCTION
  bool matchesSearch(Map<String, dynamic> report) {
    if (searchQuery.isEmpty) return true;

    final query = searchQuery.toLowerCase();

    String timestamp = report["timestamp"] != null
        ? DateFormat("dd MMM yyyy HH:mm")
        .format(report["timestamp"].toDate())
        : "";

    String station = report["handledBy"] ?? "";
    String reporter = report["reporterName"] ?? "";
    String status = report["status"] ?? "";

    /// 🆕 NEW LOCATION FIELDS
    String ward = report["ward"] ?? "";
    String subcounty = report["subcounty"] ?? "";
    String county = report["county"] ?? "";

    return timestamp.toLowerCase().contains(query) ||
        station.toLowerCase().contains(query) ||
        reporter.toLowerCase().contains(query) ||
        status.toLowerCase().contains(query) ||
        ward.toLowerCase().contains(query) ||
        subcounty.toLowerCase().contains(query) ||
        county.toLowerCase().contains(query) ||
        "$ward $subcounty".toLowerCase().contains(query) ||
        "$ward $subcounty $county".toLowerCase().contains(query);
  }

  Future<void> deleteReport(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection("reports")
          .doc(docId)
          .delete();

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

  /// 🔥 VIEW DETAILS UPDATED
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
              Text("Station: ${report["handledBy"] ?? "Unknown"}"),

              /// 🆕 LOCATION DETAILS
              const SizedBox(height: 10),
              Text("Ward: ${report["ward"] ?? "Unknown"}"),
              Text("Subcounty: ${report["subcounty"] ?? "Unknown"}"),
              Text("County: ${report["county"] ?? "Unknown"}"),
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

          /// 🔍 UPDATED SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText:
                "Search by station, reporter, status, ward, subcounty, county...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.trim();
                });
              },
            ),
          ),

          /// 📋 FIRE REPORTS LIST
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

                    String station = report["handledBy"] ?? "Unknown";
                    String reporter = report["reporterName"] ?? "Unknown";
                    String status = report["status"] ?? "Unknown";

                    /// 🆕 LOCATION
                    String ward = report["ward"] ?? "Unknown";
                    String subcounty = report["subcounty"] ?? "Unknown";
                    String county = report["county"] ?? "Unknown";

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
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
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                              ),
                              child: const Text("View"),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => deleteReport(doc.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Icon(Icons.delete),
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