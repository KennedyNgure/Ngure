import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'feed_fire_call_screen.dart';
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

  /// 🔥 Track expanded card
  String? expandedReportId;

  @override
  void initState() {
    super.initState();
    loadStationCounty();
  }

  /// Load station's county from Firestore
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

  /// Mark report as handled
  Future<void> markAsHandled(String reportId) async {
    await FirebaseFirestore.instance
        .collection("reports")
        .doc(reportId)
        .update({"status": "handled"});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Fire marked as handled")),
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
                MaterialPageRoute(builder: (context) => ReportFireScreen()),
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
            /// 🚒 Station Info
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

            /// ⚡ Quick Actions
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
                        builder: (context) =>
                            NewFireReportScreen(stationName: widget.stationName),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  icon: const Icon(Icons.phone),
                  label: const Text("Feed Fire Call"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            FeedFireCallScreen(stationName: widget.stationName),
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
                        builder: (context) => InterstationCommunicationScreen(
                            stationName: widget.stationName),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 25),

            /// 🔥 TITLE
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Incoming Fire Reports",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),

            /// 🔍 SEARCH
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

            /// 📋 REPORT LIST
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("reports")
                    .where("status", isEqualTo: "pending")
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text("Error: ${snapshot.error}"),
                    );
                  }

                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData ||
                      snapshot.data!.docs.isEmpty) {
                    return const Center(
                        child: Text("No pending fire reports available"));
                  }

                  final reports = snapshot.data!.docs
                      .map((doc) => {
                    "id": doc.id,
                    ...doc.data() as Map<String, dynamic>
                  })
                      .where((report) {
                    if (searchQuery == null ||
                        searchQuery!.isEmpty) return true;

                    String ward =
                    (report["ward"] ?? "").toLowerCase();
                    String subcounty =
                    (report["subcounty"] ?? "").toLowerCase();
                    String county =
                    (report["county"] ?? "").toLowerCase();

                    return ward.contains(searchQuery!) ||
                        subcounty.contains(searchQuery!) ||
                        county.contains(searchQuery!);
                  }).toList();

                  if (reports.isEmpty) {
                    return const Center(
                        child: Text("No fire reports match your search"));
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
                                  report["fireType"] ??
                                      "Unknown Fire"),
                              subtitle: Text(
                                  "Ward: ${report["ward"] ?? ""}, Subcounty: ${report["subcounty"] ?? ""}, County: ${report["county"] ?? ""}"),
                            ),

                            /// BUTTONS
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              child: Row(
                                mainAxisAlignment:
                                MainAxisAlignment.end,
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                        Colors.green),
                                    child: const Text("Handled"),
                                    onPressed: () =>
                                        markAsHandled(
                                            report["id"]),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                        Colors.blue),
                                    child: Text(
                                      expandedReportId ==
                                          report["id"]
                                          ? "Hide"
                                          : "View",
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (expandedReportId ==
                                            report["id"]) {
                                          expandedReportId =
                                          null;
                                        } else {
                                          expandedReportId =
                                          report["id"];
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),

                            /// EXPANDED DETAILS
                            if (expandedReportId ==
                                report["id"])
                              Container(
                                width: double.infinity,
                                padding:
                                const EdgeInsets.all(12),
                                color: Colors.grey.shade100,
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        "🔥 Fire Type: ${report["fireType"] ?? ""}"),
                                    Text(
                                        "📏 Fire Size: ${report["fireSize"] ?? ""}"),
                                    Text(
                                        "🚨 Evacuation: ${report["evacuationStatus"] ?? ""}"),
                                    Text(
                                        "📍 Ward: ${report["ward"] ?? ""}"),
                                    Text(
                                        "🏙 Subcounty: ${report["subcounty"] ?? ""}"),
                                    Text(
                                        "🌍 County: ${report["county"] ?? ""}"),
                                    const SizedBox(height: 5),

                                    if (report["reporterName"] !=
                                        null)
                                      Text(
                                          "👤 Reporter: ${report["reporterName"]}"),

                                    if (report["reporterPhone"] !=
                                        null)
                                      Text(
                                          "📞 Phone: ${report["reporterPhone"]}"),

                                    if (report["peopleTrapped"] !=
                                        null)
                                      Text(
                                          "🧍 People Trapped: ${report["peopleTrapped"]}"),
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