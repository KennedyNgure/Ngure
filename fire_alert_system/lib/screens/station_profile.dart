import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StationProfile extends StatefulWidget {
  final String stationName;

  const StationProfile({super.key, required this.stationName});

  @override
  State<StationProfile> createState() => _StationProfileState();
}

class _StationProfileState extends State<StationProfile> {
  final TextEditingController stationNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // Location State
  String? selectedCounty;
  String? selectedSubCounty;
  String? selectedWard;

  bool passwordVisible = false;
  bool _isLoading = false;

  // --- KENYA LOCATION DATA STRUCTURE ---
  // Format: { "County": { "Sub-County": ["Ward1", "Ward2"] } }
  final Map<String, Map<String, List<String>>> kenyaData = {
    "Nairobi": {
      "Westlands": ["Parklands", "Kitisuru", "Kangemi", "Mountain View"],
      "Dagoretti North": ["Kileleshwa", "Kawangware", "Gatina"],
      "Kasarani": ["Clay City", "Mwiki", "Kasarani", "Njiru"],
      "Lang'ata": ["Karen", "South C", "Mugumo-ini"],
    },
    "Mombasa": {
      "Nyali": ["Frere Town", "Ziwa La Ng'ombe", "Mkomani"],
      "Mvita": ["Majengo", "Railway", "Tononoka"],
      "Likoni": ["Mtongwe", "Shika Adabu", "Bofu"],
    },
    "Kiambu": {
      "Thika Town": ["Township", "Kamenu", "Hospital"],
      "Ruiru": ["Biashara", "Gatongora", "Kahawa Sukari"],
      "Kikuyu": ["Kikuyu", "Sigona", "Kinoo"],
    },
    "Nakuru": {
      "Nakuru East": ["Biashara", "Kivumbini", "Flamingo"],
      "Naivasha": ["Hells Gate", "Lake View", "Mai Mahiu"],
    }
    // Add more counties and their hierarchy here
  };

