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
    loadStationLocation();
  }

  /// Fetch station location from Firestore
  Future<void> loadStationLocation() async {
    var doc = await FirebaseFirestore.instance
        .collection("stations")
        .doc(widget.stationName)
        .get();

    if (doc.exists) {
      var data = doc.data()!;

      setState(() {
        stationLatitude = data["latitude"];
        stationLongitude = data["longitude"];
      });
    }
  }

  /// Calculate distance using Haversine formula
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Station Dashboard"),
        backgroundColor: Colors.red,
        actions: [
          TextButton.icon(
            onPressed: () {
              if (widget.stationName.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        StationProfile(stationName: widget.stationName),
                  ),
                );
              }
            },
            icon: const Icon(Icons.person, color: Colors.white),
            label: const Text("Profile", style: TextStyle(color: Colors.white)),
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
            label: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// Warning if location not set
            if (stationLatitude == null || stationLongitude == null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Station location not set. Update it in Profile.",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

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

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Quick Actions",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            NewFireReportScreen(stationName: widget.stationName),
                      ),
                    );
                  },
                  icon: const Icon(Icons.warning),
                  label: const Text("New Alert"),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
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
                  icon: const Icon(Icons.chat),
                  label: const Text("Interstation Communication"),
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

            /// Fire Reports
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

                  return ListView.builder(
                    itemCount: reports.length,
                    itemBuilder: (context, index) {

                      var report =
                      reports[index].data() as Map<String, dynamic>;

                      double reportLat = report["latitude"];
                      double reportLon = report["longitude"];

                      double distance = 0;

                      if (stationLatitude != null &&
                          stationLongitude != null) {
                        distance = calculateDistance(
                          stationLatitude!,
                          stationLongitude!,
                          reportLat,
                          reportLon,
                        );
                      }

                      /// Only show reports within 20km
                      if (stationLatitude != null &&
                          stationLongitude != null &&
                          distance > 20) {
                        return const SizedBox();
                      }

                      return Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.local_fire_department,
                            color: Colors.red,
                          ),
                          title: Text(report["description"] ?? "Fire Report"),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Location: $reportLat, $reportLon"),
                              Text("Distance: ${distance.toStringAsFixed(2)} km"),
                              if (report["timestamp"] != null)
                                Text(
                                  report["timestamp"].toDate().toString(),
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