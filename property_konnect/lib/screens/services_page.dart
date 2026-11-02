// ============================================================
// services_page.dart  (FULL UPDATED FILE)
//
// NEW in this version
//  1. REPORT BUTTON on the service details sheet (shown to
//     everyone EXCEPT the device that posted the service).
//     - Reason picker (5 EN/SW reasons, RadioGroup — no
//       deprecated groupValue/onChanged params).
//     - Writes to the shared `reports` collection with the
//       UNIFIED shape used across the app: doc id
//       `property_service_{serviceId}_{deviceId}` and fields
//       kind 'property_service', targetCollection
//       'property_services', targetId, targetName, targetOwnerId,
//       reason, details (optional), deviceId, reporterId,
//       status 'open', createdAt. One device can report a
//       service only ONCE (doc id dedupes).
//     - Best-effort `reportCount` increment on the post itself
//       (kept in its own try block — if the Firestore rules
//       deny it, the report itself is still saved).
//
// PREVIOUS FEATURES KEPT
//  1. CATEGORY CHIPS above the location filter — one tap finds
//     cleaners, movers, plumbers, agents, etc. (no typing).
//  2. CONTACT BUTTONS on the service details: Call, WhatsApp,
//     Email and Open link. The phone number and email are NOT
//     shown as text — only the buttons. Every phone / email /
//     link is VALIDATED before it is opened.
//  3. SERVICE LINK IS OPTIONAL (but must be a valid web link
//     when entered).
//  4. BOOKMARKS: tap the bookmark icon on a card / details to
//     save a provider; open the bookmark icon in the app bar to
//     see them on the Favourites page (Services tab).
//  5. EDIT YOUR POST: the original poster can update title,
//     category, location, description, price, phone, email and
//     link without deleting and reposting. Edit / Delete buttons
//     are visible ONLY on the device that posted it.
//  6. SECURE OWNERSHIP WITHOUT SIGN-IN: no account is needed to
//     use this page AT ALL. Every post stores the DEVICE ID of
//     the poster in `userId`. Edit / delete permission is
//     granted only when this device's ID equals the post's
//     userId (and Firestore Security Rules enforce the same
//     match on the server). There is no sign-in flow here.
//  7. MULTI-TERM SEARCH: "cleaner Kisumu" matches both words even
//     when they are in different fields.
//  8. PAGINATION: posts load 15 at a time ("Load more"), plus a
//     small separate query keeps Ads-Verified posts on top.
//  9. BETTER CARDS: category, location, price (if any), short
//     description, Call shortcut, bookmark.
// 10. PULL TO REFRESH.
// 11. AUTO-DISMISSING SNACKBARS: every message disappears by
//     itself after a few seconds — nothing stays stuck on
//     screen.
//
// Needs the file service_actions.dart and `url_launcher` in
// pubspec.yaml.
// ============================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'favourites_page.dart';
import 'post_helpers.dart';
import 'service_actions.dart';

// Provides DeviceIdService — the stable per-device identifier
// used as the poster id (no sign-in anywhere on this page).
import 'property_details_page.dart' show DeviceIdService;

// PropertyService now lives in service_actions.dart; re-exported
// here so existing imports of services_page.dart keep working.
export 'service_actions.dart' show PropertyService;

