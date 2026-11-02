// ============================================================
// student_services_page.dart  (FULL UPDATED FILE)
//
// UPDATED IN THIS VERSION:
//  1. REPORTING
//     - Every listing has a Report button (card + details sheet).
//     - Reason dialog (misleading, scam/fraud, spam, offensive,
//       other) + optional details. Each user can report a
//       listing ONCE; duplicate reports are blocked. Reports now
//       go to the SHARED `reports` collection (same shape as the
//       rest of the app: kind 'student_service', targetCollection,
//       targetId/targetName/targetOwnerId, reason, details,
//       deviceId, reporterId, status 'open', createdAt) and bump
//       a `reportCount` field so admins can query flagged
//       listings.
//  2. PAGINATION
//     - Services load in batches (default 10) instead of
//       retrieving everything at once. A "Load more" button
//       fetches the next batch; pull-to-refresh reloads from
//       the start. Firestore uses limit() + startAfterDocument.
//  3. EDITING (providers can edit their own listings)
//     - Owners get an Edit button (details sheet). The edit
//       form is pre-filled; the 4-digit delete code must be
//       re-entered to confirm the update (same security as
//       delete). No need to delete + repost.
//
// KEPT FROM PREVIOUS VERSION:
//  - Plain filter panel (search + category + campus).
//  - Campus dropdown merges duplicates/variants.
//  - Search commits only via the search button / keyboard
//    search action — no live filtering while typing.
//  - Ads-verified posts first (among the loaded batch),
//    delete flow unchanged.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'post_helpers.dart';

// ============================================================
// CAMPUS NORMALISATION (merges duplicates / spelling variants)
// ============================================================

const Set<String> _genericCampusWords = {
  'campus',
  'campuses',
  'main',
  'branch',
  'university',
  'uni',
  'college',
  'the',
  'of',
  'and',
  'town',
  'site',
};

/// Same key for "maseno (main campus)", "Maseno( Main Campus).",
/// "Main Campus Maseno", "Maseno University" ...
String _campusKey(String raw) {
  final cleaned = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  final meaningful =
  cleaned.where((w) => !_genericCampusWords.contains(w)).toList();

  final words = meaningful.isNotEmpty ? meaningful : cleaned;
  words.sort(); // word order does not matter

  return words.join(' ');
}

/// "Maseno( Main Campus)." -> "Maseno (Main Campus)"
String _prettyCampus(String raw) {
  var text = raw.trim();
  text = text.replaceAll(RegExp(r'[.,;:\s]+$'), '');
  text = text.replaceAll(RegExp(r'\s*\('), ' (');
  text = text.replaceAll(RegExp(r'\s*\)'), ')');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  return text.replaceAllMapped(
    RegExp(r'(^|[\s(])([a-z])'),
        (match) => '${match[1]}${match[2]!.toUpperCase()}',
  );
}

class _CampusOption {
  final String key;
  final String label;

  const _CampusOption(this.key, this.label);
}

// ============================================================
// SERVICE MODEL
// ============================================================

class StudentService {
  final String id;
  final String title;
  final String category;
  final String campus;
  final String location;
  final String description;
  final String contact;
  final String email;
  final String serviceLink;
  final String userId;
  final String postedBy;
  final String deleteCode;
  final bool adsVerified;
  final DateTime? createdAt;

  const StudentService({
    required this.id,
    required this.title,
    required this.category,
    required this.campus,
    required this.location,
    required this.description,
    required this.contact,
    required this.email,
    required this.serviceLink,
    required this.userId,
    required this.postedBy,
    required this.deleteCode,
    required this.adsVerified,
    required this.createdAt,
  });

