import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'report_fire_screen.dart';
import 'station_profile.dart';
import 'package:fire_alert_app/screens/new_fire_report_screen.dart';
import 'interstation_communication_screen.dart';

class StationDashboard extends StatefulWidget {
  final String stationName;

  const StationDashboard({super.key, required this.stationName});

  @override
  State<StationDashboard> createState() => _StationDashboardState();
}

class _StationDashboardState extends State<StationDashboard> {
  double? stationLatitude;
  double? stationLongitude;

  @override
  void initState() {
    super.initState();
  }

  /// Load station coordinates from Firestore
  Future<void> loadStationLocation() async {
    var doc = await FirebaseFirestore.instance
        .collection("stations")
        .doc(widget.stationName)
        .get();

    if (doc.exists) {
      var data = doc.data()!;

      setState(() {
        stationLatitude = (data["latitude"] as num).toDouble();
        stationLongitude = (data["longitude"] as num).toDouble();
      });
    }
  }

  /// Haversine distance calculation
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371;

    double dLat = (lat2 - lat1) * pi / 180;
    double dLon = (lon2 - lon1) * pi / 180;

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * pi / 180) *
                cos(lat2 * pi / 180) *
                sin(dLon / 2) *
                sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  /// Update fire status
  Future<void> markAsHandled(String reportId) async {
    await FirebaseFirestore.instance
        .collection("reports")
        .doc(reportId)
        .update({"status": "handled"});

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Fire marked as handled"),
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
            label: const Text("Profile",
                style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const ReportFireScreen(),
                ),
              );
            },
            icon: const Icon(Icons.logout, color: Colors.white),
            label:
            const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            /// Station Card
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(
                  Icons.local_fire_department,
                  color: Colors.red,
                  size: 40,
                ),
                title: Text(
                  widget.stationName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text("Monitoring fire alerts"),
              ),
            ),

            const SizedBox(height: 20),

            /// Quick actions
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Quick Actions",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  icon: const Icon(Icons.warning),
                  label: const Text("New Alert"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NewFireReportScreen(
                          stationName: widget.stationName,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(width: 20),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                  icon: const Icon(Icons.chat),
                  label: const Text("Inter-station Communication"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            InterstationCommunicationScreen(
                              stationName: widget.stationName,
                            ),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 25),

            /// Fire reports title
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

            /// Fire reports list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("reports")
                    .where("status", isEqualTo: "pending")
                    .orderBy("timestamp", descending: true)
                    .limit(20)
                    .snapshots(),

                builder: (context, snapshot) {

                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData ||
                      snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text("No pending fire reports"),
                    );
                  }

                  var reports = snapshot.data!.docs;

                  return ListView.builder(
                    itemCount: reports.length,
                    itemBuilder: (context, index) {

                      var doc = reports[index];
                      var report =
                      doc.data() as Map<String, dynamic>;

                      /// Safe latitude
                      double reportLat =
                      (report["latitude"] is num)
                          ? (report["latitude"] as num)
                          .toDouble()
                          : 0.0;

                      /// Safe longitude
                      double reportLon =
                      (report["longitude"] is num)
                          ? (report["longitude"] as num)
                          .toDouble()
                          : 0.0;

                      double distance = 0.0;

                      if (stationLatitude != null &&
                          stationLongitude != null) {
                        distance = calculateDistance(
                          stationLatitude!,
                          stationLongitude!,
                          reportLat,
                          reportLon,
                        );
                      }

                      /// Only show within 20km
                      if (stationLatitude != null &&
                          stationLongitude != null &&
                          distance > 20) {
                        return const SizedBox.shrink();
                      }

                      Timestamp? timestamp =
                      report["timestamp"] as Timestamp?;

                      return Card(
                        elevation: 4,
                        margin: const EdgeInsets.symmetric(
                            vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [

                              Row(
                                children: const [
                                  Icon(
                                    Icons.local_fire_department,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Active Fire Alert",
                                    style: TextStyle(
                                      fontWeight:
                                      FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),

                              const Divider(),

                              Text(
                                  "Reporter: ${report["name"] ?? "Unknown"}"),
                              Text(
                                  "Phone: ${report["phone"] ?? "N/A"}"),
                              Text(
                                  "Description: ${report["description"] ?? ""}"),

                              const SizedBox(height: 6),

                              Text(
                                  "Fire Type: ${report["fireType"] ?? "Unknown"}"),
                              Text(
                                  "Fire Size: ${report["fireSize"] ?? "Unknown"}"),

                              const SizedBox(height: 6),

                              Text(
                                  "People Trapped/Injured: ${report["peopleTrapped"] ?? "0"}"),
                              Text(
                                  "Evacuation Status: ${report["evacuationStatus"] ?? "Unknown"}"),

                              const SizedBox(height: 6),

                              Text("Location: $reportLat, $reportLon"),
                              Text(
                                  "Distance: ${distance.toStringAsFixed(2)} km"),

                              if (timestamp != null)
                                Text(
                                  "Reported: ${timestamp.toDate()}",
                                  style: const TextStyle(
                                      fontSize: 12),
                                ),

                              const SizedBox(height: 10),

                              Align(
                                alignment:
                                Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton
                                      .styleFrom(
                                    backgroundColor:
                                    Colors.green,
                                  ),
                                  icon:
                                  const Icon(Icons.check),
                                  label: const Text(
                                      "Mark as Handled"),
                                  onPressed: () {
                                    markAsHandled(doc.id);
                                  },
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
      ),
    );
  }
}