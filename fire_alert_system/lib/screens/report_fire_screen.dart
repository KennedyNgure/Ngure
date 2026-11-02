import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// =====================================
// FIRE REPORT SERVICE
// =====================================
class FireReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> submitReport({
    required String description,
    required double lat,
    required double lon,
    required String ward,
    required String subcounty,
    required String county,
    String? name,
    String? phone,
  }) async {
    await _firestore.collection("reports").add({
      "description": description,
      "latitude": lat,
      "longitude": lon,
      "ward": ward,
      "subcounty": subcounty,
      "county": county,
      "reporterName": name,
      "reporterPhone": phone,
      "status": "pending",
      "timestamp": FieldValue.serverTimestamp(),
    });
  }
}

// =====================================
// REPORT FIRE SCREEN
// =====================================
class ReportFireScreen extends StatefulWidget {
  const ReportFireScreen({super.key});

  @override
  State<ReportFireScreen> createState() => _ReportFireScreenState();
}

class _ReportFireScreenState extends State<ReportFireScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FireReportService service = FireReportService();

  bool isLoading = false;

  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.red),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.red, width: 2)),
    );
  }

  Future<Position> getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception("Location services are disabled.");

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) throw Exception("Permission denied.");

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<Map<String, String>> getLocationDetails(double lat, double lon) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon');
      final response = await http.get(url, headers: {'User-Agent': 'fire_app'});
      final data = json.decode(response.body);
      final address = data['address'] ?? {};

      return {
        "ward": address['town'] ?? address['village'] ?? address['suburb'] ?? "Unknown",
        "subcounty": address['county'] ?? "Unknown",
        "county": address['state'] ?? "Unknown",
      };
    } catch (e) {
      return {"ward": "Unknown", "subcounty": "Unknown", "county": "Unknown"};
    }
  }

  Future<void> reportFire() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);

    try {
      Position position = await getLocation();
      final loc = await getLocationDetails(position.latitude, position.longitude);

      await service.submitReport(
        description: descriptionController.text.trim(),
        lat: position.latitude,
        lon: position.longitude,
        ward: loc["ward"]!,
        subcounty: loc["subcounty"]!,
        county: loc["county"]!,
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
      );

      _showSnackBar("🚨 Fire Report Sent Successfully", Colors.green);
      descriptionController.clear();
    } catch (e) {
      _showSnackBar("Error: Check Location Settings", Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(controller: nameController, decoration: _inputStyle("Full Name", Icons.person), validator: (v) => v!.isEmpty ? "Required" : null),
                    const SizedBox(height: 16),
                    TextFormField(controller: phoneController, keyboardType: TextInputType.phone, decoration: _inputStyle("Phone Number", Icons.phone), validator: (v) => v!.length < 10 ? "Invalid phone" : null),
                    const SizedBox(height: 16),
                    TextFormField(controller: descriptionController, maxLines: 4, decoration: _inputStyle("Fire Description", Icons.description), validator: (v) => v!.isEmpty ? "Describe the fire" : null),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 5),
                        onPressed: isLoading ? null : reportFire,
                        child: isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("🚨 DISPATCH REPORT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 30),
      decoration: const BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Report Fire", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const Text("Every second counts. Fill details below.", style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 20),
          Row(
            children: [
              _headerButton(Icons.health_and_safety, "Safety Tips", () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyTipsScreen()))),
              const SizedBox(width: 12),
              _headerButton(Icons.call, "Emergency Contacts", () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()))),
            ],
          )
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.white))]),
      ),
    );
  }
}

