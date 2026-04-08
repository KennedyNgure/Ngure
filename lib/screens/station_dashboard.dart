import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'feed_fire_call_screen.dart';
import 'login_screen.dart';
import 'report_fire_screen.dart';
import 'station_profile.dart';
import 'new_fire_report_screen.dart';
import 'interstation_communication_screen.dart';

class StationDashboard extends StatefulWidget {
  final String stationName;

  const StationDashboard({super.key, required this.stationName});

  @override
  State<StationDashboard> createState() => _StationDashboardState();
}

class _StationDashboardState extends State<StationDashboard> {
  String? stationCounty;
  final TextEditingController searchController = TextEditingController();
  String? searchQuery;

  String? expandedReportId;
  List<String> previousReportIds = [];

  @override
  void initState() {
    super.initState();
    loadStationCounty();
  }

  Future<void> loadStationCounty() async {
    var query = await FirebaseFirestore.instance
        .collection("stations")
        .where("station_name", isEqualTo: widget.stationName)
        .get();

    if (query.docs.isNotEmpty) {
      var data = query.docs.first.data();
      setState(() {
        stationCounty = (data["county"] ?? "").toString().trim();
      });
    }
  }

  Future<void> markAsHandled(String reportId) async {
    await FirebaseFirestore.instance
        .collection("reports")
        .doc(reportId)
        .update({
      "status": "handled",
      "handledBy": widget.stationName,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Fire marked as handled")),
    );
  }

  void _triggerAlarm(String description) {
    SystemSound.play(SystemSoundType.alert);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("🔥 New Fire Alert!"),
        content: Text(
          "New fire reported:\n${description.isNotEmpty ? description : 'No description provided'}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Station Dashboard"),
        backgroundColor: Colors.red,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      StationProfile(stationName: widget.stationName),
                ),
              );
            },
            icon: const Icon(Icons.person, color: Colors.white),
            label: const Text("Profile", style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => LoginScreen()),
              );
            },
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.local_fire_department,
                    color: Colors.red, size: 40),
                title: Text(widget.stationName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(stationCounty ?? ""),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  icon: const Icon(Icons.warning),
                  label: const Text("New Alert"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NewFireReportScreen(
                            stationName: widget.stationName),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  icon: const Icon(Icons.phone),
                  label: const Text("Feed Fire Call"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FeedFireCallScreen(
                            stationName: widget.stationName),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  icon: const Icon(Icons.chat),
                  label: const Text("Inter-station Communication"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InterstationCommunicationScreen(
                            stationName: widget.stationName),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 25),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Incoming Fire Reports",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search by Ward, Subcounty, or County",
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase().trim();
                });
              },
            ),

            const SizedBox(height: 10),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("reports")
                    .where("status", isEqualTo: "pending")
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final reports = snapshot.data!.docs
                      .map((doc) => {
                    "id": doc.id,
                    ...doc.data() as Map<String, dynamic>
                  })
                      .where((report) {
                    if (searchQuery == null || searchQuery!.isEmpty) return true;

                    return (report["ward"] ?? "")
                        .toString()
                        .toLowerCase()
                        .contains(searchQuery!) ||
                        (report["subcounty"] ?? "")
                            .toString()
                            .toLowerCase()
                            .contains(searchQuery!) ||
                        (report["county"] ?? "")
                            .toString()
                            .toLowerCase()
                            .contains(searchQuery!);
                  }).toList();

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    for (var report in reports) {
                      if (!previousReportIds.contains(report["id"]) &&
                          report["county"]?.toString().toLowerCase() ==
                              stationCounty?.toLowerCase()) {
                        _triggerAlarm(report["description"] ?? "No description");
                      }
                    }

                    previousReportIds =
                        reports.map((r) => r["id"].toString()).toList();
                  });

                  if (reports.isEmpty) {
                    return const Center(child: Text("No fire reports available"));
                  }

                  return ListView.builder(
                    itemCount: reports.length,
                    itemBuilder: (context, index) {
                      final report = reports[index];

                      return Card(
                        elevation: 3,
                        margin:
                        const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(
                                report["description"] ?? "No Description",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                  "${report["ward"]}, ${report["subcounty"]}, ${report["county"]}"),
                            ),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text("Handled"),
                                  onPressed: () {
                                    markAsHandled(report["id"]);
                                  },
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                  ),
                                  child: Text(
                                    expandedReportId == report["id"]
                                        ? "Hide"
                                        : "View",
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      expandedReportId =
                                      expandedReportId == report["id"]
                                          ? null
                                          : report["id"];
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (expandedReportId == report["id"])
                              Container(
                                padding: const EdgeInsets.all(12),
                                color: Colors.grey.shade100,
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text("🌍 County: ${report["county"] ?? ""}"),
                                    Text(
                                        "📍 Subcounty: ${report["subcounty"] ?? ""}"),
                                    Text("🏘 Ward: ${report["ward"] ?? ""}"),
                                    const SizedBox(height: 5),
                                    Text(
                                        "📝 Description: ${report["description"] ?? ""}"),
                                    const SizedBox(height: 5),

                                    if (report["reporterName"] != null)
                                      Text("👤 Reporter: ${report["reporterName"]}"),

                                    if (report["reporterPhone"] != null)
                                      Text("📞 Phone: ${report["reporterPhone"]}"),

                                    const SizedBox(height: 5),

                                    Text(
                                      report["timestamp"] != null
                                          ? "⏰ ${report["timestamp"].toDate()}"
                                          : "",
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}