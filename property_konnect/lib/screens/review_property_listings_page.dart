// ============================================================
// review_property_listings_page.dart  (FULL UPDATED FILE)
//
// NEW / CHANGED in this version
//  1. SEARCH — now covers title, name, location, town, county,
//     price, type, propertyType, purpose, rent cycle
//     (rentCycle / priceCycle / paymentCycle), owner ID and
//     listing ID, so the search hint is finally honest.
//  2. VERIFICATION — a confirmation prompt appears before
//     Verify / Unverify (and Remove already had one), reducing
//     accidental changes.
//  3. OWNER VERIFICATION DECOUPLED — approving or unverifying a
//     single listing NO LONGER touches the owner's
//     `landlord_status`. An owner with five verified listings
//     keeps their landlord status even if one listing is
//     unverified. Owner-level verification lives on the
//     Verify Property Owners page only.
//  4. DEACTIVATED TAB — each deactivated card now shows the
//     DATE and the REASON of deactivation (read from
//     deactivatedAt / deactivationReason / reason), so admins
//     understand why a listing is unavailable.
//  5. CSV EXPORT — now includes Listing ID, Owner ID, Purpose,
//     Status, Deactivated At and Deactivation Reason, producing
//     a far more useful administrative report.
//  6. PERFORMANCE — pagination. The stream fetches 20 documents
//     at a time; a "Load more" button at the bottom of each tab
//     fetches the next 20. (Once the collection grows further,
//     switch to startAfterDocument queries or a Cloud Function
//     backend; see notes at the bottom.)
//  7. AUTHORIZATION — the page checks that the signed-in user
//     is an admin before rendering any actions (client-side
//     convenience check). Firestore Security Rules remain the
//     real enforcement: `properties` writes are admin-only,
//     so even a modified client cannot verify, unverify or
//     delete listings.
//  8. DELETION — removing a listing now, best-effort, deletes
//     its images from Firebase Storage, writes an audit entry
//     to the shared `admin_audit_logs` collection, and only
//     then deletes the document. Full cleanup of subcollections
//     and cross-collection references still belongs in a
//     server-side Cloud Function (recommended at the bottom of
//     this file).
//  9. ERROR STATE — the Firestore stream checks hasError and
//     shows a dedicated error screen with a RETRY button
//     instead of an endless spinner.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'data.dart';
import 'download_helper.dart';
import 'property_details_page.dart';

class ReviewPropertyListingsPage extends StatefulWidget {
  const ReviewPropertyListingsPage({super.key});

  @override
  State<ReviewPropertyListingsPage> createState() =>
      _ReviewPropertyListingsPageState();
}

