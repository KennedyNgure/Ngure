// lib/screens/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'registered_stations_screen.dart';
import 'safety_tips01.dart';
import 'fire_reports_screen.dart';
import 'login_screen.dart';
import 'faq_screen.dart'; // ✅ ADD THIS IMPORT

class AdminDashboard extends StatefulWidget {
  final bool isAdmin;

  const AdminDashboard({super.key, required this.isAdmin});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  TextEditingController searchController = TextEditingController();
  String searchQuery = "";

  DateTime getStartOfWeek() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  /// 🔥 TOP CARDS
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

                /// 🔥 Reports
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
                    child: Container(
                      width: 120,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: [
                          const Icon(Icons.local_fire_department,
                              color: Colors.red, size: 40),
                          const SizedBox(height: 10),
                          const Text("Reports"),
                          Text(reportCount.toString()),
                        ],
                      ),
                    ),
                  ),
                ),

                /// 🚒 Stations
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
                    child: Container(
                      width: 120,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: [
                          const Icon(Icons.fire_truck,
                              color: Colors.blue, size: 40),
                          const SizedBox(height: 10),
                          const Text("Stations"),
                          Text(stationCount.toString()),
                        ],
                      ),
                    ),
                  ),
                ),

                /// 🛡️ Safety Tips
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SafetyTips01(),
                      ),
                    );
                  },
                  child: Card(
                    child: Container(
                      width: 120,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: const [
                          Icon(Icons.health_and_safety,
                              color: Colors.green, size: 40),
                          SizedBox(height: 10),
                          Text("Safety"),
                        ],
                      ),
                    ),
                  ),
                ),

                /// ❓ FAQs (NEW)
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                        const FAQScreen(isAdmin: true),
                      ),
                    );
                  },
                  child: Card(
                    child: Container(
                      width: 120,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: const [
                          Icon(Icons.help_outline,
                              color: Colors.purple, size: 40),
                          SizedBox(height: 10),
                          Text("FAQs"),
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

  /// 📊 STATISTICS
  Widget buildStatistics() {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime weekStart = getStartOfWeek();
    DateTime monthStart = DateTime(now.year, now.month, 1);
    DateTime yearStart = DateTime(now.year, 1, 1);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("reports").snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        int todayCount = 0;
        int weekCount = 0;
        int monthCount = 0;
        int yearCount = 0;

        for (var doc in snapshot.data!.docs) {
          var data = doc.data() as Map<String, dynamic>;
          if (data["timestamp"] == null) continue;

          DateTime time = data["timestamp"].toDate();

          if (time.isAfter(today)) todayCount++;
          if (time.isAfter(weekStart)) weekCount++;
          if (time.isAfter(monthStart)) monthCount++;
          if (time.isAfter(yearStart)) yearCount++;
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            statCard("Today", todayCount, Icons.today, Colors.red),
            statCard("Week", weekCount, Icons.calendar_view_week, Colors.orange),
            statCard("Month", monthCount, Icons.calendar_month, Colors.deepOrange),
            statCard("Year", yearCount, Icons.date_range, Colors.redAccent),
          ],
        );
      },
    );
  }

  Widget statCard(String title, int value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 5),
              Text(title),
              Text(
                value.toString(),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              )
            ],
          ),
        ),
      ),
    );
  }

  /// 🏆 STATION PERFORMANCE
  Widget buildStationPerformance() {
    DateTime weekStart = getStartOfWeek();

    return Column(
      children: [
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
          stream: FirebaseFirestore.instance
              .collection("reports")
              .where("status", isEqualTo: "handled")
              .snapshots(),
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

              String station = data["handledBy"] ?? "Unknown";

              stationCounts[station] =
                  (stationCounts[station] ?? 0) + 1;
            }

            var stations = stationCounts.entries.where((entry) {
              if (searchQuery.isEmpty) return true;
              return entry.key.toLowerCase().contains(searchQuery);
            }).toList();

            stations.sort((a, b) => b.value.compareTo(a.value));

            return Column(
              children: stations.map((entry) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_fire_department,
                        color: Colors.red),
                    title: Text(entry.key),
                    trailing: Text(
                      "${entry.value} handled",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green),
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

  void logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
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
                fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            buildTopCards(context),
            const SizedBox(height: 20),
            const Text(
              "Fire Statistics",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            buildStatistics(),
            const SizedBox(height: 20),
            const Text(
              "Station Performance (This Week)",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            buildStationPerformance(),
          ],
        ),
      ),
    );
  }
}