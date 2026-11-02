import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_localizations.dart';
import 'app_settings.dart';
import 'favourites_service.dart';
import 'property_search_page.dart';
// Provides PropertyDetailsPage and DeviceIdService.
import 'property_details_page.dart';
// Provides RoommatePost and kRoommateCollection.
import 'roommate_posting_finding_page.dart';
// Provides PropertyService, ServiceBookmarks, ServiceContactButtons,
// ServiceActions and SearchMatcher.
import 'service_actions.dart';

// ============================================================
// FAVOURITES SIGNAL
// ============================================================
class FavouritesSignal {
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void notify() => changes.value++;
}

// ============================================================
// FAVOURITES PAGE
//
// THREE tabs:
//   0. Properties : the saved properties (compare up to 3,
//                   long-press to select).
//   1. Services   : service providers bookmarked from the
//                   Services page (Call / WhatsApp / Email /
//                   Open link, Remove).
//   2. Roommates  : NEW - roommate requests saved from the
//                   Roommate Finder (Call / WhatsApp / Remove).
//
// `initialTab`: 0 = Properties (default), 1 = Services,
// 2 = Roommates. The Services page opens this page on tab 1.
//
// SEARCH: multi-term - every word must match somewhere
// (e.g. "cleaner Kisumu"), for all tabs.
//
// Translation: every user-facing string goes through _tr(),
// which resolves it through AppLocalizations for the language
// chosen in App Settings.
//
// APP BAR VISIBILITY: the AppBar sets its OWN foregroundColor /
// iconTheme / actionsIconTheme / titleTextStyle per brightness
// so the title and every button are visible in light and dark.
// ============================================================

class FavouritesPage extends StatefulWidget {
  /// 0 = Properties tab, 1 = Services tab, 2 = Roommates tab.
  final int initialTab;

  const FavouritesPage({super.key, this.initialTab = 0});

  @override
  State<FavouritesPage> createState() => _FavouritesPageState();
}