class _ReviewPropertyListingsPageState extends State<ReviewPropertyListingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  // PAGINATION — fetch in pages of 20; "Load more" grows the
  // limit. (Keeping a live stream + full client filtering is
  // only sensible while the collection is small.)
  static const int _pageSize = 20;
  int _limit = _pageSize;

  // ERROR RETRY — bumping this rebuilds the stream.
  int _retryKey = 0;

  // ADMIN GUARD — checked once on open.
  late Future<Map<String, dynamic>?> _adminCheck;

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

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _pageBackground =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _saleColor =>
      _isDark ? Colors.orange.shade300 : Colors.orange.shade800;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  // ------------------------------------------------------------
  // ADMIN GUARD
  //
  // Convenience check only: the user's `users` doc must say
  // admin (role == 'admin' or isAdmin == true). If the doc is
  // missing or the read fails we still render the page — the
  // FIRESTORE SECURITY RULES are the real enforcement and will
  // reject any non-admin write no matter what the client does.
  // ------------------------------------------------------------

  Future<Map<String, dynamic>?> _fetchAdminUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return null;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      return snap.data();
    } catch (_) {
      // Network hiccup etc. — fall through; rules still guard.
      return null;
    }
  }

  bool _isAdminData(Map<String, dynamic>? data) {
    if (data == null) return true; // cannot tell → let rules decide
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    if (role == 'admin') return true;
    if (data['isAdmin'] == true) return true;
    // A known non-admin role → block in the UI too.
    if (role.isNotEmpty) return false;
    if (data.containsKey('isAdmin') && data['isAdmin'] == false) {
      return false;
    }
    return true;
  }

  // ------------------------------------------------------------
  // PROPERTY TYPE FILTERS — fetched from data.dart
  // ------------------------------------------------------------

  static const String _allFilter = 'All';

  List<String> _typesFrom(Map<String, List<String>> categories) {
    final types = <String>[];

    for (final subtypes in categories.values) {
      for (final type in subtypes) {
        if (!types.contains(type)) types.add(type);
      }
    }

    return types;
  }

  List<String> get _filters {
    final rentTypes = _typesFrom(PropertyCategories.rentCategories);
    final saleTypes = _typesFrom(PropertyCategories.saleCategories);

    final types = switch (_selectedPurpose) {
      'rent' => rentTypes,
      'sale' => saleTypes,
      _ => [
        ...rentTypes,
        ...saleTypes.where((type) => !rentTypes.contains(type)),
      ],
    };

    return [_allFilter, ...types];
  }

  String _filterLabel(String label) {
    switch (label) {
      case 'All':
        return _tr('All', 'Zote');
      case 'Apartment':
        return _tr('Apartment', 'Apartimenti');
      case 'House':
        return _tr('House', 'Nyumba');
      case 'Studio':
        return _tr('Studio', 'Studio');
      case 'Hostel':
        return _tr('Hostel', 'Hosteli');
      case 'Shop':
        return _tr('Shop', 'Duka');
      case 'Office':
        return _tr('Office', 'Ofisi');
      case 'Warehouse':
        return _tr('Warehouse', 'Ghala');
      case 'Airbnb':
        return _tr('Airbnb', 'Airbnb');
      case 'Guest House':
        return _tr('Guest House', 'Nyumba ya Wageni');
      case 'Hotel':
        return _tr('Hotel', 'Hoteli');
      case 'Residential Plot':
        return _tr('Residential Plot', 'Kiwanja cha Makazi');
      case 'Agricultural Land':
        return _tr('Agricultural Land', 'Ardhi ya Kilimo');
      case 'Ranch':
        return _tr('Ranch', 'Shamba la Mifugo');
      default:
        return label;
    }
  }

  // ------------------------------------------------------------
  // PURPOSE FILTER (For Rent / For Sale)
  // ------------------------------------------------------------

  static const List<String> _purposeFilters = ['all', 'rent', 'sale'];

  String _selectedPurpose = 'all';
  String _selectedFilter = _allFilter;

  List<QueryDocumentSnapshot> _unverifiedDocs = [];
  List<QueryDocumentSnapshot> _verifiedDocs = [];
  List<QueryDocumentSnapshot> _deactivatedDocs = [];

  String _purposeLabel(String purpose) {
    switch (purpose) {
      case 'rent':
        return _tr('For Rent', 'Ya Kupanga');
      case 'sale':
        return _tr('For Sale', 'Ya Kuuza');
      default:
        return _tr('All', 'Zote');
    }
  }

  bool _isForSale(Map<String, dynamic> data) {
    return (data['purpose'] ?? '').toString().trim().toLowerCase() == 'sale';
  }

  bool _matchesPurposeFilter(Map<String, dynamic> data) {
    if (_selectedPurpose == 'all') return true;
    return _selectedPurpose == 'sale'
        ? _isForSale(data)
        : !_isForSale(data);
  }

  // ------------------------------------------------------------
  // DEACTIVATED DETECTION + DEACTIVATION DETAILS
  // ------------------------------------------------------------

  static const Set<String> _inactiveStatuses = {
    'deactivated',
    'inactive',
    'deleted',
    'disabled',
  };

  bool _isDeactivatedProperty(Map<String, dynamic> data) {
    if (data['isDeactivated'] == true) return true;
    if (data['isDeleted'] == true || data['deleted'] == true) return true;
    if (data['deactivatedAt'] != null) return true;
    if (data['isActive'] == false) return true;

    final status = data['status']?.toString().toLowerCase();
    if (status != null && _inactiveStatuses.contains(status)) return true;

    final propertyStatus = data['property_status']?.toString().toLowerCase();
    if (propertyStatus != null && _inactiveStatuses.contains(propertyStatus)) {
      return true;
    }

    return false;
  }

  /// The date the listing was deactivated, if stored.
  DateTime? _deactivatedAt(Map<String, dynamic> data) {
    final raw = data['deactivatedAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  /// The reason the listing was deactivated, if stored.
  String _deactivationReason(Map<String, dynamic> data) {
    for (final key in [
      'deactivationReason',
      'deactivationNote',
      'reason',
    ]) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  // ------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _adminCheck = _fetchAdminUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // Firestore actions
  //
  // NOTE — property verification and LANDLORD verification are
  // now decoupled. These actions only touch the listing's own
  // `property_status`; the owner's `landlord_status` is managed
  // exclusively on the Verify Property Owners page. Verifying
  // one listing must not flip the whole owner account, and
  // unverifying one listing must not deverify an owner whose
  // other listings are fine.
  // ------------------------------------------------------------

  Future<void> approve(String id, String ownerId) async {
    final confirmed = await _confirmAction(
      title: _tr('Verify listing?', 'Thibitisha chapisho?'),
      message: _tr(
          'This marks this listing as verified. The owner\'s overall '
              'verification is NOT changed — manage that on the '
              'Verify Property Owners page.',
          'Hii inathibitisha chapisho hiki tu. Hali ya mmiliki '
              'haitabadilika — aisimamie kwenye ukurasa wa Kuthibitisha '
              'Wamiliki.'),
      confirmLabel: _tr('Verify', 'Thibitisha'),
    );
    if (confirmed != true) return;

    await FirebaseFirestore.instance
        .collection('properties')
        .doc(id)
        .update({'property_status': 'verified'});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('Listing verified.', 'Chapisho limethibitishwa.')),
      ));
    }
  }

  Future<void> unverify(String id, String ownerId) async {
    final confirmed = await _confirmAction(
      title: _tr('Unverify listing?', 'Ondoa uthibitisho?'),
      message: _tr(
          'This listing moves back to the Unverified tab and is no '
              ' longer shown as verified. Other listings by the same '
              'owner and the owner\'s overall status are NOT changed.',
          'Chapisho hiki kinarudi kwenye kichupo cha Hijathibitishwa. '
              'Machapisho mengine ya mmiliki na hali yake HAITABADILIKA.'),
      confirmLabel: _tr('Unverify', 'Ondoa Uthibitisho'),
    );
    if (confirmed != true) return;

    await FirebaseFirestore.instance
        .collection('properties')
        .doc(id)
        .update({'property_status': 'unverified'});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
        Text(_tr('Listing unverified.', 'Chapisho hajathibitishwa.')),
      ));
    }
  }

  /// Generic bilingual confirmation dialog. Returns true only
  /// when the user explicitly confirms.
  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _greenDeep,
            )),
        content: Text(message, style: TextStyle(color: _bodyText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: destructive
                  ? (_isDark ? Colors.red.shade300 : Colors.red.shade700)
                  : _green,
              foregroundColor:
              destructive ? (_isDark ? Colors.black : Colors.white) : Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return result == true;
  }

  // ------------------------------------------------------------
  // REMOVE LISTING
  //
  // Deletes, best-effort and in order:
  //   1. the listing's images from Firebase Storage,
  //   2. an audit entry in `admin_audit_logs`,
  //   3. the properties document itself.
  //
  // Storage / audit failures never block the document delete.
  // Full cleanup of subcollections, favourites, report
  // references and any other cross-collection links should be
  // owned by a server-side Cloud Function (see header notes).
  // ------------------------------------------------------------

  Future<void> _removeListing(
      BuildContext context,
      String id,
      String title,
      Map<String, dynamic> data,
      ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(_tr('Remove listing?', 'Kufuta chapisho?'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _greenDeep,
            )),
        content: Text(
          _tr('This permanently removes "$title", including its images. '
              'This action cannot be undone.',
              'Hii inafuta "$title" kabisa, pamoja na picha zake. '
                  'Hatua hii haiwezi kurudishwa.'),
          style: TextStyle(color: _bodyText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _isDark
                  ? Colors.red.shade300
                  : Colors.red.shade700,
              foregroundColor: _isDark ? Colors.black : Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('Remove', 'Ondoa')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 1. Best-effort image cleanup from Storage.
    await _deleteListingImages(data);

    // 2. Best-effort audit entry.
    await _logAdminAction(
      action: 'delete_property',
      ownerId: (data['ownerId'] ?? '').toString(),
      ownerName: (data['ownerName'] ?? '').toString(),
      reason: 'Removed by admin from Review Listings',
      details: 'Listing "$title" ($id) permanently deleted.',
      previousStatus: (data['property_status'] ?? '').toString(),
    );

    // 3. Delete the document itself.
    await FirebaseFirestore.instance
        .collection('properties')
        .doc(id)
        .delete();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
            Text(_tr('Listing removed.', 'Chapisho limefutwa.'))),
      );
    }
  }

  /// Deletes every image URL stored on the listing from
  /// Firebase Storage. Never throws — cleanup is best-effort.
  Future<void> _deleteListingImages(Map<String, dynamic> data) async {
    final urls = <String>[];

    for (final key in ['images', 'imageUrls', 'photos', 'image_paths']) {
      final value = data[key];
      if (value is List) {
        urls.addAll(value.whereType<String>());
      } else if (value is String && value.isNotEmpty) {
        urls.add(value);
      }
    }

    for (final url in urls) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {
        // Missing file, wrong bucket or no permission — skip.
      }
    }
  }

  /// Writes an audit entry to the shared `admin_audit_logs`
  /// collection (admin-only per the Firestore rules). Never
  /// throws — logging must not block the action itself.
  Future<void> _logAdminAction({
    required String action,
    required String ownerId,
    required String ownerName,
    String reason = '',
    String details = '',
    String previousStatus = '',
    String newStatus = '',
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance
          .collection('admin_audit_logs')
          .add({
        'ownerId': ownerId,
        'ownerName': ownerName,
        'action': action,
        'reason': reason,
        'details': details,
        'previousStatus': previousStatus,
        'newStatus': newStatus,
        'performedBy': user?.uid ?? '',
        'performedByName': user?.displayName ?? '',
        'performedByRole': 'admin',
        'performedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort audit log — never block the main action.
    }
  }

  // ------------------------------------------------------------
  // View → full property details page (admin view)
  // ------------------------------------------------------------

  void _viewListing(Map<String, dynamic> data, String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyDetailsPage(
          property: {'id': id, ...data},
          isAdminView: true,
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Download the whole visible (filtered/searched) list
  //
  // The CSV now includes Listing ID, Owner ID, Purpose, Status,
  // Deactivated At and Deactivation Reason, so it doubles as a
  // real administrative report.
  // ------------------------------------------------------------

  Future<void> _downloadList(List<QueryDocumentSnapshot> docs) async {
    await DownloadHelper.downloadCsv(
      context: context,
      fileNamePrefix: 'property_listings',
      headers: [
        _tr('Listing ID', 'ID ya Chapisho'),
        _tr('Title', 'Jina'),
        _tr('Type', 'Aina'),
        _tr('Purpose', 'Kusudi'),
        _tr('Location', 'Eneo'),
        _tr('Town', 'Mji'),
        _tr('County', 'Kaunti'),
        _tr('Price', 'Bei'),
        _tr('Rent Cycle', 'Mzunguko wa Kodi'),
        _tr('Owner ID', 'ID ya Mmiliki'),
        _tr('Status', 'Hali'),
        _tr('Deactivated At', 'Imezimwa Tarehe'),
        _tr('Deactivation Reason', 'Sababu ya Kuzimwa'),
      ],
      rows: docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final type = (data['type'] ?? '').toString();
        final rentCycle = (data['rentCycle'] ??
            data['priceCycle'] ??
            data['paymentCycle'] ??
            _defaultCycleFor(type))
            .toString();

        final deactivatedAt = _deactivatedAt(data);
        final reason = _deactivationReason(data);
        final deactivated = _isDeactivatedProperty(data);

        return [
          doc.id,
          data['title'] ?? data['name'],
          type,
          _isForSale(data)
              ? _tr('For Sale', 'Ya Kuuza')
              : _tr('For Rent', 'Ya Kupanga'),
          data['location'],
          data['town'],
          data['county'],
          data['price'],
          rentCycle,
          (data['ownerId'] ?? '').toString(),
          deactivated
              ? _tr('Deactivated', 'Imezimwa')
              : (data['property_status']?.toString().toLowerCase() ==
              'verified'
              ? _tr('Verified', 'Imethibitishwa')
              : _tr('Unverified', 'Hajathibitishwa')),
          (deactivated && deactivatedAt != null)
              ? _formatDate(deactivatedAt)
              : '',
          (deactivated && reason.isNotEmpty) ? reason : '',
        ];
      }).toList(),
    );
  }

  String _defaultCycleFor(String type) {
    return type.toLowerCase().contains('hostel')
        ? 'Semesterly'
        : 'Monthly';
  }

  bool _matchesFilter(String type, String filter) {
    if (filter == _allFilter) return true;
    return type.trim().toLowerCase() == filter.trim().toLowerCase();
  }

  // ------------------------------------------------------------
  // SEARCH — now searches every field the hint promises:
  // title, name, location, town, county, price, type,
  // propertyType, purpose, rentCycle, priceCycle,
  // paymentCycle, owner ID and listing ID.
  // ------------------------------------------------------------

  bool _matchesSearch(String docId, Map<String, dynamic> data, String term) {
    if (term.isEmpty) return true;

    final searchableText = [
      docId,
      data['title'],
      data['name'],
      data['location'],
      data['town'],
      data['county'],
      data['price'],
      data['type'],
      data['propertyType'],
      data['purpose'],
      data['rentCycle'],
      data['priceCycle'],
      data['paymentCycle'],
      data['ownerId'],
    ].join(' ').toLowerCase();

    return searchableText.contains(term);
  }

  @override
  Widget build(BuildContext context) {
    final filters = _filters;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _adminCheck,
      builder: (context, adminSnap) {
        // Only block when we positively know the user is NOT an
        // admin. Missing data → rules still enforce everything.
        if (adminSnap.hasData && !_isAdminData(adminSnap.data)) {
          return Scaffold(
            backgroundColor: _pageBackground,
            appBar: AppBar(
              title: Text(_tr('Review Listings', 'Kagua Machapisho')),
              backgroundColor: _green,
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 70,
                        color: _isDark
                            ? Colors.grey.shade600
                            : Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      _tr('Admin access only.',
                          'Ni waangalizi tu wanaweza kufikia.'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _pageBackground,
          appBar: AppBar(
            title: Text(_tr('Review Listings', 'Kagua Machapisho')),
            backgroundColor: _green,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: _tr('Download list', 'Pakua orodha'),
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: () {
                  _downloadList(
                    switch (_tabController.index) {
                      0 => _unverifiedDocs,
                      1 => _verifiedDocs,
                      _ => _deactivatedDocs,
                    },
                  );
                },
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                Tab(text: _tr('Unverified', 'Hajathibitishwa')),
                Tab(text: _tr('Verified', 'Imethibitishwa')),
                Tab(text: _tr('Deactivated', 'Zimezimwa')),
              ],
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: _bodyText),
                  decoration: InputDecoration(
                    hintText: _tr(
                        'Search by title, location, rent, cycle, type, '
                            'owner ID...',
                        'Tafuta kwa jina, eneo, kodi, mzunguko, aina, '
                            'ID ya mmiliki...'),
                    hintStyle: TextStyle(color: _mutedText),
                    prefixIcon: Icon(
                      Icons.search,
                      color: _green,
                    ),
                    filled: true,
                    fillColor: _greenSurface,
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _green, width: 2),
                    ),
                  ),
                ),
              ),

              // ------------------------------------------------
              // PURPOSE FILTER (All | For Rent | For Sale)
              // ------------------------------------------------
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  itemCount: _purposeFilters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) =>
                      _purposeButton(_purposeFilters[index]),
                ),
              ),

              // ------------------------------------------------
              // PROPERTY TYPE CHIPS — built from data.dart
              // ------------------------------------------------
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  itemCount: filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => _filterButton(filters[index]),
                ),
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  // Paginated stream: only the first `_limit`
                  // documents are fetched; "Load more" grows it.
                  stream: FirebaseFirestore.instance
                      .collection('properties')
                      .limit(_limit)
                      .snapshots(),
                  builder: (context, snapshot) {
                    // ERROR STATE — dedicated screen with retry.
                    if (snapshot.hasError) {
                      return _buildErrorState(snapshot.error);
                    }

                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: _green,
                        ),
                      );
                    }

                    final searchTerm =
                    _searchController.text.trim().toLowerCase();

                    final unverified = <QueryDocumentSnapshot>[];
                    final verified = <QueryDocumentSnapshot>[];
                    final deactivated = <QueryDocumentSnapshot>[];

                    for (final doc in snapshot.data!.docs) {
                      final data =
                      doc.data() as Map<String, dynamic>;

                      if (!_matchesPurposeFilter(data)) {
                        continue;
                      }

                      if (_selectedFilter != _allFilter) {
                        final type = (data['type'] ??
                            data['propertyType'] ??
                            '')
                            .toString();
                        if (!_matchesFilter(type, _selectedFilter)) {
                          continue;
                        }
                      }

                      if (!_matchesSearch(doc.id, data, searchTerm)) {
                        continue;
                      }

                      // DEACTIVATED first — such listings go ONLY
                      // into the Deactivated tab.
                      if (_isDeactivatedProperty(data)) {
                        deactivated.add(doc);
                        continue;
                      }

                      final verifiedListing =
                          (data['property_status'] ?? '')
                              .toString()
                              .toLowerCase() == 'verified';

                      if (verifiedListing) {
                        verified.add(doc);
                      } else {
                        unverified.add(doc);
                      }
                    }

                    _unverifiedDocs = unverified;
                    _verifiedDocs = verified;
                    _deactivatedDocs = deactivated;

                    // If the page came back full there may be
                    // more documents beyond the current limit.
                    final mayHaveMore =
                        snapshot.data!.docs.length >= _limit;

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildListingList(unverified, tabIndex: 0,
                            mayHaveMore: mayHaveMore),
                        _buildListingList(verified, tabIndex: 1,
                            mayHaveMore: mayHaveMore),
                        _buildListingList(deactivated, tabIndex: 2,
                            mayHaveMore: mayHaveMore),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // ERROR STATE with retry
  // ------------------------------------------------------------

  Widget _buildErrorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 70,
              color: _isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              _tr('Could not load listings',
                  'Machapisho hayakupatikana'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _mutedText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _tr('Check your connection and try again.',
                  'Angalia mtandao wako kisha ujaribu tena.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _mutedText),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _retryKey++; // rebuilds the stream
                });
              },
              icon: const Icon(Icons.refresh),
              label: Text(_tr('Retry', 'Jaribu Tena')),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // PURPOSE BUTTON
  // ------------------------------------------------------------

  Widget _purposeButton(String purpose) {
    final selected = _selectedPurpose == purpose;

    return ChoiceChip(
      label: Text(_purposeLabel(purpose)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedPurpose = purpose;

          if (!_filters.contains(_selectedFilter)) {
            _selectedFilter = _allFilter;
          }
        });
      },
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : _bodyText,
      ),
      selectedColor: purpose == 'sale' ? _saleColor : _green,
      backgroundColor: _greenSurface,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  // ------------------------------------------------------------
  // FILTER BUTTON
  // ------------------------------------------------------------

  Widget _filterButton(String label) {
    final selected = _selectedFilter == label;

    return ChoiceChip(
      label: Text(_filterLabel(label)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = label;
        });
      },
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : _bodyText,
      ),
      selectedColor: _green,
      backgroundColor: _greenSurface,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  // ------------------------------------------------------------
  // LISTING LIST — tabIndex: 0 unverified, 1 verified,
  // 2 deactivated. Includes a Load-more footer while more
  // documents may exist beyond the current page.
  // ------------------------------------------------------------

  Widget _buildListingList(
      List<QueryDocumentSnapshot> docs, {
        required int tabIndex,
        required bool mayHaveMore,
      }) {
    if (docs.isEmpty && !mayHaveMore) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tabIndex == 1
                    ? Icons.verified_outlined
                    : tabIndex == 2
                    ? Icons.block_outlined
                    : Icons.pending_outlined,
                size: 70,
                color: _isDark
                    ? Colors.grey.shade600
                    : Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                tabIndex == 1
                    ? _tr('No verified listings yet',
                    'Hakuna machapisho yaliyothibitishwa bado')
                    : tabIndex == 2
                    ? _tr('No deactivated listings',
                    'Hakuna machapisho yaliyozimwa')
                    : _tr('No pending listings',
                    'Hakuna machapisho yanayosubiri'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _mutedText,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: docs.length + (mayHaveMore ? 1 : 0),
      itemBuilder: (context, index) {
        // "Load more" footer.
        if (index == docs.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                setState(() {
                  _limit += _pageSize;
                });
              },
              icon: const Icon(Icons.expand_more),
              label: Text(_tr(
                  'Load more listings', 'Pakua machapisho zaidi')),
            ),
          );
        }

        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;

        return _listingCard(doc, data, tabIndex: tabIndex);
      },
    );
  }

  // ------------------------------------------------------------
  // LISTING CARD
  // ------------------------------------------------------------

  Widget _listingCard(
      QueryDocumentSnapshot doc,
      Map<String, dynamic> data, {
        required int tabIndex,
      }) {
    final String id = doc.id;

    final String ownerId = (data['ownerId'] ?? '').toString();

    final String title = (data['title'] ??
        data['name'] ??
        _tr('Untitled Property', 'Mali Bila Jina'))
        .toString();

    final String type = (data['type'] ?? '').toString();

    final String location = [
      data['location'],
      data['town'],
      data['county'],
    ]
        .where((value) => value != null && value.toString().isNotEmpty)
        .map((value) => value.toString())
        .join(', ');

    final String rentCycle = (data['rentCycle'] ??
        data['priceCycle'] ??
        data['paymentCycle'] ??
        _defaultCycleFor(type))
        .toString();

    final dynamic rawPrice = data['price'];
    final String price = rawPrice == null
        ? ''
        : 'KES ${rawPrice.toString()} / $rentCycle';

    final bool forSale = _isForSale(data);
    final bool isDeactivatedTab = tabIndex == 2;

    // Deactivation details for the Deactivated tab.
    final deactivatedAt = _deactivatedAt(data);
    final deactivationReason = _deactivationReason(data);

    return Card(
      color: _cardColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDeactivatedTab
              ? Colors.red.withValues(alpha: 0.5)
              : _cardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDeactivatedTab
                        ? Colors.red.withValues(alpha: 0.10)
                        : _green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDeactivatedTab
                        ? Icons.block_outlined
                        : Icons.home_work_outlined,
                    color: isDeactivatedTab
                        ? (_isDark
                        ? Colors.red.shade300
                        : Colors.red.shade700)
                        : _green,
                    size: 20,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _bodyText,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _mutedText,
                        ),
                      ),

                      if (price.isNotEmpty) ...[
                        const SizedBox(height: 2),

                        Text(
                          price,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _greenDeep,
                          ),
                        ),
                      ],

                      // PURPOSE — For Rent / For Sale badge.
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (forSale
                              ? _saleColor
                              : (_isDark
                              ? Colors.blue.shade300
                              : Colors.blue.shade700))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          forSale
                              ? _tr('For Sale', 'Ya Kuuza')
                              : _tr('For Rent', 'Ya Kupanga'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: forSale
                                ? _saleColor
                                : (_isDark
                                ? Colors.blue.shade300
                                : Colors.blue.shade700),
                          ),
                        ),
                      ),

                      if (isDeactivatedTab) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _tr('Deactivated — hidden from tenants',
                                'Imezimwa — imefichwa kwa wapangaji'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _isDark
                                  ? Colors.red.shade300
                                  : Colors.red.shade700,
                            ),
                          ),
                        ),

                        // DEACTIVATION DETAILS — date + reason.
                        if (deactivatedAt != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 12,
                                color: _mutedText,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${_tr('Deactivated on', 'Ilizimwa tarehe')} '
                                      '${_formatDate(deactivatedAt)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _mutedText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (deactivationReason.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.notes_outlined,
                                size: 12,
                                color: _mutedText,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${_tr('Reason', 'Sababu')}: '
                                      '$deactivationReason',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _mutedText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                if (tabIndex == 1)
                  Icon(
                    Icons.verified,
                    color: _green,
                    size: 20,
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ----------------------------------------------------
            // WORD BUTTONS:
            //   Normal tabs : View | Verify/Unverify | Remove
            //   Deactivated : View | Remove (reactivation is
            //   done from the Verify Property Owners page)
            // ----------------------------------------------------

            Row(
              children: [
                Expanded(
                  child: _wordButton(
                    label: _tr('View', 'Angalia'),
                    color: _isDark
                        ? Colors.blue.shade300
                        : Colors.blue.shade700,
                    onPressed: () => _viewListing(data, id),
                  ),
                ),

                if (!isDeactivatedTab) ...[
                  const SizedBox(width: 8),

                  Expanded(
                    child: _wordButton(
                      label: tabIndex == 1
                          ? _tr('Unverify', 'Ondoa Uthibitisho')
                          : _tr('Verify', 'Thibitisha'),
                      color: tabIndex == 1
                          ? (_isDark
                          ? Colors.orange.shade300
                          : Colors.orange)
                          : _green,
                      onPressed: tabIndex == 1
                          ? () => unverify(id, ownerId)
                          : () => approve(id, ownerId),
                    ),
                  ),
                ],

                const SizedBox(width: 8),

                Expanded(
                  child: _wordButton(
                    label: _tr('Remove', 'Ondoa'),
                    color: _isDark
                        ? Colors.red.shade300
                        : Colors.red.shade700,
                    onPressed: () => _removeListing(
                        context, id, title, data),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // WORD BUTTON
  // ------------------------------------------------------------

  Widget _wordButton({
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    final disabledColor = _isDark ? Colors.grey.shade700 : Colors.grey.shade300;

    return Material(
      color: onPressed == null
          ? disabledColor
          : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: onPressed == null ? _mutedText : color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BACKEND RECOMMENDATIONS (not this file)
//
//  1. Firestore Security Rules already enforce admin-only
//     writes on `properties` and `admin_audit_logs` — keep it
//     that way; the client-side check here is convenience only.
//  2. Permanent deletion of a listing should ultimately be
//     owned by a Cloud Function (e.g. deletePropertyListing,
//     region africa-south1 to match your Firestore location)
//     that atomically removes the document, its Storage
//     images, subcollections, favourites entries and report
//     references. The client-side cleanup here is best-effort.
//  3. At scale, replace the growing-limit pagination with
//     startAfterDocument cursors or move Review Listings to
//     server-side queries.
// ============================================================