// ============================================================
// hostels_page.dart  (FULL UPDATED FILE)
// Shows hostels whose property verification is 'verified'.
// Ads-verified listings are shown FIRST (within loaded results).
// Logs a view (per property + user, no double counting).
// Deactivated properties are hidden.
//
// UPDATED:
//  - NORMALISED + DE-DUPLICATED dropdowns (campus, room type,
//    area). "Bedsitter" / "Bedsitter." / "bedsitter " are one
//    value. Filtering compares the same normalised keys.
//  - Reads the real Firestore fields: campusName, subCounty,
//    unitDetails, accommodationType, area, location (split by
//    comma so "Luanda, Luanda, Vihiga" does not repeat Luanda).
//  - PAGINATION: listings load in batches (startAfterDocument),
//    auto-loading near the bottom + a "Load more" button +
//    pull-to-refresh.
//  - RATINGS: each hostel card shows stars, average and review
//    count (from the `reviews` collection, one query per batch).
//  - Price shown as "KES 20,000 / semester".
//  - LabelNormalizer: reuse it in add_property_page.dart so new
//    listings are saved clean.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_localizations.dart';
import 'app_settings.dart';
import 'property_details_page.dart';
import 'registration_page.dart';

// ============================================================
// LABEL NORMALIZER
// Use LabelNormalizer.display(value) when SAVING a listing
// (accommodationType, unitDetails, campusName, area ...) so
// similar values never create inconsistent filtering.
// ============================================================
class LabelNormalizer {
  LabelNormalizer._();

  /// Trim, collapse spaces, tidy brackets, strip leading/trailing
  /// punctuation. "Maseno(Odero Kango campus)." ->
  /// "Maseno (Odero Kango campus)"
  static String clean(dynamic value) {
    var s = (value ?? '').toString().trim();
    if (s.isEmpty) return '';

    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAllMapped(RegExp(r'(\S)\('), (m) => '${m[1]} (');
    s = s.replaceAll(RegExp(r'\(\s+'), '(');
    s = s.replaceAll(RegExp(r'\s+\)'), ')');
    s = s.replaceAll(
      RegExp(r'^[\s.,;:\-–_/]+|[\s.,;:\-–_/]+$'),
      '',
    );
    return s.trim();
  }

  /// Case-insensitive comparison key. "Single Room", "single room"
  /// and "Single room " all give "single room".
  static String key(dynamic value) => clean(value).toLowerCase();

  /// Cleaned, Title Case text for display and for saving.
  static String display(dynamic value) {
    final cleaned = clean(value);
    if (cleaned.isEmpty) return '';

    // Keep short ALL-CAPS words (JKUAT) only when the text is
    // mixed case; a fully upper-case text becomes Title Case.
    final mixedCase = cleaned != cleaned.toUpperCase();

    return cleaned
        .split(' ')
        .map((w) => _titleWord(w, keepAcronyms: mixedCase))
        .join(' ');
  }

  static String _titleWord(String word, {required bool keepAcronyms}) {
    if (word.isEmpty) return word;

    final letters = word.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (keepAcronyms &&
        letters.length > 1 &&
        letters.length <= 5 &&
        letters == letters.toUpperCase()) {
      return word;
    }

    final lower = word.toLowerCase();
    final i = lower.indexOf(RegExp(r'[a-z]'));
    if (i < 0) return word;

    return lower.substring(0, i) +
        lower[i].toUpperCase() +
        lower.substring(i + 1);
  }
}

class _RatingSummary {
  final double average;
  final int count;

  const _RatingSummary(this.average, this.count);
}

class _FilterOptions {
  final List<String> campuses;
  final List<String> rooms;
  final List<String> areas;
  final DateTime fetchedAt;

  _FilterOptions({
    required this.campuses,
    required this.rooms,
    required this.areas,
  }) : fetchedAt = DateTime.now();

  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < const Duration(minutes: 10);
}

class HostelsPage extends StatefulWidget {
  const HostelsPage({super.key});

  @override
  State<HostelsPage> createState() => _HostelsPageState();
}

class _HostelsPageState extends State<HostelsPage> {
  // ------------------------------------------------------------
  // CONFIG
  // ------------------------------------------------------------

  /// Listings loaded per batch.
  static const int _pageSize = 10;

  /// Value of the `type` field that marks a hostel in Firestore.
  static const String _hostelTypeValue = 'Hostel';

  /// Dropdown options are cached across visits (10 minutes).
  static _FilterOptions? _optionsCache;

  // ------------------------------------------------------------
  // WIZARD STATE
  // ------------------------------------------------------------

  int wizardStep = 0; // 0..3
  static const int wizardStepCount = 4;

