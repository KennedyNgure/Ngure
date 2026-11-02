// ============================================================
// property_owner_dashboard.dart  (FULL UPDATED FILE)
//
// CHANGE IN THIS VERSION
//  - The "Renew (+30 days) / Ongeza muda" button is REMOVED
//    from every listing row (both the wide and the compact
//    layout). View / Edit and Mark Available / Unavailable
//    remain.
//  - The now-unused _renewListing() action and the _renewalDays
//    constant were removed with it. The expiry line (e.g.
//    "Expires 12 Dec 2026 (30 days left)") is still shown on
//    each listing so owners keep seeing when a listing ends.
//
// Everything else is unchanged: greeting card with profile
// completion, Profile | Logout row, server-side statistics,
// paginated My Listings with search + filters, the biometric
// setup prompt, no back button, and the Add Property FAB.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'add_property_page.dart';
import 'app_settings.dart';
import 'fingerprint_setup_page.dart';
import 'homepage.dart';
import 'my_properties_page.dart';
import 'profile_page.dart';

/// Filters available in the My Listings card.
enum _ListingFilter { all, available, unavailable, verified, unverified }

/// Property owner dashboard, structured as cards:
///
///   0. (Only when it fails) Profile error banner with a Retry button.
///   1. Greeting card — "Good morning/afternoon/evening, <name>",
///      avatar, email, verification pill and PROFILE COMPLETION.
///   2. Buttons card — Profile | Logout in one row (Logout asks
///      for confirmation, then goes to the public HomePage).
///   3. Statistics card — total, available, unavailable, verified
///      and pending listings (server-side counts, so they are
///      correct even when only some listings are loaded).
///   4. My Listings card — search, filter chips, and the owner's
///      listings (paginated). Each listing shows its main photo,
///      expiry date, View/Edit and Mark Available/Unavailable.
///
/// Add Property is a single floating action button at the bottom
/// right of the page.
///
/// NO BACK BUTTON: the app-bar back arrow is removed AND the
/// system/phone back gesture is blocked on this page, so the
/// Logout button is the only way to leave the dashboard.
///
/// BIOMETRIC FLOW (same pattern as AdminDashboardPage, on every login):
///   1. Check the owner's Firestore profile — is biometric login
///      already set up (EXPLICIT FLAGS ONLY)? If YES -> show the
///      dashboard immediately (no prompt).
///   2. If NOT set up, check whether the device being used has a
///      fingerprint / face scan enrolled (and is not web).
///      If NO  -> just show the dashboard.
///   3. If the device CAN use biometrics -> prompt the user to set
///      it up. Accepting opens FingerprintSetupPage; on return
///      the profile is re-read and a confirmation is shown.
///
/// If the profile cannot be loaded, the biometric check is skipped
/// (we cannot tell whether it is set up) and a Retry banner is shown.
/// A successful retry runs the biometric check if it has not run yet.
class PropertyOwnerDashboard extends StatefulWidget {
  const PropertyOwnerDashboard({super.key});

  @override
  State<PropertyOwnerDashboard> createState() =>
      _PropertyOwnerDashboardState();
}

class _PropertyOwnerDashboardState extends State<PropertyOwnerDashboard> {
  // ----------------------------------------------------------
  // CONFIG
  // ----------------------------------------------------------

  /// How many listings are fetched per page.
  static const int _pageSize = 10;

  /// A listing is flagged "expiring soon" within this many days.
  static const int _expiringSoonDays = 7;

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Fields that make up a "complete" owner profile:
  /// (English label, Swahili label, Firestore keys to look at).
  /// A field counts as filled if ANY of its keys has a value.
  /// Adjust the keys to match what your ProfilePage saves.
  static const List<(String, String, List<String>)> _requiredProfileFields = [
    ('Full name', 'Jina kamili', ['name', 'fullName']),
    ('Email', 'Barua pepe', ['email']),
    ('Phone number', 'Namba ya simu', ['phone', 'phoneNumber', 'phone_number']),
    ('ID number', 'Namba ya kitambulisho',
    ['idNumber', 'nationalId', 'national_id']),
  ];

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Key used to scroll to the "My Listings" card.
  final GlobalKey _listingsCardKey = GlobalKey();

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Owner profile info for the greeting card.
  String _ownerName = '';
  String _verificationStatus = 'unverified';
  String _accountEmail = '';

  /// The signed-in owner's profile, read at start-up and used by
  /// the biometric check and the profile-completion indicator.
  Map<String, dynamic>? _profile;

  /// True when the last profile load failed.
  bool _profileError = false;

  /// True while a manual profile retry is running.
  bool _profileRetrying = false;

  /// True once the biometric check has run (or been decided).
  bool _biometricChecked = false;

  /// True once the startup check has finished. The dashboard is
  /// hidden behind a loading state until then, so it never flashes
  /// before the biometric prompt.
  bool _startupCheckDone = false;

  // ---------------- Listings (paginated) ----------------

  List<DocumentSnapshot<Map<String, dynamic>>> _listings = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _listingsLoading = false;
  String? _listingsError;

  /// Incremented on every refresh so results of an older, slower
  /// request can never overwrite newer data.
  int _listingsToken = 0;

