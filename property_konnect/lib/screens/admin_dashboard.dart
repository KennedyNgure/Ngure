import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'manage_reviews_page.dart';

import 'verify_property_owners_page.dart';
import 'manage_reports_page.dart';
import 'other_app_services_page.dart';
import 'review_property_listings_page.dart';
import 'roommates_posts.dart';
import 'terms_page.dart';
import 'homepage.dart';
import 'privacy_policy_page.dart';
import 'faqs_page.dart';
import 'fingerprint_setup_page.dart';
import 'app_management_page.dart';
import 'app_settings.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // ==========================================================
  // THEME + TRANSLATION
  // ==========================================================

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _greenDeep =>
      _isDark ? kBrandGreenOnDark : const Color(0xFF146C43);

  Color get _greenSurface =>
      _isDark ? const Color(0xFF152219) : const Color(0xFFEAF7EF);

  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _pageBackground =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _mutedText => _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _bodyText => _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _accentBlue =>
      _isDark ? Colors.blue.shade300 : Colors.blue.shade700;

  Color get _accentPurple =>
      _isDark ? Colors.purple.shade300 : const Color(0xFF7B4FC9);

  Color get _accentGreen =>
      _isDark ? Colors.green.shade300 : const Color(0xFF1FA85A);

  Color get _accentRed =>
      _isDark ? Colors.red.shade300 : Colors.red.shade600;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  bool _isSuperAdmin = false;
  bool _checkingAdmin = true;
  bool _loggingOut = false;

  /// NEW: true while the startup biometric check runs. The
  /// dashboard is hidden behind a loading state until it
  /// finishes, so the dashboard never flashes before the
  /// biometric prompt appears.
  bool _biometricCheckDone = false;

  String _greetingName = '';

  // The signed-in admin's profile, read once at start-up and used
  // by the biometric check below.
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _startup();
  }

  Future<void> _startup() async {
    await _checkAdmin();

    // NEW: only after the admin profile is loaded do we run the
    // biometric check — it needs the profile to know whether
    // biometrics were already set up.
    await _checkBiometricSetup();

    if (mounted) {
      setState(() {
        _biometricCheckDone = true;
      });
    }
  }

  // ==========================================================
  // GREETING (changes with the time of day)
  // ==========================================================

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return _tr('Good morning', 'Habari za asubuhi');
    }

    if (hour < 17) {
      return _tr('Good afternoon', 'Habari za mchana');
    }

    return _tr('Good evening', 'Habari za jioni');
  }

  // ==========================================================
  // CHECK ADMIN
  // ==========================================================

  Future<void> _checkAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final data = userDoc.data();

        final fullName =
        (data?['fullName'] ?? data?['name'] ?? data?['displayName'] ?? '')
            .toString()
            .trim();

        final role = (data?['role'] ?? '').toString().trim().toLowerCase();

        if (mounted) {
          setState(() {
            _profile = data;
            _greetingName = fullName;

            _isSuperAdmin =
                role == 'admin' && fullName.toUpperCase() == 'KENNEDY NGURE';
          });
        }
      }
    } catch (e) {
      debugPrint('Admin check error: $e');

      if (mounted) {
        setState(() {
          _isSuperAdmin = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _checkingAdmin = false;
        });
      }
    }
  }

  // ==========================================================
  // BIOMETRIC (fingerprint / face) CHECK — runs on every login.
  //
  //  1. Admin has biometrics set up already -> show dashboard
  //     immediately (no prompt, nothing else happens).
  //  2. Not set up, device HAS fingerprint or face enrolled ->
  //     prompt pops up offering to set it up. Accepting opens
  //     FingerprintSetupPage; on return the profile is re-read
  //     and a confirmation is shown.
  //  3. Not set up, device has none (or this is web) -> just
  //     show the dashboard.
  // ==========================================================

  bool _isTrue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().trim().toLowerCase() == 'true';
  }

  /// FIX: True when the admin's profile says fingerprint/face is
  /// set up — EXPLICIT FLAGS ONLY.
  ///
  /// Previously this also returned true when
  /// `registrationStage == 'completed'`, which meant admins who
  /// had completed registration but NEVER set up biometrics
  /// (fingerprintEnabled: false) were treated as "already set
  /// up", so the setup prompt never appeared and the BIOMETRIC
  /// ON badge showed incorrectly.
  ///
  /// The field list is now aligned with login_page.dart's
  /// _biometricFlagKeys so both files check the same flags.
  bool _hasBiometricSetup(Map<String, dynamic> data) {
    const fields = [
      'fingerprintEnabled',
      'fingerprintAdded',
      'fingerprintSetup',
      'hasFingerprint',
      'biometricEnabled',
      'biometricsEnabled',
      'isBiometricEnabled',
      'isFingerprintEnabled',
      'biometric_enabled',
      'fingerprint_enabled',
    ];

    for (final field in fields) {
      if (_isTrue(data[field])) return true;
    }

    // NOTE: registrationStage == 'completed' is deliberately NOT
    // treated as "biometrics set up". Completing registration does
    // not guarantee the fingerprint step actually succeeded.
    return false;
  }

  /// True when the device itself has a fingerprint or face
  /// enrolled (and can therefore use biometrics).
  Future<bool> _deviceHasBiometrics() async {
    if (kIsWeb) return false;

    try {
      final auth = LocalAuthentication();

      if (!await auth.isDeviceSupported()) return false;

      // canCheckBiometrics: does the device have the hardware.
      final canCheck = await auth.canCheckBiometrics;
      if (!canCheck) return false;

      // availableBiometrics: has the user actually enrolled at
      // least one fingerprint / face?
      final available = await auth.getAvailableBiometrics();

      return available.isNotEmpty;
    } catch (e) {
      debugPrint('Biometric availability check failed: $e');
      return false;
    }
  }

  Future<void> _checkBiometricSetup() async {
    final data = _profile;

    // No profile / not an admin -> nothing to do.
    if (data == null || !mounted) return;

    final role = (data['role'] ?? '').toString().trim().toLowerCase();

    if (role != 'admin') return;

    // CASE 1: biometrics already set up -> show the dashboard,
    // no prompt at all.
    if (_hasBiometricSetup(data)) {
      debugPrint('ADMIN BIOMETRICS: already set up — showing dashboard.');
      return;
    }

    // CASE 3: device cannot use biometrics (or web) -> just show
    // the dashboard.
    if (!await _deviceHasBiometrics()) {
      debugPrint('ADMIN BIOMETRICS: device has no biometrics — skipping.');
      return;
    }

    if (!mounted) return;

    // CASE 2: not set up but the device supports it -> prompt.
    final setUpNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: Icon(Icons.fingerprint, size: 44, color: _green),
          title: Text(
            _tr('Secure your admin account', 'Linda akaunti yako ya usimamizi'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _greenDeep,
            ),
          ),
          content: Text(
            _tr(
              'Your device supports fingerprint or face unlock. Set it up now to protect access to the admin dashboard.',
              'Kifaa chako kinaauni alama ya kidole au uso. Iweke sasa ili kulinda ufikiaji wa dashibodi ya usimamizi.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_tr('Later', 'Baadaye')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_tr('Set up now', 'Weka sasa')),
            ),
          ],
        );
      },
    );

    if (setUpNow == true && mounted) {
      // Open the same setup page used during registration. If
      // it was opened from the registration flow it writes
      // 'fingerprintEnabled': true + advances the stage, which
      // _hasBiometricSetup above detects on the next login.
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const FingerprintSetupPage(isLoginFlow: true),
        ),
      );

      // NEW: re-read the profile so the dashboard reflects the
      // new biometric state immediately, and confirm to the user.
      await _checkAdmin();

      if (!mounted) return;

      final nowSetUp = _profile != null && _hasBiometricSetup(_profile!);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nowSetUp
                ? _tr(
              'Biometric unlock is now active for your admin account.',
              'Kufungua kwa alama ya kidole/uso kumewashwa kwa akaunti yako ya usimamizi.',
            )
                : _tr(
              'Biometric setup was not completed. You can set it up again on your next login.',
              'Usanidi wa alama ya kidole/uso haukukamilika. Unaweza kuweka tena kwenye kuingia ijayo.',
            ),
          ),
          backgroundColor: nowSetUp ? _green : Colors.red,
        ),
      );
    }
  }

  // ==========================================================
  // LOGOUT
  // ==========================================================

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() {
      _loggingOut = true;
    });

    try {
      // Sign out from Firebase Authentication.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Remove all previous pages from the navigation stack
      // and take the user to the homepage.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const HomePage(),
        ),
            (route) => false,
      );
    } catch (e) {
      debugPrint('Logout error: $e');

      if (!mounted) return;

      setState(() {
        _loggingOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_tr('Logout failed: ', 'Imeshindikana kutoka: ')}$e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==========================================================
  // LOGOUT CONFIRMATION
  // ==========================================================

  Future<void> _confirmLogout() async {
    if (_loggingOut) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            _tr('Logout', 'Toka'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _greenDeep,
            ),
          ),
          content: Text(
            _tr(
              'Are you sure you want to logout?',
              'Una uhakika unataka kutoka?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(_tr('Cancel', 'Ghairi')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(_tr('Logout', 'Toka')),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _logout();
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      // NEW: loading/splash state while the startup admin +
      // biometric checks run, so the dashboard does not flash
      // behind the biometric prompt.
      body: !_biometricCheckDone ? _buildStartupLoader() : _buildDashboard(),
    );
  }

  Widget _buildStartupLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.admin_panel_settings_rounded,
              size: 56, color: _green),
          const SizedBox(height: 18),
          CircularProgressIndicator(color: _green),
          const SizedBox(height: 14),
          Text(
            _tr(
              'Preparing your admin dashboard...',
              'Inaandaa dashibodi yako ya usimamizi...',
            ),
            style: TextStyle(color: _mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // ========================================================
          // HEADER
          // ========================================================

          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _green,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppSettings.appName.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _greetingName.isEmpty
                            ? _greeting()
                            : '${_greeting()}, $_greetingName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tr(
                          "Here's what's happening on your platform",
                          'Mambo yanayotokea kwenye jukwaa lako',
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // ==================================================
                // LOGOUT BUTTON
                // ==================================================

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _loggingOut
                      ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                  )
                      : IconButton(
                    tooltip: _tr('Logout', 'Toka'),
                    icon: const Icon(
                      Icons.power_settings_new,
                      color: Color(0xFFE0374A),
                      size: 24,
                    ),
                    onPressed: _confirmLogout,
                  ),
                ),
              ],
            ),
          ),

          // ========================================================
          // BODY
          // ========================================================

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('My Admin Details', 'Maelezo Yangu ya Usimamizi'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _greenDeep,
                  ),
                ),
                const SizedBox(height: 8),
                _buildAdminDetailsCard(),
                const SizedBox(height: 16),
                Text(
                  _tr('Administrative Actions', 'Vitendo vya Usimamizi'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _greenDeep,
                  ),
                ),
                const SizedBox(height: 8),
                _buildAdminActions(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ADMIN DETAILS CARD
  // ==========================================================

  Widget _buildAdminDetailsCard() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Card(
        color: _cardColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _tr('Not signed in', 'Hujasaini ndani'),
            style: TextStyle(color: _bodyText),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: _green),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;

        if (data == null) {
          return Card(
            color: _cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _tr(
                  'Admin profile not found',
                  'Profaili ya msimamizi haipatikani',
                ),
                style: TextStyle(color: _bodyText),
              ),
            ),
          );
        }

        final fullName =
        (data['fullName'] ?? data['name'] ?? data['displayName'] ?? 'Admin')
            .toString();

        final email = (data['email'] ?? user.email ?? '').toString();

        final phone = (data['phone'] ?? '').toString();

        final role = (data['role'] ?? 'admin').toString();

        final status = (data['status'] ?? '').toString();

        String dateRegistered = '';

        final createdAt = data['createdAt'];

        if (createdAt is Timestamp) {
          dateRegistered = DateFormat.yMMMd().format(createdAt.toDate());
        }

        return Material(
          color: _cardColor,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: _accentGreen.withValues(alpha: 0.12),
                      child: Text(
                        fullName.isNotEmpty ? fullName[0].toUpperCase() : 'A',
                        style: TextStyle(
                          color: _greenDeep,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _greenDeep,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _badge(role.toUpperCase(), _accentGreen),
                              if (status.isNotEmpty)
                                _badge(status.toUpperCase(), _accentBlue),
                              // NEW: biometric status badge.
                              if (_hasBiometricSetup(data))
                                _badge(
                                  _tr('BIOMETRIC ON', 'ALAMA YA KIDOLE ON'),
                                  _accentGreen,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Edit button
                    Material(
                      color: _accentBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _editAdminDetails(data),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.edit,
                            color: _accentBlue,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Divider(height: 22, color: _cardBorder),
                _detailRow(Icons.email_outlined, email),
                if (phone.isNotEmpty) _detailRow(Icons.phone_outlined, phone),
                if (dateRegistered.isNotEmpty)
                  _detailRow(
                    Icons.calendar_today_outlined,
                    _tr(
                      'Registered $dateRegistered',
                      'Alijiandikisha $dateRegistered',
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // BADGE
  // ==========================================================

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ==========================================================
  // DETAIL ROW
  // ==========================================================

  Widget _detailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: _bodyText),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EDIT ADMIN DETAILS
  // ==========================================================

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _green),
      filled: true,
      fillColor: _greenSurface,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _green, width: 2),
      ),
    );
  }

  Future<void> _editAdminDetails(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    // NOTE: these controllers are intentionally not disposed
    // manually. Disposing them right after the dialog closes can
    // throw "used after being disposed" while the dialog is still
    // animating out. They hold no listeners, so they are simply
    // garbage collected.
    final nameController = TextEditingController(
      text: (data['fullName'] ?? data['name'] ?? data['displayName'] ?? '')
          .toString(),
    );

    final phoneController = TextEditingController(
      text: (data['phone'] ?? '').toString(),
    );

    final emailController = TextEditingController(
      text: (data['email'] ?? user.email ?? '').toString(),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            _tr('Edit My Details', 'Hariri Maelezo Yangu'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _greenDeep,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  decoration: _fieldDecoration(_tr('Full Name', 'Jina Kamili')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: _fieldDecoration(_tr('Phone', 'Simu')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: _fieldDecoration(_tr('Email', 'Barua pepe')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(_tr('Cancel', 'Ghairi')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(_tr('Save', 'Hifadhi')),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    final newName = nameController.text.trim();
    final newPhone = phoneController.text.trim();
    final newEmail = emailController.text.trim();

    if (newName.isEmpty || newEmail.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Name and email cannot be empty.',
              'Jina na barua pepe haziwezi kuwa tupu.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );

      return;
    }

    try {
      // NOTE: only the Firestore profile record is updated. The
      // login email in Firebase Authentication is NOT changed here
      // (that needs verifyBeforeUpdateEmail and a verification step).
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'fullName': newName,
        'phone': newPhone,
        'email': newEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Details updated successfully.',
              'Maelezo yamesasishwa kwa mafanikio.',
            ),
          ),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_tr('Failed to update details: ', 'Imeshindikana kusasisha maelezo: ')}$e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==========================================================
  // ADMINISTRATIVE ACTIONS
  // ==========================================================

  Widget _buildAdminActions(BuildContext context) {
    return Column(
      children: [
        _actionCard(
          context,
          icon: Icons.verified_outlined,
          iconColor: _accentGreen,
          title: _tr('Verify Landlords', 'Thibitisha Wamiliki'),
          subtitle: _tr(
            'Approve pending landlord accounts',
            'Idhinisha akaunti za wamiliki zinazosubiri',
          ),
          page: const VerifyPropertyOwnersPage(),
        ),
        const SizedBox(height: 8),

        _actionCard(
          context,
          icon: Icons.flag_outlined,
          iconColor: _accentRed,
          title: _tr('Manage Reports', 'Simamia Ripoti'),
          subtitle: _tr(
            'Review and resolve reports from users',
            'Kagua na kutatua ripoti kutoka kwa watumiaji',
          ),
          page: ManageReportsPage(),
        ),
        const SizedBox(height: 8),

        _actionCard(
          context,
          icon: Icons.rate_review_outlined,
          iconColor: _accentBlue,
          title: _tr('Review Listings', 'Kagua Machapisho'),
          subtitle: _tr(
            'Check and manage hostel & home posts',
            'Angalia na kusimamia machapisho ya hosteli na nyumba',
          ),
          page: const ReviewPropertyListingsPage(),
        ),
        const SizedBox(height: 8),
        _actionCard(
          context,
          icon: Icons.help_outline,
          iconColor: _accentBlue,
          title: _tr('FAQs', 'Maswali ya Kawaida'),
          subtitle: _tr(
            'Manage help articles and requests',
            'Simamia makala za msaada na maombi',
          ),
          page: const FAQsPage(),
        ),
        const SizedBox(height: 8),
        _actionCard(
          context,
          icon: Icons.group_outlined,
          iconColor: _accentPurple,
          title: _tr('Roommate Posts', 'Machapisho ya Wenzi wa Chumba'),
          subtitle: _tr(
            'View posts from the roommate finder',
            'Angalia machapisho ya kitafuta wenzi wa chumba',
          ),
          page: const RoommatesPostsPage(),
        ),
        const SizedBox(height: 8),
        _actionCard(
          context,
          icon: Icons.description_outlined,
          iconColor: _accentBlue,
          title: _tr('Terms & Conditions', 'Sheria na Masharti'),
          subtitle: _tr(
            'Manage the app terms of service',
            'Simamia sheria za matumizi ya programu',
          ),
          page: const TermsPage(),
        ),
        const SizedBox(height: 8),
        _actionCard(
          context,
          icon: Icons.miscellaneous_services_outlined,
          iconColor: _accentGreen,
          title: _tr('Student Hub', 'Kituo cha wanafunzi'),
          subtitle: _tr(
            'Manage campus communities, Student marketplace, student services and '
                'property services',
            'Simamia jumuiya za kampus, soko la wanafunzi, huduma za wanafunzi na '
                'huduma za mali',
          ),
          page: const OtherAppServicesPage(),
        ),
        const SizedBox(height: 8),
        _actionCard(
          context,
          icon: Icons.privacy_tip_outlined,
          iconColor: _accentGreen,
          title: _tr('Privacy Policy', 'Sera ya Faragha'),
          subtitle: _tr(
            'Manage the app privacy policy',
            'Simamia sera ya faragha ya programu',
          ),
          page: const PrivacyPolicyPage(),
        ),
        _actionCard(
          context,
          icon: Icons.rate_review_outlined,
          iconColor: _accentGreen,
          title: _tr('Manage Reviews', 'Simamia Maoni'),
          subtitle: _tr(
            'View, hide or delete tenant reviews',
            'Tazama, ficha au futa maoni ya wapangaji',
          ),
          page: const ManageTenantReviewsPage(),
        ),

        // ========================================================
        // APP MANAGEMENT — super admin only
        // ========================================================

        if (!_checkingAdmin && _isSuperAdmin) ...[
          const SizedBox(height: 8),
          _actionCard(
            context,
            icon: Icons.settings,
            iconColor: _accentPurple,
            title: _tr('App Management', 'Usimamizi wa Programu'),
            subtitle: _tr(
              'Configure the platform settings',
              'Sanidi mipangilio ya jukwaa',
            ),
            page: const AppManagementPage(),
          ),
        ],
      ],
    );
  }

  // ==========================================================
  // ACTION CARD
  // ==========================================================

  Widget _actionCard(
      BuildContext context, {
        required IconData icon,
        required Color iconColor,
        required String title,
        required String subtitle,
        required Widget page,
      }) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => page),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _greenDeep,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: _mutedText),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _mutedText, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}