  // '' means "not chosen" (no filtering on that answer).
  // These hold the cleaned DISPLAY text; comparisons use keys.
  String selectedCampus = '';
  String selectedRoomType = '';
  String selectedArea = '';

  final budgetController = TextEditingController();

  bool wizardApplied = false;

  // Dropdown option lists (normalised, no repeats).
  List<String> _campuses = [];
  List<String> _roomOptions = [];
  List<String> _areas = [];

  // ------------------------------------------------------------
  // PAGINATION STATE
  // ------------------------------------------------------------

  final ScrollController _scroll = ScrollController();

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _loaded = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _loading = false;
  bool _firstLoadDone = false;
  String? _error;

  // propertyId -> rating summary
  final Map<String, _RatingSummary> _ratings = {};

  Query<Map<String, dynamic>> get _baseQuery =>
      FirebaseFirestore.instance
          .collection('properties')
          .where('property_status', isEqualTo: 'verified')
          .where('type', isEqualTo: _hostelTypeValue);

  // ------------------------------------------------------------
  // THEME HELPERS
  // ------------------------------------------------------------

  SettingsController get _settings => AppSettings.of(context);

  bool get _isDark => _settings.isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _brandDeep =>
      _isDark ? kBrandGreenOnDark : const Color(0xFF146C43);

