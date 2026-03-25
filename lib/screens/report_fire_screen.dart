import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'registration_screen.dart';

// =====================================
// FIRE REPORT SERVICE
// =====================================
class FireReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future submitReport({
    required String fireType,
    required String fireSize,
    required int peopleTrapped,
    required String evacuationStatus,
    required double lat,
    required double lon,
    required String ward,
    required String subcounty,
    required String county,
    String? name,
    String? phone,
  }) async {
    await _firestore.collection("reports").add({
      "fireType": fireType,
      "fireSize": fireSize,
      "peopleTrapped": peopleTrapped,
      "evacuationStatus": evacuationStatus,
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
  final String? stationName; // <- must be declared

  // Remove const because we might pass non-const stationName
  ReportFireScreen({super.key, this.stationName});

  @override
  State<ReportFireScreen> createState() => _ReportFireScreenState();
}

class _ReportFireScreenState extends State<ReportFireScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController peopleController = TextEditingController();

  final FireReportService service = FireReportService();

  String? selectedFireType;
  String? selectedFireSize;
  String? evacuationStatus;

  bool isLoading = false;

  final List<String> fireTypes = [
    'Forest/Bush Fire',
    'House/Building Fire',
    'Vehicle Fire',
    'Electrical Fire',
    'Industrial'
  ];

  final List<String> fireSizes = ["Small", "Medium", "Large"];

  final List<String> evacuationOptions = [
    "Evacuated",
    "Evacuation in progress",
    "People still inside",
  ];

  // GET LOCATION
  Future<Position> getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Show a notification to the user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "📍 Location must be ON to capture your location as the fire reporter. "
                "This helps in sending units to your location quickly.",
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
            "❌ Location permission is permanently denied. "
                "Enable it in settings to report fire accurately.",
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
    if (selectedFireType == null || selectedFireSize == null || evacuationStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fire details")),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      Position position = await getLocation();
      final locationDetails = await getLocationDetails(position.latitude, position.longitude);

      await service.submitReport(
        fireType: selectedFireType!,
        fireSize: selectedFireSize!,
        peopleTrapped: int.tryParse(peopleController.text) ?? 0,
        evacuationStatus: evacuationStatus!,
        lat: position.latitude,
        lon: position.longitude,
        ward: locationDetails["ward"]!,
        subcounty: locationDetails["subcounty"]!,
        county: locationDetails["county"]!,
        name: nameController.text.isEmpty ? null : nameController.text.trim(),
        phone: phoneController.text.isEmpty ? null : phoneController.text.trim(),
      );

      setState(() => isLoading = false);
      nameController.clear();
      phoneController.clear();
      peopleController.clear();

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
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const SafetyTipsScreen()));
            },
          ),
          TextButton(
            child: const Text("Emergency Contacts", style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const EmergencyContactsScreen()));
            },
          ),
          TextButton(
            child: const Text("Stations Registration", style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => RegistrationScreen()));
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Full Name (optional)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Phone Number (optional)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: selectedFireType,
                decoration: const InputDecoration(
                  labelText: "Type of Fire 🔥",
                  border: OutlineInputBorder(),
                ),
                items: fireTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                onChanged: (value) => setState(() => selectedFireType = value),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: selectedFireSize,
                decoration: const InputDecoration(
                  labelText: "Size of Fire",
                  border: OutlineInputBorder(),
                ),
                items: fireSizes.map((size) => DropdownMenuItem(value: size, child: Text(size))).toList(),
                onChanged: (value) => setState(() => selectedFireSize = value),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: peopleController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Number of people trapped or injured",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: evacuationStatus,
                decoration: const InputDecoration(
                  labelText: "Evacuation Status",
                  border: OutlineInputBorder(),
                ),
                items: evacuationOptions.map((status) => DropdownMenuItem(value: status, child: Text(status))).toList(),
                onChanged: (value) => setState(() => evacuationStatus = value),
              ),
              const SizedBox(height: 30),
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                ),
                onPressed: reportFire,
                child: const Text("🚨 REPORT FIRE", style: TextStyle(fontSize: 20)),
              ),
            ],
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fire Safety Tips"),
        backgroundColor: Colors.orange,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          ListTile(leading: Icon(Icons.warning, color: Colors.red), title: Text("Stay calm and evacuate immediately.")),
          ListTile(leading: Icon(Icons.warning, color: Colors.red), title: Text("Do not use elevators during a fire.")),
          ListTile(leading: Icon(Icons.warning, color: Colors.red), title: Text("Cover nose and mouth with cloth to avoid smoke.")),
          ListTile(leading: Icon(Icons.warning, color: Colors.red), title: Text("Stay low to the ground when escaping smoke.")),
          ListTile(leading: Icon(Icons.warning, color: Colors.red), title: Text("Call emergency services immediately.")),
        ],
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
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
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

  // Load all counties from Firestore
  Future<void> loadCounties() async {
    final querySnapshot = await _firestore.collection('stations').get();
    final countySet = querySnapshot.docs.map((doc) => doc['county'] as String).toSet();
    setState(() => counties = countySet.toList());
  }

  // Load subcounties based on selected county
  Future<void> loadSubcounties() async {
    if (selectedCounty == null) return;
    final querySnapshot = await _firestore
        .collection('stations')
        .where('county', isEqualTo: selectedCounty)
        .get();
    final subcountySet = querySnapshot.docs.map((doc) => doc['subcounty'] as String).toSet();
    setState(() {
      subcounties = subcountySet.toList();
      selectedSubcounty = null;
      wards = [];
      selectedWard = null;
      stations = [];
    });
  }

  // Load wards based on selected county & subcounty
  Future<void> loadWards() async {
    if (selectedCounty == null || selectedSubcounty == null) return;
    final querySnapshot = await _firestore
        .collection('stations')
        .where('county', isEqualTo: selectedCounty)
        .where('subcounty', isEqualTo: selectedSubcounty)
        .get();
    final wardSet = querySnapshot.docs.map((doc) => doc['ward'] as String).toSet();
    setState(() {
      wards = wardSet.toList();
      selectedWard = null;
      stations = [];
    });
  }

  // Load stations based on county, subcounty, and ward
  Future<void> loadStations() async {
    if (selectedCounty == null || selectedSubcounty == null || selectedWard == null) return;
    final querySnapshot = await _firestore
        .collection('stations')
        .where('county', isEqualTo: selectedCounty)
        .where('subcounty', isEqualTo: selectedSubcounty)
        .where('ward', isEqualTo: selectedWard)
        .get();
    setState(() {
      stations = querySnapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  // Call a phone number
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // County dropdown
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Select County"),
              value: selectedCounty,
              items: counties.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
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
              items: subcounties.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
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
              items: wards.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
              onChanged: (val) {
                setState(() => selectedWard = val);
                loadStations();
              },
            ),
            const Divider(height: 30),
            // Station list
            Expanded(
              child: stations.isEmpty
                  ? const Center(child: Text("Select ward, subcounty, and county to view stations"))
                  : ListView.separated(
                itemCount: stations.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final station = stations[index];
                  return ListTile(
                    leading: const Icon(Icons.local_fire_department, color: Colors.red),
                    title: Text(station['station_name'] ?? 'Unknown Station'),
                    subtitle: Text("Tap to call ${station['phone'] ?? 'N/A'}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.call),
                      onPressed: () {
                        if (station['phone'] != null) callNumber(station['phone']);
                      },
                    ),
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