  /// 🛠️ Modern Input Decoration
  InputDecoration _buildInputDecoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.red),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)),
    );
  }

  /// 🌍 Forward Geocoding
  Future<Map<String, double>> getCoordinatesFromAddress(String ward, String subcounty, String county) async {
    final query = "$ward, $subcounty, $county, Kenya";
    final url = Uri.parse("https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1");

    final response = await http.get(url, headers: {'User-Agent': 'fire_app'});
    final data = json.decode(response.body);

    if (data.isEmpty) {
      throw Exception("Location coordinates not found. Please try a more general area.");
    }

    return {
      "lat": double.parse(data[0]["lat"]),
      "lon": double.parse(data[0]["lon"]),
    };
  }

  /// Load Station Data
  Future<void> loadStation() async {
    setState(() => _isLoading = true);
    try {
      var query = await FirebaseFirestore.instance
          .collection("stations")
          .where("station_name", isEqualTo: widget.stationName)
          .get();

      if (query.docs.isNotEmpty) {
        var data = query.docs.first.data();
        setState(() {
          stationNameController.text = data["station_name"] ?? "";
          emailController.text = data["email"] ?? "";
          phoneController.text = data["phone"] ?? "";

          // Pre-populate dropdowns if data exists
          if (kenyaData.containsKey(data["county"])) {
            selectedCounty = data["county"];
            if (kenyaData[selectedCounty]!.containsKey(data["subcounty"])) {
              selectedSubCounty = data["subcounty"];
              if (kenyaData[selectedCounty]![selectedSubCounty]!.contains(data["ward"])) {
                selectedWard = data["ward"];
              }
            }
          }
        });
      }
    } catch (e) {
      _showSnackBar("Error loading profile: $e", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Validation Logic
  bool _isValidForm() {
    // Email Validation
    final email = emailController.text.trim();
    if (!RegExp(r'^[\w-\.]+@gmail\.com$').hasMatch(email)) {
      _showSnackBar("Please enter a valid @gmail.com address", Colors.orange);
      return false;
    }

    // Phone Validation (10 digits)
    final phone = phoneController.text.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
      _showSnackBar("Phone number must be exactly 10 digits", Colors.orange);
      return false;
    }

    // Location Validation
    if (selectedCounty == null || selectedSubCounty == null || selectedWard == null) {
      _showSnackBar("Please complete the location details", Colors.orange);
      return false;
    }

    return true;
  }

  /// Update Station Logic
  Future<void> updateStation() async {
    if (!_isValidForm()) return;

    setState(() => _isLoading = true);
    try {
      // 1. Get Coordinates based on dropdown selections
      final coords = await getCoordinatesFromAddress(selectedWard!, selectedSubCounty!, selectedCounty!);

      // 2. Prepare Update Map
      Map<String, dynamic> updateData = {
        "email": emailController.text.trim(),
        "phone": phoneController.text.trim(),
        "ward": selectedWard,
        "subcounty": selectedSubCounty,
        "county": selectedCounty,
        "latitude": coords["lat"],
        "longitude": coords["lon"],
      };

      // 3. Update Firestore
      var query = await FirebaseFirestore.instance
          .collection("stations")
          .where("station_name", isEqualTo: widget.stationName)
          .get();

      if (query.docs.isEmpty) throw Exception("Station not found in database.");

      await FirebaseFirestore.instance
          .collection("stations")
          .doc(query.docs.first.id)
          .update(updateData);

      // 4. Update Auth Password if provided
      if (passwordController.text.isNotEmpty) {
        User? user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await user.updatePassword(passwordController.text.trim());
        }
      }

      _showSnackBar("✅ Profile updated successfully", Colors.green);
      passwordController.clear();
    } catch (e) {
      _showSnackBar("Error: $e", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void initState() {
    super.initState();
    loadStation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Edit Profile", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.red,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // --- PROFILE HEADER ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 30, top: 10),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
                  ),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.local_fire_department, size: 50, color: Colors.red),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.stationName,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const Text("Official Station Profile", style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle("Account Information"),
                      _buildCard([
                        TextField(
                          controller: stationNameController,
                          readOnly: true,
                          decoration: _buildInputDecoration("Station Name", Icons.business),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _buildInputDecoration("Email Address (@gmail.com)", Icons.email),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          decoration: _buildInputDecoration("Phone (e.g. 0712345678)", Icons.phone).copyWith(counterText: ""),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: passwordController,
                          obscureText: !passwordVisible,
                          decoration: _buildInputDecoration(
                            "New Password (optional)",
                            Icons.lock,
                            suffix: IconButton(
                              icon: Icon(passwordVisible ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => passwordVisible = !passwordVisible),
                            ),
                          ),
                        ),
                      ]),

                      const SizedBox(height: 20),
                      _sectionTitle("Geographic Location"),
                      _buildCard([
                        // COUNTY DROPDOWN
                        DropdownButtonFormField<String>(
                          value: selectedCounty,
                          decoration: _buildInputDecoration("County", Icons.map),
                          items: kenyaData.keys.map((county) {
                            return DropdownMenuItem(value: county, child: Text(county));
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedCounty = val;
                              selectedSubCounty = null; // Reset sub-level
                              selectedWard = null;      // Reset sub-level
                            });
                          },
                        ),
                        const SizedBox(height: 15),

                        // SUB-COUNTY DROPDOWN
                        DropdownButtonFormField<String>(
                          value: selectedSubCounty,
                          decoration: _buildInputDecoration("Sub-County", Icons.location_city),
                          items: selectedCounty == null
                              ? []
                              : kenyaData[selectedCounty]!.keys.map((sub) {
                            return DropdownMenuItem(value: sub, child: Text(sub));
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedSubCounty = val;
                              selectedWard = null; // Reset sub-level
                            });
                          },
                        ),
                        const SizedBox(height: 15),

                        // WARD DROPDOWN
                        DropdownButtonFormField<String>(
                          value: selectedWard,
                          decoration: _buildInputDecoration("Ward", Icons.explore),
                          items: (selectedCounty == null || selectedSubCounty == null)
                              ? []
                              : kenyaData[selectedCounty]![selectedSubCounty]!.map((ward) {
                            return DropdownMenuItem(value: ward, child: Text(ward));
                          }).toList(),
                          onChanged: (val) => setState(() => selectedWard = val),
                        ),
                      ]),

                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            elevation: 4,
                          ),
                          onPressed: _isLoading ? null : updateStation,
                          child: const Text(
                            "SAVE UPDATES",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: children),
    );
  }
}