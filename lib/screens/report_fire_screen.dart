import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


final FireReportService service = FireReportService();

// =====================================
// FIRE REPORT SERVICE
// =====================================
class FireReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future submitReport({
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
  final String? stationName;

  const ReportFireScreen({super.key, this.stationName});

  @override
  State<ReportFireScreen> createState() => _ReportFireScreenState();
}

class _ReportFireScreenState extends State<ReportFireScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool isLoading = false;

  // GET LOCATION
  Future<Position> getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "📍 Location must be ON to capture your location as the fire reporter.",
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
      throw Exception("Location services are disabled.");
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "❌ Location permission is permanently denied. Enable it in settings.",
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      throw Exception("Location permission permanently denied.");
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // REVERSE GEOCODING
  Future<Map<String, String>> getLocationDetails(double lat, double lon) async {
    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon');
    final response = await http.get(url, headers: {'User-Agent': 'fire_app'});
    final data = json.decode(response.body);
    final address = data['address'];

    return {
      "ward": address['town'] ?? address['village'] ?? address['suburb'] ?? "Unknown",
      "subcounty": address['county'] ?? "Unknown",
      "county": address['state'] ?? "Unknown",
    };
  }

  // REPORT FIRE
  Future<void> reportFire() async {
    if (!_formKey.currentState!.validate()) return;

    if (descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter Fire Description")),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      Position position = await getLocation();
      final locationDetails =
      await getLocationDetails(position.latitude, position.longitude);

      await service.submitReport(
        description: descriptionController.text.trim(),
        lat: position.latitude,
        lon: position.longitude,
        ward: locationDetails["ward"]!,
        subcounty: locationDetails["subcounty"]!,
        county: locationDetails["county"]!,
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
      );

      setState(() => isLoading = false);
      nameController.clear();
      phoneController.clear();
      descriptionController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🚨 Fire Report Sent Successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Fire"),
        backgroundColor: Colors.red,
        actions: [
          TextButton(
            child: const Text("Safety Tips", style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SafetyTipsScreen()),
              );
            },
          ),
          TextButton(
            child: const Text("Emergency Contacts", style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EmergencyContactsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Full Name
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Full Name",
                    hintText: "John Doe",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please enter your full name";
                    }
                    if (!RegExp(r"^[a-zA-Z ]+$").hasMatch(value.trim())) {
                      return "Name can contain letters and spaces only";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),
                // Phone Number
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Phone Number",
                    hintText: "0XXXXXXXXX",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please enter your phone number";
                    }
                    if (!RegExp(r"^[0-9]{10}$").hasMatch(value.trim())) {
                      return "Enter a valid 10-digit phone number";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),
                // Fire Description
                TextField(
                  controller: descriptionController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: "Fire Description",
                    hintText: "Describe the fire:\n"
                        "• What is burning? (e.g., house, car, forest, electrical wires)\n"
                        "• How intense is it? (small, spreading, out of control)\n"
                        "• Are people trapped or injured?",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 30),
                isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  ),
                  onPressed: reportFire,
                  child: const Text(
                    "🚨 REPORT FIRE",
                    style: TextStyle(fontSize: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================
// SAFETY TIPS SCREEN
// =====================================

class SafetyTipsScreen extends StatelessWidget {
  const SafetyTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tipsRef = FirebaseFirestore.instance.collection('safety_tips');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Safety Tips"),
        backgroundColor: Colors.orange,
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: tipsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text("Something went wrong loading tips"),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No tips available"));
          }

          final tips = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: tips.length,
            itemBuilder: (context, index) {
              final data = tips[index].data() as Map<String, dynamic>;

              // ✅ SAFE ACCESS (prevents crash)
              final tipText = data['description'] ?? 'No tip available';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.warning, color: Colors.red),
                  title: Text(tipText),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
// =====================================
// EMERGENCY CONTACTS SCREEN
// =====================================
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  String? selectedCounty;
  String? selectedSubcounty;
  String? selectedWard;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<String> counties = [];
  List<String> subcounties = [];
  List<String> wards = [];
  List<Map<String, dynamic>> stations = [];

  @override
  void initState() {
    super.initState();
    loadCounties();
  }

  // ================================
// LOAD COUNTIES (VERIFIED ONLY)
// ================================
  Future<void> loadCounties() async {
    final querySnapshot = await _firestore
        .collection('stations')
        .where('status', isEqualTo: 'verified')
        .get();

    final countySet = querySnapshot.docs
        .map((doc) => doc['county'] as String)
        .toSet();

    setState(() => counties = countySet.toList());
  }

// ================================
// LOAD SUBCOUNTIES (VERIFIED ONLY)
// ================================
  Future<void> loadSubcounties() async {
    if (selectedCounty == null) return;

    final querySnapshot = await _firestore
        .collection('stations')
        .where('status', isEqualTo: 'verified')
        .where('county', isEqualTo: selectedCounty)
        .get();

    final subcountySet = querySnapshot.docs
        .map((doc) => doc['subcounty'] as String)
        .toSet();

    setState(() {
      subcounties = subcountySet.toList();
      selectedSubcounty = null;
      wards = [];
      selectedWard = null;
      stations = [];
    });
  }

// ================================
// LOAD WARDS (VERIFIED ONLY)
// ================================
  Future<void> loadWards() async {
    if (selectedCounty == null || selectedSubcounty == null) return;

    final querySnapshot = await _firestore
        .collection('stations')
        .where('status', isEqualTo: 'verified')
        .where('county', isEqualTo: selectedCounty)
        .where('subcounty', isEqualTo: selectedSubcounty)
        .get();

    final wardSet = querySnapshot.docs
        .map((doc) => doc['ward'] as String)
        .toSet();

    setState(() {
      wards = wardSet.toList();
      selectedWard = null;
      stations = [];
    });
  }

// ================================
// LOAD STATIONS (VERIFIED ONLY)
// ================================
  Future<void> loadStations() async {
    if (selectedCounty == null ||
        selectedSubcounty == null ||
        selectedWard == null) {
      return;
    }

    final querySnapshot = await _firestore
        .collection('stations')
        .where('status', isEqualTo: 'verified')
        .where('county', isEqualTo: selectedCounty)
        .where('subcounty', isEqualTo: selectedSubcounty)
        .where('ward', isEqualTo: selectedWard)
        .get();

    setState(() {
      stations = querySnapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  Future<void> callNumber(String number) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: number);

    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot launch phone app")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Contacts"),
        backgroundColor: Colors.blue,
      ),

      // ================= BODY =================
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // County dropdown
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Select County"),
              value: selectedCounty,
              items: counties
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (val) {
                setState(() => selectedCounty = val);
                loadSubcounties();
              },
            ),

            const SizedBox(height: 10),

            // Subcounty dropdown
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Select Subcounty"),
              value: selectedSubcounty,
              items: subcounties
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (val) {
                setState(() => selectedSubcounty = val);
                loadWards();
              },
            ),

            const SizedBox(height: 10),

            // Ward dropdown
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Select Ward"),
              value: selectedWard,
              items: wards
                  .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                  .toList(),
              onChanged: (val) {
                setState(() => selectedWard = val);
                loadStations();
              },
            ),

            const Divider(height: 30),

            // Station list
            Expanded(
              child: stations.isEmpty
                  ? const Center(
                child: Text(
                    "Select ward, subcounty, and county to view stations"),
              )
                  : ListView.separated(
                itemCount: stations.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final station = stations[index];

                  return ListTile(
                    leading: const Icon(
                      Icons.local_fire_department,
                      color: Colors.red,
                    ),
                    title: Text(
                        station['station_name'] ?? 'Unknown Station'),
                    subtitle: Text(
                        "Tap to call ${station['phone'] ?? 'N/A'}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.call),
                      onPressed: () {
                        if (station['phone'] != null) {
                          callNumber(station['phone']);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // ================= BOTTOM 999 BUTTON =================
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.phone, color: Colors.white),
            label: const Text(
              "Call 999",
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size.fromHeight(55),
            ),
            onPressed: () {
              callNumber("999");
            },
          ),
        ),
      ),
    );
  }
}