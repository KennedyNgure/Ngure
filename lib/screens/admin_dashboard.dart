import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'report_fire_screen.dart';
import 'registered_stations_screen.dart';
import 'fire_reports_screen.dart';

class AdminDashboard extends StatelessWidget {
  final bool isAdmin;

  const AdminDashboard({super.key, required this.isAdmin});

  DateTime getStartOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime getStartOfWeek() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  Widget buildStatistics(BuildContext context) {
    DateTime today = getStartOfToday();
    DateTime weekStart = getStartOfWeek();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("reports").snapshots(),
      builder: (context, reportSnapshot) {
        if (!reportSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        int todayCount = 0;
        int weekCount = 0;

        for (var doc in reportSnapshot.data!.docs) {
          var data = doc.data() as Map<String, dynamic>;

          if (data["timestamp"] != null) {
            DateTime time = data["timestamp"].toDate();

            if (time.isAfter(today)) {
              todayCount++;
            }

            if (time.isAfter(weekStart)) {
              weekCount++;
            }
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("stations").snapshots(),
          builder: (context, stationSnapshot) {
            if (!stationSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            int stationCount = stationSnapshot.data!.docs.length;
            int reportCount = reportSnapshot.data!.docs.length;

            return SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [

                  /// Fires Today
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.today, color: Colors.red, size: 40),
                          const SizedBox(height: 10),
                          const Text(
                            "Fires Today",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            todayCount.toString(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        ],
                      ),
                    ),
                  ),

                  /// Fires This Week
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_month,
                              color: Colors.orange, size: 40),
                          const SizedBox(height: 10),
                          const Text(
                            "This Week",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            weekCount.toString(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        ],
                      ),
                    ),
                  ),

                  /// Stations Card
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                          const RegisteredStationsScreen(),
                        ),
                      );
                    },
                    child: Card(
                      elevation: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      child: Container(
                        width: 160,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.fire_truck,
                                color: Colors.blue, size: 40),
                            const SizedBox(height: 10),
                            const Text(
                              "Stations",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              stationCount.toString(),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),

                  /// Fire Reports Card
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FireReportsScreen(),
                        ),
                      );
                    },
                    child: Card(
                      elevation: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      child: Container(
                        width: 160,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.local_fire_department,
                                color: Colors.red, size: 40),
                            const SizedBox(height: 10),
                            const Text(
                              "Fire Reports",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              reportCount.toString(),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget buildStationPerformance() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("reports").snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        Map<String, int> stationCounts = {};

        for (var doc in snapshot.data!.docs) {
          var data = doc.data() as Map<String, dynamic>;
          String station = data["nearest_station"] ?? "Unknown";

          stationCounts[station] = (stationCounts[station] ?? 0) + 1;
        }

        List<MapEntry<String, int>> sortedStations =
        stationCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Column(
          children: sortedStations.map((entry) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.fire_truck, color: Colors.red),
                title: Text(entry.key),
                trailing: Text(
                  "${entry.value} fires handled",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) {
      return const Scaffold(
        body: Center(
          child: Text(
            "Access Denied\nAdmin Only",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        backgroundColor: Colors.red,
        actions: [
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
            label: const Text(
              "Logout",
              style: TextStyle(color: Colors.white),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              "Fire Statistics",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            buildStatistics(context),
            const SizedBox(height: 30),
            const Text(
              "Station Performance",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            buildStationPerformance(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}