  factory StudentService.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};
    final timestamp = data['createdAt'];

    return StudentService(
      id: document.id,
      title: (data['title'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      campus: (data['campus'] ?? '').toString(),
      location: (data['location'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      contact: (data['contact'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      serviceLink: (data['serviceLink'] ?? '').toString(),
      userId: (data['userId'] ?? '').toString(),
      postedBy: (data['postedBy'] ?? '').toString(),
      deleteCode: (data['deleteCode'] ?? '').toString(),
      adsVerified: data['adsVerified'] == true,
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

// ============================================================
// PAGE
// ============================================================

class StudentServicesPage extends StatefulWidget {
  const StudentServicesPage({super.key});

  @override
  State<StudentServicesPage> createState() => _StudentServicesPageState();
}

class _StudentServicesPageState extends State<StudentServicesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  static const String _allKey = 'all';

  // ---------------- PAGINATION STATE ----------------
  // Services are fetched in batches (no snapshot stream of the
  // whole collection). `_lastDocument` is the cursor for the
  // next `startAfterDocument` query.
  static const int _pageSize = 10;

  final List<StudentService> _services = [];
  final Set<String> _loadedIds = <String>{};
  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _loadError = '';

  String _selectedCampusKey = _allKey;
  String _selectedCategory = _allKey;

  // The committed search query. This ONLY changes when the user
  // taps the search button (or presses enter) — NOT while typing.
  String _searchText = '';
  String _ownerId = '';

  // Services the current user (device) has already reported.
  final Set<String> _reportedByMe = <String>{};

  static const String _otherCategory = 'Other';

  static const List<String> _categories = [
    'Laundry & Cleaning',
    'Moving & Transport',
    'Printing & Stationery',
    'Study Spaces',
    'Food & Groceries',
    'Health & Counselling',
    'Jobs & Internships',
    'Safety & Emergency',
    'Computer & Technology',
    'Beauty & Personal Care',
    'Repairs & Maintenance',
    _otherCategory,
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

  String? _required(String? v) => validateRequired(context, v);
  String? _phone(String? v) => validatePhone(context, v);
  String? _email(String? v) => validateEmail(context, v);
  String? _code(String? v) => validateDeleteCode(context, v);

  @override
  void initState() {
    super.initState();
    loadOwnerId().then((id) {
      if (mounted) setState(() => _ownerId = id);
    });
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // PAGINATION — batched Firestore queries
  // ============================================================

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _loadError = '';
    });

    try {
      final snapshot = await _firestore
          .collection('student_services')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _services
          ..clear()
          ..addAll(snapshot.docs.map(StudentService.fromFirestore));
        _loadedIds
          ..clear()
          ..addAll(snapshot.docs.map((d) => d.id));
        _lastDocument = snapshot.docs.isEmpty ? null : snapshot.docs.last;
        _hasMore = snapshot.docs.length == _pageSize;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _lastDocument == null) return;

    setState(() => _loadingMore = true);

    try {
      final snapshot = await _firestore
          .collection('student_services')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      final fresh = snapshot.docs
          .map(StudentService.fromFirestore)
          .where((s) => !_loadedIds.contains(s.id))
          .toList();

      setState(() {
        _services.addAll(fresh);
        _loadedIds.addAll(fresh.map((s) => s.id));
        if (snapshot.docs.isNotEmpty) {
          _lastDocument = snapshot.docs.last;
        }
        _hasMore = snapshot.docs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  // ============================================================
  // REPORTING
  // ============================================================

  static const List<String> _reportReasons = [
    'Misleading information',
    'Scam or fraud',
    'Spam or duplicate',
    'Offensive content',
    'Other',
  ];

  Future<void> _reportService(StudentService service) async {
    final reporterId = _ownerId.isNotEmpty ? _ownerId : await loadOwnerId();
    if (!mounted) return;
    if (reporterId.isNotEmpty) setState(() => _ownerId = reporterId);

    // One report per user per listing.
    if (_reportedByMe.contains(service.id)) {
      _showMessage(_tr('You have already reported this listing.',
          'Umesha ripoti chapisho hili.'));
      return;
    }

    final isOwner = reporterId.isNotEmpty && reporterId == service.userId;
    if (isOwner) return; // owners cannot report their own listing.

    String reason = _reportReasons.first;
    final detailsController = TextEditingController();

    final confirmed = await showDialog<({String reason, String details})>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.flag_outlined, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_tr('Report listing', 'Ripoti chapisho')),
              ),
            ],
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _tr(
                      'Why are you reporting "${service.title}"?',
                      'Kwa nini unaripoti "${service.title}"?',
                    ),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  const SizedBox(height: 8),
                  // UPDATED: RadioGroup replaces the deprecated
                  // groupValue / onChanged on each RadioListTile.
                  RadioGroup<String>(
                    groupValue: reason,
                    onChanged: (v) {
                      if (v != null) setDialogState(() => reason = v);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in _reportReasons)
                          RadioListTile<String>(
                            value: item,
                            dense: true,
                            title: Text(
                              item == 'Other'
                                  ? _tr('Other', 'Nyingine')
                                  : item,
                              style: const TextStyle(fontSize: 13.5),
                            ),
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_tr('Cancel', 'Ghairi')),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(
                (
                reason: reason,
                details: detailsController.text.trim(),
                ),
              ),
              icon: const Icon(Icons.flag_outlined),
              label: Text(_tr('Report', 'Ripoti')),
            ),
          ],
        );
      },
    );

    if (confirmed == null || !mounted) return;

    try {
      // UPDATED: reports now go to the SHARED `reports` collection
      // in the same shape as the rest of the app:
      //   doc id: student_service_<targetId>_<deviceId>
      //   kind: 'student_service', targetCollection: 'student_services',
      //   targetId / targetName / targetOwnerId,
      //   reason / details, deviceId + reporterId,
      //   status: 'open', createdAt.
      // One device can report a listing ONCE — the doc id dedupes.
      final docRef = _firestore.collection('reports').doc(
        'student_service_${service.id}_'
            '${reporterId.isEmpty ? 'anonymous' : reporterId}',
      );

      try {
        final existing = await docRef.get();

        if (existing.exists) {
          if (!mounted) return;
          setState(() => _reportedByMe.add(service.id));
          _showMessage(_tr('You have already reported this listing.',
              'Umesha ripoti chapisho hili.'));
          return;
        }
      } catch (_) {
        // Could not check: try to submit anyway.
      }

      await docRef.set({
        'kind': 'student_service',
        'targetCollection': 'student_services',
        'targetId': service.id,
        'targetName': service.title,
        'targetOwnerId': service.userId,
        'reason': confirmed.reason,
        'details': confirmed.details,
        'deviceId': reporterId,
        'reporterId': reporterId,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Best-effort counter bump so admins can query:
      // where('reportCount', '>=', 1).
      try {
        await _firestore
            .collection('student_services')
            .doc(service.id)
            .update({'reportCount': FieldValue.increment(1)});
      } catch (_) {
        // Non-critical: never block the report.
      }

      if (!mounted) return;
      setState(() => _reportedByMe.add(service.id));
      _showMessage(_tr('Thanks. This listing has been reported.',
          'Asante. Chapisho hili kimeripotiwa.'));
    } catch (_) {
      _showMessage(_tr('Could not send the report. Please try again.',
          'Imeshindikana kutuma ripoti. Tafadhali jaribu tena.'));
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr('Student Services', 'Huduma za Wanafunzi'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        onPressed: _showPostServiceDialog,
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
    if (_initialLoading) {
      return Center(child: CircularProgressIndicator(color: _brand));
    }

    if (_loadError.isNotEmpty) {
      return _buildErrorState(_loadError);
    }

    // Pull-to-refresh reloads the FIRST batch.
    return RefreshIndicator(
      color: _brand,
      onRefresh: _loadInitial,
      child: _buildContent(_services),
    );
  }

  Widget _buildContent(List<StudentService> services) {
    final campusOptions = _buildCampusOptions(services);

    // A campus that no longer exists in the loaded data resets to "All".
    if (_selectedCampusKey != _allKey &&
        !campusOptions.any((o) => o.key == _selectedCampusKey)) {
      _selectedCampusKey = _allKey;
    }

    final filtered = _filterServices(services);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildHero(),
        const SizedBox(height: 16),
        _buildFilterPanel(campusOptions),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _tr('Student Services', 'Huduma za Wanafunzi'),
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
        else ...[
          for (final service in filtered) _buildServiceCard(service),

          // ---------------- LOAD MORE ----------------
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: BorderSide(color: _brand),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brand,
                  ),
                )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  _loadingMore
                      ? _tr('Loading...', 'Inapakia...')
                      : _tr('Load more services', 'Pakia huduma zaidi'),
                ),
              ),
            )
          else if (services.length >= _pageSize)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: Text(
                  _tr('You have reached the end.',
                      'Umeufikia mwisho wa huduma.'),
                  style: TextStyle(color: _subtle, fontSize: 12.5),
                ),
              ),
            ),
        ],
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
            Icons.miscellaneous_services_rounded,
            color: Colors.white,
            size: 38,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Student Life Made Easier',
                      'Maisha ya Mwanafunzi Yarahisishwa'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _tr(
                    'Find useful services around your campus, or post a service for other students. No account needed.',
                    'Pata huduma muhimu karibu na chuo chako au posti huduma kwa wanafunzi wengine. Huhitaji akaunti.',
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

  // ============================================================
  // FILTER PANEL: search bar + service category + campus name
  // ============================================================

  bool get _hasActiveFilters =>
      _selectedCampusKey != _allKey ||
          _selectedCategory != _allKey ||
          _searchText.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _selectedCampusKey = _allKey;
      _selectedCategory = _allKey;
      _searchText = '';
      _searchController.clear();
    });
  }

  OutlineInputBorder _outline(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  InputDecoration _filterDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _brand),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: _outline(_borderColor),
      border: _outline(_borderColor),
      focusedBorder: _outline(_brand, width: 1.6),
    );
  }

  // ------------------------------------------------------------
  // SEARCH BEHAVIOUR
  //
  //  - NO live filtering: typing alone does NOT change the
  //    results. The field has NO onChanged handler.
  //  - COMMITTED SEARCH: the search icon button (or the
  //    keyboard's search/enter action) commits the query.
  //  - An EMPTY field + tapping search clears ALL filters.
  // ------------------------------------------------------------

  void _commitSearch() {
    FocusScope.of(context).unfocus();

    final query = _searchController.text.trim();

    if (query.isEmpty) {
      // Empty query -> clear every filter.
      setState(() {
        _searchText = '';
        _selectedCampusKey = _allKey;
        _selectedCategory = _allKey;
      });
      return;
    }

    setState(() => _searchText = query);
  }

  Widget _buildFilterPanel(List<_CampusOption> campusOptions) {
    final categoryDropdown = DropdownButtonFormField<String>(
      key: ValueKey('category-$_selectedCategory'),
      initialValue: _selectedCategory,
      isExpanded: true,
      decoration: _filterDecoration(
        _tr('Service category', 'Aina ya huduma'),
        Icons.category_outlined,
      ),
      items: [
        DropdownMenuItem<String>(
          value: _allKey,
          child: Text(_tr('All categories', 'Aina zote')),
        ),
        ..._categories.map(
              (item) => DropdownMenuItem<String>(
            value: item,
            child: Text(
              item == _otherCategory ? _tr('Other', 'Nyingine') : item,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _selectedCategory = value);
      },
    );

    final campusDropdown = DropdownButtonFormField<String>(
      key: ValueKey('campus-$_selectedCampusKey-${campusOptions.length}'),
      initialValue: _selectedCampusKey,
      isExpanded: true,
      decoration: _filterDecoration(
        _tr('Campus name', 'Jina la kampasi'),
        Icons.school_outlined,
      ),
      items: [
        DropdownMenuItem<String>(
          value: _allKey,
          child: Text(_tr('All campuses', 'Vyuo vyote')),
        ),
        ...campusOptions.map(
              (option) => DropdownMenuItem<String>(
            value: option.key,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _selectedCampusKey = value);
      },
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _brand.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.tune, color: _brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr('Find a service', 'Tafuta huduma'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr(
                        'Type your search, then tap the search button.',
                        'Andika utafutaji wako, kisha gonga kitufe cha kutafuta.',
                      ),
                      style: TextStyle(fontSize: 11.5, color: _subtle),
                    ),
                  ],
                ),
              ),
              if (_hasActiveFilters)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: Text(_tr('Clear', 'Futa')),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ---------------- SEARCH BAR ----------------
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _commitSearch(),
            // NOTE: no onChanged — no live filtering.
            decoration: InputDecoration(
              hintText: _tr('Search services...', 'Tafuta huduma...'),
              prefixIcon: Icon(Icons.search, color: _brand),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      tooltip: _tr('Clear', 'Futa'),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchText = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  IconButton(
                    tooltip: _tr('Search', 'Tafuta'),
                    onPressed: _commitSearch,
                    icon: const Icon(Icons.search),
                    color: _brand,
                  ),
                ],
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: _outline(_borderColor),
              border: _outline(_borderColor),
              focusedBorder: _outline(_brand, width: 1.6),
            ),
          ),
          const SizedBox(height: 12),

          // ---------------- CATEGORY + CAMPUS ----------------
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 560) {
                return Row(
                  children: [
                    Expanded(child: categoryDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: campusDropdown),
                  ],
                );
              }

              return Column(
                children: [
                  categoryDropdown,
                  const SizedBox(height: 12),
                  campusDropdown,
                ],
              );
            },
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

  /// Green badge shown on admin-verified posts.
  Widget _verifiedBadge() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brand.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 12, color: _brand),
          const SizedBox(width: 4),
          Text(
            _tr('Ads Verified', 'Imethibitishwa'),
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

  Widget _buildServiceCard(StudentService service) {
    final isOwner = _ownerId.isNotEmpty && _ownerId == service.userId;
    final reported = _reportedByMe.contains(service.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: service.adsVerified
              ? _brand.withValues(alpha: .55)
              : _borderColor,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(_categoryIcon(service.category), color: _brand),
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
                      Icon(Icons.verified, size: 16, color: _brand),
                    // ---- CARD MENU: edit (owner) / report ----
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: _subtle),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        if (value == 'report') {
                          _reportService(service);
                        } else if (value == 'edit') {
                          _showEditServiceDialog(service);
                        }
                      },
                      itemBuilder: (context) => [
                        if (isOwner)
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined,
                                    size: 18, color: _brand),
                                const SizedBox(width: 10),
                                Text(_tr('Edit listing', 'Haribu chapisho')),
                              ],
                            ),
                          ),
                        if (!isOwner)
                          PopupMenuItem<String>(
                            value: 'report',
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined,
                                    size: 18, color: Colors.orange.shade700),
                                const SizedBox(width: 10),
                                Text(
                                  reported
                                      ? _tr('Already reported',
                                      'Umesha ripoti')
                                      : _tr('Report listing',
                                      'Ripoti chapisho'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                _infoRow(Icons.category_outlined, service.category),
                _infoRow(Icons.school_outlined, service.campus),
                if (service.location.trim().isNotEmpty)
                  _infoRow(Icons.location_on_outlined, service.location),
                if (service.adsVerified) _verifiedBadge(),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _showServiceDetails(service),
                    icon: const Icon(Icons.visibility_outlined, size: 17),
                    label: Text(_tr('View', 'Angalia')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brand,
                      side: BorderSide(color: _brand),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showServiceDetails(StudentService service) async {
    final isOwner = _ownerId.isNotEmpty && _ownerId == service.userId;
    final reported = _reportedByMe.contains(service.id);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 700),
      builder: (sheetContext) {
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
                      IconButton(
                        tooltip: _tr('Close', 'Funga'),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (service.adsVerified) ...[
                    const SizedBox(height: 6),
                    _verifiedBadge(),
                  ],
                  const SizedBox(height: 14),
                  _detailRow(Icons.category_outlined,
                      _tr('Category', 'Aina ya huduma'), service.category),
                  _detailRow(Icons.school_outlined,
                      _tr('Campus name', 'Jina la kampasi'), service.campus),
                  if (service.location.trim().isNotEmpty)
                    _detailRow(Icons.location_on_outlined,
                        _tr('Location', 'Mahali'), service.location),
                  if (service.serviceLink.trim().isNotEmpty) ...[
                    _detailRow(Icons.link, _tr('Service link', 'Kiungo cha huduma'),
                        service.serviceLink),
                    openLinkButton(context, service.serviceLink, _brand),
                  ],

                  if (isOwner) ...[
                    _privateNote(),
                    if (service.contact.trim().isNotEmpty)
                      _detailRow(Icons.phone_outlined,
                          _tr('Phone', 'Simu'), service.contact),
                    if (service.email.trim().isNotEmpty)
                      _detailRow(Icons.email_outlined,
                          _tr('Email', 'Barua pepe'), service.email),
                    if (service.postedBy.trim().isNotEmpty)
                      _detailRow(Icons.person_outline,
                          _tr('Posted by', 'Iliwekwa na'), service.postedBy),
                  ],

                  const SizedBox(height: 12),
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
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(_tr('Close', 'Funga')),
                        ),
                      ),
                    ],
                  ),
                  if (!isOwner) ...[
                    const SizedBox(height: 10),
                    // ---- REPORT (non-owners only) ----
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade700,
                          side: BorderSide(
                            color: Colors.orange.shade700,
                          ),
                        ),
                        onPressed: reported
                            ? null
                            : () {
                          Navigator.of(sheetContext).pop();
                          _reportService(service);
                        },
                        icon: Icon(
                          reported ? Icons.check_circle_outline : Icons.flag_outlined,
                          size: 18,
                        ),
                        label: Text(
                          reported
                              ? _tr('You reported this listing',
                              'Umeripoti chapisho hili')
                              : _tr('Report this listing',
                              'Ripoti chapisho hiki'),
                        ),
                      ),
                    ),
                  ],
                  if (isOwner) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // ---- EDIT (owner) ----
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _brand,
                              side: BorderSide(color: _brand),
                            ),
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _showEditServiceDialog(service);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: Text(_tr('Edit', 'Haribu')),
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
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _privateNote() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: _brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _tr(
                'Only you can see the phone number, email and name below. Other students cannot.',
                'Ni wewe pekee unayeweza kuona nambari ya simu, barua pepe na jina hapa chini. Wanafunzi wengine hawawezi.',
              ),
              style: TextStyle(fontSize: 12, height: 1.4, color: _subtle),
            ),
          ),
        ],
      ),
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

  // ============================================================
  // POST SERVICE (unchanged flow)
  // ============================================================

  Future<void> _showPostServiceDialog() async {
    final ownerId = await loadOwnerId();

    if (!mounted) return;
    _ownerId = ownerId;

    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final otherCategoryController = TextEditingController();
    final campusController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final linkController = TextEditingController();
    final codeController = TextEditingController();

    String category = _categories.first;
    String? formError;
    bool posting = false;

    final privateHelper = _tr(
      'Private: only you can see this.',
      'Siri: ni wewe pekee unayeweza kuona hii.',
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.add_business_outlined, color: _brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tr('Post Student Service',
                          'Posti Huduma ya Mwanafunzi'),
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
                          hint: _tr('e.g. Affordable laundry service',
                              'mfano huduma ya ufuaji nafuu'),
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
                                child: Text(
                                  item == _otherCategory
                                      ? _tr('Other', 'Nyingine')
                                      : item,
                                ),
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
                            hint: _tr('e.g. Hair braiding',
                                'mfano Kusuka nywele'),
                            icon: Icons.edit_outlined,
                            capitalization: TextCapitalization.sentences,
                            validator: _required,
                          ),
                        postTextField(
                          controller: campusController,
                          label: _tr('Campus name', 'Jina la kampasi'),
                          hint: _tr('e.g. Maseno University',
                              'mfano Chuo Kikuu cha Maseno'),
                          icon: Icons.school_outlined,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: locationController,
                          label: _tr('Location', 'Mahali'),
                          hint: _tr('e.g. Kahawa Wendani',
                              'mfano Kahawa Wendani'),
                          icon: Icons.location_on_outlined,
                          capitalization: TextCapitalization.sentences,
                          validator: _required,
                        ),
                        postTextField(
                          controller: descriptionController,
                          label: _tr('Service details', 'Maelezo ya huduma'),
                          hint: _tr(
                            'Explain the service, availability, prices or anything students should know.',
                            'Eleza huduma, upatikanaji, bei au jambo lolote ambalo wanafunzi wanapaswa kujua.',
                          ),
                          hintMaxLines: 3,
                          icon: Icons.notes_outlined,
                          capitalization: TextCapitalization.sentences,
                          maxLines: 4,
                          validator: _required,
                        ),
                        postTextField(
                          controller: phoneController,
                          label: _tr('Phone number', 'Nambari ya simu'),
                          helper: privateHelper,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          digitsOnly: true,
                          validator: _phone,
                        ),
                        postTextField(
                          controller: emailController,
                          label: _tr('Email', 'Barua pepe'),
                          helper: privateHelper,
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _email,
                        ),
                        postTextField(
                          controller: nameController,
                          label: _tr('Your name', 'Jina lako'),
                          helper: privateHelper,
                          icon: Icons.person_outline,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: linkController,
                          label: _tr('Service link', 'Kiungo cha huduma'),
                          hint: _tr(
                            'WhatsApp group link / Telegram group link / website link / name of app / any other link',
                            'Kiungo cha kundi la WhatsApp / kundi la Telegram / tovuti / jina la programu / kiungo kingine',
                          ),
                          helper: _tr(
                            'Public: students use this link to reach you.',
                            'Wazi: wanafunzi hutumia kiungo hiki kukufikia.',
                          ),
                          hintMaxLines: 3,
                          icon: Icons.link,
                          keyboardType: TextInputType.url,
                          validator: _required,
                        ),
                        postTextField(
                          controller: codeController,
                          label: _tr('4-digit delete code',
                              'Msimbo wa kufuta wa tarakimu 4'),
                          hint: _tr('Enter 4 digits', 'Weka tarakimu 4'),
                          helper: _tr(
                            'Keep this code. You will need it to delete your post.',
                            'Hifadhi msimbo huu. Utauhitaji kufuta chapisho lako.',
                          ),
                          icon: Icons.lock_outline,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          digitsOnly: true,
                          validator: _code,
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
                  onPressed: posting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(_tr('Cancel', 'Ghairi')),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: posting
                      ? null
                      : () async {
                    if (!formKey.currentState!.validate()) {
                      setDialogState(() {
                        formError = _tr(
                          'Please fill in every field correctly.',
                          'Tafadhali jaza kila sehemu ipasavyo.',
                        );
                      });
                      return;
                    }

                    setDialogState(() {
                      formError = null;
                      posting = true;
                    });

                    final ok = await _postService(
                      title: titleController.text.trim(),
                      category: category == _otherCategory
                          ? otherCategoryController.text.trim()
                          : category,
                      campus: campusController.text.trim(),
                      location: locationController.text.trim(),
                      description: descriptionController.text.trim(),
                      contact: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      name: nameController.text.trim(),
                      serviceLink: linkController.text.trim(),
                      deleteCode: codeController.text.trim(),
                    );

                    if (!dialogContext.mounted) return;

                    if (ok) {
                      Navigator.of(dialogContext).pop();
                    } else {
                      setDialogState(() {
                        posting = false;
                        formError = _tr(
                          'Could not post the service. Please try again.',
                          'Haikuwezekana kuweka huduma. Tafadhali jaribu tena.',
                        );
                      });
                    }
                  },
                  icon: posting
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.send_outlined),
                  label: Text(_tr('Post', 'Posti')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _postService({
    required String title,
    required String category,
    required String campus,
    required String location,
    required String description,
    required String contact,
    required String email,
    required String name,
    required String serviceLink,
    required String deleteCode,
  }) async {
    try {
      final ownerId = await loadOwnerId();

      final doc = await _firestore.collection('student_services').add({
        'title': title,
        'category': category,
        'campus': campus,
        'location': location,
        'description': description,
        'contact': contact,
        'email': email,
        'serviceLink': serviceLink,
        'userId': ownerId,
        'postedBy': name,
        'deleteCode': deleteCode,
        'reportCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        // Optimistically show the new post without reloading.
        setState(() {
          _ownerId = ownerId;
          _loadedIds.add(doc.id);
          _services.insert(
            0,
            StudentService(
              id: doc.id,
              title: title,
              category: category,
              campus: campus,
              location: location,
              description: description,
              contact: contact,
              email: email,
              serviceLink: serviceLink,
              userId: ownerId,
              postedBy: name,
              deleteCode: deleteCode,
              adsVerified: false,
              createdAt: DateTime.now(),
            ),
          );
        });
        _showMessage(_tr('Student service posted successfully.',
            'Huduma ya mwanafunzi imewekwa kikamilifu.'));
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // EDIT SERVICE (owner only, delete code required)
  // ============================================================

  Future<void> _showEditServiceDialog(StudentService service) async {
    if (_ownerId.isEmpty || _ownerId != service.userId) return;

    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: service.title);
    final campusController = TextEditingController(text: service.campus);
    final locationController = TextEditingController(text: service.location);
    final descriptionController =
    TextEditingController(text: service.description);
    final phoneController = TextEditingController(text: service.contact);
    final emailController = TextEditingController(text: service.email);
    final nameController = TextEditingController(text: service.postedBy);
    final linkController = TextEditingController(text: service.serviceLink);
    final codeController = TextEditingController();

    String? formError;
    bool saving = false;

    final privateHelper = _tr(
      'Private: only you can see this.',
      'Siri: ni wewe pekee unayeweza kuona hii.',
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.edit_outlined, color: _brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child:
                    Text(_tr('Edit Listing', 'Haribu Chapisho')),
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
                          icon: Icons.title,
                          capitalization: TextCapitalization.sentences,
                          validator: _required,
                        ),
                        postTextField(
                          controller: campusController,
                          label: _tr('Campus name', 'Jina la kampasi'),
                          icon: Icons.school_outlined,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: locationController,
                          label: _tr('Location', 'Mahali'),
                          icon: Icons.location_on_outlined,
                          capitalization: TextCapitalization.sentences,
                          validator: _required,
                        ),
                        postTextField(
                          controller: descriptionController,
                          label: _tr('Service details', 'Maelezo ya huduma'),
                          icon: Icons.notes_outlined,
                          capitalization: TextCapitalization.sentences,
                          maxLines: 4,
                          validator: _required,
                        ),
                        postTextField(
                          controller: phoneController,
                          label: _tr('Phone number', 'Nambari ya simu'),
                          helper: privateHelper,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          digitsOnly: true,
                          validator: _phone,
                        ),
                        postTextField(
                          controller: emailController,
                          label: _tr('Email', 'Barua pepe'),
                          helper: privateHelper,
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _email,
                        ),
                        postTextField(
                          controller: nameController,
                          label: _tr('Your name', 'Jina lako'),
                          helper: privateHelper,
                          icon: Icons.person_outline,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: linkController,
                          label: _tr('Service link', 'Kiungo cha huduma'),
                          helper: _tr(
                            'Public: students use this link to reach you.',
                            'Wazi: wanafunzi hutumia kiungo hiki kukufikia.',
                          ),
                          icon: Icons.link,
                          keyboardType: TextInputType.url,
                          validator: _required,
                        ),
                        postTextField(
                          controller: codeController,
                          label: _tr('Confirm your 4-digit delete code',
                              'Thibitisha msimbo wako wa kufuta'),
                          hint: _tr('Enter 4 digits', 'Weka tarakimu 4'),
                          helper: _tr(
                            'Enter your delete code to confirm the changes.',
                            'Weka msimbo wako wa kufuta kuthibitisha mabadiliko.',
                          ),
                          icon: Icons.lock_outline,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          digitsOnly: true,
                          validator: _code,
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
                          'Please fill in every field correctly.',
                          'Tafadhali jaza kila sehemu ipasavyo.',
                        );
                      });
                      return;
                    }

                    // The delete code confirms the edit.
                    if (service.deleteCode.trim().isNotEmpty &&
                        codeController.text.trim() !=
                            service.deleteCode.trim()) {
                      setDialogState(() {
                        formError = _tr(
                          'Wrong delete code. Changes were not saved.',
                          'Msimbo wa kufuta si sahihi. Mabadiliko hayakuhifadhiwa.',
                        );
                      });
                      return;
                    }

                    setDialogState(() {
                      formError = null;
                      saving = true;
                    });

                    final ok = await _updateService(
                      service,
                      title: titleController.text.trim(),
                      campus: campusController.text.trim(),
                      location: locationController.text.trim(),
                      description: descriptionController.text.trim(),
                      contact: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      name: nameController.text.trim(),
                      serviceLink: linkController.text.trim(),
                    );

                    if (!dialogContext.mounted) return;

                    if (ok) {
                      Navigator.of(dialogContext).pop();
                    } else {
                      setDialogState(() {
                        saving = false;
                        formError = _tr(
                          'Could not save the changes. Please try again.',
                          'Imeshindikana kuhifadhi mabadiliko. Tafadhali jaribu tena.',
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
                      : const Icon(Icons.save_outlined),
                  label: Text(_tr('Save changes', 'Hifadhi mabadiliko')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _updateService(
      StudentService service, {
        required String title,
        required String campus,
        required String location,
        required String description,
        required String contact,
        required String email,
        required String name,
        required String serviceLink,
      }) async {
    try {
      await _firestore
          .collection('student_services')
          .doc(service.id)
          .update({
        'title': title,
        'campus': campus,
        'location': location,
        'description': description,
        'contact': contact,
        'email': email,
        'postedBy': name,
        'serviceLink': serviceLink,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          final index =
          _services.indexWhere((s) => s.id == service.id);
          if (index >= 0) {
            _services[index] = StudentService(
              id: service.id,
              title: title,
              category: service.category,
              campus: campus,
              location: location,
              description: description,
              contact: contact,
              email: email,
              serviceLink: serviceLink,
              userId: service.userId,
              postedBy: name,
              deleteCode: service.deleteCode,
              adsVerified: service.adsVerified,
              createdAt: service.createdAt,
            );
          }
        });
        _showMessage(_tr('Listing updated.', 'Chapisho limeharibiwa.'));
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // DELETE (unchanged flow)
  // ============================================================

  Future<void> _confirmDeleteService(StudentService service) async {
    if (_ownerId.isEmpty || _ownerId != service.userId) return;

    final confirmed = await confirmDeleteWithCode(
      context,
      title: _tr('Delete service?', 'Ufute huduma?'),
      message: service.deleteCode.trim().isEmpty
          ? _tr('This service will be permanently removed.',
          'Huduma hii itaondolewa kabisa.')
          : _tr('Enter your 4-digit delete code to remove this service.',
          'Weka msimbo wako wa kufuta wa tarakimu 4 ili kuondoa huduma hii.'),
      storedCode: service.deleteCode,
    );

    if (!confirmed) return;

    try {
      await _firestore.collection('student_services').doc(service.id).delete();
      if (mounted) {
        setState(() {
          _services.removeWhere((s) => s.id == service.id);
          _loadedIds.remove(service.id);
        });
      }
      _showMessage(_tr('Service deleted.', 'Huduma imefutwa.'));
    } catch (_) {
      _showMessage(_tr('Unable to delete this service.',
          'Imeshindikana kufuta huduma hii.'));
    }
  }

  // ============================================================
  // FILTERING + SORTING
  //
  // Ads-verified posts come first among the LOADED batch, in
  // "All" and in every filter. The poster's name is NOT
  // searchable.
  // ============================================================

  static final List<String> _knownCategoriesLower = _categories
      .where((c) => c != _otherCategory)
      .map((c) => c.toLowerCase())
      .toList();

  bool _matchesCategory(StudentService service) {
    if (_selectedCategory == _allKey) return true;

    final category = service.category.trim().toLowerCase();

    // "Other" = any custom category typed by the poster.
    if (_selectedCategory == _otherCategory) {
      return category == 'other' || !_knownCategoriesLower.contains(category);
    }

    return category == _selectedCategory.toLowerCase();
  }

  List<StudentService> _filterServices(List<StudentService> services) {
    final words = _searchText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    final filtered = services.where((service) {
      if (_selectedCampusKey != _allKey &&
          _campusKey(service.campus) != _selectedCampusKey) {
        return false;
      }

      if (!_matchesCategory(service)) return false;

      if (words.isEmpty) return true;

      final searchable = [
        service.title,
        service.category,
        service.campus,
        service.location,
        service.description,
      ].join(' ').toLowerCase();

      // Every typed word must appear somewhere in the post.
      return words.every(searchable.contains);
    }).toList();

    // Verified first, preserving the existing order within each group.
    final verified = filtered.where((s) => s.adsVerified).toList();
    final unverified = filtered.where((s) => !s.adsVerified).toList();

    return [...verified, ...unverified];
  }

  /// Evaluates the fetched campuses and merges duplicates / word-order
  /// and spelling variants into one entry each.
  List<_CampusOption> _buildCampusOptions(List<StudentService> services) {
    // key -> (label variant -> how many posts use it)
    final variants = <String, Map<String, int>>{};

    for (final service in services) {
      final raw = service.campus.trim();
      if (raw.isEmpty) continue;

      final key = _campusKey(raw);
      if (key.isEmpty) continue;

      final label = _prettyCampus(raw);
      final counts = variants.putIfAbsent(key, () => <String, int>{});
      counts[label] = (counts[label] ?? 0) + 1;
    }

    final options = <_CampusOption>[];

    variants.forEach((key, counts) {
      // Most used spelling wins; on a tie the shorter one.
      final labels = counts.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          if (byCount != 0) return byCount;
          return a.key.length.compareTo(b.key.length);
        });

      options.add(_CampusOption(key, labels.first.key));
    });

    options.sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );

    return options;
  }

  IconData _categoryIcon(String category) {
    final value = category.toLowerCase();

    if (value.contains('laundry')) return Icons.local_laundry_service_outlined;
    if (value.contains('moving')) return Icons.local_shipping_outlined;
    if (value.contains('printing')) return Icons.print_outlined;
    if (value.contains('study')) return Icons.menu_book_outlined;
    if (value.contains('food')) return Icons.restaurant_outlined;
    if (value.contains('health')) return Icons.health_and_safety_outlined;
    if (value.contains('job')) return Icons.work_outline_rounded;
    if (value.contains('safety')) return Icons.security_outlined;
    if (value.contains('computer') || value.contains('technology')) {
      return Icons.computer_outlined;
    }
    if (value.contains('beauty')) return Icons.face_retouching_natural;
    if (value.contains('repair')) return Icons.build_outlined;

    return Icons.miscellaneous_services_outlined;
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
            _tr('No student services found',
                'Hakuna huduma za wanafunzi zilizopatikana'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 7),
          Text(
            _tr(
              'Try another category or campus, change your search, or post a service yourself.',
              'Jaribu aina au kampasi nyingine, badilisha utafutaji wako, au weka huduma mwenyewe.',
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
              _tr('Unable to load student services.',
                  'Imeshindikana kupakia huduma za wanafunzi.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: BorderSide(color: _brand),
              ),
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh),
              label: Text(_tr('Try again', 'Jaribu tena')),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}