// ============================================================
// PAGE
// ============================================================

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  String _selectedLocation = 'All locations';
  String _selectedCategory = 'All';
  String _searchText = '';

  // ------------------------------------------------------------
  // PAGINATION + LIVE DATA
  // ------------------------------------------------------------
  static const int _pageSize = 15;
  int _limit = _pageSize;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _recentSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _verifiedSub;

  List<PropertyService> _recent = [];
  List<PropertyService> _verified = [];

  bool _recentLoaded = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  String? _error;
  Completer<void>? _refreshCompleter;

  // ------------------------------------------------------------
  // POSTER ID (device id, cached) — replaces sign-in entirely.
  // Every post stores this id in `userId`; only the device that
  // created a post can edit / delete it.
  // ------------------------------------------------------------
  String _posterId = '';

  // ------------------------------------------------------------
  // BOOKMARKS (ids of saved services on this device)
  // ------------------------------------------------------------
  final ValueNotifier<Set<String>> _bookmarks =
  ValueNotifier<Set<String>>(<String>{});

  static const String _otherCategory = 'Other';

  static const List<String> _categories = [
    'Moving & Transport',
    'Cleaning Services',
    'Painting & Decor',
    'Plumbing & Electrical',
    'Furniture & Appliances',
    'Internet & TV Installation',
    'Security & CCTV',
    'House Hunting & Agents',
    'Legal & Documentation',
    'Repairs & Maintenance',
    _otherCategory,
  ];

  static const Map<String, String> _categorySw = {
    'Moving & Transport': 'Uhamishaji na Usafiri',
    'Cleaning Services': 'Huduma za Usafi',
    'Painting & Decor': 'Upakaji Rangi na Mapambo',
    'Plumbing & Electrical': 'Mabomba na Umeme',
    'Furniture & Appliances': 'Samani na Vifaa',
    'Internet & TV Installation': 'Intaneti na TV',
    'Security & CCTV': 'Usalama na CCTV',
    'House Hunting & Agents': 'Utafutaji Nyumba na Mawakala',
    'Legal & Documentation': 'Sheria na Nyaraka',
    'Repairs & Maintenance': 'Ukarabati na Matengenezo',
    _otherCategory: 'Nyingine',
  };

  // ------------------------------------------------------------
  // REPORT REASONS (EN, SW) — used by the Report button on the
  // service details sheet.
  // ------------------------------------------------------------
  static const List<(String, String)> _kReportReasons = [
    ('Scam or fraud', 'Udanganyifu'),
    ('Wrong or fake contact details', 'Maelezo ya mawasiliano si sahihi'),
    ('Inappropriate content', 'Maudhui yasiyofaa'),
    ('Spam or duplicate post', 'Tangazo la mara kwa mara'),
    ('Other', 'Sababu nyingine'),
  ];

  bool get _isDark => AppSettings.of(context).isDark;
  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;
  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;
  Color get _borderColor =>
      _isDark ? const Color(0xFF2A3A2F) : Colors.grey.shade200;
  Color get _subtle =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: .68);

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  String _categoryLabel(String category) {
    if (AppSettings.of(context).languageCode == 'sw') {
      return _categorySw[category] ?? category;
    }
    return category;
  }

  String? _required(String? v) => validateRequired(context, v);
  String? _phone(String? v) => validatePhone(context, v);
  String? _email(String? v) => validateEmail(context, v);

  // ------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadPosterId();
    _listenRecent();
    _listenVerified();
    _loadBookmarks();
    ServiceBookmarks.changes.addListener(_loadBookmarks);
  }

  @override
  void dispose() {
    ServiceBookmarks.changes.removeListener(_loadBookmarks);
    _recentSub?.cancel();
    _verifiedSub?.cancel();
    _searchController.dispose();
    _bookmarks.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // POSTER ID — fetched once, cached for the session.
  // ------------------------------------------------------------

  Future<void> _loadPosterId() async {
    try {
      final id = await DeviceIdService.get();
      if (mounted) _posterId = id;
    } catch (e) {
      debugPrint('Poster id load error: $e');
    }
  }

  // ------------------------------------------------------------
  // DATA — paginated stream of the newest posts, plus a small
  // separate stream of Ads-Verified posts so they always stay on
  // top, even if they are older than the loaded page.
  // ------------------------------------------------------------

  void _completeRefresh() {
    final completer = _refreshCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    _refreshCompleter = null;
  }

  void _listenRecent() {
    _recentSub?.cancel();

    final limit = _limit;

    _recentSub = _firestore
        .collection('property_services')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .listen(
          (snapshot) {
        if (!mounted) return;

        setState(() {
          _recent =
              snapshot.docs.map(PropertyService.fromFirestore).toList();
          _hasMore = snapshot.docs.length >= limit;
          _recentLoaded = true;
          _loadingMore = false;
          _error = null;
        });

        _completeRefresh();
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _error = error.toString();
          _recentLoaded = true;
          _loadingMore = false;
        });

        _completeRefresh();
      },
    );
  }

  void _listenVerified() {
    _verifiedSub?.cancel();

    _verifiedSub = _firestore
        .collection('property_services')
        .where('adsVerified', isEqualTo: true)
        .limit(50)
        .snapshots()
        .listen(
          (snapshot) {
        if (!mounted) return;

        final list =
        snapshot.docs.map(PropertyService.fromFirestore).toList()
          ..sort((a, b) {
            final aTime = a.createdAt;
            final bTime = b.createdAt;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

        setState(() => _verified = list);
      },
      // The verified list is a bonus — ignore its errors.
      onError: (Object _) {},
    );
  }

  void _loadMore() {
    if (_loadingMore) return;

    setState(() {
      _loadingMore = true;
      _limit += _pageSize;
    });

    _listenRecent();
  }

  /// Pull to refresh: back to the first page and re-read.
  Future<void> _refresh() async {
    _limit = _pageSize;
    _refreshCompleter = Completer<void>();

    _listenRecent();
    _listenVerified();
    _loadBookmarks();

    await _refreshCompleter?.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
  }

  /// Verified posts first, then the newest posts. Duplicates are
  /// removed.
  List<PropertyService> get _merged {
    final seen = <String>{};
    final all = <PropertyService>[];

    for (final service in [..._verified, ..._recent]) {
      if (seen.add(service.id)) all.add(service);
    }

    return [
      ...all.where((s) => s.adsVerified),
      ...all.where((s) => !s.adsVerified),
    ];
  }

  // ------------------------------------------------------------
  // BOOKMARKS
  // ------------------------------------------------------------

  Future<void> _loadBookmarks() async {
    final ids = await ServiceBookmarks.loadIds();
    if (!mounted) return;
    _bookmarks.value = ids;
  }

  Future<void> _toggleBookmark(PropertyService service) async {
    final wasSaved = _bookmarks.value.contains(service.id);

    // Optimistic update.
    final updated = {..._bookmarks.value};
    if (wasSaved) {
      updated.remove(service.id);
    } else {
      updated.add(service.id);
    }
    _bookmarks.value = updated;

    try {
      if (wasSaved) {
        await ServiceBookmarks.remove(service.id);
      } else {
        await ServiceBookmarks.add(service.id);
      }

      if (!mounted) return;

      _showMessage(
        wasSaved
            ? _tr('Removed from favourites.', 'Imeondolewa kwa vipendwa.')
            : _tr('Saved to favourites.', 'Imehifadhiwa kwa vipendwa.'),
        actionLabel: wasSaved ? null : _tr('View', 'Angalia'),
        onAction: wasSaved ? null : _openFavourites,
        duration: const Duration(seconds: 4),
      );
    } catch (_) {
      // Revert.
      final reverted = {..._bookmarks.value};
      if (wasSaved) {
        reverted.add(service.id);
      } else {
        reverted.remove(service.id);
      }
      _bookmarks.value = reverted;

      _showMessage(_tr('Could not update favourites. Please try again.',
          'Imeshindikana kusasisha vipendwa. Tafadhali jaribu tena.'));
    }
  }

  void _openFavourites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavouritesPage(initialTab: 1)),
    ).then((_) {
      if (mounted) _loadBookmarks();
    });
  }

  Widget _bookmarkButton(PropertyService service, {double size = 24}) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _bookmarks,
      builder: (context, saved, _) {
        final isSaved = saved.contains(service.id);

        return IconButton(
          tooltip: isSaved
              ? _tr('Remove from favourites', 'Ondoa kwa vipendwa')
              : _tr('Save to favourites', 'Hifadhi kwa vipendwa'),
          visualDensity: VisualDensity.compact,
          onPressed: () => _toggleBookmark(service),
          icon: Icon(
            isSaved ? Icons.bookmark : Icons.bookmark_border,
            color: _brand,
            size: size,
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // OWNERSHIP — NO SIGN-IN. The post's `userId` stores the
  // DEVICE ID of the device that created it. Only that device
  // can edit / delete (and Firestore Security Rules enforce the
  // same match on the server).
  // ------------------------------------------------------------

  bool _isPoster(PropertyService service) {
    if (_posterId.isEmpty) return false;
    return service.userId.isNotEmpty && _posterId == service.userId;
  }

  // ------------------------------------------------------------
  // REPORT A SERVICE — shown to everyone EXCEPT the poster.
  //
  // The report goes to the shared `reports` collection with
  // the UNIFIED shape used across the app: doc id
  // `property_service_{serviceId}_{deviceId}` and fields
  // kind 'property_service', targetCollection 'property_services',
  // targetId, targetName, targetOwnerId, reason, details,
  // deviceId, reporterId, status 'open', createdAt — so one
  // device can report a service only once and the admin Manage
  // Reports page can filter it under "Services".
  // ------------------------------------------------------------

  Future<void> _reportService(PropertyService service) async {
    if (_posterId.isEmpty) {
      await _loadPosterId();
    }

    if (_posterId.isEmpty) {
      _showMessage(_tr('Could not identify this device. Please try again.',
          'Imeshindikana kutambua kifaa hiki. Tafadhali jaribu tena.'));
      return;
    }

    final reports = _firestore.collection('reports');
    // UPDATED: unified doc id — property_service_<targetId>_<deviceId>.
    // One device can report a service only ONCE — the doc id dedupes.
    final reportId = 'property_service_${service.id}_$_posterId';

    // One report per device per service (best effort — if the
    // read is denied by rules, the write below still dedupes by
    // the same doc id).
    try {
      final existing = await reports.doc(reportId).get();
      if (existing.exists) {
        if (!mounted) return;
        _showMessage(_tr('You have already reported this service.',
            'Umesharipoti huduma hii.'));
        return;
      }
    } catch (_) {}

    final result = await _chooseReportReason();
    if (result == null || !mounted) return;

    try {
      // UPDATED: unified report shape — same fields the rest of
      // the app writes to the shared `reports` collection
      // (kind, targetCollection, targetId, targetName,
      // targetOwnerId, reason, details, deviceId, reporterId,
      // status 'open', createdAt).
      await reports.doc(reportId).set({
        'kind': 'property_service',
        'targetCollection': 'property_services',
        'targetId': service.id,
        'targetName': service.title,
        'targetOwnerId': service.userId,
        'reason': result.reason,
        'details': result.details,
        'deviceId': _posterId,
        'reporterId': _posterId,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      _showMessage(
        e.code == 'permission-denied'
            ? _tr('You are not allowed to report right now.',
            'Huruhusiwi kuripoti kwa sasa.')
            : _tr('Could not send the report. Please try again.',
            'Imeshindikana kutuma ripoti. Tafadhali jaribu tena.'),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      _showMessage(_tr('Could not send the report. Please try again.',
          'Imeshindikana kutuma ripoti. Tafadhali jaribu tena.'));
      return;
    }

    // Best-effort report counter on the post itself (kept in its
    // own try block — if the rules deny it, the report saved
    // above is unaffected).
    try {
      await _firestore.collection('property_services').doc(service.id).set(
        {'reportCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
    } catch (_) {}

    if (!mounted) return;
    _showMessage(
      _tr('Report submitted. Our team will review it.',
          'Ripoti imetumwa. Timu yetu itaipitia.'),
      duration: const Duration(seconds: 4),
    );
  }

  /// Reason picker + optional details for the Report button
  /// (RadioGroup — no deprecated groupValue/onChanged parameters).
  Future<({String reason, String details})?> _chooseReportReason() {
    String selected = _kReportReasons.first.$1;
    final detailsController = TextEditingController();

    return showDialog<({String reason, String details})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: Icon(Icons.flag_outlined,
              color: Colors.orange.shade700, size: 32),
          title: Text(
            _tr('Why are you reporting this service?',
                'Kwa nini unaripoti huduma hii?'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (value) =>
                      setDialogState(() => selected = value ?? selected),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (en, sw) in _kReportReasons)
                        RadioListTile<String>(
                          value: en,
                          title: Text(_tr(en, sw)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsController,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'More details (optional)',
                      'Maelezo zaidi (si lazima)',
                    ),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('Cancel', 'Ghairi')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _brand),
              onPressed: () => Navigator.pop(
                dialogContext,
                (
                reason: selected,
                details: detailsController.text.trim(),
                ),
              ),
              child: Text(_tr('Submit', 'Tuma')),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr('Services', 'Huduma'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: _tr('Saved services', 'Huduma zilizohifadhiwa'),
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: _openFavourites,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        onPressed: () => _showServiceForm(),
        icon: const Icon(Icons.add),
        label: Text(_tr('Post Service', 'Posti Huduma')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_recentLoaded) {
      return Center(child: CircularProgressIndicator(color: _brand));
    }

    if (_error != null && _recent.isEmpty && _verified.isEmpty) {
      return _buildErrorState(_error!);
    }

    return RefreshIndicator(
      color: _brand,
      onRefresh: _refresh,
      child: _buildContent(_merged),
    );
  }

  Widget _buildContent(List<PropertyService> services) {
    final locations = _getLocations(services);
    final filtered = _filterServices(services);
    final filtersActive = _selectedCategory != 'All' ||
        _selectedLocation != 'All locations' ||
        _searchText.isNotEmpty;

    return ListView(
      // Needed so pull-to-refresh works even with short lists.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildHero(),
        const SizedBox(height: 16),
        _buildSearch(),
        const SizedBox(height: 12),
        // CATEGORY CHIPS — above the location filter.
        _buildCategoryChips(),
        const SizedBox(height: 12),
        _buildLocationFilter(locations),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _tr('Services', 'Huduma'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${filtered.length}',
              style: TextStyle(color: _brand, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          _buildEmptyState()
        else
          for (final service in filtered) _buildServiceCard(service),

        // ---- PAGINATION ----
        if (filtersActive && _hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              _tr(
                'Results come from the latest ${_recent.length} posts. Load more to search further back.',
                'Matokeo yanatoka kwenye machapisho ${_recent.length} ya hivi karibuni. Pakia zaidi kutafuta nyuma zaidi.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtle, fontSize: 12),
            ),
          ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              onPressed: _loadingMore ? null : _loadMore,
              icon: _loadingMore
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.expand_more),
              label: Text(_tr('Load more services', 'Pakia huduma zaidi')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: BorderSide(color: _brand),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isDark
              ? const [Color(0xFF0E3D2A), Color(0xFF126B45)]
              : const [kBrandGreen, Color(0xFF2E9E6B)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.home_repair_service_rounded,
            color: Colors.white,
            size: 38,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Services for Your New Home',
                      'Huduma kwa Nyumba Yako Mpya'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _tr(
                    'Find movers, cleaners, repairs and more, or post a service for other property seekers. No account needed to browse.',
                    'Pata wahamishaji, wasafishaji, ukarabati na zaidi, au posti huduma kwa watafuta mali wengine. Huhitaji akaunti kutazama.',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _searchText = value.trim()),
      decoration: InputDecoration(
        hintText: _tr('e.g. cleaner Kisumu', 'mfano msafishaji Kisumu'),
        prefixIcon: Icon(Icons.search, color: _brand),
        suffixIcon: _searchText.isEmpty
            ? null
            : IconButton(
          tooltip: _tr('Clear', 'Futa'),
          onPressed: () {
            _searchController.clear();
            setState(() => _searchText = '');
          },
          icon: const Icon(Icons.clear),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _brand, width: 1.6),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // CATEGORY CHIPS
  // ------------------------------------------------------------

  Widget _buildCategoryChips() {
    final options = ['All', ..._categories];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = options[index];
          final selected = _selectedCategory == category;

          return ChoiceChip(
            avatar: Icon(
              category == 'All'
                  ? Icons.apps_rounded
                  : ServiceActions.categoryIcon(category),
              size: 16,
              color: selected ? Colors.white : _brand,
            ),
            label: Text(
              category == 'All'
                  ? _tr('All', 'Zote')
                  : _categoryLabel(category),
            ),
            selected: selected,
            showCheckmark: false,
            selectedColor: _brand,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : null,
            ),
            side: BorderSide(color: selected ? _brand : _borderColor),
            onSelected: (_) => setState(() => _selectedCategory = category),
          );
        },
      ),
    );
  }

  Widget _buildLocationFilter(List<String> locations) {
    final options = ['All locations', ...locations];

    if (!options.contains(_selectedLocation)) {
      _selectedLocation = 'All locations';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.location_on_outlined, color: _brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('${_selectedLocation}_${options.length}'),
              initialValue: _selectedLocation,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _tr('Location', 'Mahali'),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              items: options
                  .map(
                    (location) => DropdownMenuItem<String>(
                  value: location,
                  child: Text(
                    location == 'All locations'
                        ? _tr('All locations', 'Maeneo yote')
                        : location,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedLocation = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _subtle),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _subtle, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brand.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _brand),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _brand,
            ),
          ),
        ],
      ),
    );
  }

  /// Green badge shown on admin-verified posts.
  Widget _verifiedBadge() =>
      _badge(Icons.verified, _tr('Ads Verified', 'Imethibitishwa'));

  Widget _yourPostBadge() =>
      _badge(Icons.phone_android_outlined,
          _tr('Your post', 'Chapisho lako'));

  // ------------------------------------------------------------
  // SERVICE CARD — category, location, price (if any), short
  // description, Call shortcut, bookmark.
  // ------------------------------------------------------------

  Widget _buildServiceCard(PropertyService service) {
    final isPoster = _isPoster(service);
    final hasPhone = service.contact.trim().isNotEmpty;
    final hasPrice = service.price.trim().isNotEmpty;
    final description = service.description.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: service.adsVerified
              ? _brand.withValues(alpha: .55)
              : _borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: .12),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        if (service.adsVerified)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child:
                            Icon(Icons.verified, size: 16, color: _brand),
                          ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    _infoRow(
                      Icons.category_outlined,
                      _categoryLabel(service.category),
                    ),
                    _infoRow(Icons.location_on_outlined, service.location),
                    if (hasPrice)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.payments_outlined,
                                size: 14, color: _brand),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                service.price.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _brand,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _bookmarkButton(service),
            ],
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 8),
              child: Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _subtle, fontSize: 13, height: 1.4),
              ),
            ),
          if (service.adsVerified || isPoster)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (service.adsVerified) _verifiedBadge(),
                  if (isPoster) _yourPostBadge(),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                // CONTACT SHORTCUT — validates the number first.
                if (hasPhone)
                  OutlinedButton.icon(
                    onPressed: () => ServiceActions.call(
                      service.contact,
                      tr: _tr,
                      onMessage: _showMessage,
                    ),
                    icon: const Icon(Icons.call_outlined, size: 17),
                    label: Text(_tr('Call', 'Piga simu')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brand,
                      side: BorderSide(color: _brand),
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showServiceDetails(service),
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: Text(_tr('View', 'Angalia')),
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // SERVICE DETAILS — contact BUTTONS only (no phone / email text)
  // ------------------------------------------------------------

  Future<void> _showServiceDetails(PropertyService service) async {
    final isPoster = _isPoster(service);
    String? sheetMessage;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 700),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: .4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              service.title,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _bookmarkButton(service),
                          IconButton(
                            tooltip: _tr('Close', 'Funga'),
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      if (service.adsVerified || isPoster) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (service.adsVerified) _verifiedBadge(),
                            if (isPoster) _yourPostBadge(),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      _detailRow(
                        Icons.category_outlined,
                        _tr('Category', 'Aina ya huduma'),
                        _categoryLabel(service.category),
                      ),
                      _detailRow(
                        Icons.location_on_outlined,
                        _tr('Location', 'Mahali'),
                        service.location,
                      ),
                      if (service.price.trim().isNotEmpty)
                        _detailRow(
                          Icons.payments_outlined,
                          _tr('Price', 'Bei'),
                          service.price.trim(),
                        ),
                      if (service.postedBy.trim().isNotEmpty)
                        _detailRow(
                          Icons.person_outline,
                          _tr('Posted by', 'Iliwekwa na'),
                          service.postedBy,
                        ),
                      const SizedBox(height: 4),

                      // ---- CONTACT BUTTONS ----
                      Text(
                        _tr('Contact this provider', 'Wasiliana na mtoa huduma'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ServiceContactButtons(
                        service: service,
                        brand: _brand,
                        tr: _tr,
                        onMessage: (message) =>
                            setSheetState(() => sheetMessage = message),
                      ),
                      if (sheetMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            sheetMessage!,
                            style: TextStyle(
                              color: _isDark
                                  ? Colors.red.shade300
                                  : Colors.red.shade700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),
                      Text(
                        _tr('Service Details', 'Maelezo ya Huduma'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _brand.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          service.description.trim().isEmpty
                              ? _tr('No additional details were provided.',
                              'Hakuna maelezo ya ziada yaliyowekwa.')
                              : service.description,
                          style: const TextStyle(height: 1.5, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(),
                              child: Text(_tr('Close', 'Funga')),
                            ),
                          ),
                          // EDIT + DELETE — visible ONLY on the
                          // device that posted the service.
                          if (isPoster) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _brand,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  _showServiceForm(existing: service);
                                },
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(_tr('Edit', 'Hariri')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  _confirmDeleteService(service);
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: Text(_tr('Delete', 'Futa')),
                              ),
                            ),
                          ],
                        ],
                      ),

                      // ---- REPORT (non-posters only) ----
                      if (!isPoster) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade700,
                              side: BorderSide(
                                  color: Colors.orange.shade700),
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _reportService(service);
                            },
                            icon: const Icon(Icons.flag_outlined),
                            label: Text(_tr(
                                'Report this service',
                                'Ripoti huduma hii')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: _brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: _subtle)),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // POST / EDIT FORM
  //
  //  existing == null -> "Post a Service"
  //  existing != null -> "Edit Service" (posting device only)
  //
  // NO SIGN-IN ANYWHERE: the post's `userId` stores the DEVICE
  // ID. The service link is OPTIONAL. There is NO 4-digit delete
  // code: ownership is enforced by matching device ids (and
  // Firestore Security Rules enforce the same on the server).
  // ------------------------------------------------------------

  Future<void> _showServiceForm({PropertyService? existing}) async {
    final editing = existing != null;

    if (editing && !_isPoster(existing)) {
      _showMessage(_tr(
          'Only the device that posted this service can edit it.',
          'Kifaa kilichoweka huduma hii pekee ndicho kinaweza kuihariri.'));
      return;
    }

    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: existing?.title);
    final otherCategoryController = TextEditingController();
    final locationController = TextEditingController(text: existing?.location);
    final descriptionController =
    TextEditingController(text: existing?.description);
    final priceController = TextEditingController(text: existing?.price);
    final phoneController = TextEditingController(text: existing?.contact);
    final emailController = TextEditingController(text: existing?.email);
    final nameController = TextEditingController();
    final linkController = TextEditingController(text: existing?.serviceLink);

    String category = _categories.first;

    if (existing != null) {
      final known = _categories.contains(existing.category) &&
          existing.category != _otherCategory;

      if (known) {
        category = existing.category;
      } else {
        category = _otherCategory;
        otherCategoryController.text = existing.category;
      }
    }

    String? formError;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    editing
                        ? Icons.edit_outlined
                        : Icons.add_business_outlined,
                    color: _brand,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      editing
                          ? _tr('Edit Service', 'Hariri Huduma')
                          : _tr('Post a Service', 'Posti Huduma'),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        postTextField(
                          controller: titleController,
                          label: _tr('Service title', 'Jina la huduma'),
                          hint: _tr('e.g. Reliable house movers',
                              'mfano Wahamishaji wa nyumba wa kuaminika'),
                          icon: Icons.title,
                          capitalization: TextCapitalization.sentences,
                          validator: _required,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<String>(
                            initialValue: category,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _tr('Category', 'Aina ya huduma'),
                              prefixIcon: const Icon(Icons.category_outlined),
                            ),
                            items: _categories
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(_categoryLabel(item)),
                              ),
                            )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => category = value);
                              }
                            },
                          ),
                        ),
                        if (category == _otherCategory)
                          postTextField(
                            controller: otherCategoryController,
                            label: _tr('Type the category',
                                'Andika aina ya huduma'),
                            hint: _tr('e.g. Gardening',
                                'mfano Bustani na Kilimo'),
                            icon: Icons.edit_outlined,
                            capitalization: TextCapitalization.sentences,
                            validator: _required,
                          ),
                        postTextField(
                          controller: locationController,
                          label: _tr('Location', 'Mahali'),
                          hint: _tr('County / town / estate, e.g. Kisumu',
                              'Kaunti / mji / mtaa, mfano Kisumu'),
                          icon: Icons.location_on_outlined,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: descriptionController,
                          label: _tr('Service details', 'Maelezo ya huduma'),
                          hint: _tr(
                            'Explain the service, availability, prices or anything clients should know.',
                            'Eleza huduma, upatikanaji, bei au jambo lolote ambalo wateja wanapaswa kujua.',
                          ),
                          hintMaxLines: 3,
                          icon: Icons.notes_outlined,
                          capitalization: TextCapitalization.sentences,
                          maxLines: 4,
                          validator: _required,
                        ),
                        postTextField(
                          controller: priceController,
                          label: _tr('Price (optional)', 'Bei (si lazima)'),
                          hint: _tr('e.g. From KES 1,500 per trip',
                              'mfano Kuanzia KES 1,500 kwa safari'),
                          icon: Icons.payments_outlined,
                          capitalization: TextCapitalization.sentences,
                          validator: (value) =>
                          (value ?? '').trim().length > 80
                              ? _tr('Keep the price under 80 characters.',
                              'Weka bei isiyozidi herufi 80.')
                              : null,
                        ),
                        postTextField(
                          controller: phoneController,
                          label: _tr('Phone number', 'Nambari ya simu'),
                          helper: _tr(
                            'Not shown publicly. Used for the Call and WhatsApp buttons.',
                            'Haionyeshwi hadharani. Hutumika kwa vitufe vya Piga simu na WhatsApp.',
                          ),
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          digitsOnly: true,
                          validator: (value) {
                            final base = _phone(value);
                            if (base != null) return base;
                            return ServiceActions.isValidPhone(value ?? '')
                                ? null
                                : _tr('Enter a valid Kenyan phone number.',
                                'Weka nambari sahihi ya simu ya Kenya.');
                          },
                        ),
                        postTextField(
                          controller: emailController,
                          label: _tr('Email (optional)', 'Barua pepe (si lazima)'),
                          helper: _tr(
                            'Not shown publicly. Used for the Email button.',
                            'Haionyeshwi hadharani. Hutumika kwa kitufe cha Barua pepe.',
                          ),
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _email,
                        ),
                        if (!editing)
                          postTextField(
                            controller: nameController,
                            label: _tr('Your name', 'Jina lako'),
                            icon: Icons.person_outline,
                            capitalization: TextCapitalization.words,
                            validator: _required,
                          ),
                        postTextField(
                          controller: linkController,
                          label: _tr('Service link (optional)',
                              'Kiungo cha huduma (si lazima)'),
                          hint: _tr(
                            'WhatsApp group / Telegram group / website link',
                            'Kiungo cha kundi la WhatsApp / Telegram / tovuti',
                          ),
                          hintMaxLines: 2,
                          icon: Icons.link,
                          keyboardType: TextInputType.url,
                          validator: (value) =>
                              ServiceActions.validateOptionalLink(
                                  value, _tr),
                        ),
                        if (formError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              formError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(_tr('Cancel', 'Ghairi')),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                    if (!formKey.currentState!.validate()) {
                      setDialogState(() {
                        formError = _tr(
                          'Please fill in every required field correctly.',
                          'Tafadhali jaza kila sehemu muhimu ipasavyo.',
                        );
                      });
                      return;
                    }

                    setDialogState(() {
                      formError = null;
                      saving = true;
                    });

                    final linkText = linkController.text.trim();
                    final link = linkText.isEmpty
                        ? ''
                        : ServiceActions.normalizeLink(linkText)
                        .toString();

                    final chosenCategory = category == _otherCategory
                        ? otherCategoryController.text.trim()
                        : category;

                    final errorCode = editing
                        ? await _updateService(
                      existing,
                      title: titleController.text.trim(),
                      category: chosenCategory,
                      location: locationController.text.trim(),
                      description:
                      descriptionController.text.trim(),
                      price: priceController.text.trim(),
                      contact: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      serviceLink: link,
                    )
                        : await _createService(
                      title: titleController.text.trim(),
                      category: chosenCategory,
                      location: locationController.text.trim(),
                      description:
                      descriptionController.text.trim(),
                      price: priceController.text.trim(),
                      contact: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      name: nameController.text.trim(),
                      serviceLink: link,
                    );

                    if (!dialogContext.mounted) return;

                    if (errorCode == null) {
                      Navigator.of(dialogContext).pop();
                    } else {
                      setDialogState(() {
                        saving = false;
                        formError = errorCode == 'permission-denied'
                            ? _tr(
                          'You are not allowed to do this. Only the device that posted this service can edit it.',
                          'Huruhusiwi kufanya hivi. Ni kifaa kilichoweka huduma hii pekee kinachoweza kuihariri.',
                        )
                            : _tr(
                          'Could not save the service. Please try again.',
                          'Haikuwezekana kuhifadhi huduma. Tafadhali jaribu tena.',
                        );
                      });
                    }
                  },
                  icon: saving
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Icon(editing ? Icons.save_outlined : Icons.send_outlined),
                  label: Text(
                    editing
                        ? _tr('Save changes', 'Hifadhi mabadiliko')
                        : _tr('Post', 'Posti'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Returns null on success, otherwise an error code.
  ///
  /// NO SIGN-IN: the post's `userId` field stores THIS DEVICE'S
  /// id (from DeviceIdService). Only this device can later edit
  /// or delete the post.
  Future<String?> _createService({
    required String title,
    required String category,
    required String location,
    required String description,
    required String price,
    required String contact,
    required String email,
    required String name,
    required String serviceLink,
  }) async {
    try {
      final posterId = _posterId.isNotEmpty
          ? _posterId
          : await DeviceIdService.get();

      if (_posterId.isEmpty) _posterId = posterId;

      await _firestore.collection('property_services').add({
        'title': title,
        'category': category,
        'location': location,
        'description': description,
        'price': price,
        'contact': contact,
        'email': email,
        'serviceLink': serviceLink,
        'userId': posterId,
        'postedBy': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showMessage(_tr('Service posted successfully.',
            'Huduma imewekwa kikamilifu.'));
      }

      return null;
    } on FirebaseException catch (e) {
      return e.code;
    } catch (_) {
      return 'error';
    }
  }

  /// The posting device edits its own post — no delete + repost
  /// needed. Returns null on success, otherwise an error code.
  Future<String?> _updateService(
      PropertyService service, {
        required String title,
        required String category,
        required String location,
        required String description,
        required String price,
        required String contact,
        required String email,
        required String serviceLink,
      }) async {
    try {
      await _firestore
          .collection('property_services')
          .doc(service.id)
          .update({
        'title': title,
        'category': category,
        'location': location,
        'description': description,
        'price': price,
        'contact': contact,
        'email': email,
        'serviceLink': serviceLink,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showMessage(_tr('Service updated.', 'Huduma imesasishwa.'));
      }

      return null;
    } on FirebaseException catch (e) {
      return e.code;
    } catch (_) {
      return 'error';
    }
  }

  // ------------------------------------------------------------
  // DELETE — plain confirmation. Permission is checked by
  // matching device ids (post.userId == this device id), NOT by
  // a client-side code and NOT by sign-in.
  // ------------------------------------------------------------

  Future<void> _confirmDeleteService(PropertyService service) async {
    if (!_isPoster(service)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Delete service?', 'Ufute huduma?')),
        content: Text(
          _tr(
            'This service will be permanently removed. This cannot be undone.',
            'Huduma hii itaondolewa kabisa. Hatua hii haiwezi kutenduliwa.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Delete', 'Futa')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _firestore.collection('property_services').doc(service.id).delete();
      _showMessage(_tr('Service deleted.', 'Huduma imefutwa.'));
    } on FirebaseException catch (e) {
      _showMessage(
        e.code == 'permission-denied'
            ? _tr('You are not allowed to delete this service.',
            'Huruhusiwi kufuta huduma hii.')
            : _tr('Unable to delete this service.',
            'Imeshindikana kufuta huduma hii.'),
      );
    } catch (_) {
      _showMessage(_tr('Unable to delete this service.',
          'Imeshindikana kufuta huduma hii.'));
    }
  }

  // ============================================================
  // FILTERING
  //
  //  - category chip
  //  - location dropdown
  //  - MULTI-TERM search: every word must appear somewhere in the
  //    post (title, category, location, description, name, price).
  //  - Ads-VERIFIED posts always first.
  // ============================================================

  bool _matchesCategory(PropertyService service) {
    final category = service.category.trim().toLowerCase();

    if (_selectedCategory == _otherCategory) {
      // "Other" = any custom category typed by the poster.
      return !_categories
          .where((item) => item != _otherCategory)
          .any((item) => item.toLowerCase() == category);
    }

    return category == _selectedCategory.toLowerCase();
  }

  List<PropertyService> _filterServices(List<PropertyService> services) {
    final filtered = services.where((service) {
      if (_selectedCategory != 'All' && !_matchesCategory(service)) {
        return false;
      }

      if (_selectedLocation != 'All locations' &&
          service.location.toLowerCase() != _selectedLocation.toLowerCase()) {
        return false;
      }

      if (_searchText.isEmpty) return true;

      final searchable = [
        service.title,
        service.category,
        _categoryLabel(service.category),
        service.location,
        service.description,
        service.postedBy,
        service.price,
      ].join(' ');

      return SearchMatcher.matches(searchable, _searchText);
    }).toList();

    // Verified first, preserving the existing order within each group.
    return [
      ...filtered.where((s) => s.adsVerified),
      ...filtered.where((s) => !s.adsVerified),
    ];
  }

  List<String> _getLocations(List<PropertyService> services) {
    final seen = <String, String>{};

    for (final service in services) {
      final location = service.location.trim();
      if (location.isNotEmpty) {
        seen.putIfAbsent(location.toLowerCase(), () => location);
      }
    }

    return seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 55),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 54, color: _brand.withValues(alpha: .65)),
          const SizedBox(height: 14),
          Text(
            _tr('No services found', 'Hakuna huduma zilizopatikana'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 7),
          Text(
            _tr(
              'Try another category or location, or post a service yourself.',
              'Jaribu aina au eneo lingine, au weka huduma mwenyewe.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _subtle, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 12),
            Text(
              _tr('Unable to load services.',
                  'Imeshindikana kupakia huduma.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _recentLoaded = false;
                  _error = null;
                });
                _listenRecent();
                _listenVerified();
              },
              icon: const Icon(Icons.refresh),
              label: Text(_tr('Try again', 'Jaribu tena')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: BorderSide(color: _brand),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MESSAGES — every snackbar AUTO-DISAPPEARS after
  // [duration] (default 3 seconds), so nothing stays stuck on
  // screen. The bookmark snackbar keeps its "View" action for a
  // slightly longer 4-second window (passed by the caller).
  // ============================================================

  void _showMessage(
      String message, {
        String? actionLabel,
        VoidCallback? onAction,
        Duration duration = const Duration(seconds: 3),
      }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(label: actionLabel, onPressed: onAction)
              : null,
        ),
      );
  }
}