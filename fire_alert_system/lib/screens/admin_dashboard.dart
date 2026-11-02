import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'registered_stations_screen.dart';
import 'safety_tips01.dart';
import 'fire_reports_screen.dart';
import 'login_screen.dart';
import 'faq_screen.dart';
import 'terms_and_conditions_screen.dart';

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

  /// Professional Header with Gradient
  Widget buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: const BoxDecoration(
        color: Colors.red,
        gradient: LinearGradient(
          colors: [Colors.red, Color(0xFFB71C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            "Welcome, Admin",
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 5),
          Text(
            "Fire Alert Management System",
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// Modern Action Card for the Grid
  Widget buildActionCard({
    required IconData icon,
    required Color color,
    required String label,
    String? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              radius: 25,
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            if (value != null)
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildActionGrid(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("reports").snapshots(),
      builder: (context, reportSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("stations").snapshots(),
          builder: (context, stationSnapshot) {
            int reportCount = reportSnapshot.hasData ? reportSnapshot.data!.docs.length : 0;
            int stationCount = stationSnapshot.hasData ? stationSnapshot.data!.docs.length : 0;

            return GridView.count(
              crossAxisCount: 3, // Mobile friendly 3-column grid
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                buildActionCard(
                  icon: Icons.assignment,
                  color: Colors.red,
                  label: "Reports",
                  value: reportCount.toString(),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FireReportsScreen(filter: "all"))),
                ),
                buildActionCard(
                  icon: Icons.local_fire_department,
                  color: Colors.blue,
                  label: "Stations",
                  value: stationCount.toString(),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisteredStationsScreen())),
                ),
                buildActionCard(
                  icon: Icons.health_and_safety,
                  color: Colors.green,
                  label: "Safety Tips",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SafetyTips01())),
                ),
                buildActionCard(
                  icon: Icons.help_center,
                  color: Colors.purple,
                  label: "FAQs",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FAQScreen(isAdmin: true))),
                ),
                buildActionCard(
                  icon: Icons.gavel,
                  color: Colors.brown,
                  label: "Terms & Conditions",
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen(isAdmin: true))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Enhanced Statistics Layout
  Widget buildStatisticsSection() {
    return Container(
      margin: const EdgeInsets.all(15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Fire Incident Summary",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection("reports").snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              int today = 0, week = 0, month = 0, year = 0;
              DateTime now = DateTime.now();

              for (var doc in snapshot.data!.docs) {
                var data = doc.data() as Map<String, dynamic>;
                if (data["timestamp"] == null) continue;
                DateTime time = data["timestamp"].toDate();
                if (time.isAfter(DateTime(now.year, now.month, now.day))) today++;
                if (time.isAfter(getStartOfWeek())) week++;
                if (time.isAfter(DateTime(now.year, now.month, 1))) month++;
                if (time.isAfter(DateTime(now.year, 1, 1))) year++;
              }

              return Row(
                children: [
                  _buildStatItem("Today", today, Colors.red),
                  _buildStatItem("Week", week, Colors.orange),
                  _buildStatItem("Month", month, Colors.deepOrange),
                  _buildStatItem("Year", year, Colors.redAccent),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int val, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(val.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  /// 🏆 PROFESSIONAL STATION PERFORMANCE SCORECARD
  Widget buildStationPerformance() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Station Performance",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  Text(
                    "Ranking based on handled reports",
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              const Icon(Icons.analytics_outlined, color: Colors.red),
            ],
          ),
          const SizedBox(height: 15),

          // Professional Search Bar
          TextField(
            controller: searchController,
            onChanged: (v) => setState(() => searchQuery = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: "Search fire station...",
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 20, color: Colors.red),
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("reports")
                .where("status", isEqualTo: "handled")
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: LinearProgressIndicator(color: Colors.red));
              }

              // Data Calculation
              Map<String, int> counts = {};
              for (var doc in snapshot.data!.docs) {
                String station = doc['handledBy'] ?? "Unknown";
                counts[station] = (counts[station] ?? 0) + 1;
              }

              // Filter and Sort
              var sorted = counts.entries
                  .where((e) => e.key.toLowerCase().contains(searchQuery))
                  .toList();
              sorted.sort((a, b) => b.value.compareTo(a.value));

              if (sorted.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text("No data found", style: TextStyle(color: Colors.grey[400])),
                  ),
                );
              }

              // Top performance value for relative calculation
              int topValue = sorted.first.value;

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  String name = sorted[index].key;
                  int value = sorted[index].value;
                  double progress = value / topValue; // Relative performance

                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    child: Row(
                      children: [
                        // Rank Badge
                        _buildRankBadge(index),
                        const SizedBox(width: 15),

                        // Station Details & Progress Bar
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  Text(
                                    "$value Incidents",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey[100],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    index == 0 ? Colors.orange : Colors.red.withOpacity(0.7),
                                  ),
                                ),
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
        ],
      ),
    );
  }

  /// 🏅 HELPER: BUILDS THE RANK BADGE (1st, 2nd, 3rd or Circle)
  Widget _buildRankBadge(int index) {
    if (index == 0) {
      return const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xFFFFD700), // Gold
        child: Icon(Icons.emoji_events, color: Colors.white, size: 18),
      );
    } else if (index == 1) {
      return const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xFFC0C0C0), // Silver
        child: Icon(Icons.emoji_events, color: Colors.white, size: 18),
      );
    } else if (index == 2) {
      return const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xFFCD7F32), // Bronze
        child: Icon(Icons.emoji_events, color: Colors.white, size: 18),
      );
    } else {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.grey[100],
        child: Text(
          "${index + 1}",
          style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAdmin) {
      return const Scaffold(body: Center(child: Text("Unauthorized Access")));
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.red,
        title: const Text("Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            buildHeader(),
            const SizedBox(height: 20),
            buildActionGrid(context),
            buildStatisticsSection(),
            buildStationPerformance(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}