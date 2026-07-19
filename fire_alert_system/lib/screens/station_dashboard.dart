// lib/screens/station_dashboard.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'feed_fire_call_screen.dart';
import 'login_screen.dart';
import 'station_profile.dart';
import 'new_fire_report_screen.dart';
import 'interstation_communication_screen.dart';
import 'handled_fire_reports.dart';

class StationDashboard extends StatefulWidget {
  final String stationName;

  const StationDashboard({super.key, required this.stationName});

  @override
  State<StationDashboard> createState() => _StationDashboardState();
}

class _StationDashboardState extends State<StationDashboard> {
  String? stationCounty;
  String? stationSubCounty;
  String? stationWard;
  bool isVerified = false;
  bool isLoading = true;

  final TextEditingController searchController = TextEditingController();
  String? searchQuery;

  String? expandedReportId;
  List<String> previousReportIds = [];

  @override
  void initState() {
    super.initState();
    loadStationData();
  }

  Future<void> loadStationData() async {
    try {
      var query = await FirebaseFirestore.instance
          .collection("stations")
          .where("station_name", isEqualTo: widget.stationName)
          .get();

      if (query.docs.isNotEmpty) {
        var data = query.docs.first.data();
        setState(() {
          stationCounty = (data["county"] ?? "").toString().trim();
          stationSubCounty = (data["subcounty"] ?? "").toString().trim();
          stationWard = (data["ward"] ?? "").toString().trim();
          isVerified = data["status"] == "verified";
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading station data: $e");
    }
  }

  Future<void> markAsHandled(String reportId) async {
    await FirebaseFirestore.instance.collection("reports").doc(reportId).update({
      "status": "handled",
      "handledBy": widget.stationName,
      "handledAt": FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Incident marked as handled"), backgroundColor: Colors.green),
    );
  }

  void _triggerAlarm(String description) {
    SystemSound.play(SystemSoundType.alert);
    showDialog(
      context: context,
      barrierDismissible: false, // Force attention
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 10),
            Text("EMERGENCY ALERT"),
          ],
        ),
        content: Text("New fire reported in your area:\n\n$description"),
        actions: [
          // NEW CANCEL BUTTON
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context),
            child: const Text("RESPOND", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Station Terminal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.red,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StationProfile(stationName: widget.stationName))),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : Column(
        children: [
          _buildHeader(),
          Expanded(
            child: !isVerified ? _buildUnverifiedView() : _buildActiveDashboard(),
          ),
        ],
      ),
    );
  }

  /// 🏢 HEADER SECTION WITH DETAILED LOCATION
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: const BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.stationName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // Location Details Row
          Wrap(
            spacing: 15,
            runSpacing: 5,
            children: [
              _headerLocationItem(Icons.map, stationWard ?? "..."),
              _headerLocationItem(Icons.location_city, stationSubCounty ?? "..."),
              _headerLocationItem(Icons.explore, stationCounty ?? "..."),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerLocationItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  /// 🚫 UNVERIFIED STATE
  Widget _buildUnverifiedView() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user_outlined, size: 80, color: Colors.orange),
              const SizedBox(height: 20),
              const Text("Verification Pending", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                "Your station account is awaiting administrative approval. Access to emergency data is currently restricted.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ ACTIVE DASHBOARD
  Widget _buildActiveDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQuickActions(),
          const SizedBox(height: 25),
          const Text("Live Incident Feed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildSearchBar(),
          const SizedBox(height: 15),
          _buildReportsList(),
        ],
      ),
    );
  }

  /// ⚡ QUICK ACTION GRID
  Widget _buildQuickActions() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: [
        _actionCard("New Alert", Icons.warning_amber_rounded, Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewFireReportScreen(stationName: widget.stationName)))),
        _actionCard("Feed Call", Icons.phone_callback_rounded, Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => FeedFireCallScreen(stationName: widget.stationName)))),
        _actionCard("Messages", Icons.forum_rounded, Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => InterstationCommunicationScreen(stationName: widget.stationName)))),
        _actionCard("Handled Fire Reports", Icons.fact_check_rounded, Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => HandledFireReportsScreen(stationName: widget.stationName)))),
      ],
    );
  }

  Widget _actionCard(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: searchController,
      onChanged: (v) => setState(() => searchQuery = v.toLowerCase().trim()),
      decoration: InputDecoration(
        hintText: "Search by Ward or Sub-county...",
        prefixIcon: const Icon(Icons.search, color: Colors.red),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildReportsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("reports")
          .where("status", isEqualTo: "pending")
          .where("county", isEqualTo: stationCounty)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final reports = snapshot.data!.docs
            .map((doc) => {"id": doc.id, ...doc.data() as Map<String, dynamic>})
            .where((r) {
          if (searchQuery == null || searchQuery!.isEmpty) return true;
          String space = "${r["ward"]} ${r["subcounty"]}".toLowerCase();
          return space.contains(searchQuery!);
        }).toList();

        // Alarm Logic
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (var r in reports) {
            if (!previousReportIds.contains(r["id"])) {
              _triggerAlarm(r["description"] ?? "Fire incident detected.");
            }
          }
          previousReportIds = reports.map((r) => r["id"].toString()).toList();
        });

        if (reports.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.cloud_done_rounded, size: 60, color: Colors.grey[300]),
                  const SizedBox(height: 10),
                  const Text("All clear. No pending incidents.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            bool isExpanded = expandedReportId == report["id"];

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    title: Text(report["description"] ?? "Fire Alert", style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text("${report["ward"]}, ${report["subcounty"]}", style: TextStyle(color: Colors.red[700])),
                    trailing: const Icon(Icons.new_releases, color: Colors.red),
                    onTap: () => setState(() => expandedReportId = isExpanded ? null : report["id"]),
                  ),
                  if (isExpanded)
                    Container(
                      padding: const EdgeInsets.all(15),
                      width: double.infinity,
                      decoration: BoxDecoration(color: Colors.red[50], borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailText("Area", "${report["ward"]}, ${report["subcounty"]}"),
                          _detailText("Reporter", report["reporterName"] ?? "Anonymous"),
                          const SizedBox(height: 8),
                          const Text("Full Description:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(report["description"] ?? "No details provided"),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              icon: const Icon(Icons.check),
                              label: const Text("ACKNOWLEDGE & HANDLE"),
                              onPressed: () => markAsHandled(report["id"]),
                            ),
                          )
                        ],
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

  Widget _detailText(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black, fontSize: 13),
          children: [
            TextSpan(text: "$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: val),
          ],
        ),
      ),
    );
  }
}