class _FavouritesPageState extends State<FavouritesPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const String _legacyLocalKey = 'favourite_properties';

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _busy = false;

  String _deviceId = '';

  // Firestore documents are used directly.
  List<Map<String, dynamic>> _properties = [];

  // Bookmarked service providers.
  List<PropertyService> _services = [];

  // Saved roommate requests.
  List<RoommatePost> _roommates = [];

  // ----------------------------------------------------------
  // SEARCH
  // ----------------------------------------------------------

  String _searchQuery = '';

  // ----------------------------------------------------------
  // COMPARISON SELECTION (Properties tab)
  // ----------------------------------------------------------

  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  // ----------------------------------------------------------
  // OWNER LINKING (same approach as the search page).
  // ----------------------------------------------------------

  final Map<String, Map<String, dynamic>?> _ownerCache = {};
  final Map<String, Future<Map<String, dynamic>?>> _ownerFutures = {};

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ----------------------------------------------------------
  // SETTINGS HELPERS
  // ----------------------------------------------------------

  SettingsController get _settings => AppSettings.of(context);

  bool get _isDark => _settings.isDark;

  /// Translation driven by the language chosen in App Settings.
  String _tr(String en, String sw) {
    final code = _settings.languageCode;
    if (code == 'sw') return sw;
    return AppLocalizations.trText(en, code);
  }

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _scaffold => _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _card => _isDark ? kDarkCard : Colors.white;

  Color get _bodyText =>
      _isDark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);

  Color get _mutedText =>
      _isDark ? const Color(0xFFA9B8AF) : const Color(0xFF5B6B62);

  Color get _cardBorder =>
      _isDark ? const Color(0xFF28352C) : const Color(0xFFE3ECE6);

  Color get _appBarForeground => _isDark ? Colors.white : _bodyText;

  bool get _onServicesTab => _tabController.index == 1;

  bool get _onRoommatesTab => _tabController.index == 2;

  // ----------------------------------------------------------
  // PRICE FORMATTING (thousands separators)
  // ----------------------------------------------------------

  String _formatPrice(double price) {
    final whole = price.toStringAsFixed(0);
    final regex = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return whole.replaceAllMapped(regex, (match) => ',');
  }

  // ----------------------------------------------------------
  // LIFECYCLE
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addObserver(this);
    FavouritesSignal.changes.addListener(_onSignal);
    ServiceBookmarks.changes.addListener(_onSignal);
    FavouritesService.roommateChanges.addListener(_onSignal);
    _loadFavourites();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FavouritesSignal.changes.removeListener(_onSignal);
    ServiceBookmarks.changes.removeListener(_onSignal);
    FavouritesService.roommateChanges.removeListener(_onSignal);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;

    if (!mounted) return;

    setState(() {
      // Selection / compare only exists on the Properties tab.
      if (_tabController.index != 0 && _selectionMode) {
        _selectionMode = false;
        _selectedIds.clear();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadFavourites(silent: true);
    }
  }

  void _onSignal() {
    if (mounted) _loadFavourites(silent: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  // ----------------------------------------------------------
  // LOAD
  //
  // Fault-tolerant refresh: every source has its own
  // try/catch, a failing source is skipped, and the previously
  // loaded list is NEVER cleared by an error.
  // ----------------------------------------------------------

  Future<void> _loadFavourites({bool silent = false}) async {
    // Prevent duplicate/parallel loads.
    if (_busy) return;
    _busy = true;

    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    try {
      if (_deviceId.isEmpty) _deviceId = await DeviceIdService.get();

      final user = FirebaseAuth.instance.currentUser;
      final Set<String> ids = {};

      // 1) Main store: `favorites` documents of THIS DEVICE.
      //    (Roommate favourites live in the same collection but
      //    have no propertyId, so they are skipped here.)
      try {
        final snap = await _firestore
            .collection('favorites')
            .where('deviceId', isEqualTo: _deviceId)
            .get();

        for (final doc in snap.docs) {
          final id = doc.data()['propertyId']?.toString() ?? '';
          if (id.isNotEmpty) ids.add(id);
        }
      } catch (e) {
        debugPrint('Favourites (device) load error: $e');
      }

      // 2) Main store: `favorites` documents of the SIGNED-IN
      //    ACCOUNT. Deduplicated automatically by the Set.
      if (user != null) {
        try {
          final snap = await _firestore
              .collection('favorites')
              .where('userId', isEqualTo: user.uid)
              .get();

          for (final doc in snap.docs) {
            final id = doc.data()['propertyId']?.toString() ?? '';
            if (id.isNotEmpty) ids.add(id);
          }
        } catch (e) {
          debugPrint('Favourites (account) load error: $e');
        }

        // 3) Legacy: users/{uid}/favourites
        try {
          final snap = await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('favourites')
              .get();

          ids.addAll(snap.docs.map((doc) => doc.id));
        } catch (_) {}
      }

      // 4) Legacy: local list on this device.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        ids.addAll(prefs.getStringList(_legacyLocalKey) ?? []);
      } catch (_) {}

      final results = await _fetchProperties(ids.toList());

      // Bookmarked services (null = failed, keep the old list).
      final services = await _loadSavedServices();

      // Saved roommate requests (null = failed, keep the old list).
      final roommates = await _loadSavedRoommates();

      if (mounted) {
        setState(() {
          _properties = results;
          if (services != null) _services = services;
          if (roommates != null) _roommates = roommates;
        });
        // Drop selections for properties that no longer exist.
        _selectedIds.removeWhere(
              (id) => !results.any((p) => _propertyIdOf(p) == id),
        );
        if (_selectedIds.isEmpty) _selectionMode = false;
      }
    } catch (e) {
      debugPrint('Favourites load error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'Unable to load favourites',
                'Imeshindikana kupakia vipendwa',
              ),
            ),
          ),
        );
      }
    } finally {
      _busy = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  // ----------------------------------------------------------
  // SAVED SERVICES - bookmarks from the Services page.
  // ----------------------------------------------------------

  Future<List<PropertyService>?> _loadSavedServices() async {
    try {
      final ids = (await ServiceBookmarks.loadIds()).toList();

      if (ids.isEmpty) return [];

      final batches = <List<String>>[];
      for (int i = 0; i < ids.length; i += 10) {
        batches.add(ids.skip(i).take(10).toList());
      }

      final snapshots = await Future.wait(
        batches.map((batch) async {
          try {
            return await _firestore
                .collection('property_services')
                .where(FieldPath.documentId, whereIn: batch)
                .get();
          } catch (e) {
            debugPrint('Saved services batch error: $e');
            return null;
          }
        }),
      );

      final seen = <String>{};
      final services = <PropertyService>[];

      for (final snapshot in snapshots) {
        if (snapshot == null) continue;

        for (final doc in snapshot.docs) {
          if (seen.add(doc.id)) {
            services.add(PropertyService.fromFirestore(doc));
          }
        }
      }

      services.sort((a, b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return services;
    } catch (e) {
      debugPrint('Saved services load error: $e');
      return null;
    }
  }

  // ----------------------------------------------------------
  // SAVED ROOMMATE REQUESTS (NEW)
  // Loads the saved ids, then the `roommates` documents 10 at a
  // time (Firestore whereIn limit). Requests that were deleted
  // or hidden simply no longer appear.
  // ----------------------------------------------------------

  Future<List<RoommatePost>?> _loadSavedRoommates() async {
    try {
      final ids = (await FavouritesService.roommateFavouriteIds()).toList();

      if (ids.isEmpty) return [];

      final batches = <List<String>>[];
      for (int i = 0; i < ids.length; i += 10) {
        batches.add(ids.skip(i).take(10).toList());
      }

      final snapshots = await Future.wait(
        batches.map((batch) async {
          try {
            return await _firestore
                .collection(kRoommateCollection)
                .where(FieldPath.documentId, whereIn: batch)
                .get();
          } catch (e) {
            debugPrint('Saved roommates batch error: $e');
            return null;
          }
        }),
      );

      final seen = <String>{};
      final posts = <RoommatePost>[];

      for (final snapshot in snapshots) {
        if (snapshot == null) continue;

        for (final doc in snapshot.docs) {
          if (!seen.add(doc.id)) continue;

          final post = RoommatePost.fromFirestore(doc);
          if (post.isHidden) continue;

          posts.add(post);
        }
      }

      posts.sort((a, b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return posts;
    } catch (e) {
      debugPrint('Saved roommates load error: $e');
      return null;
    }
  }

  // Loads the property documents for the given ids, 10 at a time
  // (Firestore whereIn limit). A failing batch is skipped. After
  // loading, each property is linked to its OWNER.
  Future<List<Map<String, dynamic>>> _fetchProperties(
      List<String> ids,
      ) async {
    if (ids.isEmpty) return [];

    final batches = <List<String>>[];
    for (int i = 0; i < ids.length; i += 10) {
      batches.add(ids.skip(i).take(10).toList());
    }

    final snapshots = await Future.wait(
      batches.map((batch) async {
        try {
          return await _firestore
              .collection('properties')
              .where(FieldPath.documentId, whereIn: batch)
              .get();
        } catch (e) {
          debugPrint('Favourites property batch error: $e');
          return null;
        }
      }),
    );

    final List<Map<String, dynamic>> results = [];
    final Set<String> seenIds = <String>{};

    for (final snapshot in snapshots) {
      if (snapshot == null) continue;

      for (final doc in snapshot.docs) {
        if (seenIds.contains(doc.id)) continue;
        seenIds.add(doc.id);

        results.add({
          ...doc.data(),
          'id': doc.id,
        });
      }
    }

    // ---- owner linking + embedding ----
    final ownerIds = <String>{};
    for (final property in results) {
      final ownerId = _ownerIdOf(property);
      if (ownerId.isNotEmpty) ownerIds.add(ownerId);
    }

    final owners = <String, Map<String, dynamic>?>{};
    await Future.wait(
      ownerIds.map((ownerId) async {
        owners[ownerId] = await _ownerFuture(ownerId);
      }),
    );

    for (final property in results) {
      final ownerId = _ownerIdOf(property);
      if (ownerId.isEmpty) continue;

      final owner = owners[ownerId];
      if (owner != null) {
        final existingOwner = property['owner'];
        property['owner'] = (existingOwner is Map && existingOwner.isNotEmpty)
            ? existingOwner
            : owner;
      }
    }

    return results;
  }

  // ----------------------------------------------------------
  // OWNER HELPERS
  // ----------------------------------------------------------

  String _fieldOf(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _ownerIdOf(Map<String, dynamic> data) {
    final direct = _fieldOf(data, [
      'ownerId',
      'ownerUid',
      'owner_id',
      'owner_uid',
      'uid',
      'userId',
      'user_id',
      'landlordId',
    ]);
    if (direct.isNotEmpty) return direct;

    final ownerField = data['owner'];
    if (ownerField is Map) {
      final fromMap = _fieldOf(
        Map<String, dynamic>.from(ownerField),
        ['uid', 'id', 'userId', 'ownerId'],
      );
      if (fromMap.isNotEmpty) return fromMap;
    }

    final ownerText = ownerField?.toString().trim() ?? '';
    if (ownerText.isNotEmpty &&
        ownerText != 'guest' &&
        ownerField is! Map &&
        ownerField is! List) {
      return ownerText;
    }

    return '';
  }

  Future<Map<String, dynamic>?> _ownerFuture(String ownerId) {
    if (_ownerCache.containsKey(ownerId)) {
      return Future.value(_ownerCache[ownerId]);
    }
    return _ownerFutures.putIfAbsent(ownerId, () async {
      Map<String, dynamic>? result;
      try {
        final doc = await _firestore.collection('users').doc(ownerId).get();

        if (doc.exists) {
          final data = doc.data()!;
          final accountStatus =
              data['accountStatus']?.toString().toLowerCase() ?? '';
          final userStatus = data['status']?.toString().toLowerCase() ?? '';

          final deactivated = data['isDeactivated'] == true ||
              data['isActive'] == false ||
              accountStatus == 'deactivated' ||
              accountStatus == 'deleted' ||
              userStatus == 'deactivated' ||
              userStatus == 'deleted';

          result = deactivated ? null : {...data, 'id': doc.id};
        }
      } catch (_) {
        result = null;
      }
      _ownerCache[ownerId] = result;
      return result;
    });
  }

  // ============================================================
  // PROPERTY FIELD HELPERS
  // ============================================================

  String _propertyIdOf(Map<String, dynamic> property) =>
      property['id']?.toString() ?? property['propertyId']?.toString() ?? '';

  String _titleOf(Map<String, dynamic> property) =>
      property['title']?.toString() ??
          _tr('Untitled Property', 'Mali Isiyo na Jina');

  String _areaOf(Map<String, dynamic> property) =>
      property['area']?.toString() ?? property['subcounty']?.toString() ?? '';

  String _countyOf(Map<String, dynamic> property) =>
      property['county']?.toString() ?? '';

  String _paymentCycleOf(Map<String, dynamic> property) =>
      property['paymentCycle']?.toString() ??
          property['paymentPeriod']?.toString() ??
          'month';

  double _priceOf(Map<String, dynamic> property) {
    final raw = property['price'];
    if (raw is num) return raw.toDouble();
    if (raw != null) return double.tryParse(raw.toString()) ?? 0;
    return 0;
  }

  // ============================================================
  // SEARCH (multi-term: every word must match somewhere)
  // ============================================================

  List<Map<String, dynamic>> get _filteredProperties {
    final query = _searchQuery.trim();
    if (query.isEmpty) return _properties;

    return _properties.where((property) {
      final haystack = [
        _titleOf(property),
        _areaOf(property),
        _countyOf(property),
        property['subCounty']?.toString() ?? '',
        property['type']?.toString() ?? '',
      ].join(' ');
      return SearchMatcher.matches(haystack, query);
    }).toList();
  }

  List<PropertyService> get _filteredServices {
    final query = _searchQuery.trim();
    if (query.isEmpty) return _services;

    return _services.where((service) {
      final haystack = [
        service.title,
        service.category,
        service.location,
        service.description,
        service.postedBy,
        service.price,
      ].join(' ');
      return SearchMatcher.matches(haystack, query);
    }).toList();
  }

  List<RoommatePost> get _filteredRoommates {
    final query = _searchQuery.trim();
    if (query.isEmpty) return _roommates;

    return _roommates.where((post) {
      final haystack = [
        post.name,
        post.campus,
        post.hostelName,
        post.area,
        post.accommodationType,
        post.gender,
        post.preferences,
      ].join(' ');
      return SearchMatcher.matches(haystack, query);
    }).toList();
  }

  // ============================================================
  // SELECTION / COMPARISON
  // ============================================================

  void _toggleSelection(String propertyId) {
    setState(() {
      if (_selectedIds.contains(propertyId)) {
        _selectedIds.remove(propertyId);
      } else {
        if (_selectedIds.length >= 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _tr(
                  'You can compare up to 3 properties',
                  'Unaweza kulinganisha mali 3 tu',
                ),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        _selectedIds.add(propertyId);
      }

      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _openComparison() {
    final selected = _properties
        .where((p) => _selectedIds.contains(_propertyIdOf(p)))
        .toList();

    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Select at least 2 properties to compare',
              'Chagua mali angalau 2 za kulinganisha',
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ComparisonDialog(
        properties: selected,
        isDark: _isDark,
        brand: _brand,
        card: _card,
        bodyText: _bodyText,
        mutedText: _mutedText,
        cardBorder: _cardBorder,
        tr: _tr,
      ),
    );
  }

  // ============================================================
  // REMOVE FAVOURITE (property)
  //
  // Resilient cleanup: EVERY storage location is attempted
  // independently with its own try/catch.
  // ============================================================

  Future<void> removeFavourite(String propertyId) async {
    int deletedCount = 0;
    final List<Future<void>> accountCopyDeletes = [];

    try {
      if (_deviceId.isEmpty) _deviceId = await DeviceIdService.get();

      final user = FirebaseAuth.instance.currentUser;

      // 1) Device copy: {propertyId}_{deviceId}. Best effort.
      try {
        await _firestore
            .collection('favorites')
            .doc('${propertyId}_$_deviceId')
            .delete();
        deletedCount++;
      } catch (e) {
        debugPrint('Favourites remove (device copy) error: $e');
      }

      // 2) Account copies. Best effort.
      if (user != null) {
        try {
          final snap = await _firestore
              .collection('favorites')
              .where('userId', isEqualTo: user.uid)
              .where('propertyId', isEqualTo: propertyId)
              .get();

          for (final doc in snap.docs) {
            accountCopyDeletes.add(
              doc.reference.delete().then((_) {
                deletedCount++;
              }).catchError((e) {
                debugPrint('Favourites remove (account copy) error: $e');
              }),
            );
          }
        } catch (e) {
          debugPrint('Favourites remove (account query) error: $e');
        }

        // 3) Legacy Firestore location. Best effort.
        try {
          await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('favourites')
              .doc(propertyId)
              .delete();
          deletedCount++;
        } catch (e) {
          debugPrint('Favourites remove (legacy firestore) error: $e');
        }
      }

      // 4) Legacy local list. Best effort.
      try {
        final prefs = await SharedPreferences.getInstance();
        final local = List<String>.from(
          prefs.getStringList(_legacyLocalKey) ?? [],
        );

        if (local.remove(propertyId)) {
          await prefs.setStringList(_legacyLocalKey, local);
          deletedCount++;
        }
      } catch (e) {
        debugPrint('Favourites remove (legacy local) error: $e');
      }

      await Future.wait(accountCopyDeletes);

      if (!mounted) return;

      if (deletedCount > 0) {
        setState(() {
          _properties.removeWhere(
                (property) => _propertyIdOf(property) == propertyId,
          );
          _selectedIds.remove(propertyId);
          if (_selectedIds.isEmpty) _selectionMode = false;
        });

        FavouritesSignal.notify();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr('Removed from favourites', 'Imeondolewa kwa vipendwa'),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'Unable to remove favourite',
                'Imeshindikana kuondoa kipendwa',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Favourites remove error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Unable to remove favourite',
              'Imeshindikana kuondoa kipendwa',
            ),
          ),
        ),
      );
    }
  }

  // ============================================================
  // REMOVE CONFIRMATION (shared dialog)
  // ============================================================

  Future<bool> _confirmDialog({String? message}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: Text(
          _tr('Remove from favourites?', 'Ondoa kwa vipendwa?'),
          style: TextStyle(color: _bodyText),
        ),
        content: Text(
          message ??
              _tr(
                'Do you really want to remove from favourites?',
                'Je, kweli unataka kuondoa kwa vipendwa?',
              ),
          style: TextStyle(color: _mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Remove', 'Ondoa')),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _confirmRemove(String propertyId) async {
    if (await _confirmDialog()) {
      await removeFavourite(propertyId);
    }
  }

  // ============================================================
  // REMOVE A SAVED SERVICE
  // ============================================================

  Future<void> _confirmRemoveService(PropertyService service) async {
    final confirmed = await _confirmDialog(
      message: _tr(
        'Remove "${service.title}" from your saved services?',
        'Ondoa "${service.title}" kwenye huduma ulizohifadhi?',
      ),
    );

    if (!confirmed) return;

    try {
      await ServiceBookmarks.remove(service.id);

      if (!mounted) return;

      setState(() {
        _services.removeWhere((s) => s.id == service.id);
      });

      ServiceBookmarks.notify();

      _showSnack(
        _tr('Removed from favourites', 'Imeondolewa kwa vipendwa'),
      );
    } catch (e) {
      debugPrint('Saved service remove error: $e');
      _showSnack(
        _tr('Unable to remove favourite', 'Imeshindikana kuondoa kipendwa'),
      );
    }
  }

  // ============================================================
  // REMOVE A SAVED ROOMMATE REQUEST (NEW)
  // ============================================================

  Future<void> _confirmRemoveRoommate(RoommatePost post) async {
    final label = post.name.isEmpty
        ? _tr('this roommate request', 'ombi hili la mwenzi wa chumba')
        : _tr("${post.name}'s roommate request",
        'ombi la mwenzi wa chumba la ${post.name}');

    final confirmed = await _confirmDialog(
      message: _tr(
        'Remove $label from your saved roommate requests?',
        'Ondoa $label kwenye maombi uliyohifadhi?',
      ),
    );

    if (!confirmed) return;

    try {
      await FavouritesService.removeRoommateFavourite(post.id);

      if (!mounted) return;

      setState(() {
        _roommates.removeWhere((p) => p.id == post.id);
      });

      _showSnack(
        _tr('Removed from favourites', 'Imeondolewa kwa vipendwa'),
      );
    } catch (e) {
      debugPrint('Saved roommate remove error: $e');
      _showSnack(
        _tr('Unable to remove favourite', 'Imeshindikana kuondoa kipendwa'),
      );
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // OPEN PROPERTY DETAILS
  // ============================================================

  void _openPropertyDetails(Map<String, dynamic> property) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyDetailsPage(
          property: property,
          isAdminView: false,
          isTenantView: true,
        ),
      ),
    ).then((_) {
      // The favourite may have been removed on the details page.
      if (mounted) _loadFavourites(silent: true);
    });
  }

  // ============================================================
  // BUILD (mobile friendly)
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool showSearch = _onServicesTab
        ? _services.isNotEmpty
        : _onRoommatesTab
        ? _roommates.isNotEmpty
        : (_properties.isNotEmpty && !_selectionMode);

    final String searchHint = _onServicesTab
        ? _tr('e.g. cleaner Kisumu', 'mfano msafishaji Kisumu')
        : _onRoommatesTab
        ? _tr('Search by name, campus or area',
        'Tafuta kwa jina, chuo au eneo')
        : _tr('Search by name, area or county',
        'Tafuta kwa jina, eneo au kaunti');

    return Scaffold(
      backgroundColor: _scaffold,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: _appBarForeground,
        iconTheme: IconThemeData(color: _appBarForeground),
        actionsIconTheme: IconThemeData(color: _appBarForeground),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: _appBarForeground,
        ),
        elevation: 1,
        scrolledUnderElevation: 1,
        title: _selectionMode
            ? Text(
          '${_selectedIds.length} ${_tr('selected', 'zilizochaguliwa')}',
        )
            : Text(_tr('My Favourites', 'Vipendwa Vyangu')),
        leading: _selectionMode
            ? IconButton(
          icon: const Icon(Icons.close_rounded),
          color: _brand,
          onPressed: _exitSelectionMode,
          tooltip: _tr('Cancel selection', 'Ghairi uteuzi'),
        )
            : null,
        actions: _selectionMode
            ? [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed:
              _selectedIds.length >= 2 ? _openComparison : null,
              icon: Icon(
                Icons.compare_arrows_rounded,
                color:
                _selectedIds.length >= 2 ? _brand : _mutedText,
              ),
              label: Text(
                _tr('Compare', 'Linganisha'),
                style: TextStyle(
                  color:
                  _selectedIds.length >= 2 ? _brand : _mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ]
            : null,
        // ---------------- TABS ----------------
        bottom: TabBar(
          controller: _tabController,
          labelColor: _brand,
          unselectedLabelColor: _mutedText,
          indicatorColor: _brand,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle:
          const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 12.5),
          tabs: [
            Tab(
              child: Text(
                '${_tr('Properties', 'Mali')} (${_properties.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Tab(
              child: Text(
                '${_tr('Services', 'Huduma')} (${_services.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Tab(
              child: Text(
                '${_tr('Roommates', 'Wenzi')} (${_roommates.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ---------------- SEARCH BAR ----------------
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: searchHint,
                    prefixIcon: Icon(Icons.search_rounded, color: _brand),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                      icon:
                      Icon(Icons.close_rounded, color: _mutedText),
                      onPressed: _clearSearch,
                    ),
                    filled: true,
                    fillColor: _card,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _brand),
                    ),
                  ),
                  style: TextStyle(color: _bodyText, fontSize: 14.5),
                ),
              ),

            // ---------------- TAB CONTENT ----------------
            Expanded(
              child: _loading
                  ? Center(
                child: CircularProgressIndicator(color: _brand),
              )
                  : TabBarView(
                controller: _tabController,
                children: [
                  _propertiesTab(),
                  _servicesTab(),
                  _roommatesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PROPERTIES TAB
  // ============================================================

  Widget _propertiesTab() {
    final double width = MediaQuery.sizeOf(context).width;
    final int crossAxisCount = width >= 900
        ? 3
        : width >= 600
        ? 2
        : 1;

    final double imageHeight = crossAxisCount == 1 ? 150.0 : 160.0;
    final double mainAxisExtent = imageHeight +
        34 /* info padding */ +
        46 /* title + location + price block */ +
        60 /* buttons */;

    final visible = _filteredProperties;

    return RefreshIndicator(
      color: _brand,
      onRefresh: () => _loadFavourites(silent: true),
      child: _properties.isEmpty
          ? _emptyState()
          : visible.isEmpty
          ? _noSearchResults()
          : GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: mainAxisExtent,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          return _favouriteCard(visible[index]);
        },
      ),
    );
  }

  // ============================================================
  // SERVICES TAB - bookmarked providers
  // ============================================================

  Widget _servicesTab() {
    final visible = _filteredServices;

    return RefreshIndicator(
      color: _brand,
      onRefresh: () => _loadFavourites(silent: true),
      child: _services.isEmpty
          ? _emptyServicesState()
          : visible.isEmpty
          ? _noSearchResults()
          : ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          return _serviceCard(visible[index]);
        },
      ),
    );
  }

  Widget _serviceCard(PropertyService service) {
    final description = service.description.trim();
    final price = service.price.trim();

    return Card(
      color: _card,
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: service.adsVerified
              ? _brand.withValues(alpha: 0.55)
              : _cardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ServiceActions.categoryIcon(service.category),
                    color: _brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              service.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: _bodyText,
                              ),
                            ),
                          ),
                          if (service.adsVerified)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.verified,
                                  size: 16, color: _brand),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      _serviceInfoRow(
                        Icons.category_outlined,
                        service.category,
                      ),
                      _serviceInfoRow(
                        Icons.location_on_outlined,
                        service.location,
                      ),
                      if (price.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              Icon(Icons.payments_outlined,
                                  size: 14, color: _brand),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  price,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _brand,
                                  ),
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
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: _mutedText,
                ),
              ),
            ],
            const SizedBox(height: 12),

            // CONTACT BUTTONS - validated before opening.
            ServiceContactButtons(
              service: service,
              brand: _brand,
              tr: _tr,
              onMessage: _showSnack,
              compact: true,
            ),

            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _wordButton(
                label: _tr('Remove', 'Ondoa'),
                color: _isDark ? Colors.red.shade300 : Colors.red.shade700,
                onTap: () => _confirmRemoveService(service),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceInfoRow(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _mutedText),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: _mutedText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyServicesState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 80,
                    color: _isDark
                        ? const Color(0xFF54655B)
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _tr('No saved services yet',
                        'Hakuna huduma zilizohifadhiwa bado'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _bodyText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tr(
                      'Open the Services page and tap the bookmark icon on a provider to save it here.',
                      'Fungua ukurasa wa Huduma kisha gusa alama ya kuhifadhi kwenye mtoa huduma ili kumhifadhi hapa.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _mutedText),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ROOMMATES TAB (NEW) - saved roommate requests
  // ============================================================

  Widget _roommatesTab() {
    final visible = _filteredRoommates;

    return RefreshIndicator(
      color: _brand,
      onRefresh: () => _loadFavourites(silent: true),
      child: _roommates.isEmpty
          ? _emptyRoommatesState()
          : visible.isEmpty
          ? _noSearchResults()
          : ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          return _roommateCard(visible[index]);
        },
      ),
    );
  }

  String _periodLabel(String value) {
    switch (value) {
      case 'Per Month':
        return _tr('Per Month', 'Kwa Mwezi');
      case 'Per Semester':
        return _tr('Per Semester', 'Kwa Muhula');
      case 'Per Year':
        return _tr('Per Year', 'Kwa Mwaka');
      default:
        return value;
    }
  }

  String _genderLabel(String value) {
    switch (value) {
      case 'Male':
        return _tr('Male', 'Kiume');
      case 'Female':
        return _tr('Female', 'Kike');
      case 'Other':
        return _tr('Other', 'Nyingine');
      default:
        return value;
    }
  }

  String _roommateBudget(RoommatePost post) {
    if (post.budget.isEmpty) {
      return _tr('Budget not given', 'Bajeti haijatajwa');
    }

    final period = post.budgetPeriod.isEmpty
        ? ''
        : ' · ${_periodLabel(post.budgetPeriod)}';
    return 'KES ${post.budget}$period';
  }

  /// 0712345678 / +254712345678 / 254712345678 -> 254712345678
  String _internationalPhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('254')) return digits;
    if (digits.startsWith('0')) digits = digits.substring(1);

    return '254$digits';
  }

  Future<void> _callRoommate(String phone) async {
    try {
      final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
      if (!ok) {
        _showSnack(_tr('Unable to start the call.',
            'Imeshindikana kuanza simu.'));
      }
    } catch (_) {
      _showSnack(
          _tr('Unable to start the call.', 'Imeshindikana kuanza simu.'));
    }
  }

  Future<void> _whatsAppRoommate(String phone) async {
    try {
      final ok = await launchUrl(
        Uri.parse('https://wa.me/${_internationalPhone(phone)}'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        _showSnack(_tr('Unable to open WhatsApp.',
            'Imeshindikana kufungua WhatsApp.'));
      }
    } catch (_) {
      _showSnack(_tr(
          'Unable to open WhatsApp.', 'Imeshindikana kufungua WhatsApp.'));
    }
  }

  Widget _roommateInfoRow(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: _brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, color: _mutedText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roommateCard(RoommatePost post) {
    final hasPhone = post.phone.trim().isNotEmpty;
    final preferences = post.preferences.trim();

    return Card(
      color: _card,
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- NAME + SAVED HEART ----
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.people_alt_outlined, color: _brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    post.name.isEmpty
                        ? _tr('Roommate request', 'Ombi la mwenzi wa chumba')
                        : post.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: _bodyText,
                    ),
                  ),
                ),
                const Icon(Icons.favorite, color: Colors.red, size: 20),
              ],
            ),

            // ---- DETAILS (phone number is never shown) ----
            _roommateInfoRow(Icons.school_outlined, post.campus),
            _roommateInfoRow(Icons.home_work_outlined, post.hostelName),
            _roommateInfoRow(Icons.location_on_outlined, post.area),
            _roommateInfoRow(Icons.home_outlined, post.accommodationType),
            _roommateInfoRow(
              Icons.people_outline,
              post.gender.isEmpty ? '' : _genderLabel(post.gender),
            ),
            _roommateInfoRow(Icons.payments_outlined, _roommateBudget(post)),

            if (preferences.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                preferences,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: _mutedText,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ---- CALL / WHATSAPP ----
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                    hasPhone ? () => _callRoommate(post.phone) : null,
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(_tr('Call', 'Piga')),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasPhone
                        ? () => _whatsAppRoommate(post.phone)
                        : null,
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('WhatsApp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _wordButton(
                label: _tr('Remove', 'Ondoa'),
                color: _isDark ? Colors.red.shade300 : Colors.red.shade700,
                onTap: () => _confirmRemoveRoommate(post),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyRoommatesState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_alt_outlined,
                    size: 80,
                    color: _isDark
                        ? const Color(0xFF54655B)
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _tr('No saved roommate requests yet',
                        'Hakuna maombi ya wenzi yaliyohifadhiwa bado'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _bodyText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tr(
                      'Open the Roommate Finder and tap the heart on a request to save it here.',
                      'Fungua Mtafuta Mwenzi wa Chumba kisha gusa moyo kwenye ombi ili kulihifadhi hapa.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _mutedText),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // FAVOURITE CARD (mobile friendly)
  // ============================================================

  Widget _favouriteCard(Map<String, dynamic> property) {
    final String propertyId = _propertyIdOf(property);
    final String title = _titleOf(property);
    final String area = _areaOf(property);
    final String county = _countyOf(property);
    final String paymentCycle = _paymentCycleOf(property);
    final double price = _priceOf(property);

    final bool selected = _selectedIds.contains(propertyId);

    // IMAGES
    List<String> images = [];

    final dynamic rawImages =
        property['images'] ?? property['unitImages'] ?? property['imageUrls'];

    if (rawImages is List) {
      images = rawImages
          .map((image) => image.toString())
          .where((image) => image.isNotEmpty)
          .toList();
    }

    return Stack(
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          color: selected ? _brand.withValues(alpha: 0.06) : _card,
          elevation: 1.5,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? _brand : _cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: _selectionMode
                ? (propertyId.isEmpty
                ? null
                : () => _toggleSelection(propertyId))
                : () => _openPropertyDetails(property),
            onLongPress: _selectionMode || propertyId.isEmpty
                ? null
                : () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectionMode = true;
                _selectedIds.add(propertyId);
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // IMAGE
                LayoutBuilder(
                  builder: (context, constraints) {
                    final double imageHeight =
                    constraints.maxWidth < 260 ? 140 : 160;

                    return SizedBox(
                      height: imageHeight,
                      width: double.infinity,
                      child: images.isNotEmpty
                          ? Image.network(
                        images.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(),
                      )
                          : _placeholder(),
                    );
                  },
                ),

                // PROPERTY INFORMATION
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
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
                        const SizedBox(height: 3),
                        if (area.isNotEmpty || county.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: _mutedText,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  [area, county]
                                      .where((v) => v.isNotEmpty)
                                      .join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: _mutedText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'KES ${_formatPrice(price)} / $paymentCycle',
                            style: TextStyle(
                              color: _brand,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // VIEW + REMOVE BUTTONS
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _wordButton(
                          label: _tr('View', 'Angalia'),
                          color: _brand,
                          onTap: () => _openPropertyDetails(property),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _wordButton(
                          label: _tr('Remove', 'Ondoa'),
                          color: _isDark
                              ? Colors.red.shade300
                              : Colors.red.shade700,
                          onTap: propertyId.isEmpty
                              ? null
                              : () => _confirmRemove(propertyId),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // SELECTION CHECKBOX (top-right corner in selection mode)
        if (_selectionMode)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: selected ? _brand : Colors.white70,
              shape: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  selected ? Icons.check_rounded : Icons.circle_outlined,
                  size: 20,
                  color: selected
                      ? Colors.white
                      : (_isDark ? Colors.black54 : Colors.black38),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // WORD BUTTON
  // ============================================================

  Widget _wordButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // IMAGE PLACEHOLDER
  // ============================================================

  Widget _placeholder() {
    return Container(
      color: _isDark ? const Color(0xFF202B23) : const Color(0xFFEDF3EF),
      child: Center(
        child: Icon(
          Icons.home_work,
          size: 60,
          color: _isDark ? const Color(0xFF54655B) : Colors.grey.shade400,
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY STATE (scrollable so pull-to-refresh still works)
  // ============================================================

  Widget _emptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 80,
                    color: _isDark
                        ? const Color(0xFF54655B)
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _tr('No favourites yet', 'Hakuna vipendwa bado'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _bodyText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tr(
                      'Open a property and tap "Add to favourites" to save it here.',
                      'Fungua mali kisha gusa "Ongeza kwa vipendwa" ili kuihifadhi hapa.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _mutedText),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _openPropertySearch,
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.search_rounded),
                    label: Text(
                      _tr('Find Properties', 'Tafuta Mali'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openPropertySearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PropertySearchPage()),
    ).then((_) {
      if (mounted) _loadFavourites(silent: true);
    });
  }

  // ============================================================
  // NO SEARCH RESULTS
  // ============================================================

  Widget _noSearchResults() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 64,
                    color: _isDark
                        ? const Color(0xFF54655B)
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _tr(
                      'No favourites match your search',
                      'Hakuna kipendwa kinacholingana na utafutaji',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _bodyText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      'Try different words, a different area or county.',
                      'Jaribu maneno mengine, eneo au kaunti nyingine.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _mutedText),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _clearSearch,
                    child: Text(
                      _tr('Clear search', 'Futa utafutaji'),
                      style: TextStyle(
                        color: _brand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================
// COMPARISON DIALOG
// ==============================================================

class _ComparisonDialog extends StatelessWidget {
  const _ComparisonDialog({
    required this.properties,
    required this.isDark,
    required this.brand,
    required this.card,
    required this.bodyText,
    required this.mutedText,
    required this.cardBorder,
    required this.tr,
  });

  final List<Map<String, dynamic>> properties;
  final bool isDark;
  final Color brand;
  final Color card;
  final Color bodyText;
  final Color mutedText;
  final Color cardBorder;

  /// Translation callback from the page.
  final String Function(String en, String sw) tr;

  String _formatPrice(double price) {
    final whole = price.toStringAsFixed(0);
    final regex = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return whole.replaceAllMapped(regex, (match) => ',');
  }

  String _cycleOf(Map<String, dynamic> p) =>
      p['paymentCycle']?.toString() ?? p['paymentPeriod']?.toString() ?? 'month';

  double _priceOf(Map<String, dynamic> p) {
    final raw = p['price'];
    if (raw is num) return raw.toDouble();
    if (raw != null) return double.tryParse(raw.toString()) ?? 0;
    return 0;
  }

  String _roomTypeOf(Map<String, dynamic> p) {
    for (final key in [
      'roomType',
      'unitType',
      'subtype',
      'propertyType',
      'bedrooms',
    ]) {
      final value = p[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '—';
  }

  List<String> _amenitiesOf(Map<String, dynamic> p) {
    for (final key in ['amenities', 'features', 'facilities']) {
      final value = p[key];
      if (value is List) {
        return value
            .map((a) => a.toString())
            .where((a) => a.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, List<String>>>[
      MapEntry(
        tr('Rent', 'Kodi'),
        properties
            .map((p) => 'KES ${_formatPrice(_priceOf(p))} / ${_cycleOf(p)}')
            .toList(),
      ),
      MapEntry(
        tr('Location', 'Eneo'),
        properties.map((p) {
          final area =
              p['area']?.toString() ?? p['subcounty']?.toString() ?? '';
          final county = p['county']?.toString() ?? '';
          final location =
          [area, county].where((v) => v.isNotEmpty).join(', ');
          return location.isEmpty ? '—' : location;
        }).toList(),
      ),
      MapEntry(
        tr('Room type', 'Aina ya chumba'),
        properties.map((p) => _roomTypeOf(p)).toList(),
      ),
      MapEntry(
        tr('Amenities', 'Vifaa'),
        properties.map((p) {
          final amenities = _amenitiesOf(p);
          return amenities.isEmpty ? '—' : amenities.join(', ');
        }).toList(),
      ),
    ];

    return Dialog(
      backgroundColor: card,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows_rounded, color: brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('Compare Properties', 'Linganisha Mali'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: brand,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: mutedText),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollable comparison table
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // Property titles header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(width: 86),
                        for (final p in properties) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: brand.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                p['title']?.toString() ??
                                    tr('Untitled', 'Isiyo na Jina'),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: brand,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Comparison rows
                    for (final row in rows) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 86,
                            child: Padding(
                              padding:
                              const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                row.key,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: mutedText,
                                ),
                              ),
                            ),
                          ),
                          for (final value in row.value) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                margin:
                                const EdgeInsets.symmetric(vertical: 2),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : Colors.black.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: cardBorder),
                                ),
                                child: Text(
                                  value,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: bodyText,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Done', 'Nimemaliza')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}