// =====================================
// EMERGENCY CONTACTS SCREEN (ROBUST VERSION)
// =====================================
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  String? selectedCounty, selectedSubcounty, selectedWard;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<String> counties = [];
  List<String> subcounties = [];
  List<String> wards = [];
  List<Map<String, dynamic>> stations = [];

  bool isLoadingCounties = true;
  bool isLoadingSubcounties = false;
  bool isLoadingWards = false;
  bool isLoadingStations = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadData('county', null, (list) {
      setState(() {
        counties = list;
        isLoadingCounties = false;
      });
    });
  }

  Future<void> _loadData(String field, String? filterValue, Function(List<String>) onComplete) async {
    try {
      Query query = _firestore.collection('stations').where('status', isEqualTo: 'verified');

      if (filterValue != null) {
        if (field == 'subcounty') query = query.where('county', isEqualTo: filterValue);
        if (field == 'ward') query = query.where('subcounty', isEqualTo: filterValue);
      }

      final snap = await query.get();

      final Set<String> uniqueValues = {};
      for (var doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data[field] != null && data[field].toString().isNotEmpty) {
          uniqueValues.add(data[field].toString());
        }
      }

      List<String> sortedList = uniqueValues.toList();
      sortedList.sort();
      onComplete(sortedList);
    } catch (e) {
      debugPrint("Error fetching $field: $e");
    }
  }

  Future<void> _loadStations() async {
    if (selectedWard == null) return;
    setState(() => isLoadingStations = true);
    try {
      final snap = await _firestore
          .collection('stations')
          .where('status', isEqualTo: 'verified')
          .where('ward', isEqualTo: selectedWard)
          .get();
      setState(() {
        stations = snap.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
        isLoadingStations = false;
      });
    } catch (e) {
      setState(() => isLoadingStations = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Station Contacts", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue[800],
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildFilterSection(),
          Expanded(
            child: isLoadingStations
                ? const Center(child: CircularProgressIndicator())
                : stations.isEmpty
                ? _emptyState()
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: stations.length,
              itemBuilder: (context, index) {
                final s = stations[index];
                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.blue[50], child: const Icon(Icons.fire_truck, color: Colors.blue)),
                    title: Text(s['station_name'] ?? 'Fire Station', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(s['phone'] ?? 'No phone number'),
                    trailing: CircleAvatar(
                      backgroundColor: Colors.green,
                      child: IconButton(
                        icon: const Icon(Icons.call, color: Colors.white),
                        onPressed: () => _call(s['phone']),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _quickCall999(),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[800],
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25)),
      ),
      child: Column(
        children: [
          _customDropdown(
            hint: "Select County",
            val: selectedCounty,
            items: counties,
            loading: isLoadingCounties,
            onChange: (v) async {
              setState(() {
                selectedCounty = v;
                selectedSubcounty = null;
                selectedWard = null;
                subcounties = [];
                wards = [];
                stations = [];
                isLoadingSubcounties = true;
              });
              await _loadData('subcounty', v, (list) {
                setState(() {
                  subcounties = list;
                  isLoadingSubcounties = false;
                });
              });
            },
          ),
          const SizedBox(height: 10),
          _customDropdown(
            hint: "Select Subcounty",
            val: selectedSubcounty,
            items: subcounties,
            loading: isLoadingSubcounties,
            enabled: selectedCounty != null,
            onChange: (v) async {
              setState(() {
                selectedSubcounty = v;
                selectedWard = null;
                wards = [];
                stations = [];
                isLoadingWards = true;
              });
              await _loadData('ward', v, (list) {
                setState(() {
                  wards = list;
                  isLoadingWards = false;
                });
              });
            },
          ),
          const SizedBox(height: 10),
          _customDropdown(
            hint: "Select Ward",
            val: selectedWard,
            items: wards,
            loading: isLoadingWards,
            enabled: selectedSubcounty != null,
            onChange: (v) {
              setState(() => selectedWard = v);
              _loadStations();
            },
          ),
        ],
      ),
    );
  }

  Widget _customDropdown({
    required String hint,
    required String? val,
    required List<String> items,
    required Function(String?) onChange,
    bool loading = false,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: Text(loading ? "Loading..." : hint),
          value: items.contains(val) ? val : null,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: enabled && !loading ? onChange : null,
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.location_city, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 10),
        Text(
          selectedWard == null ? "Select location above to find stations" : "No verified stations in this ward",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    ),
  );

  Widget _quickCall999() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          minimumSize: const Size.fromHeight(55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        icon: const Icon(Icons.phone, color: Colors.white),
        label: const Text("CALL EMERGENCY (999)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        onPressed: () => _call("999"),
      ),
    ),
  );

  Future<void> _call(String? num) async {
    if (num == null) return;
    final Uri uri = Uri(scheme: 'tel', path: num);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw 'Could not launch $num';
      }
    } catch (e) {
      debugPrint("Call Error: $e");
    }
  }
}

// =====================================
// SAFETY TIPS SCREEN
// =====================================
class SafetyTipsScreen extends StatelessWidget {
  const SafetyTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text("Fire Safety Tips", style: TextStyle(color: Colors.white)), backgroundColor: Colors.orange[700], iconTheme: const IconThemeData(color: Colors.white), elevation: 0),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('safety_tips').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No safety tips available. Stay safe!"));
          }
          final tips = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tips.length,
            itemBuilder: (context, index) {
              final data = tips[index].data() as Map<String, dynamic>;
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(backgroundColor: Colors.orange[50], child: const Icon(Icons.warning_amber_rounded, color: Colors.orange)),
                  title: Text(data['description'] ?? 'No tip available', style: const TextStyle(fontSize: 15, height: 1.4)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}