  /// Listings with an action (availability) in progress.
  /// Only THESE listings' buttons are disabled.
  final Set<String> _busyIds = {};

  // ---------------- Search + filter ----------------

  String _searchQuery = '';
  _ListingFilter _filter = _ListingFilter.all;

  // ---------------- Statistics (server-side counts) ----------------

  int? _statTotal;
  int? _statAvailable;
  int? _statVerified;
  int? _statRejected;
  bool _statsError = false;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  // ----------------------------------------------------------
  // SETTINGS HELPERS (live from AppSettings)
  // ----------------------------------------------------------

  SettingsController get _settings => AppSettings.of(context);

  bool get _isDark => _settings.isDark;

  String _tr(String en, String sw) =>
      _settings.languageCode == 'sw' ? sw : en;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _scaffold =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _card => _isDark ? kDarkCard : Colors.white;

  Color get _cardBorder =>
      _isDark ? const Color(0xFF28352C) : const Color(0xFFE3ECE6);

  Color get _bodyText =>
      _isDark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);

  Color get _mutedText =>
      _isDark ? const Color(0xFFA9B8AF) : const Color(0xFF5B6B62);

  Color get _okColor =>
      _isDark ? Colors.green.shade300 : Colors.green.shade700;

  Color get _warnColor =>
      _isDark ? Colors.orange.shade300 : Colors.orange.shade800;

  Color get _errColor =>
      _isDark ? Colors.red.shade300 : Colors.red.shade700;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _fmtDate(DateTime d) =>
      '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  // ----------------------------------------------------------
  // GREETING HELPERS
  // ----------------------------------------------------------

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return _tr('Good morning', 'Habari za asubuhi');
    } else if (hour < 17) {
      return _tr('Good afternoon', 'Habari za mchana');
    } else {
      return _tr('Good evening', 'Habari za jioni');
    }
  }

  String _displayName() {
    final first = _ownerName.trim().split(' ').first;
    return first.isEmpty ? _tr('Owner', 'Mmiliki') : first;
  }

  (String, Color, IconData) _verificationInfo() {
    final status = _verificationStatus.toLowerCase();

    if (status == 'verified' ||
        status == 'approved' ||
        status == 'active') {
      return (_tr('Verified', 'Imethibitishwa'), _okColor, Icons.verified);
    }

    if (status == 'rejected') {
      return (_tr('Rejected', 'Imekataliwa'), _errColor, Icons.cancel);
    }

    return (
    _tr('Pending', 'Inasubiri'),
    _warnColor,
    Icons.hourglass_top_rounded
    );
  }

  // ----------------------------------------------------------
  // PROFILE COMPLETION
  // ----------------------------------------------------------

  bool _hasValue(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    return true;
  }

  /// Labels (already translated) of required profile fields that
  /// are still empty. Returns null when the profile is not loaded.
  List<String>? _missingProfileFields() {
    final data = _profile;
    if (data == null) return null;

    final missing = <String>[];

    for (final (en, sw, keys) in _requiredProfileFields) {
      var filled = keys.any((k) => _hasValue(data[k]));

      // The email can also come from the sign-in account.
      if (!filled && keys.contains('email')) {
        filled = _hasValue(_auth.currentUser?.email);
      }

      if (!filled) missing.add(_tr(en, sw));
    }

    return missing;
  }

  // ----------------------------------------------------------
  // INIT — load profile, then run the biometric check, then
  // show the dashboard.
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _startup();
  }

  Future<void> _startup() async {
    // 1. Load the owner profile (also used by the greeting card).
    final profileOk = await _loadOwnerProfile();

    // 2. Biometric check needs the profile to know whether
    //    biometrics were already set up. If the profile could not
    //    be loaded we cannot know, so we skip it (Retry runs it
    //    later) instead of wrongly prompting.
    if (profileOk) {
      await _checkBiometricSetup();
    }

    // 3. Everything done — reveal the dashboard.
    if (mounted) {
      setState(() => _startupCheckDone = true);
    }

    // 4. Load listings + statistics in parallel.
    if (mounted) {
      _loadListings(reset: true);
      _loadStats();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Returns true when the profile was read successfully.
  /// On failure sets [_profileError] so the dashboard can show a
  /// message and a Retry button.
  Future<bool> _loadOwnerProfile() async {
    if (_uid.isEmpty) return true;

    try {
      final doc = await _db.collection('users').doc(_uid).get();

      if (!mounted) return false;

      final data = doc.data() ?? <String, dynamic>{};

      setState(() {
        _profileError = false;
        _profile = data;
        _ownerName =
            data['name']?.toString() ?? data['fullName']?.toString() ?? '';
        _accountEmail =
            data['email']?.toString() ?? _auth.currentUser?.email ?? '';

        _verificationStatus = data['landlord_status']?.toString() ??
            data['ownerVerification']?.toString() ??
            'unverified';
      });

      return true;
    } catch (e) {
      debugPrint('DASHBOARD PROFILE LOAD ERROR: $e');

      if (mounted) {
        setState(() => _profileError = true);
      }

      return false;
    }
  }

  Future<void> _retryProfile() async {
    if (_profileRetrying) return;

    setState(() => _profileRetrying = true);

    final ok = await _loadOwnerProfile();

    // The biometric check was skipped at start-up because the
    // profile failed; run it now that we have the profile.
    if (ok && !_biometricChecked) {
      await _checkBiometricSetup();
    }

    if (mounted) {
      setState(() => _profileRetrying = false);
    }
  }

  // ----------------------------------------------------------
  // BIOMETRIC (fingerprint / face) CHECK — same pattern as
  // AdminDashboardPage, runs on every login.
  //
  //  1. Owner has biometrics set up already (EXPLICIT PROFILE
  //     FLAGS ONLY) -> show the dashboard immediately (no
  //     prompt, nothing else happens).
  //  2. Not set up, device HAS fingerprint or face enrolled ->
  //     prompt pops up offering to set it up. Accepting opens
  //     FingerprintSetupPage; on return the profile is re-read
  //     and a confirmation is shown.
  //  3. Not set up, device has none (or this is web) -> just
  //     show the dashboard.
  // ----------------------------------------------------------

  bool _isTrue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().trim().toLowerCase() == 'true';
  }

  /// True when the owner's profile says fingerprint/face is set
  /// up — EXPLICIT FLAGS ONLY.
  ///
  /// The field list is aligned with login_page.dart's
  /// _biometricFlagKeys and AdminDashboardPage's _hasBiometricSetup
  /// so all files check the same flags.
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
  /// enrolled (and can therefore use biometrics). Web never has.
  Future<bool> _deviceHasBiometrics() async {
    if (kIsWeb) return false;

    try {
      if (!await _localAuth.isDeviceSupported()) return false;

      // canCheckBiometrics: does the device have the hardware.
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      // availableBiometrics: has the user actually enrolled at
      // least one fingerprint / face?
      final available = await _localAuth.getAvailableBiometrics();

      return available.isNotEmpty;
    } catch (e) {
      debugPrint('Biometric availability check failed: $e');
      return false;
    }
  }

  Future<void> _checkBiometricSetup() async {
    if (_uid.isEmpty || !mounted) return;

    _biometricChecked = true;

    final data = _profile;

    // CASE 1: biometrics already set up -> show the dashboard,
    // no prompt at all.
    if (data != null && _hasBiometricSetup(data)) {
      debugPrint('OWNER BIOMETRICS: already set up — showing dashboard.');
      return;
    }

    // CASE 3: device cannot use biometrics (or web) -> just
    // show the dashboard.
    if (!await _deviceHasBiometrics()) {
      debugPrint('OWNER BIOMETRICS: device has no biometrics — skipping.');
      return;
    }

    if (!mounted) return;

    // CASE 2: not set up but the device supports it -> prompt.
    final setUpNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final bool dark = AppSettings.of(dialogContext).isDark;
        final sw = AppSettings.of(dialogContext).languageCode == 'sw';
        final Color brand = dark ? kBrandGreenOnDark : kBrandGreen;
        final Color text =
        dark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);
        final Color muted =
        dark ? const Color(0xFFA9B8AF) : const Color(0xFF5B6B62);

        return AlertDialog(
          backgroundColor: dark ? kDarkCard : Colors.white,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: Icon(Icons.fingerprint, color: brand, size: 44),
          title: Text(
            sw
                ? 'Weka kuingia kwa alama ya kidole'
                : 'Set up fingerprint login',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: text,
            ),
          ),
          content: Text(
            sw
                ? 'Kifaa chako kina alama ya kidole au uso. Weka sasa ili uingie kwa haraka na usalama mara ijayo. Taarifa zako za kibayometriki hubaki kwenye kifaa chako pekee.'
                : 'Your device has a fingerprint or face scan set up. Set it up now to log in faster and more securely next time. Your biometric information stays on your device only.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                sw ? 'Sasa si' : 'Not now',
                style: TextStyle(color: muted),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: brand,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.fingerprint, size: 20),
              label: Text(sw ? 'Weka sasa' : 'Set up now'),
            ),
          ],
        );
      },
    );

    if (setUpNow != true || !mounted) return;

    // Open the same setup page used during registration. It
    // writes 'fingerprintEnabled': true + advances the stage,
    // which _hasBiometricSetup above detects on the next login.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FingerprintSetupPage(isLoginFlow: true),
      ),
    );

    // Re-read the profile so the dashboard reflects the new
    // biometric state immediately, and confirm to the user.
    await _loadOwnerProfile();

    if (!mounted) return;

    final nowSetUp = _profile != null && _hasBiometricSetup(_profile!);

    _showSnack(
      nowSetUp
          ? _tr(
        'Fingerprint / face login is now active for your account.',
        'Kuingia kwa alama ya kidole / uso kumewashwa kwa akaunti yako.',
      )
          : _tr(
        'Biometric setup was not completed. You can set it up again on your next login.',
        'Usanidi wa alama ya kidole/uso haukukamilika. Unaweza kuweka tena kwenye kuingia ijayo.',
      ),
    );
  }

  // ----------------------------------------------------------
  // LISTINGS — paginated loading
  // ----------------------------------------------------------

  /// Base query: every property of the signed-in owner, ordered by
  /// document id. Ordering by document id needs no composite index
  /// and gives a stable order for pagination.
  Query<Map<String, dynamic>> get _ownerQuery => _db
      .collection(AppSettings.propertiesCollection)
      .where('ownerId', isEqualTo: _uid);

  /// Loads one page of listings.
  ///  * reset: true  -> start over from the first page (refresh).
  ///  * reset: false -> load the next page ("Load more").
  Future<void> _loadListings({bool reset = false}) async {
    if (_uid.isEmpty) return;

    if (!reset && (_listingsLoading || !_hasMore)) return;

    final token = reset ? ++_listingsToken : _listingsToken;

    setState(() {
      _listingsLoading = true;
      if (reset) _listingsError = null;
    });

    try {
      var query = _ownerQuery.orderBy(FieldPath.documentId).limit(_pageSize);

      if (!reset && _lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snap = await query.get();

      // A newer refresh started while this one was running.
      if (!mounted || token != _listingsToken) return;

      setState(() {
        if (reset) {
          _listings =
          List<DocumentSnapshot<Map<String, dynamic>>>.of(snap.docs);
          _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
        } else {
          _listings.addAll(snap.docs);
          if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
        }
        _hasMore = snap.docs.length == _pageSize;
        _listingsError = null;
      });
    } catch (e) {
      debugPrint('DASHBOARD LISTINGS LOAD ERROR: $e');

      if (mounted && token == _listingsToken) {
        setState(() => _listingsError = e.toString());
      }
    } finally {
      if (mounted && token == _listingsToken) {
        setState(() => _listingsLoading = false);
      }
    }
  }

  /// Re-reads one listing and swaps it into the loaded list, so a
  /// single change does not require reloading every page.
  Future<void> _refreshListing(String id) async {
    try {
      final fresh = await _db
          .collection(AppSettings.propertiesCollection)
          .doc(id)
          .get();

      if (!mounted) return;

      final index = _listings.indexWhere((d) => d.id == id);
      if (index == -1) return;

      setState(() {
        if (fresh.exists) {
          _listings[index] = fresh;
        } else {
          _listings.removeAt(index);
        }
      });
    } catch (e) {
      debugPrint('DASHBOARD LISTING REFRESH ERROR: $e');
    }
  }

  /// Reloads everything (pull-to-refresh and after returning from
  /// Add Property / View-Edit / Profile).
  Future<void> _refreshAll() async {
    await Future.wait([
      _loadListings(reset: true),
      _loadStats(),
      if (_profileError) _loadOwnerProfile(),
    ]);
  }

  // ----------------------------------------------------------
  // STATISTICS — server-side counts (cheap, not affected by
  // pagination)
  // ----------------------------------------------------------

  Future<int> _count(Query<Object?> query) async {
    final snap = await query.count().get();
    return snap.count ?? 0;
  }

  Future<void> _loadStats() async {
    if (_uid.isEmpty) return;

    try {
      final base = _ownerQuery;

      final results = await Future.wait([
        _count(base),
        _count(base.where('availability', isEqualTo: 'available')),
        _count(base.where('property_status', isEqualTo: 'verified')),
        _count(base.where('property_status', isEqualTo: 'rejected')),
      ]);

      if (!mounted) return;

      setState(() {
        _statTotal = results[0];
        _statAvailable = results[1];
        _statVerified = results[2];
        _statRejected = results[3];
        _statsError = false;
      });
    } catch (e) {
      debugPrint('DASHBOARD STATS ERROR: $e');
      if (mounted) setState(() => _statsError = true);
    }
  }

  int? get _statUnavailable => (_statTotal == null || _statAvailable == null)
      ? null
      : (_statTotal! - _statAvailable!).clamp(0, _statTotal!);

  /// Pending = not verified and not rejected.
  int? get _statPending {
    if (_statTotal == null ||
        _statVerified == null ||
        _statRejected == null) {
      return null;
    }
    return (_statTotal! - _statVerified! - _statRejected!)
        .clamp(0, _statTotal!);
  }

  // ----------------------------------------------------------
  // SEARCH + FILTER (applied to the loaded listings)
  // ----------------------------------------------------------

  String _propertyTypeOf(Map<String, dynamic> data) =>
      (data['propertyType'] ??
          data['property_type'] ??
          data['type'] ??
          data['category'] ??
          '')
          .toString();

  bool _matchesFilter(Map<String, dynamic> data) {
    final isAvailable = data['availability'] == 'available';
    final status = (data['property_status']?.toString() ?? 'unverified')
        .toLowerCase();

    switch (_filter) {
      case _ListingFilter.all:
        return true;
      case _ListingFilter.available:
        return isAvailable;
      case _ListingFilter.unavailable:
        return !isAvailable;
      case _ListingFilter.verified:
        return status == 'verified';
      case _ListingFilter.unverified:
        return status != 'verified' && status != 'rejected';
    }
  }

  bool _matchesSearch(Map<String, dynamic> data) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;

    final title = (data['title']?.toString() ?? '').toLowerCase();
    final location = (data['location']?.toString() ?? '').toLowerCase();
    final type = _propertyTypeOf(data).toLowerCase();

    return title.contains(q) || location.contains(q) || type.contains(q);
  }

  List<DocumentSnapshot<Map<String, dynamic>>> get _visibleListings {
    return _listings.where((d) {
      final data = d.data() ?? <String, dynamic>{};
      return _matchesFilter(data) && _matchesSearch(data);
    }).toList();
  }

  bool get _filtersActive =>
      _filter != _ListingFilter.all || _searchQuery.trim().isNotEmpty;

  String _filterLabel(_ListingFilter f) {
    switch (f) {
      case _ListingFilter.all:
        return _tr('All', 'Zote');
      case _ListingFilter.available:
        return _tr('Available', 'Zinapatikana');
      case _ListingFilter.unavailable:
        return _tr('Unavailable', 'Hazipatikani');
      case _ListingFilter.verified:
        return _tr('Verified', 'Zimethibitishwa');
      case _ListingFilter.unverified:
        return _tr('Unverified', 'Hazijathibitishwa');
    }
  }

  // ----------------------------------------------------------
  // LISTING DATA HELPERS (image + expiry)
  // ----------------------------------------------------------

  /// Finds the main photo URL. Looks at several common field
  /// names — adjust to whatever AddPropertyPage saves.
  String? _mainImageUrl(Map<String, dynamic> data) {
    String? asUrl(dynamic v) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map) {
        final u = v['url'] ?? v['downloadUrl'];
        if (u is String && u.trim().isNotEmpty) return u.trim();
      }
      return null;
    }

    for (final key in const [
      'mainImage',
      'main_image',
      'mainPhoto',
      'coverImage',
      'imageUrl',
      'image',
      'thumbnail',
    ]) {
      final url = asUrl(data[key]);
      if (url != null) return url;
    }

    for (final key in const [
      'images',
      'imageUrls',
      'photos',
      'photoUrls',
    ]) {
      final value = data[key];
      if (value is List && value.isNotEmpty) {
        final url = asUrl(value.first);
        if (url != null) return url;
      }
    }

    return null;
  }

  DateTime? _expiryOf(Map<String, dynamic> data) {
    final v = data['expiresAt'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  (String, Color, IconData) _expiryInfo(DateTime? expiry) {
    if (expiry == null) {
      return (
      _tr('No expiry date set', 'Hakuna tarehe ya kuisha'),
      _mutedText,
      Icons.event_outlined
      );
    }

    final now = DateTime.now();

    if (expiry.isBefore(now)) {
      return (
      _tr('Expired on ${_fmtDate(expiry)}',
          'Iliisha tarehe ${_fmtDate(expiry)}'),
      _errColor,
      Icons.event_busy_outlined
      );
    }

    final days = expiry.difference(now).inDays;
    final color = days <= _expiringSoonDays ? _warnColor : _okColor;

    return (
    _tr('Expires ${_fmtDate(expiry)} ($days days left)',
        'Inaisha ${_fmtDate(expiry)} (siku $days zimebaki)'),
    color,
    Icons.event_available_outlined
    );
  }

  // ----------------------------------------------------------
  // NAVIGATION
  // ----------------------------------------------------------

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );

    // The owner may have filled in missing details.
    if (mounted) await _loadOwnerProfile();
  }

  Future<void> _openAddProperty() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddPropertyPage()),
    );

    // Show the new listing and update the statistics.
    if (mounted) await _refreshAll();
  }

  Future<void> _openListing(String propertyId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyPropertiesPage(propertyId: propertyId),
      ),
    );

    // The listing may have been edited or deleted there.
    if (mounted) await _refreshAll();
  }

  /// Scrolls to the My Listings card.
  void _scrollToListings() {
    final context = _listingsCardKey.currentContext;

    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  // ----------------------------------------------------------
  // LOGOUT (confirmation -> sign out -> HomePage)
  // ----------------------------------------------------------

  Future<void> _confirmLogout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final bool dark = AppSettings.of(dialogContext).isDark;
        final sw = AppSettings.of(dialogContext).languageCode == 'sw';
        final Color brand = dark ? kBrandGreenOnDark : kBrandGreen;
        final Color text =
        dark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);
        final Color muted =
        dark ? const Color(0xFFA9B8AF) : const Color(0xFF5B6B62);

        return AlertDialog(
          backgroundColor: dark ? kDarkCard : Colors.white,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: Icon(Icons.logout, color: brand, size: 34),
          title: Text(
            sw
                ? 'Una uhakika unataka kutoka nje ya akaunti?'
                : 'Are you sure you want to logout?',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: text,
            ),
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                sw ? 'Ghairi' : 'Cancel',
                style: TextStyle(color: muted),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: brand,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(sw ? 'Toka' : 'Logout'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _logout();
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('LOGOUT ERROR: $e');
    }

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
    );
  }

  // ----------------------------------------------------------
  // LISTING ACTIONS (availability)
  //
  // Each action marks ONLY its own listing as busy, so other
  // listings' buttons stay usable.
  // ----------------------------------------------------------

  Future<void> _toggleAvailability(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (_busyIds.contains(doc.id)) return;

    final data = doc.data() ?? <String, dynamic>{};
    final isAvailable = data['availability'] == 'available';
    final title =
        data['title']?.toString() ?? _tr('This listing', 'Orodha hii');

    setState(() => _busyIds.add(doc.id));

    try {
      await doc.reference.update({
        'availability': isAvailable ? 'unavailable' : 'available',
        'availabilityUpdatedAt': FieldValue.serverTimestamp(),
      });

      await _refreshListing(doc.id);
      _loadStats();

      if (mounted) {
        _showSnack(
          isAvailable
              ? _tr('"$title" marked as unavailable.',
              '"$title" imeandikwa haipatikani.')
              : _tr('"$title" marked as available.',
              '"$title" imeandikwa inapatikana.'),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          '${_tr('Failed to update availability: ', 'Imeshindikana kusasisha upatikanaji: ')}$e',
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(doc.id));
    }
  }

  // ----------------------------------------------------------
  // PROFILE ERROR BANNER
  // ----------------------------------------------------------

  Widget _profileErrorBanner() {
    return Card(
      elevation: 0,
      color: _errColor.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _errColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: _errColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _tr(
                  'We could not load your profile. Some details on this page may be missing.',
                  'Hatukuweza kupakia wasifu wako. Baadhi ya taarifa kwenye ukurasa huu zinaweza kukosekana.',
                ),
                style: TextStyle(color: _bodyText, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            _profileRetrying
                ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _errColor,
              ),
            )
                : TextButton.icon(
              onPressed: _retryProfile,
              icon: Icon(Icons.refresh, size: 18, color: _errColor),
              label: Text(
                _tr('Retry', 'Jaribu tena'),
                style: TextStyle(
                  color: _errColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // CARD 1 — GREETING (+ profile completion)
  // ----------------------------------------------------------

  Widget _profileCompletion() {
    final missing = _missingProfileFields();
    if (missing == null) return const SizedBox.shrink();

    final total = _requiredProfileFields.length;
    final done = total - missing.length;
    final progress = total == 0 ? 1.0 : done / total;
    final complete = missing.isEmpty;
    final color = complete ? _okColor : _warnColor;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  complete
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    complete
                        ? _tr('Profile complete', 'Wasifu umekamilika')
                        : _tr('Profile ${(progress * 100).round()}% complete',
                        'Wasifu umekamilika ${(progress * 100).round()}%'),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                color: color,
                backgroundColor: color.withValues(alpha: 0.18),
              ),
            ),
            if (!complete) ...[
              const SizedBox(height: 8),
              Text(
                '${_tr('Missing', 'Vinavyokosekana')}: ${missing.join(', ')}',
                style: TextStyle(fontSize: 12, color: _mutedText),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _brand,
                  ),
                  onPressed: _openProfile,
                  child: Text(
                    _tr('Complete your profile', 'Kamilisha wasifu wako'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _greetingCard() {
    final (verifyLabel, verifyColor, verifyIcon) = _verificationInfo();

    final initial = _ownerName.trim().isNotEmpty
        ? _ownerName.trim()[0].toUpperCase()
        : '?';

    return Card(
      elevation: 1.5,
      color: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _brand,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 22,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()}, ${_displayName()}!',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: _bodyText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_accountEmail.isNotEmpty)
                        Text(
                          _accountEmail,
                          style: TextStyle(fontSize: 12, color: _mutedText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Verification status pill.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: verifyColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(verifyIcon, size: 15, color: verifyColor),
                  const SizedBox(width: 5),
                  Text(
                    '${_tr('Account', 'Akaunti')}: $verifyLabel',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: verifyColor,
                    ),
                  ),
                ],
              ),
            ),

            // Profile completion indicator.
            _profileCompletion(),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // CARD 2 — PROFILE | LOGOUT (ONE ROW)
  // ----------------------------------------------------------

  Widget _buttonsCard() {
    return Card(
      elevation: 1.5,
      color: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // ---------------- PROFILE ----------------
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: BorderSide(color: _brand),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _openProfile,
                icon: const Icon(Icons.person_outline, size: 19),
                label: Text(
                  _tr('Profile', 'Wasifu'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // ---------------- LOGOUT ------------------
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _errColor,
                  side: BorderSide(color: _errColor),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout, size: 19),
                label: Text(
                  _tr('Logout', 'Toka'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // CARD 3 — STATISTICS
  // ----------------------------------------------------------

  Widget _statTile({
    required String label,
    required int? value,
    required Color color,
    required IconData icon,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              value?.toString() ?? '–',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: _mutedText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsCard() {
    return Card(
      elevation: 1.5,
      color: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.insights_outlined,
                      color: _brand, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tr('Overview', 'Muhtasari'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _brand,
                    ),
                  ),
                ),
                if (_statsError)
                  TextButton.icon(
                    onPressed: _loadStats,
                    icon: Icon(Icons.refresh, size: 16, color: _errColor),
                    label: Text(
                      _tr('Retry', 'Jaribu tena'),
                      style: TextStyle(color: _errColor, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                final tileWidth = (constraints.maxWidth - gap * 2) / 3;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    _statTile(
                      label: _tr('Total', 'Jumla'),
                      value: _statTotal,
                      color: _brand,
                      icon: Icons.home_work_outlined,
                      width: tileWidth,
                    ),
                    _statTile(
                      label: _tr('Available', 'Zinapatikana'),
                      value: _statAvailable,
                      color: _okColor,
                      icon: Icons.event_available_outlined,
                      width: tileWidth,
                    ),
                    _statTile(
                      label: _tr('Unavailable', 'Hazipatikani'),
                      value: _statUnavailable,
                      color: _mutedText,
                      icon: Icons.event_busy_outlined,
                      width: tileWidth,
                    ),
                    _statTile(
                      label: _tr('Verified', 'Zimethibitishwa'),
                      value: _statVerified,
                      color: _okColor,
                      icon: Icons.verified_outlined,
                      width: tileWidth,
                    ),
                    _statTile(
                      label: _tr('Pending', 'Zinasubiri'),
                      value: _statPending,
                      color: _warnColor,
                      icon: Icons.hourglass_top_rounded,
                      width: tileWidth,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // CARD 4 — MY LISTINGS (search + filters + list + pagination)
  // ----------------------------------------------------------

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      style: TextStyle(color: _bodyText),
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        isDense: true,
        hintText: _tr(
          'Search by title, location or type',
          'Tafuta kwa jina, mahali au aina',
        ),
        hintStyle: TextStyle(color: _mutedText, fontSize: 13),
        prefixIcon: Icon(Icons.search, color: _mutedText),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
          icon: Icon(Icons.close, color: _mutedText, size: 20),
          onPressed: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _brand, width: 1.5),
        ),
      ),
    );
  }

  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _ListingFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_filterLabel(f)),
                selected: _filter == f,
                showCheckmark: false,
                selectedColor: _brand,
                backgroundColor: _card,
                side: BorderSide(
                  color: _filter == f ? _brand : _cardBorder,
                ),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _filter == f ? Colors.white : _bodyText,
                ),
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  Widget _listingsBody(
      List<DocumentSnapshot<Map<String, dynamic>>> visible) {
    // Very first load.
    if (_listings.isEmpty && _listingsLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(color: _brand)),
      );
    }

    // Load failed and nothing to show.
    if (_listings.isEmpty && _listingsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 40, color: _errColor),
            const SizedBox(height: 8),
            Text(
              '${_tr('Could not load your listings.', 'Imeshindikana kupakia orodha zako.')}\n$_listingsError',
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedText, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _loadListings(reset: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_tr('Retry', 'Jaribu tena')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: BorderSide(color: _brand),
              ),
            ),
          ],
        ),
      );
    }

    // Owner has no listings at all.
    if (_listings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.add_home_work_outlined,
                  size: 44, color: _mutedText),
              const SizedBox(height: 10),
              Text(
                _tr(
                  'You have no listings yet. Tap "Add Property" to list your first property.',
                  'Hakuna orodha zako bado. Gusa "Ongeza Mali" kuweka mali yako ya kwanza.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: _mutedText, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 40, color: _mutedText),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      'No listings match your search or filter.',
                      'Hakuna orodha zinazolingana na utafutaji au kichujio chako.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _mutedText, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _filter = _ListingFilter.all;
                      });
                    },
                    child: Text(
                      _tr('Clear search and filter',
                          'Futa utafutaji na kichujio'),
                      style: TextStyle(color: _brand),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (var i = 0; i < visible.length; i++) ...[
            _listingRow(visible[i]),
            if (i != visible.length - 1)
              Divider(height: 1, color: _cardBorder),
          ],

        // Pagination footer.
        if (_listingsError != null && _listings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _tr('Could not load more listings.',
                  'Imeshindikana kupakia orodha zaidi.'),
              style: TextStyle(color: _errColor, fontSize: 12.5),
            ),
          ),

        if (_hasMore) ...[
          const SizedBox(height: 12),
          if (_filtersActive)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _tr(
                  'Search and filters apply to the listings loaded so far. Load more to include older listings.',
                  'Utafutaji na vichujio hutumika kwa orodha zilizopakiwa tu. Pakia zaidi ili kujumuisha orodha nyingine.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: _mutedText, fontSize: 11.5),
              ),
            ),
          _listingsLoading
              ? Center(child: CircularProgressIndicator(color: _brand))
              : SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _loadListings(),
              icon: const Icon(Icons.expand_more, size: 20),
              label: Text(_tr('Load more', 'Pakia zaidi')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: BorderSide(color: _brand),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _listingsCard() {
    final visible = _visibleListings;

    return Card(
      key: _listingsCardKey,
      elevation: 1.5,
      color: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -------------- CARD TITLE --------------
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.home_work_outlined,
                      color: _brand, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tr('My Listings', 'Orodha Zangu'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _brand,
                    ),
                  ),
                ),
                if (_listings.isNotEmpty)
                  Text(
                    '${visible.length} ${_tr('shown', 'zinaonyeshwa')}',
                    style: TextStyle(fontSize: 12, color: _mutedText),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // -------------- SEARCH + FILTERS --------------
            _searchField(),
            const SizedBox(height: 10),
            _filterChips(),

            const SizedBox(height: 12),
            Divider(height: 1, color: _cardBorder),
            const SizedBox(height: 4),

            // -------------- LISTINGS --------------
            _listingsBody(visible),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // LISTING ROW (inside the My Listings card)
  // ----------------------------------------------------------

  Widget _thumbnail(String? url) {
    const double size = 84;

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.home_work_outlined, color: _mutedText, size: 30),
    );

    if (url == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: size,
            height: size,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _brand,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _listingRow(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final title = data['title']?.toString() ??
        _tr('Untitled listing', 'Orodha Bili Jina');
    final location = data['location']?.toString() ?? '';
    final type = _propertyTypeOf(data);
    final propertyStatus = data['property_status']?.toString() ?? 'unverified';
    final isAvailable = data['availability'] == 'available';
    final imageUrl = _mainImageUrl(data);
    final expiry = _expiryOf(data);
    final (expiryLabel, expiryColor, expiryIcon) = _expiryInfo(expiry);

    // Only THIS listing's buttons are disabled while it updates.
    final busy = _busyIds.contains(doc.id);

    final statusColor = propertyStatus == 'verified'
        ? _okColor
        : (propertyStatus == 'rejected' ? _errColor : _warnColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- photo + title / location / type ----------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumbnail(imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _bodyText,
                      ),
                    ),
                    if (location.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 14, color: _mutedText),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: _mutedText),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (type.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.apartment_outlined,
                                size: 14, color: _mutedText),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                type,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: _mutedText),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ---------- status pills ----------
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_tr('Verification', 'Uthibitisho')}: $propertyStatus',
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (isAvailable ? _okColor : _mutedText)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAvailable
                      ? _tr('Available', 'Inapatikana')
                      : _tr('Unavailable', 'Haipatikani'),
                  style: TextStyle(
                    color: isAvailable ? _okColor : _mutedText,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ---------- expiry ----------
          Row(
            children: [
              Icon(expiryIcon, size: 15, color: expiryColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  expiryLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: expiryColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ---------- actions ----------
          // NOTE: the "Renew (+30 days) / Ongeza muda" button was
          // REMOVED — each listing now has View / Edit and
          // Mark Available / Unavailable only.
          LayoutBuilder(
            builder: (context, constraints) {
              // View / Edit — opens the owner's full property
              // detail page (photos, analytics, edit, download,
              // delete).
              final viewEditButton = OutlinedButton.icon(
                onPressed: () => _openListing(doc.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: BorderSide(color: _brand),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(_tr('View / Edit', 'Angalia / Hariri')),
              );

              final toggleButton = FilledButton.icon(
                onPressed: busy ? null : () => _toggleAvailability(doc),
                style: FilledButton.styleFrom(
                  backgroundColor: isAvailable ? _warnColor : _brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: busy
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : Icon(
                  isAvailable
                      ? Icons.event_busy_outlined
                      : Icons.event_available_outlined,
                  size: 18,
                ),
                label: Text(
                  isAvailable
                      ? _tr('Mark as Unavailable', 'Andika Haipatikani')
                      : _tr('Mark as Available', 'Andika Inapatikana'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );

              if (constraints.maxWidth > 520) {
                return Row(
                  children: [
                    Expanded(child: viewEditButton),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: toggleButton),
                  ],
                );
              }

              return Column(
                children: [
                  SizedBox(width: double.infinity, child: viewEditButton),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: toggleButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // BUILD
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // PopScope(canPop: false) blocks the phone's back button /
    // back gesture, so Logout is the only way out of this page.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _scaffold,
        appBar: AppBar(
          // BACK BUTTON REMOVED — no arrow in the app bar.
          automaticallyImplyLeading: false,
          title: Text(_tr('Owner Dashboard', 'Dashibodi ya Mmiliki')),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
        ),
        // Loading state while the startup profile + biometric
        // checks run, so the dashboard does not flash behind the
        // biometric prompt.
        body: !_startupCheckDone
            ? _buildStartupLoader()
            : _buildDashboardBody(),
        // ADD PROPERTY — the single Add Property entry point,
        // at the bottom right of the page.
        floatingActionButton: _startupCheckDone
            ? FloatingActionButton.extended(
          onPressed: _openAddProperty,
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_home_work_outlined),
          label: Text(_tr('Add Property', 'Ongeza Mali')),
        )
            : null,
      ),
    );
  }

  Widget _buildStartupLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.home_work_outlined, size: 56, color: _brand),
          const SizedBox(height: 18),
          CircularProgressIndicator(color: _brand),
          const SizedBox(height: 14),
          Text(
            _tr(
              'Preparing your dashboard...',
              'Inaandaa dashibodi yako...',
            ),
            style: TextStyle(color: _mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBody() {
    if (_uid.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _tr('You are signed out.', 'Umetoka nje ya akaunti.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedText),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _brand,
      onRefresh: _refreshAll,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile error + Retry (only when the load failed).
            if (_profileError) ...[
              _profileErrorBanner(),
              const SizedBox(height: 14),
            ],

            // CARD 1 — greeting + profile completion.
            _greetingCard(),

            const SizedBox(height: 14),

            // CARD 2 — Profile | Logout in one row.
            _buttonsCard(),

            const SizedBox(height: 14),

            // CARD 3 — statistics.
            _statsCard(),

            const SizedBox(height: 14),

            // CARD 4 — My Listings.
            _listingsCard(),

            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}