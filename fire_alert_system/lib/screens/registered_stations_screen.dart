import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisteredStationsScreen extends StatefulWidget {
  const RegisteredStationsScreen({super.key});

  @override
  State<RegisteredStationsScreen> createState() => _RegisteredStationsScreenState();
}

class _RegisteredStationsScreenState extends State<RegisteredStationsScreen> {
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  /// 🔥 TOGGLE VERIFY STATUS
  Future<void> toggleVerify(String docId, String currentStatus) async {
    String newStatus = currentStatus == "verified" ? "unverified" : "verified";

    await FirebaseFirestore.instance.collection("stations").doc(docId).update({
      "status": newStatus,
    });

    if (!mounted) return;
    _showSnackBar("Station marked as $newStatus", newStatus == "verified" ? Colors.green : Colors.orange);
  }

  /// 🗑 DELETE STATION
  Future<void> deleteStation(String docId, String stationName) async {
    try {
      await FirebaseFirestore.instance.collection("stations").doc(docId).delete();
      _showSnackBar("$stationName deleted successfully", Colors.red);
    } catch (e) {
      _showSnackBar("Error: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  /// CONFIRM DELETE DIALOG
  void confirmDelete(String docId, String stationName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Station?"),
        content: Text("Are you sure you want to remove $stationName? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context);
              deleteStation(docId, stationName);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  bool matchesSearch(Map<String, dynamic> station) {
    final query = searchQuery.toLowerCase();
    return (station["station_name"] ?? "").toLowerCase().contains(query) ||
        (station["ward"] ?? "").toLowerCase().contains(query) ||
        (station["county"] ?? "").toLowerCase().contains(query) ||
        (station["status"] ?? "").toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Fire Stations", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        elevation: 0,
      ),
      body: Column(
        children: [
          // MODERN SEARCH HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 25),
            decoration: const BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => searchQuery = val),
              decoration: InputDecoration(
                hintText: "Search by name, location, or status...",
                prefixIcon: const Icon(Icons.search, color: Colors.red),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection("stations").where("role", isNotEqualTo: "admin").snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.red));

                var docs = snapshot.data!.docs.where((doc) => matchesSearch(doc.data() as Map<String, dynamic>)).toList();

                if (docs.isEmpty) {
                  return Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 10),
                      Text("No stations found", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                    ],
                  ));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    var station = doc.data() as Map<String, dynamic>;
                    String status = station["status"] ?? "unverified";
                    bool isVerified = status == "verified";

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Icon + Name + Status
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.red[50],
                                  child: const Icon(Icons.fire_truck, color: Colors.red),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    station["station_name"] ?? "Unknown",
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isVerified ? Colors.green[50] : Colors.orange[50],
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isVerified ? Colors.green : Colors.orange),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(color: isVerified ? Colors.green[700] : Colors.orange[700], fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 25),

                            // Contact Details
                            _infoRow(Icons.phone_android, station["phone"] ?? "N/A"),
                            _infoRow(Icons.email_outlined, station["email"] ?? "N/A"),

                            const SizedBox(height: 10),

                            // Location Badge
                            Wrap(
                              spacing: 8,
                              children: [
                                _locationChip(station["ward"]),
                                _locationChip(station["subcounty"]),
                                _locationChip(station["county"], isCounty: true),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: isVerified ? Colors.orange : Colors.green,
                                      side: BorderSide(color: isVerified ? Colors.orange : Colors.green),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => toggleVerify(doc.id, status),
                                    icon: Icon(isVerified ? Icons.cancel_outlined : Icons.verified_user_outlined),
                                    label: Text(isVerified ? "Unverify" : "Verify Station"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10)),
                                  child: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => confirmDelete(doc.id, station["station_name"] ?? "Station"),
                                  ),
                                ),
                              ],
                            )
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

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _locationChip(String? text, {bool isCounty = false}) {
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCounty ? Colors.blue[50] : Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: isCounty ? Colors.blue[800] : Colors.grey[700], fontWeight: isCounty ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }
}