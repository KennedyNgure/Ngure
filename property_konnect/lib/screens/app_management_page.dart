import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';

/// Admin-only settings, account management and application statistics.
/// The caller should ensure this page is reachable only by an administrator.
class AppManagementPage extends StatefulWidget {
  const AppManagementPage({super.key});

  @override
  State<AppManagementPage> createState() => _AppManagementPageState();
}

class _AppManagementPageState extends State<AppManagementPage> {
  static const String _helperAppName = 'admin-creator';
  static const Color _brand = Color(0xFF16834A);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _settingsFormKey = GlobalKey<FormState>();
  final _adminFormKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _supportEmailController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPhoneController = TextEditingController();
  final _searchController = TextEditingController();

  bool _settingsLoaded = false;
  bool _savingSettings = false;
  bool _creatingAdmin = false;
  bool _showAddAdmin = false;
  String _adminSearch = '';

  static const List<String> _propertyTypes = [
    'Homes',
    'Hostels',
    'Stalls',
    'Estates',
    'Studios',
    'BnBs',
    'Warehouses',
    'Apartments',
    'Land',
    'Residential Plot',
    'Agricultural Land',
    'Ranch',
  ];

  bool get _isDark => AppSettings.of(context).isDark;
  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;
  Color get _pageColor => _isDark ? const Color(0xFF101713) : const Color(0xFFF5F7F5);
  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;
  Color get _textColor => _isDark ? Colors.white : const Color(0xFF202820);
  Color get _mutedColor => _isDark ? Colors.white70 : Colors.black54;
  Color get _borderColor => _isDark ? const Color(0xFF344239) : Colors.grey.shade200;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyController.dispose();
    _supportEmailController.dispose();
    _whatsappController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPhoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await _db.collection('app_config').doc('settings').get();
      final data = doc.data() ?? <String, dynamic>{};
      _companyController.text = (data['companyName'] ?? '').toString();
      _supportEmailController.text = (data['supportEmail'] ?? '').toString();
      _whatsappController.text = (data['whatsappContact'] ?? '').toString();
    } catch (e) {
      if (mounted) _snack('${_tr('Could not load settings', 'Imeshindikana kupakia mipangilio')}: $e');
    } finally {
      if (mounted) setState(() => _settingsLoaded = true);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveSettings() async {
    if (!_settingsFormKey.currentState!.validate()) return;
    setState(() => _savingSettings = true);
    try {
      await _db.collection('app_config').doc('settings').set({
        'companyName': _companyController.text.trim(),
        'supportEmail': _supportEmailController.text.trim(),
        'whatsappContact': _whatsappController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      }, SetOptions(merge: true));
      _snack(_tr('Settings saved.', 'Mipangilio imehifadhiwa.'));
    } catch (e) {
      _snack('${_tr('Could not save settings', 'Imeshindikana kuhifadhi mipangilio')}: $e');
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  String _normalizeType(dynamic value) {
    final type = (value ?? '').toString().trim().toLowerCase();
    final key = type.replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    const aliases = <String, String>{
      'home': 'homes', 'homes': 'homes', 'house': 'homes', 'houses': 'homes',
      'hostel': 'hostels', 'hostels': 'hostels',
      'stall': 'stalls', 'stalls': 'stalls',
      'estate': 'estates', 'estates': 'estates',
      'studio': 'studios', 'studios': 'studios',
      'bnb': 'bnbs', 'bnbs': 'bnbs', 'b and b': 'bnbs',
      'warehouse': 'warehouses', 'warehouses': 'warehouses',
      'apartment': 'apartments', 'apartments': 'apartments',
      'land': 'land', 'residential plot': 'residential plot',
      'plot': 'residential plot', 'plots': 'residential plot',
      'agricultural land': 'agricultural land', 'farm land': 'agricultural land',
      'ranch': 'ranch', 'ranches': 'ranch',
    };
    return aliases[key] ?? key;
  }

  int _countType(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String type) {
    final target = _normalizeType(type);
    return docs.where((doc) => _normalizeType(
      doc.data()['propertyType'] ?? doc.data()['type'] ?? doc.data()['category'],
    ) == target).length;
  }

  Future<void> _createAdmin() async {
    if (!_adminFormKey.currentState!.validate()) return;
    final name = _adminNameController.text.trim();
    final email = _adminEmailController.text.trim().toLowerCase();
    final phone = _adminPhoneController.text.trim();
    final currentAdmin = _auth.currentUser;
    if (currentAdmin == null) {
      _snack(_tr('Please sign in again.', 'Tafadhali ingia tena.'));
      return;
    }

    setState(() => _creatingAdmin = true);
    FirebaseApp? helperApp;
    try {
      // If the email already has a Firebase Auth account, offer to promote
      // its existing profile rather than creating a duplicate Auth account.
      final matching = await _db.collection('users').where('email', isEqualTo: email).limit(1).get();
      if (matching.docs.isNotEmpty) {
        final existing = matching.docs.first;
        if (!mounted) return;
        final promote = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_tr('Account already exists', 'Akaunti tayari ipo')),
            content: Text(_tr(
              'A profile with this email was found. Promote that profile to administrator?',
              'Wasifu wenye barua pepe hii umepatikana. Ubadilishe kuwa msimamizi?',
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_tr('Cancel', 'Ghairi'))),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_tr('Promote', 'Badilisha'))),
            ],
          ),
        ) ?? false;
        if (promote) {
          await existing.reference.set({
            'role': 'admin',
            'isActive': true,
            'status': 'verified',
            'adminUpdatedAt': FieldValue.serverTimestamp(),
            'adminUpdatedBy': currentAdmin.uid,
          }, SetOptions(merge: true));
          _clearAdminForm();
          _snack(_tr('Existing account promoted to admin.', 'Akaunti iliyopo imebadilishwa kuwa msimamizi.'));
        }
        return;
      }

      final temporaryPassword = _randomPassword();
      helperApp = await Firebase.initializeApp(
        name: _helperAppName,
        options: Firebase.app().options,
      );
      final helperAuth = FirebaseAuth.instanceFor(app: helperApp);
      final credential = await helperAuth.createUserWithEmailAndPassword(
        email: email,
        password: temporaryPassword,
      );
      final newUser = credential.user;
      if (newUser == null) throw StateError('Firebase did not return a user.');
      await helperAuth.signOut();

      // Firestore uses the primary app, where the current administrator remains signed in.
      await _db.collection('users').doc(newUser.uid).set({
        'fullName': name,
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'admin',
        'status': 'verified',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentAdmin.uid,
      });

      // The new administrator chooses their own password from this link.
      await helperAuth.sendPasswordResetEmail(email: email);
      _clearAdminForm();
      _snack(_tr('Admin account created. A password-reset email has been sent.', 'Akaunti ya msimamizi imeundwa. Barua pepe ya kuweka nenosiri imetumwa.'));
    } on FirebaseAuthException catch (e) {
      _snack('${_tr('Could not create admin', 'Imeshindikana kuunda msimamizi')}: ${e.message ?? e.code}');
    } catch (e) {
      _snack('${_tr('Could not create admin', 'Imeshindikana kuunda msimamizi')}: $e');
    } finally {
      if (helperApp != null) {
        try { await helperApp.delete(); } catch (_) {}
      }
      if (mounted) setState(() => _creatingAdmin = false);
    }
  }

  String _randomPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%';
    final random = Random.secure();
    return List.generate(24, (_) => chars[random.nextInt(chars.length)]).join();
  }

  void _clearAdminForm() {
    _adminNameController.clear();
    _adminEmailController.clear();
    _adminPhoneController.clear();
    if (mounted) setState(() => _showAddAdmin = false);
  }

  Future<void> _removeAdmin(QueryDocumentSnapshot<Map<String, dynamic>> admin) async {
    final data = admin.data();
    final name = (data['fullName'] ?? data['name'] ?? data['email'] ?? admin.id).toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Remove administrator access?', 'Ondoa ruhusa ya msimamizi?')),
        content: Text(_tr('Change $name from admin to a regular user?', 'Badilisha $name kutoka msimamizi kuwa mtumiaji wa kawaida?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_tr('Cancel', 'Ghairi'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_tr('Remove access', 'Ondoa ruhusa'))),
        ],
      ),
    ) ?? false;
    if (!confirmed) return;
    try {
      await admin.reference.update({'role': 'user', 'adminRemovedAt': FieldValue.serverTimestamp()});
      _snack(_tr('Administrator access removed.', 'Ruhusa ya msimamizi imeondolewa.'));
    } catch (e) {
      _snack('${_tr('Could not update account', 'Imeshindikana kusasisha akaunti')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(_tr('App Management', 'Usimamizi wa Programu')),
        backgroundColor: _brand,
        foregroundColor: Colors.white,
      ),
      body: !_settingsLoaded
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').snapshots(),
        builder: (context, usersSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('properties').snapshots(),
          builder: (context, propertiesSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('roommates').snapshots(),
            builder: (context, roommatesSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db.collection('campus_communities').snapshots(),
              builder: (context, communitiesSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db.collection('services').snapshots(),
                builder: (context, servicesSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _db.collection('student_services').snapshots(),
                  builder: (context, studentServicesSnapshot) {
                    final waiting = usersSnapshot.connectionState == ConnectionState.waiting ||
                        propertiesSnapshot.connectionState == ConnectionState.waiting ||
                        roommatesSnapshot.connectionState == ConnectionState.waiting ||
                        communitiesSnapshot.connectionState == ConnectionState.waiting ||
                        servicesSnapshot.connectionState == ConnectionState.waiting ||
                        studentServicesSnapshot.connectionState == ConnectionState.waiting;
                    if (waiting) return const Center(child: CircularProgressIndicator());
                    final streamError = usersSnapshot.hasError || propertiesSnapshot.hasError ||
                        roommatesSnapshot.hasError || communitiesSnapshot.hasError ||
                        servicesSnapshot.hasError || studentServicesSnapshot.hasError;
                    if (streamError) {
                      return Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_tr(
                          'Statistics could not be loaded. Check Firestore rules and connection.',
                          'Takwimu hazikuweza kupakiwa. Angalia sheria za Firestore na muunganisho.',
                        ), textAlign: TextAlign.center),
                      ));
                    }
                    final users = usersSnapshot.data!.docs;
                    final properties = propertiesSnapshot.data!.docs;
                    final roommates = roommatesSnapshot.data!.docs;
                    final communities = communitiesSnapshot.data!.docs;
                    final services = servicesSnapshot.data!.docs;
                    final studentServices = studentServicesSnapshot.data!.docs;
                    final owners = users.where((d) => (d.data()['role'] ?? '').toString().toLowerCase() == 'owner').toList();
                    final admins = users.where((d) => (d.data()['role'] ?? '').toString().toLowerCase() == 'admin').toList();
                    final activeRoommates = roommates.where((d) => d.data()['isActive'] != false && d.data()['active'] != false).length;

                    // ---- OWNERS: deactivated owners are kept OUT of the
                    // total, verified and unverified counts. They are shown
                    // separately so the numbers always add up:
                    // total = verified + unverified.
                    final activeOwners = owners
                        .where((d) => !_isDeactivated(d.data()))
                        .toList();
                    final verifiedOwners = activeOwners
                        .where((d) => _isVerified(d.data()))
                        .length;
                    final unverifiedOwners = activeOwners.length - verifiedOwners;
                    final deactivatedOwners = owners.length - activeOwners.length;

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _sectionTitle(_tr('Overview', 'Muhtasari')),
                        _statsGrid([
                          _StatItem(_tr('Total Users', 'Watumiaji Wote'), users.length, Icons.people_alt_outlined),
                          _StatItem(_tr('Total Admins', 'Wasimamizi Wote'), admins.length, Icons.admin_panel_settings_outlined),
                          _StatItem(_tr('Property Owners', 'Wamiliki wa Mali'), owners.length, Icons.person_pin_outlined),
                          _StatItem(_tr('Active Roommate Posts', 'Machapisho Hai ya Wenzako'), activeRoommates, Icons.people_outline),
                          _StatItem(_tr('Campus Communities', 'Jamii za Kampasi'), communities.length, Icons.groups_outlined),
                          _StatItem(_tr('Services', 'Huduma'), services.length, Icons.home_repair_service_outlined),
                          _StatItem(_tr('Student Services', 'Huduma za Wanafunzi'), studentServices.length, Icons.school_outlined),
                        ]),
                        const SizedBox(height: 24),
                        _sectionTitle(_tr('Property Owner Statistics', 'Takwimu za Wamiliki wa Mali')),
                        _statsGrid([
                          _StatItem(_tr('Total Owners', 'Wamiliki Wote'), activeOwners.length, Icons.person_outline),
                          _StatItem(_tr('Verified Owners', 'Wamiliki Waliothibitishwa'), verifiedOwners, Icons.verified_outlined),
                          _StatItem(_tr('Unverified Owners', 'Wamiliki Wasiothibitishwa'), unverifiedOwners, Icons.pending_outlined),
                          _StatItem(_tr('Ads Verified Owners', 'Wamiliki Waliothibitisha Matangazo'), owners.where((d) => _isAdsVerified(d.data())).length, Icons.campaign_outlined),
                          _StatItem(_tr('Deactivated Owner Accounts', 'Akaunti za Wamiliki Zilizozimwa'), deactivatedOwners, Icons.person_off_outlined),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _tr(
                              'Deactivated owners are not included in the total, verified or unverified owner counts.',
                              'Wamiliki waliozimwa hawajumuishwi kwenye jumla, waliothibitishwa au wasiothibitishwa.',
                            ),
                            style: TextStyle(color: _mutedColor, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _sectionTitle(_tr('Listings by Property Type', 'Matangazo kwa Aina ya Mali')),
                        _statsGrid(_propertyTypes.map((type) => _StatItem(type, _countType(properties, type), _iconForType(type))).toList()),
                        const SizedBox(height: 24),
                        _sectionTitle(_tr('Application Settings', 'Mipangilio ya Programu')),
                        _settingsCard(),
                        const SizedBox(height: 24),
                        Row(children: [
                          Expanded(child: _sectionTitle(_tr('Administrators', 'Wasimamizi'))),
                          FilledButton.icon(
                            onPressed: () => setState(() => _showAddAdmin = !_showAddAdmin),
                            icon: Icon(_showAddAdmin ? Icons.close : Icons.person_add_alt_1, size: 18),
                            label: Text(_showAddAdmin ? _tr('Cancel', 'Ghairi') : _tr('Add Admin', 'Ongeza Msimamizi')),
                            style: FilledButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                          ),
                        ]),
                        if (_showAddAdmin) ...[
                          const SizedBox(height: 8),
                          _addAdminCard(),
                        ],
                        const SizedBox(height: 8),
                        _adminList(admins),
                        const SizedBox(height: 20),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Aligned with VerifyPropertyOwnersPage so statistics match
  // what that page shows: verification uses 'landlord_status',
  // ads uses 'adsverification', deactivation uses
  // 'isDeactivated'/'accountStatus'.
  bool _isVerified(Map<String, dynamic> data) {
    if ((data['landlord_status'] ?? '').toString().toLowerCase() == 'verified') return true;
    final status = (data['status'] ?? data['verificationStatus'] ?? '').toString().toLowerCase();
    return data['isVerified'] == true || data['verified'] == true || status == 'verified' || status == 'approved';
  }

  bool _isAdsVerified(Map<String, dynamic> data) {
    final value = data['adsverification'] ?? data['adsVerification'] ?? data['adsVerified'];
    return value == true || value?.toString().toLowerCase() == 'verified' ||
        data['adsVerificationStatus'] == 'verified';
  }

  bool _isDeactivated(Map<String, dynamic> data) {
    return data['isDeactivated'] == true ||
        (data['accountStatus'] ?? '').toString().toLowerCase() == 'deactivated' ||
        data['isActive'] == false;
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Homes': return Icons.house_outlined;
      case 'Hostels': return Icons.hotel_outlined;
      case 'Stalls': return Icons.storefront_outlined;
      case 'Estates': return Icons.apartment_outlined;
      case 'Studios': return Icons.weekend_outlined;
      case 'BnBs': return Icons.bed_outlined;
      case 'Warehouses': return Icons.warehouse_outlined;
      case 'Apartments': return Icons.location_city_outlined;
      case 'Land': return Icons.landscape_outlined;
      case 'Residential Plot': return Icons.map_outlined;
      case 'Agricultural Land': return Icons.grass_outlined;
      case 'Ranch': return Icons.agriculture_outlined;
      default: return Icons.home_work_outlined;
    }
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w800)),
  );

  Widget _statsGrid(List<_StatItem> items) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 1000 ? 4 : width >= 620 ? 3 : width >= 390 ? 2 : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 96,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: _borderColor)),
            child: Row(children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: _brand.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: Icon(item.icon, color: _brand, size: 21)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _mutedColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${item.value}', style: TextStyle(color: _textColor, fontSize: 22, fontWeight: FontWeight.w800)),
              ])),
            ]),
          );
        },
      );
    });
  }

  Widget _settingsCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderColor)),
    child: Form(
      key: _settingsFormKey,
      child: Column(children: [
        _textField(_companyController, _tr('Company name', 'Jina la kampuni'), icon: Icons.business_outlined),
        const SizedBox(height: 12),
        _textField(_supportEmailController, _tr('Support email', 'Barua pepe ya usaidizi'), icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress, validator: (value) {
          final v = (value ?? '').trim();
          if (v.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) return _tr('Enter a valid email.', 'Weka barua pepe sahihi.');
          return null;
        }),
        const SizedBox(height: 12),
        _textField(_whatsappController, _tr('WhatsApp contact', 'Nambari ya WhatsApp'), icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(
          onPressed: _savingSettings ? null : _saveSettings,
          icon: _savingSettings ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined, size: 18),
          label: Text(_tr('Save Settings', 'Hifadhi Mipangilio')),
          style: FilledButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
        )),
      ]),
    ),
  );

  Widget _addAdminCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderColor)),
    child: Form(
      key: _adminFormKey,
      child: Column(children: [
        _textField(_adminNameController, _tr('Full name', 'Jina kamili'), icon: Icons.person_outline, validator: (v) => (v ?? '').trim().isEmpty ? _tr('Enter a full name.', 'Weka jina kamili.') : null),
        const SizedBox(height: 12),
        _textField(_adminEmailController, _tr('Email address', 'Barua pepe'), icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress, validator: (v) {
          final value = (v ?? '').trim();
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return _tr('Enter a valid email.', 'Weka barua pepe sahihi.');
          return null;
        }),
        const SizedBox(height: 12),
        _textField(_adminPhoneController, _tr('Phone number (10 digits)', 'Nambari ya simu (tarakimu 10)'), icon: Icons.phone_outlined, keyboardType: TextInputType.phone, validator: (v) => RegExp(r'^\d{10}$').hasMatch((v ?? '').trim()) ? null : _tr('Enter exactly 10 digits.', 'Weka tarakimu 10 kamili.')),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(
          onPressed: _creatingAdmin ? null : _createAdmin,
          icon: _creatingAdmin ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.person_add_alt_1, size: 18),
          label: Text(_tr('Create Admin', 'Unda Msimamizi')),
          style: FilledButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
        )),
        const SizedBox(height: 6),
        Text(_tr('A password-reset email will be sent so the administrator can set their own password.', 'Barua pepe ya kuweka upya nenosiri itatumwa ili msimamizi aweke nenosiri lake.'), style: TextStyle(color: _mutedColor, fontSize: 12)),
      ]),
    ),
  );

  Widget _adminList(List<QueryDocumentSnapshot<Map<String, dynamic>>> admins) {
    final query = _adminSearch.trim().toLowerCase();
    final filtered = admins.where((doc) {
      final data = doc.data();
      final text = '${data['fullName'] ?? data['name'] ?? ''} ${data['email'] ?? ''} ${data['phone'] ?? ''}'.toLowerCase();
      return text.contains(query);
    }).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderColor)),
      child: Column(children: [
        Row(children: [
          Expanded(child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _adminSearch = value),
            decoration: InputDecoration(
              hintText: _tr('Search administrators', 'Tafuta wasimamizi'),
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          )),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), decoration: BoxDecoration(color: _brand.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)), child: Text('${filtered.length}', style: const TextStyle(fontWeight: FontWeight.w800, color: _brand))),
        ]),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Text(_tr('No administrators found.', 'Hakuna wasimamizi waliopatikana.'), style: TextStyle(color: _mutedColor)))
        else
          ...filtered.map((admin) {
            final data = admin.data();
            final name = (data['fullName'] ?? data['name'] ?? _tr('Administrator', 'Msimamizi')).toString();
            final email = (data['email'] ?? '').toString();
            final phone = (data['phone'] ?? '').toString();
            final isCurrent = admin.id == _auth.currentUser?.uid;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              leading: CircleAvatar(backgroundColor: _brand.withValues(alpha: .12), child: const Icon(Icons.admin_panel_settings_outlined, color: _brand)),
              title: Text(name, style: TextStyle(color: _textColor, fontWeight: FontWeight.w700)),
              subtitle: Text([email, phone].where((v) => v.isNotEmpty).join(' • '), style: TextStyle(color: _mutedColor, fontSize: 12)),
              trailing: isCurrent ? Text(_tr('You', 'Wewe'), style: const TextStyle(color: _brand, fontWeight: FontWeight.w700)) : IconButton(
                tooltip: _tr('Remove admin access', 'Ondoa ruhusa ya msimamizi'),
                onPressed: () => _removeAdmin(admin),
                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 21),
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
      ]),
    );
  }

  Widget _textField(
      TextEditingController controller,
      String label, {
        required IconData icon,
        TextInputType? keyboardType,
        String? Function(String?)? validator,
      }) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    validator: validator,
    style: TextStyle(color: _textColor),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    ),
  );
}

class _StatItem {
  final String label;
  final int value;
  final IconData icon;
  const _StatItem(this.label, this.value, this.icon);
}