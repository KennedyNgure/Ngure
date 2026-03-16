import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'report_fire_screen.dart';
import 'registered_stations_screen.dart';
import 'fire_reports_screen.dart';

class AdminDashboard extends StatefulWidget {
  final bool isAdmin;

  const AdminDashboard({super.key, required this.isAdmin});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  TextEditingController searchController = TextEditingController();
  String searchQuery = "";

  DateTime getStartOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime getStartOfWeek() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  /// Top Cards: Fire Reports + Stations
  Widget buildTopCards(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("reports").snapshots(),
      builder: (context, reportSnapshot) {
        if (!reportSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("stations").snapshots(),
          builder: (context, stationSnapshot) {
            if (!stationSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            int reportCount = reportSnapshot.data!.docs.length;
            int stationCount = stationSnapshot.data!.docs.length;

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                /// Fire Reports
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                        const FireReportsScreen(filter: "all"),
                      ),
                    );
                  },
                  child: Card(
                    elevation: 4,
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.local_fire_department,
                              color: Colors.red, size: 40),
                          const SizedBox(height: 10),
                          const Text("Fire Reports",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            reportCount.toString(),
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold),
                          )
                        ],
                      ),
                    ),
                  ),
                ),

                /// Stations
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
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.fire_truck,
                              color: Colors.blue, size: 40),
                          const SizedBox(height: 10),
                          const Text("Stations",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            stationCount.toString(),
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Fire Statistics Cards
  Widget buildStatistics() {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime weekStart = now.subtract(Duration(days: now.weekday - 1));
    DateTime monthStart = DateTime(now.year, now.month, 1);
    DateTime yearStart = DateTime(now.year, 1, 1);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("reports").snapshots(),
      builder: (context, reportSnapshot) {
        if (!reportSnapshot.hasData) return const CircularProgressIndicator();

        int todayCount = 0;
        int weekCount = 0;
        int monthCount = 0;
        int yearCount = 0;

        for (var doc in reportSnapshot.data!.docs) {
          var data = doc.data() as Map<String, dynamic>;
          if (data["timestamp"] == null) continue;

          DateTime time = data["timestamp"].toDate();
          if (time.isAfter(today)) todayCount++;
          if (time.isAfter(weekStart)) weekCount++;
          if (time.isAfter(monthStart)) monthCount++;
          if (time.isAfter(yearStart)) yearCount++;
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("stations").snapshots(),
          builder: (context, stationSnapshot) {
            if (!stationSnapshot.hasData) return const CircularProgressIndicator();

            int stationCount = stationSnapshot.data!.docs.length;

            Widget statCard(String title, int value, IconData icon, Color color) {
              return Expanded(
                child: Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: color, size: 35),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 5),
                        FittedBox(
                          child: Text(
                            value.toString(),
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                statCard("Fires Today", todayCount, Icons.today, Colors.red),
                statCard("This Week", weekCount, Icons.calendar_view_week, Colors.orange),
                statCard("This Month", monthCount, Icons.calendar_month, Colors.deepOrange),
                statCard("This Year", yearCount, Icons.date_range, Colors.redAccent),
                statCard("Registered Stations", stationCount, Icons.fire_truck, Colors.blue),
              ],
            );
          },
        );
      },
    );
  }
  /// Station Performance (This Week)
  Widget buildStationPerformance() {
    DateTime weekStart = getStartOfWeek();

    return Column(
      children: [
        /// Search Bar
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: "Search Station",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                searchQuery = value.toLowerCase();
              });
            },
          ),
        ),

        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("reports").snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }

            Map<String, int> stationCounts = {};
            for (var doc in snapshot.data!.docs) {
              var data = doc.data() as Map<String, dynamic>;
              if (data["timestamp"] == null) continue;

              DateTime time = data["timestamp"].toDate();
              if (!time.isAfter(weekStart)) continue;

              String station = data["nearest_station"] ?? "Unknown";
              stationCounts[station] = (stationCounts[station] ?? 0) + 1;
            }

            var stations = stationCounts.entries.where((entry) {
              return entry.key.toLowerCase().contains(searchQuery);
            }).toList();

            stations.sort((a, b) => b.value.compareTo(a.value));

            return Column(
              children: stations.map((entry) {
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin) {
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
            buildTopCards(context),
            const SizedBox(height: 30),
            const Text(
              "Fire Statistics",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            buildStatistics(),
            const SizedBox(height: 30),
            const Text(
              "Station Performance (This Week)",
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