  Color get _brandSoft =>
      _isDark ? const Color(0xFF152219) : const Color(0xFFEAF7EF);

  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) {
    final code = _settings.languageCode;
    if (code == 'sw') return sw;
    return AppLocalizations.trText(en, code);
  }

  // ------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadOptions();
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    budgetController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  // ------------------------------------------------------------
  // ADS VERIFICATION (sort order only, never a filter)
  // ------------------------------------------------------------

  bool _isAdsVerified(Map<String, dynamic> data) {
    return data['adsverification'] == true ||
        data['adsVerification'] == 'verified';
  }

  // ------------------------------------------------------------
  // DEACTIVATED PROPERTY DETECTION
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

  bool _isHostel(Map<String, dynamic> data) {
    final type = data['propertyType']?.toString().toLowerCase() ?? '';
    final subtype = data['subtype']?.toString().toLowerCase() ?? '';
    final category = data['category']?.toString().toLowerCase() ?? '';
    final t = data['type']?.toString().toLowerCase() ?? '';

    return type.contains('hostel') ||
        subtype.contains('hostel') ||
        category.contains('hostel') ||
        t.contains('hostel');
  }

  // ------------------------------------------------------------
  // FIELD EXTRACTION (normalised)
  // ------------------------------------------------------------

  /// Flattens a Firestore value (String / List) into cleaned
  /// parts. Strings are split on commas. Numbers are ignored.
  List<String> _partsOf(dynamic value, {int maxLength = 60}) {
    final out = <String>[];

    void add(dynamic v) {
      if (v == null || v is num || v is bool) return;
      if (v is Iterable) {
        for (final item in v) {
          add(item);
        }
        return;
      }
      for (final piece in v.toString().split(',')) {
        final cleaned = LabelNormalizer.clean(piece);
        if (cleaned.isEmpty || cleaned.length > maxLength) continue;
        out.add(cleaned);
      }
    }

    add(value);
    return out;
  }

  String _campusOf(Map<String, dynamic> data) {
    final raw = data['campusName'] ?? data['nearCampus'] ?? data['campus'];
    return LabelNormalizer.display(raw);
  }

  /// Room / unit type values of one listing (display text).
  List<String> _roomValues(Map<String, dynamic> data) {
    return [
      ..._partsOf(data['accommodationType'], maxLength: 40),
      ..._partsOf(data['accommodation_type'], maxLength: 40),
      ..._partsOf(data['unitDetails'], maxLength: 40),
      ..._partsOf(data['unitType'], maxLength: 40),
      ..._partsOf(data['roomType'], maxLength: 40),
      ..._partsOf(data['units'], maxLength: 40),
    ].map(LabelNormalizer.display).where((e) => e.isNotEmpty).toList();
  }

  /// Area values of one listing (display text).
  List<String> _areaValues(Map<String, dynamic> data) {
    return [
      ..._partsOf(data['location']),
      ..._partsOf(data['subCounty']),
      ..._partsOf(data['subcounty']),
      ..._partsOf(data['town']),
      ..._partsOf(data['estate']),
      ..._partsOf(data['area']),
      ..._partsOf(data['county']),
    ].map(LabelNormalizer.display).where((e) => e.isNotEmpty).toList();
  }

  // ------------------------------------------------------------
  // DROPDOWN OPTIONS — fetched once, cached, de-duplicated
  // ------------------------------------------------------------

  /// De-duplicates by normalised key and sorts alphabetically.
  List<String> _unique(Iterable<String> values) {
    final seen = <String, String>{};
    for (final v in values) {
      final k = LabelNormalizer.key(v);
      if (k.isEmpty) continue;
      seen.putIfAbsent(k, () => v);
    }
    final list = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<void> _loadOptions({bool force = false}) async {
    final cached = _optionsCache;
    if (!force && cached != null && cached.isFresh) {
      _applyOptions(cached);
      return;
    }

    try {
      final snap = await _baseQuery.get();

      final campuses = <String>[];
      final rooms = <String>[];
      final areas = <String>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        if (!_isHostel(data)) continue;
        if (_isDeactivatedProperty(data)) continue;

        final campus = _campusOf(data);
        if (campus.isNotEmpty) campuses.add(campus);

        rooms.addAll(_roomValues(data));
        areas.addAll(_areaValues(data));
      }

      final options = _FilterOptions(
        campuses: _unique(campuses),
        rooms: _unique(rooms),
        areas: _unique(areas),
      );

      _optionsCache = options;
      _applyOptions(options);
    } catch (_) {
      // Dropdowns stay empty; the listing itself still works.
    }
  }

  void _applyOptions(_FilterOptions options) {
    if (!mounted) return;

    setState(() {
      _campuses = options.campuses;
      _roomOptions = options.rooms;
      _areas = options.areas;

      // A chosen value that no longer exists is dropped.
      if (selectedCampus.isNotEmpty && !_hasKey(_campuses, selectedCampus)) {
        selectedCampus = '';
      }
      if (selectedRoomType.isNotEmpty &&
          !_hasKey(_roomOptions, selectedRoomType)) {
        selectedRoomType = '';
      }
      if (selectedArea.isNotEmpty && !_hasKey(_areas, selectedArea)) {
        selectedArea = '';
      }
    });
  }

  bool _hasKey(List<String> list, String value) {
    final k = LabelNormalizer.key(value);
    return list.any((e) => LabelNormalizer.key(e) == k);
  }

  // ------------------------------------------------------------
  // PAGINATION
  // ------------------------------------------------------------

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var query = _baseQuery
          .orderBy(FieldPath.documentId)
          .limit(_pageSize);

      final last = _lastDoc;
      if (last != null) {
        query = query.startAfterDocument(last);
      }

      final snap = await query.get();

      if (!mounted) return;

      final newDocs = snap.docs;

      setState(() {
        _loaded.addAll(newDocs);
        if (newDocs.isNotEmpty) _lastDoc = newDocs.last;
        _hasMore = newDocs.length == _pageSize;
        _loading = false;
        _firstLoadDone = true;
      });

      // Ratings for the new cards only.
      _loadRatings(newDocs.map((d) => d.id).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _firstLoadDone = true;
        _error = e.toString();
      });
    }
  }

  /// When filters leave fewer than one page of matches, keep
  /// loading batches (up to a safe limit) to fill the page.
  Future<void> _topUp() async {
    var guard = 0;
    while (mounted &&
        _hasMore &&
        !_loading &&
        _filteredDocs().length < _pageSize &&
        guard < 6) {
      await _loadMore();
      guard++;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loaded.clear();
      _lastDoc = null;
      _hasMore = true;
      _firstLoadDone = false;
      _error = null;
      _ratings.clear();
    });

    await _loadOptions(force: true);
    await _loadMore();
    await _topUp();
  }

  // ------------------------------------------------------------
  // RATINGS (one query per batch of up to 10 properties)
  // ------------------------------------------------------------

  Future<void> _loadRatings(List<String> ids) async {
    final todo = ids.where((id) => !_ratings.containsKey(id)).toList();
    if (todo.isEmpty) return;

    try {
      for (var i = 0; i < todo.length; i += 10) {
        final chunk = todo.sublist(
          i,
          i + 10 > todo.length ? todo.length : i + 10,
        );

        final snap = await FirebaseFirestore.instance
            .collection('reviews')
            .where('propertyId', whereIn: chunk)
            .get();

        final sums = <String, double>{};
        final counts = <String, int>{};

        for (final doc in snap.docs) {
          final data = doc.data();
          final pid = data['propertyId']?.toString() ?? '';
          final rating = data['rating'];
          if (pid.isEmpty || rating is! num) continue;

          sums[pid] = (sums[pid] ?? 0) + rating.toDouble();
          counts[pid] = (counts[pid] ?? 0) + 1;
        }

        if (!mounted) return;

        setState(() {
          for (final id in chunk) {
            final count = counts[id] ?? 0;
            _ratings[id] = count == 0
                ? const _RatingSummary(0, 0)
                : _RatingSummary((sums[id] ?? 0) / count, count);
          }
        });
      }
    } catch (_) {
      // Ratings are optional; cards simply show nothing.
    }
  }

  // ------------------------------------------------------------
  // PARSING HELPERS
  // ------------------------------------------------------------

  double? _parsePrice(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    // Strip "KES", commas, spaces etc. from string prices.
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty || cleaned == '.') return null;

    return double.tryParse(cleaned);
  }

  String _commas(num value) {
    return value.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
    );
  }

  String _priceText(Map<String, dynamic> data) {
    final price = data['price'];

    if (price is num) {
      final cycle = data['paymentCycle']?.toString() ?? '';
      final cycleText = cycle
          .replaceFirst(RegExp(r'^per[_ ]'), '')
          .replaceAll('_', ' ')
          .trim();

      return cycleText.isEmpty
          ? 'KES ${_commas(price)}'
          : 'KES ${_commas(price)} / $cycleText';
    }

    final text = price?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;

    final display = data['priceDisplay']?.toString().trim() ?? '';
    if (display.isNotEmpty) return display;

    return _tr('Price available on request', 'Bei inapatikana kwa ombi');
  }

  String? _imageOf(Map<String, dynamic> data) {
    String? first(dynamic v) {
      if (v is Iterable && v.isNotEmpty) return v.first?.toString();
      return null;
    }

    final candidates = [
      data['mainImage']?.toString(),
      data['image']?.toString(),
      first(data['images']),
      first(data['unitImages']),
    ];

    for (final c in candidates) {
      if (c != null && c.isNotEmpty) return c;
    }
    return null;
  }

  // ------------------------------------------------------------
  // FILTERS (all comparisons use normalised keys)
  // ------------------------------------------------------------

  bool _matchesFilters(Map<String, dynamic> data) {
    // Deactivated listings are never shown.
    if (_isDeactivatedProperty(data)) return false;

    if (!_isHostel(data)) return false;

    // ---- CAMPUS ----
    if (selectedCampus.isNotEmpty) {
      final campusKey = LabelNormalizer.key(_campusOf(data));
      if (campusKey != LabelNormalizer.key(selectedCampus)) return false;
    }

    // ---- ROOM TYPE ----
    if (selectedRoomType.isNotEmpty) {
      final wanted = LabelNormalizer.key(selectedRoomType);
      final keys = _roomValues(data).map(LabelNormalizer.key).toSet();
      if (!keys.contains(wanted)) return false;
    }

    // ---- BUDGET (maximum price) ----
    final maxBudget = double.tryParse(budgetController.text.trim());
    if (maxBudget != null && maxBudget > 0) {
      final price = _parsePrice(data['price']);
      // Listings without a price are still shown.
      if (price != null && price > maxBudget) return false;
    }

    // ---- PREFERRED AREA ----
    if (selectedArea.isNotEmpty) {
      final wanted = LabelNormalizer.key(selectedArea);
      final keys = _areaValues(data).map(LabelNormalizer.key).toSet();
      if (!keys.contains(wanted)) return false;
    }

    return true;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredDocs() {
    return _loaded.where((d) => _matchesFilters(d.data())).toList();
  }

  // ------------------------------------------------------------
  // VIEW LOGGING — one doc per property + user (no double count)
  // ------------------------------------------------------------

  Future<void> _logView(String propertyId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || propertyId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('property_views')
          .doc('${propertyId}_view_$uid')
          .set({
        'kind': 'view',
        'propertyId': propertyId,
        'userId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Already counted for this user, or offline — ignore.
    }
  }

  // ------------------------------------------------------------
  // WIZARD — helpers
  // ------------------------------------------------------------

  String get _stepTitle {
    switch (wizardStep) {
      case 0:
        return _tr('Which campus?', 'Chuo gani?');
      case 1:
        return _tr('Room type', 'Aina ya chumba');
      case 2:
        return _tr('Your budget', 'Bajeti yako');
      case 3:
        return _tr('Preferred area', 'Eneo unalopendelea');
      default:
        return '';
    }
  }

  bool get _isLastStep => wizardStep == wizardStepCount - 1;

  void _nextStep() {
    FocusScope.of(context).unfocus();
    if (wizardStep < wizardStepCount - 1) {
      setState(() => wizardStep++);
    }
  }

  void _previousStep() {
    FocusScope.of(context).unfocus();
    if (wizardStep > 0) {
      setState(() => wizardStep--);
    }
  }

  void _resetWizard() {
    setState(() {
      wizardStep = 0;
      selectedCampus = '';
      selectedRoomType = '';
      selectedArea = '';
      budgetController.clear();
      wizardApplied = false;
    });
  }

  void _applyWizard() {
    FocusScope.of(context).unfocus();
    setState(() => wizardApplied = true);

    _showSnack(
      _tr('Applying your search answers...',
          'Ninaweka majibu yako ya utafutaji...'),
    );

    // Make sure enough matching listings are loaded.
    _topUp();
  }

  String get _wizardSummary {
    final parts = <String>[];

    if (selectedCampus.isNotEmpty) {
      parts.add(_tr('Near $selectedCampus', 'Karibu na $selectedCampus'));
    } else {
      parts.add(_tr('Any campus', 'Chuo chochote'));
    }

    if (selectedRoomType.isNotEmpty) {
      parts.add(selectedRoomType);
    } else {
      parts.add(_tr('Any room', 'Chumba chochote'));
    }

    final budget = double.tryParse(budgetController.text.trim());
    if (budget != null && budget > 0) {
      parts.add('≤ KES ${budget.round()}');
    }

    if (selectedArea.isNotEmpty) {
      parts.add(selectedArea);
    }

    return parts.join(' · ');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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
          _tr('Find Your Hostel', 'Tafuta Hosteli Yako'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_firstLoadDone && _error == null) {
      return Center(
        child: CircularProgressIndicator(color: _brand),
      );
    }

    if (_error != null && _loaded.isEmpty) {
      return _errorState(_error!);
    }

    final filtered = _filteredDocs();

    // ---- ADS-VERIFIED FIRST, others after ----
    final adsVerified =
    filtered.where((d) => _isAdsVerified(d.data())).toList();
    final notAdsVerified =
    filtered.where((d) => !_isAdsVerified(d.data())).toList();
    final sorted = [...adsVerified, ...notAdsVerified];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: RefreshIndicator(
          color: _brand,
          onRefresh: _refresh,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              _buildIntro(),
              _buildListHostelPrompt(),
              _buildWizardSection(),
              _buildResultHeader(sorted.length),
              if (sorted.isEmpty && !_loading)
                _emptyState()
              else
                ...sorted.map(
                      (document) => _hostelCard(
                    document.id,
                    document.data(),
                  ),
                ),
              _buildPaginationFooter(sorted.isNotEmpty),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationFooter(bool hasResults) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(color: _brand),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _tr('Could not load more hostels.',
                  'Imeshindikana kupakia hosteli zaidi.'),
              style: TextStyle(color: _mutedText),
            ),
            TextButton(
              onPressed: _loadMore,
              child: Text(_tr('Try again', 'Jaribu tena')),
            ),
          ],
        ),
      );
    }

    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: OutlinedButton.icon(
          onPressed: _loadMore,
          icon: const Icon(Icons.expand_more),
          label: Text(_tr('Load more hostels', 'Pakia hosteli zaidi')),
          style: OutlinedButton.styleFrom(
            foregroundColor: _brand,
            side: BorderSide(color: _brand.withValues(alpha: .5)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      );
    }

    if (hasResults) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            _tr("You've reached the end.", 'Umefika mwisho.'),
            style: TextStyle(fontSize: 12, color: _mutedText),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildIntro() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
        children: [
          const Icon(Icons.apartment_rounded, color: Colors.white, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _tr(
                'Verified student hostels across Kenya.',
                'Hosteli za wanafunzi zilizothibitishwa kote Kenya.',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHostelPrompt() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: _brandSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brand.withValues(alpha: .25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegistrationPage()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Icon(Icons.add_home_work_outlined, color: _brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tr(
                      'Own a hostel? Tap to list it here.',
                      'Una hosteli? Gonga kuiweka hapa.',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _bodyText,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: _brand),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // STEP-BY-STEP HOSTEL SEARCH ASSISTANT
  // ============================================================

  Widget _buildWizardSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _brandSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _brand.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------------- HEADER ----------------
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _brand,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.travel_explore, color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr('Hostel Search Assistant',
                          'Msaidizi wa Kutafuta Hosteli'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr('Answer a few questions for precise results',
                          'Jibu maswali machache kwa matokeo sahihi'),
                      style: TextStyle(fontSize: 11, color: _mutedText),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _resetWizard,
                child: Text(_tr('Reset', 'Anza upya')),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // ---------------- PROGRESS BARS ----------------
          Row(
            children: [
              for (int i = 0; i < wizardStepCount; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 6,
                    decoration: BoxDecoration(
                      color: i <= wizardStep
                          ? _brand
                          : _brand.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (i < wizardStepCount - 1) const SizedBox(width: 5),
              ],
            ],
          ),

          const SizedBox(height: 6),

          Text(
            _tr('Step ${wizardStep + 1} of $wizardStepCount',
                'Hatua ${wizardStep + 1} kati ya $wizardStepCount'),
            style: TextStyle(fontSize: 11, color: _mutedText),
          ),

          const SizedBox(height: 14),

          // ---------------- STEP TITLE ----------------
          Text(
            _stepTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 14),

          // ---------------- STEP CONTENT ----------------
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _wizardStepContent(),
          ),

          const SizedBox(height: 16),

          // ---------------- NAVIGATION BUTTONS ----------------
          Row(
            children: [
              if (wizardStep > 0)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _previousStep,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(_tr('Back', 'Nyuma')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brand,
                      side: BorderSide(color: _brand.withValues(alpha: .5)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              if (wizardStep > 0) const SizedBox(width: 10),
              Expanded(
                flex: wizardStep > 0 ? 2 : 1,
                child: _isLastStep
                    ? ElevatedButton.icon(
                  onPressed: _applyWizard,
                  icon: const Icon(Icons.travel_explore),
                  label: Text(
                    _tr('Find matching hostels',
                        'Tafuta hosteli zinazofaa'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                )
                    : ElevatedButton.icon(
                  onPressed: _nextStep,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(_tr('Next', 'Endelea')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),

          // ---------------- SUMMARY ----------------
          if (wizardApplied) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _brand.withValues(alpha: .3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('Searching for:', 'Ninatafuta:'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _brand,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _wizardSummary,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _bodyText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tr(
                      'Change any answer above and tap Find again.',
                      'Badilisha jibu lolote hapo juu kisha gonga '
                          'Tafuta tena.',
                    ),
                    style: TextStyle(fontSize: 10, color: _mutedText),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _wizardStepContent() {
    switch (wizardStep) {
      case 0:
        return _stepCampus();
      case 1:
        return _stepRoomType();
      case 2:
        return _stepBudget();
      case 3:
        return _stepArea();
      default:
        return const SizedBox.shrink();
    }
  }

  // ---- SHARED SEARCHABLE DROPDOWN FIELD ----

  Widget _dropdownField({
    required String label,
    required IconData icon,
    required String value,
    required String placeholder,
    required String sheetTitle,
    required List<String> options,
    required ValueChanged<String> onPicked,
  }) {
    final hasValue = value.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: options.isEmpty
          ? null
          : () async {
        FocusScope.of(context).unfocus();
        final picked = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: _cardColor,
          shape: const RoundedRectangleBorder(
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _PickerSheet(
            title: sheetTitle,
            items: List<String>.from(options),
            selected: value,
            brand: _brand,
            bodyText: _bodyText,
            mutedText: _mutedText,
            searchHint: _tr('Search...', 'Tafuta...'),
            emptyText: _tr('No results', 'Hakuna matokeo'),
          ),
        );
        if (picked != null) {
          onPicked(picked);
        }
      },
      child: InputDecorator(
        decoration: _fieldDecoration(label, icon),
        isEmpty: false,
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  hasValue ? value : placeholder,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: hasValue ? _bodyText : _mutedText,
                  ),
                ),
              ),
            ),
            if (hasValue)
              GestureDetector(
                onTap: () => onPicked(''),
                child: Icon(Icons.close, size: 20, color: _mutedText),
              )
            else
              Icon(Icons.arrow_drop_down, color: _mutedText),
          ],
        ),
      ),
    );
  }

  // ---- STEP 1: CAMPUS ----

  Widget _stepCampus() {
    return Column(
      key: const ValueKey('step-campus'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('Which campus do you want to be near?',
              'Unataka kuwa karibu na chuo gani?'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _mutedText,
          ),
        ),
        const SizedBox(height: 8),
        _dropdownField(
          label: _tr('Campus / University', 'Chuo / Chuo Kikuu'),
          icon: Icons.school_outlined,
          value: selectedCampus,
          placeholder: _tr('Choose campus', 'Chagua chuo'),
          sheetTitle: _tr('Choose campus', 'Chagua chuo'),
          options: _campuses,
          onPicked: (picked) {
            setState(() {
              selectedCampus = picked;
              wizardApplied = false;
            });
            _topUp();
          },
        ),
        const SizedBox(height: 8),
        Text(
          _campuses.isEmpty
              ? _tr('No campuses are listed yet. You can skip this step.',
              'Hakuna vyuo vilivyoorodheshwa bado. Unaweza kuruka.')
              : _tr(
              'Campuses come from verified hostels. Leave empty to '
                  'see hostels near any campus.',
              'Vyuo vinatoka kwa hosteli zilizothibitishwa. Acha wazi '
                  'kuona hosteli karibu na chuo chochote.'),
          style: TextStyle(fontSize: 10, color: _mutedText),
        ),
      ],
    );
  }

  // ---- STEP 2: ROOM TYPE ----

  Widget _stepRoomType() {
    return Column(
      key: const ValueKey('step-room'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('What kind of room do you need?',
              'Unahitaji chumba cha aina gani?'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _mutedText,
          ),
        ),
        const SizedBox(height: 8),
        _dropdownField(
          label: _tr('Room / unit type', 'Aina ya chumba / kitengo'),
          icon: Icons.bed_outlined,
          value: selectedRoomType,
          placeholder: _tr('Any room', 'Chumba chochote'),
          sheetTitle: _tr('Choose room type', 'Chagua aina ya chumba'),
          options: _roomOptions,
          onPicked: (picked) {
            setState(() {
              selectedRoomType = picked;
              wizardApplied = false;
            });
            _topUp();
          },
        ),
        const SizedBox(height: 8),
        Text(
          _roomOptions.isEmpty
              ? _tr('No room types are listed yet. You can skip this step.',
              'Hakuna aina za vyumba zilizoonekana bado. Unaweza kuruka.')
              : _tr(
              'Room types come from verified hostels — no repeats. '
                  'Leave empty to see all room types.',
              'Aina za vyumba zinatoka kwa hosteli zilizothibitishwa — '
                  'hakuna marudio. Acha wazi kuona zote.'),
          style: TextStyle(fontSize: 10, color: _mutedText),
        ),
      ],
    );
  }

  // ---- STEP 3: BUDGET (DIGITS ONLY — STRICT) ----

  void _sanitizeBudget() {
    final raw = budgetController.text;
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');

    var sanitized = digitsOnly;
    if (sanitized.length > 9) {
      sanitized = sanitized.substring(0, 9);
    }

    if (sanitized != raw) {
      budgetController.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
      );
    }
  }

  Widget _stepBudget() {
    return Column(
      key: const ValueKey('step-budget'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('Maximum budget (KES) — optional',
              'Bajeti kubwa zaidi (KES) — hiari'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _mutedText,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: budgetController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          onChanged: (_) {
            _sanitizeBudget();
            setState(() => wizardApplied = false);
          },
          style: TextStyle(color: _bodyText),
          decoration: _fieldDecoration(
            _tr('Budget', 'Bajeti'),
            Icons.payments_outlined,
            hint: _tr('e.g. 5000', 'mf. 5000'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _tr('Numbers only. Listings without a price are still shown.',
              'Namba pekee. Orodha zisizo na bei bado zinaonyeshwa.'),
          style: TextStyle(fontSize: 10, color: _mutedText),
        ),
      ],
    );
  }

  // ---- STEP 4: PREFERRED AREA ----

  Widget _stepArea() {
    return Column(
      key: const ValueKey('step-area'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('Estate, town or location — optional',
              'Mtaa, mji au eneo — hiari'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _mutedText,
          ),
        ),
        const SizedBox(height: 8),
        _dropdownField(
          label: _tr('Preferred area', 'Eneo unalopendelea'),
          icon: Icons.place_outlined,
          value: selectedArea,
          placeholder: _tr('Any area', 'Eneo lolote'),
          sheetTitle: _tr('Choose area', 'Chagua eneo'),
          options: _areas,
          onPicked: (picked) {
            setState(() {
              selectedArea = picked;
              wizardApplied = false;
            });
            _topUp();
          },
        ),
        const SizedBox(height: 8),
        Text(
          _areas.isEmpty
              ? _tr('No areas are listed yet. You can skip this step.',
              'Hakuna maeneo yaliyoonekana bado. Unaweza kuruka.')
              : _tr(
              'Areas come from verified hostels — no repeats. '
                  'Leave empty to see hostels in every area.',
              'Maeneo yanatoka kwa hosteli zilizothibitishwa — '
                  'hakuna marudio. Acha wazi kuona yote.'),
          style: TextStyle(fontSize: 10, color: _mutedText),
        ),
      ],
    );
  }

  // ---- FIELD DECORATION ----

  InputDecoration _fieldDecoration(
      String label,
      IconData icon, {
        String? hint,
      }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: _mutedText),
      prefixIcon: Icon(icon, size: 20, color: _brand),
      filled: true,
      fillColor: _cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _brand, width: 2),
      ),
    );
  }

  Widget _buildResultHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _tr('Available hostels', 'Hosteli zinazopatikana'),
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            _hasMore
                ? _tr('$count shown', '$count zimeonyeshwa')
                : _tr('$count found', '$count zimepatikana'),
            style: TextStyle(
              color: _brand,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // RATING ROW (stars + average + review count)
  // ------------------------------------------------------------

  Widget _ratingRow(String id) {
    final summary = _ratings[id];

    // Not loaded yet: reserve no space, avoids layout jumps.
    if (summary == null) return const SizedBox.shrink();

    if (summary.count == 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(Icons.star_border_rounded, size: 17, color: _mutedText),
            const SizedBox(width: 4),
            Text(
              _tr('No reviews yet', 'Hakuna maoni bado'),
              style: TextStyle(fontSize: 12, color: _mutedText),
            ),
          ],
        ),
      );
    }

    final avg = summary.average;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (int i = 1; i <= 5; i++)
            Icon(
              avg >= i
                  ? Icons.star_rounded
                  : (avg >= i - 0.5
                  ? Icons.star_half_rounded
                  : Icons.star_border_rounded),
              size: 18,
              color: const Color(0xFFF5A623),
            ),
          const SizedBox(width: 6),
          Text(
            avg.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '(${summary.count} ${summary.count == 1 ? _tr('review', 'maoni') : _tr('reviews', 'maoni')})',
            style: TextStyle(fontSize: 12, color: _mutedText),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // HOSTEL CARD — logs a view (per user) when opened
  // ------------------------------------------------------------

  Widget _hostelCard(String id, Map<String, dynamic> data) {
    final imageUrl = _imageOf(data);
    final campus = _campusOf(data);
    final adsVerified = _isAdsVerified(data);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      color: _cardColor,
      child: InkWell(
        onTap: () {
          _logView(id);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PropertyDetailsPage(
                property: {...data, 'id': id},
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                width: double.infinity,
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _imagePlaceholder(),
              )
            else
              _imagePlaceholder(),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['title']?.toString() ?? _tr('Hostel', 'Hosteli'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (adsVerified)
                        Icon(Icons.campaign, size: 18, color: _brand),
                    ],
                  ),

                  // ---- STARS + REVIEW COUNT ----
                  _ratingRow(id),

                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: _mutedText,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          data['location']?.toString() ??
                              _tr('Location not specified',
                                  'Eneo halijatajwa'),
                          style: TextStyle(color: _mutedText),
                        ),
                      ),
                    ],
                  ),
                  if (campus.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 17,
                          color: _mutedText,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _tr('Near $campus', 'Karibu na $campus'),
                            style: TextStyle(color: _mutedText),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _priceText(data),
                    style: TextStyle(
                      color: _brandDeep,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.verified, size: 17, color: _brand),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _tr('Verified listing', 'Orodha imethibitishwa'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _tr('View →', 'Tazama →'),
                        style: TextStyle(
                          color: _brand,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 190,
      color: _isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      child: Icon(
        Icons.apartment_rounded,
        size: 55,
        color: _mutedText,
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(35),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 65,
            color: _isDark ? Colors.grey.shade600 : Colors.grey.shade400,
          ),
          const SizedBox(height: 15),
          Text(
            _tr('No hostels found', 'Hakuna hosteli zilizopatikana'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(
              'Try relaxing your campus, room type, budget or area answers '
                  'in the Hostel Search Assistant.',
              'Jaribu kupunguza majibu ya chuo, aina ya chumba, bajeti au '
                  'eneo katika Msaidizi wa Kutafuta Hosteli.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedText),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 50, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              _tr('Unable to load hostels', 'Imeshindikana kupakia hosteli'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _refresh,
              child: Text(_tr('Try again', 'Jaribu tena')),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Searchable bottom sheet used for campus / room type / area
// picking
// ============================================================
class _PickerSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final String selected;
  final Color brand;
  final Color bodyText;
  final Color mutedText;
  final String searchHint;
  final String emptyText;

  const _PickerSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.brand,
    required this.bodyText,
    required this.mutedText,
    required this.searchHint,
    required this.emptyText,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((item) => item.toLowerCase().contains(query.toLowerCase()))
        .toList();

    final height = MediaQuery.of(context).size.height * 0.75;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.mutedText.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: widget.brand, width: 2),
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                child: Text(
                  widget.emptyText,
                  style: TextStyle(color: widget.mutedText),
                ),
              )
                  : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final isSelected = item == widget.selected;

                  return ListTile(
                    title: Text(
                      item,
                      style: TextStyle(
                        color: isSelected
                            ? widget.brand
                            : widget.bodyText,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: widget.brand)
                        : null,
                    onTap: () => Navigator.pop(context, item),
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