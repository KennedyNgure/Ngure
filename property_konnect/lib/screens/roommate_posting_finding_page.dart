// ============================================================
// roommate_posting_finding_page.dart  (FULL FILE)
// "Roommate Finder": post a roommate request, or find posted
// requests with a step-by-step search assistant. No account
// needed.
//
// UPDATED:
//  - ALL filters (gender chips, campus dropdown, search box) are
//    replaced by a step-by-step SEARCH ASSISTANT (like the
//    hostels page): campus, accommodation type, gender, budget
//    range (min / max) and preferred location. Dropdowns are
//    built from Firestore, normalised and de-duplicated.
//  - FAVOURITES: a heart on every card / in the details dialog
//    saves a request (FavouritesService) - no sign-in needed.
//  - REPORT: users can report suspicious, misleading or
//    inappropriate posts (saved to the `reports` collection,
//    one report per device per post).
//  - PAGINATION: posts load in batches of 10 (orderBy createdAt
//    + startAfterDocument), auto-loading near the bottom, a
//    "Load more" button and pull-to-refresh.
//  - New posts are normalised on save (campus, accommodation
//    type, area) so filtering stays consistent.
//
// Phone number is never displayed (Call / WhatsApp still work).
// Needs url_launcher + shared_preferences in pubspec.yaml.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_localizations.dart';
import 'app_settings.dart';
import 'favourites_service.dart';
import 'hostels_page.dart' show LabelNormalizer;
import 'post_helpers.dart';
import 'property_details_page.dart' show DeviceIdService;

/// Firestore collection that stores roommate requests.
const String kRoommateCollection = 'roommates';

/// Firestore collection that stores user reports.
const String kReportsCollection = 'reports';

const Color _kRoommateGreen = Color(0xFF2E9534);
const Color _kWhatsAppGreen = Color(0xFF25D366);

// ============================================================
// MODEL
// ============================================================

class RoommatePost {
  final String id;
  final String name;
  final String phone;
  final String campus;
  final String hostelName;
  final String area;
  final String budget;
  final String budgetPeriod;
  final String gender;
  final String accommodationType;
  final String preferences;
  final String userId;
  final String deleteCode;
  final String status;
  final DateTime? createdAt;

  const RoommatePost({
    required this.id,
    required this.name,
    required this.phone,
    required this.campus,
    required this.hostelName,
    required this.area,
    required this.budget,
    required this.budgetPeriod,
    required this.gender,
    required this.accommodationType,
    required this.preferences,
    required this.userId,
    required this.deleteCode,
    required this.status,
    required this.createdAt,
  });

  /// Posts an admin removed / hid (e.g. after reports) are never
  /// shown. Set `status: 'hidden'` on a reported post to hide it.
  bool get isHidden {
    final s = status.toLowerCase();
    return s == 'deleted' ||
        s == 'hidden' ||
        s == 'removed' ||
        s == 'suspended';
  }

  static String _pick(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;

      if (value is num) {
        return value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString();
      }

      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  factory RoommatePost.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};
    final timestamp = data['createdAt'];

    return RoommatePost(
      id: document.id,
      name: _pick(data, ['name', 'fullName', 'full_name']),
      phone: _pick(data, ['phone', 'phoneNumber', 'contact']),
      campus: _pick(data, [
        'campus',
        'campusName',
        'university',
        'universityCampus',
      ]),
      hostelName: _pick(data, ['hostelName', 'hostel']),
      area: _pick(data, ['preferredArea', 'area', 'location']),
      budget: _pick(data, ['budget']),
      budgetPeriod: _pick(data, ['budgetPeriod', 'period']),
      gender: _pick(data, ['gender', 'genderPreference']),
      accommodationType:
      _pick(data, ['accommodationType', 'accommodation', 'roomType']),
      preferences: _pick(data, ['preferences', 'roommatePreferences']),
      userId: _pick(data, ['userId', 'ownerId']),
      deleteCode: _pick(data, ['deleteCode', 'deleteKey', 'delete_code']),
      status: _pick(data, ['status']),
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

// ============================================================
// CAMPUS NORMALISATION (merges duplicates / word-order variants)
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

/// Same key for "maseno (main campus)", "Maseno(main campus).",
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
  words.sort();

  return words.join(' ');
}

/// "maseno(main campus)." -> "Maseno (Main Campus)"
String _prettyCampus(String raw) {
  var text = raw.trim();
  text = text.replaceAll(RegExp(r'[.,;:\s]+$'), '');
  text = text.replaceAll(RegExp(r'\s*\('), ' (');
  text = text.replaceAll(RegExp(r'\s*\)'), ')');
  text = text.replaceAll(RegExp(r'\s+'), ' ');

  return text.replaceAllMapped(
    RegExp(r'(^|[\s(])([a-z])'),
        (match) => '${match[1]}${match[2]!.toUpperCase()}',
  );
}

class _FilterOptions {
  final List<String> campuses;
  final List<String> accommodations;
  final List<String> locations;
  final DateTime fetchedAt;

  _FilterOptions({
    required this.campuses,
    required this.accommodations,
    required this.locations,
  }) : fetchedAt = DateTime.now();

  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < const Duration(minutes: 10);
}

// ============================================================
// PAGE
// ============================================================

class RoommatePostingFindingPage extends StatefulWidget {
  const RoommatePostingFindingPage({super.key});

  @override
  State<RoommatePostingFindingPage> createState() =>
      _RoommatePostingFindingPageState();
}

class _RoommatePostingFindingPageState
    extends State<RoommatePostingFindingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const int _pageSize = 10;
  static const String _reportedKey = 'reported_roommate_posts';

  /// Dropdown options are cached across visits (10 minutes).
  static _FilterOptions? _optionsCache;

  // ---- WIZARD STATE ----
  int _step = 0; // 0..4
  static const int _stepCount = 5;

  // '' = not chosen (no filtering on that answer).
  String _campus = '';
  String _accommodation = '';
  String _gender = ''; // '', Male, Female, Other
  String _location = '';

  final TextEditingController _minController = TextEditingController();
  final TextEditingController _maxController = TextEditingController();

  bool _applied = false;

  List<String> _campusOptions = [];
  List<String> _accommodationOptions = [];
  List<String> _locationOptions = [];

  // ---- PAGINATION STATE ----
  final ScrollController _scroll = ScrollController();
  final List<RoommatePost> _posts = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _loading = false;
  bool _firstLoadDone = false;
  String? _error;

  // ---- FAVOURITES + OWNER ----
  Set<String> _favIds = <String>{};
  String _ownerId = '';

  // ---- Theme + translation helpers ----
  bool get _isDark => AppSettings.of(context).isDark;
  Color get _brand => _isDark ? kBrandGreenOnDark : _kRoommateGreen;
  Color get _pageBg =>
      _isDark ? const Color(0xFF101812) : const Color(0xFFF4F8F4);
  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;
  Color get _textColor =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade800;
  Color get _subtle => _isDark ? Colors.grey.shade400 : Colors.grey.shade700;
  Color get _brandSoft => _isDark
      ? const Color(0xFF152219)
      : const Color(0xFFEAF7EF);

  String _tr(String en, String sw) {
    final code = AppSettings.of(context).languageCode;
    if (code == 'sw') return sw;
    return AppLocalizations.trText(en, code);
  }

  String _genderLabel(String value) {
    switch (value) {
      case '':
      case 'All':
        return _tr('Any', 'Yoyote');
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

  // ------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _scroll.addListener(_onScroll);

    loadOwnerId().then((id) {
      if (mounted) setState(() => _ownerId = id);
    });

    FavouritesService.roommateFavouriteIds().then((ids) {
      if (mounted) setState(() => _favIds = ids);
    });

    FavouritesService.roommateChanges.addListener(_onFavouritesChanged);

    _loadOptions();
    _loadMore();
  }

  @override
  void dispose() {
    FavouritesService.roommateChanges.removeListener(_onFavouritesChanged);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _onFavouritesChanged() {
    FavouritesService.roommateFavouriteIds().then((ids) {
      if (mounted) setState(() => _favIds = ids);
    });
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
      var query = _firestore
          .collection(kRoommateCollection)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      final last = _lastDoc;
      if (last != null) {
        query = query.startAfterDocument(last);
      }

      final snapshot = await query.get();

      if (!mounted) return;

      setState(() {
        _posts.addAll(snapshot.docs.map(RoommatePost.fromFirestore));
        if (snapshot.docs.isNotEmpty) _lastDoc = snapshot.docs.last;
        _hasMore = snapshot.docs.length == _pageSize;
        _loading = false;
        _firstLoadDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _firstLoadDone = true;
        _error = e.toString();
      });
    }
  }

  /// When the answers leave fewer than one page of matches,
  /// keep loading batches (up to a safe limit) to fill the page.
  Future<void> _topUp() async {
    var guard = 0;
    while (mounted &&
        _hasMore &&
        !_loading &&
        _filtered().length < _pageSize &&
        guard < 6) {
      await _loadMore();
      guard++;
    }
  }

  Future<void> _refresh() async {
    _optionsCache = null;

    setState(() {
      _posts.clear();
      _lastDoc = null;
      _hasMore = true;
      _firstLoadDone = false;
      _error = null;
    });

    await _loadOptions();
    await _loadMore();
    await _topUp();
  }

  // ------------------------------------------------------------
  // DROPDOWN OPTIONS - fetched once, cached, de-duplicated
  // ------------------------------------------------------------

  List<String> _splitValues(String raw, int maxLength) {
    final out = <String>[];
    for (final piece in raw.split(',')) {
      final cleaned = LabelNormalizer.display(piece);
      if (cleaned.isEmpty || cleaned.length > maxLength) continue;
      out.add(cleaned);
    }
    return out;
  }

  List<String> _accommodationValues(RoommatePost post) =>
      _splitValues(post.accommodationType, 40);

  List<String> _locationValues(RoommatePost post) =>
      _splitValues(post.area, 60);

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

  /// One label per campus (merges word-order / spelling variants,
  /// the most used spelling wins).
  List<String> _campusLabels(List<RoommatePost> posts) {
    final variants = <String, Map<String, int>>{};

    for (final post in posts) {
      final raw = post.campus.trim();
      if (raw.isEmpty) continue;

      final key = _campusKey(raw);
      if (key.isEmpty) continue;

      final label = _prettyCampus(raw);
      final counts = variants.putIfAbsent(key, () => <String, int>{});
      counts[label] = (counts[label] ?? 0) + 1;
    }

    final labels = <String>[];

    variants.forEach((key, counts) {
      final entries = counts.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          if (byCount != 0) return byCount;
          return a.key.length.compareTo(b.key.length);
        });
      labels.add(entries.first.key);
    });

    labels.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return labels;
  }

  Future<void> _loadOptions() async {
    final cached = _optionsCache;
    if (cached != null && cached.isFresh) {
      _applyOptions(cached);
      return;
    }

    try {
      final snapshot = await _firestore.collection(kRoommateCollection).get();

      final posts = snapshot.docs
          .map(RoommatePost.fromFirestore)
          .where((p) => !p.isHidden)
          .toList();

      final options = _FilterOptions(
        campuses: _campusLabels(posts),
        accommodations:
        _unique(posts.expand((p) => _accommodationValues(p))),
        locations: _unique(posts.expand((p) => _locationValues(p))),
      );

      _optionsCache = options;
      _applyOptions(options);
    } catch (_) {
      // Dropdowns stay empty; the list itself still works.
    }
  }

  void _applyOptions(_FilterOptions options) {
    if (!mounted) return;

    setState(() {
      _campusOptions = options.campuses;
      _accommodationOptions = options.accommodations;
      _locationOptions = options.locations;

      if (_campus.isNotEmpty &&
          !options.campuses
              .any((c) => _campusKey(c) == _campusKey(_campus))) {
        _campus = '';
      }
      if (_accommodation.isNotEmpty &&
          !options.accommodations.any((a) =>
          LabelNormalizer.key(a) == LabelNormalizer.key(_accommodation))) {
        _accommodation = '';
      }
      if (_location.isNotEmpty &&
          !options.locations.any((l) =>
          LabelNormalizer.key(l) == LabelNormalizer.key(_location))) {
        _location = '';
      }
    });
  }

  // ------------------------------------------------------------
  // FILTERING (from the assistant's answers)
  // ------------------------------------------------------------

  double? _budgetValue(RoommatePost post) {
    final cleaned = post.budget.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty || cleaned == '.') return null;
    return double.tryParse(cleaned);
  }

  bool _matches(RoommatePost post) {
    if (post.isHidden) return false;

    // ---- CAMPUS ----
    if (_campus.isNotEmpty &&
        _campusKey(post.campus) != _campusKey(_campus)) {
      return false;
    }

    // ---- ACCOMMODATION TYPE ----
    if (_accommodation.isNotEmpty) {
      final wanted = LabelNormalizer.key(_accommodation);
      final keys =
      _accommodationValues(post).map(LabelNormalizer.key).toSet();
      final text = post.accommodationType.toLowerCase();

      if (!keys.contains(wanted) && !text.contains(wanted)) return false;
    }

    // ---- GENDER ----
    if (_gender.isNotEmpty &&
        post.gender.toLowerCase() != _gender.toLowerCase()) {
      return false;
    }

    // ---- BUDGET RANGE ----
    var min = double.tryParse(_minController.text.trim());
    var max = double.tryParse(_maxController.text.trim());

    if (min != null && max != null && min > max) {
      final swap = min;
      min = max;
      max = swap;
    }

    final budget = _budgetValue(post);
    // Posts without a budget are still shown.
    if (budget != null) {
      if (min != null && min > 0 && budget < min) return false;
      if (max != null && max > 0 && budget > max) return false;
    }

    // ---- PREFERRED LOCATION ----
    if (_location.isNotEmpty) {
      final wanted = LabelNormalizer.key(_location);
      final keys = _locationValues(post).map(LabelNormalizer.key).toSet();
      final text = '${post.area} ${post.hostelName}'.toLowerCase();

      if (!keys.contains(wanted) && !text.contains(wanted)) return false;
    }

    return true;
  }

  List<RoommatePost> _filtered() => _posts.where(_matches).toList();

  // ------------------------------------------------------------
  // WIZARD helpers
  // ------------------------------------------------------------

  String get _stepTitle {
    switch (_step) {
      case 0:
        return _tr('Which campus?', 'Chuo gani?');
      case 1:
        return _tr('Accommodation type', 'Aina ya malazi');
      case 2:
        return _tr('Roommate gender', 'Jinsia ya mwenzi');
      case 3:
        return _tr('Budget range', 'Kiwango cha bajeti');
      case 4:
        return _tr('Preferred location', 'Eneo unalopendelea');
      default:
        return '';
    }
  }

  bool get _isLastStep => _step == _stepCount - 1;

  void _nextStep() {
    FocusScope.of(context).unfocus();
    if (_step < _stepCount - 1) setState(() => _step++);
  }

  void _previousStep() {
    FocusScope.of(context).unfocus();
    if (_step > 0) setState(() => _step--);
  }

  void _resetWizard() {
    setState(() {
      _step = 0;
      _campus = '';
      _accommodation = '';
      _gender = '';
      _location = '';
      _minController.clear();
      _maxController.clear();
      _applied = false;
    });
  }

  void _applyWizard() {
    FocusScope.of(context).unfocus();

    // Swap a min that is higher than the max.
    final min = int.tryParse(_minController.text.trim());
    final max = int.tryParse(_maxController.text.trim());
    if (min != null && max != null && min > max) {
      _minController.text = max.toString();
      _maxController.text = min.toString();
    }

    setState(() => _applied = true);

    _showMessage(_tr('Applying your search answers...',
        'Ninaweka majibu yako ya utafutaji...'));

    _topUp();
  }

  String get _summary {
    final parts = <String>[];

    parts.add(_campus.isNotEmpty
        ? _campus
        : _tr('Any campus', 'Chuo chochote'));

    parts.add(_accommodation.isNotEmpty
        ? _accommodation
        : _tr('Any accommodation', 'Malazi yoyote'));

    if (_gender.isNotEmpty) parts.add(_genderLabel(_gender));

    final min = int.tryParse(_minController.text.trim());
    final max = int.tryParse(_maxController.text.trim());
    if (min != null && min > 0 && max != null && max > 0) {
      parts.add('KES $min - $max');
    } else if (min != null && min > 0) {
      parts.add('≥ KES $min');
    } else if (max != null && max > 0) {
      parts.add('≤ KES $max');
    }

    if (_location.isNotEmpty) parts.add(_location);

    return parts.join(' · ');
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          _tr('Roommate Finder', 'Mtafuta Mwenzi wa Chumba'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        onPressed: _showPostDialog,
        icon: const Icon(Icons.add),
        label: Text(
          _tr('Post Request', 'Posti Ombi'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_firstLoadDone && _error == null) {
      return Center(child: CircularProgressIndicator(color: _brand));
    }

    if (_error != null && _posts.isEmpty) {
      return _buildErrorState(_error!);
    }

    final filtered = _filtered();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: RefreshIndicator(
          color: _brand,
          onRefresh: _refresh,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              _buildWizard(),
              _buildResultHeader(filtered.length),
              if (filtered.isEmpty && !_loading)
                _buildEmptyState()
              else
                for (final post in filtered) _buildCard(post),
              _buildPaginationFooter(filtered.isNotEmpty),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _tr('Roommate requests', 'Maombi ya wenzi wa chumba'),
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: _textColor,
              ),
            ),
          ),
          Text(
            _hasMore
                ? _tr('$count shown', '$count zimeonyeshwa')
                : _tr('$count found', '$count zimepatikana'),
            style: TextStyle(color: _brand, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter(bool hasResults) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: _brand)),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _tr('Could not load more requests.',
                  'Imeshindikana kupakia maombi zaidi.'),
              style: TextStyle(color: _subtle),
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
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: OutlinedButton.icon(
          onPressed: _loadMore,
          icon: const Icon(Icons.expand_more),
          label: Text(_tr('Load more requests', 'Pakia maombi zaidi')),
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
            style: TextStyle(fontSize: 12, color: _subtle),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ============================================================
  // STEP-BY-STEP SEARCH ASSISTANT
  // ============================================================

  Widget _buildWizard() {
    return Container(
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
                      _tr('Roommate Search Assistant',
                          'Msaidizi wa Kutafuta Mwenzi'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr('Answer a few questions for precise results',
                          'Jibu maswali machache kwa matokeo sahihi'),
                      style: TextStyle(fontSize: 11, color: _subtle),
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
              for (int i = 0; i < _stepCount; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 6,
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? _brand
                          : _brand.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (i < _stepCount - 1) const SizedBox(width: 5),
              ],
            ],
          ),

          const SizedBox(height: 6),

          Text(
            _tr('Step ${_step + 1} of $_stepCount',
                'Hatua ${_step + 1} kati ya $_stepCount'),
            style: TextStyle(fontSize: 11, color: _subtle),
          ),

          const SizedBox(height: 14),

          Text(
            _stepTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),

          const SizedBox(height: 14),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _stepContent(),
          ),

          const SizedBox(height: 16),

          // ---------------- NAVIGATION BUTTONS ----------------
          Row(
            children: [
              if (_step > 0)
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
              if (_step > 0) const SizedBox(width: 10),
              Expanded(
                flex: _step > 0 ? 2 : 1,
                child: _isLastStep
                    ? ElevatedButton.icon(
                  onPressed: _applyWizard,
                  icon: const Icon(Icons.travel_explore),
                  label: Text(_tr('Find roommate requests',
                      'Tafuta maombi ya wenzi')),
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
          if (_applied) ...[
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
                    _summary,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _subtle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tr('Change any answer above and tap Find again.',
                        'Badilisha jibu lolote hapo juu kisha gonga '
                            'Tafuta tena.'),
                    style: TextStyle(fontSize: 10, color: _subtle),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case 0:
        return _stepCampus();
      case 1:
        return _stepAccommodation();
      case 2:
        return _stepGender();
      case 3:
        return _stepBudget();
      case 4:
        return _stepLocation();
      default:
        return const SizedBox.shrink();
    }
  }

  TextStyle get _questionStyle => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: _subtle,
  );

  TextStyle get _hintStyle => TextStyle(fontSize: 10, color: _subtle);

  InputDecoration _fieldDecoration(
      String label,
      IconData icon, {
        String? hint,
      }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: _subtle),
      prefixIcon: Icon(icon, size: 20, color: _brand),
      filled: true,
      fillColor: _cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _brand, width: 2),
      ),
    );
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
            bodyText: _textColor,
            mutedText: _subtle,
            searchHint: _tr('Search...', 'Tafuta...'),
            emptyText: _tr('No results', 'Hakuna matokeo'),
          ),
        );
        if (picked != null) onPicked(picked);
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
                    color: hasValue ? _textColor : _subtle,
                  ),
                ),
              ),
            ),
            if (hasValue)
              GestureDetector(
                onTap: () => onPicked(''),
                child: Icon(Icons.close, size: 20, color: _subtle),
              )
            else
              Icon(Icons.arrow_drop_down, color: _subtle),
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
          _tr('Which campus is the roommate from?',
              'Mwenzi wa chumba anatoka chuo gani?'),
          style: _questionStyle,
        ),
        const SizedBox(height: 8),
        _dropdownField(
          label: _tr('Campus / University', 'Chuo / Chuo Kikuu'),
          icon: Icons.school_outlined,
          value: _campus,
          placeholder: _tr('Any campus', 'Chuo chochote'),
          sheetTitle: _tr('Choose campus', 'Chagua chuo'),
          options: _campusOptions,
          onPicked: (picked) {
            setState(() {
              _campus = picked;
              _applied = false;
            });
            _topUp();
          },
        ),
        const SizedBox(height: 8),
        Text(
          _campusOptions.isEmpty
              ? _tr('No campuses are listed yet. You can skip this step.',
              'Hakuna vyuo vilivyoorodheshwa bado. Unaweza kuruka.')
              : _tr('Campuses come from posted requests — no repeats. '
              'Leave empty for any campus.',
              'Vyuo vinatoka kwa maombi yaliyowekwa — hakuna marudio. '
                  'Acha wazi kwa chuo chochote.'),
          style: _hintStyle,
        ),
      ],
    );
  }

  // ---- STEP 2: ACCOMMODATION TYPE ----

  Widget _stepAccommodation() {
    return Column(
      key: const ValueKey('step-accommodation'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('What kind of accommodation?',
              'Malazi ya aina gani?'),
          style: _questionStyle,
        ),
        const SizedBox(height: 8),
        _dropdownField(
          label: _tr('Accommodation type', 'Aina ya malazi'),
          icon: Icons.home_outlined,
          value: _accommodation,
          placeholder: _tr('Any accommodation', 'Malazi yoyote'),
          sheetTitle: _tr('Choose accommodation type',
              'Chagua aina ya malazi'),
          options: _accommodationOptions,
          onPicked: (picked) {
            setState(() {
              _accommodation = picked;
              _applied = false;
            });
            _topUp();
          },
        ),
        const SizedBox(height: 8),
        Text(
          _accommodationOptions.isEmpty
              ? _tr('No accommodation types are listed yet. '
              'You can skip this step.',
              'Hakuna aina za malazi zilizoorodheshwa bado. '
                  'Unaweza kuruka.')
              : _tr('Types come from posted requests — no repeats. '
              'Leave empty for any type.',
              'Aina zinatoka kwa maombi yaliyowekwa — hakuna marudio. '
                  'Acha wazi kwa aina yoyote.'),
          style: _hintStyle,
        ),
      ],
    );
  }

  // ---- STEP 3: GENDER ----

  Widget _stepGender() {
    const options = ['', 'Male', 'Female', 'Other'];

    return Column(
      key: const ValueKey('step-gender'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('Whose requests do you want to see?',
              'Unataka kuona maombi ya nani?'),
          style: _questionStyle,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: options.map((value) {
            final selected = _gender == value;

            return ChoiceChip(
              label: Text(_genderLabel(value)),
              selected: selected,
              selectedColor: _brand,
              checkmarkColor: Colors.white,
              backgroundColor: _isDark ? const Color(0xFF1A241D) : null,
              labelStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: selected ? Colors.white : _subtle,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (_) {
                setState(() {
                  _gender = value;
                  _applied = false;
                });
                _topUp();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          _tr('Leave on "Any" to see every gender.',
              'Acha kwenye "Yoyote" kuona jinsia zote.'),
          style: _hintStyle,
        ),
      ],
    );
  }

  // ---- STEP 4: BUDGET RANGE (DIGITS ONLY) ----

  Widget _budgetField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
      ],
      onChanged: (_) => setState(() => _applied = false),
      style: TextStyle(color: _textColor),
      decoration: _fieldDecoration(
        label,
        Icons.payments_outlined,
        hint: hint,
      ),
    );
  }

  Widget _stepBudget() {
    return Column(
      key: const ValueKey('step-budget'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('Budget range (KES) — optional',
              'Kiwango cha bajeti (KES) — hiari'),
          style: _questionStyle,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _budgetField(
                controller: _minController,
                label: _tr('Minimum', 'Kiwango cha chini'),
                hint: _tr('e.g. 2000', 'mf. 2000'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _budgetField(
                controller: _maxController,
                label: _tr('Maximum', 'Kiwango cha juu'),
                hint: _tr('e.g. 8000', 'mf. 8000'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _tr('Numbers only. Requests without a budget are still shown.',
              'Namba pekee. Maombi yasiyo na bajeti bado yanaonyeshwa.'),
          style: _hintStyle,
        ),
      ],
    );
  }

  // ---- STEP 5: PREFERRED LOCATION ----

  Widget _stepLocation() {
    return Column(
      key: const ValueKey('step-location'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('Estate, town or location — optional',
              'Mtaa, mji au eneo — hiari'),
          style: _questionStyle,
        ),
        const SizedBox(height: 8),
        _dropdownField(
          label: _tr('Preferred location', 'Eneo unalopendelea'),
          icon: Icons.place_outlined,
          value: _location,
          placeholder: _tr('Any location', 'Eneo lolote'),
          sheetTitle: _tr('Choose location', 'Chagua eneo'),
          options: _locationOptions,
          onPicked: (picked) {
            setState(() {
              _location = picked;
              _applied = false;
            });
            _topUp();
          },
        ),
        const SizedBox(height: 8),
        Text(
          _locationOptions.isEmpty
              ? _tr('No locations are listed yet. You can skip this step.',
              'Hakuna maeneo yaliyoorodheshwa bado. Unaweza kuruka.')
              : _tr('Locations come from posted requests — no repeats. '
              'Leave empty for any location.',
              'Maeneo yanatoka kwa maombi yaliyowekwa — hakuna '
                  'marudio. Acha wazi kwa eneo lolote.'),
          style: _hintStyle,
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // CARD
  // ------------------------------------------------------------

  String _budgetText(RoommatePost post) {
    if (post.budget.isEmpty) {
      return _tr('Budget not given', 'Bajeti haijatajwa');
    }

    final period = post.budgetPeriod.isEmpty
        ? ''
        : ' · ${_periodLabel(post.budgetPeriod)}';
    return 'KES ${post.budget}$period';
  }

  Widget _cardRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: _subtle, fontSize: 14.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heartButton(RoommatePost post) {
    final saved = _favIds.contains(post.id);

    return IconButton(
      tooltip: saved
          ? _tr('Remove from favourites', 'Ondoa kwa vipendwa')
          : _tr('Save to favourites', 'Hifadhi kwa vipendwa'),
      onPressed: () => _toggleFavourite(post),
      icon: Icon(
        saved ? Icons.favorite : Icons.favorite_border,
        color: saved ? Colors.red : _subtle,
      ),
    );
  }

  Widget _buildCard(RoommatePost post) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? .25 : .06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.campus.isNotEmpty)
                        _cardRow(Icons.school_outlined, post.campus),
                      if (post.hostelName.isNotEmpty)
                        _cardRow(Icons.home_work_outlined, post.hostelName),
                      if (post.area.isNotEmpty)
                        _cardRow(Icons.location_on_outlined, post.area),
                      _cardRow(Icons.payments_outlined, _budgetText(post)),
                    ],
                  ),
                ),
              ),
              _heartButton(post),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showDetails(post),
                icon: const Icon(Icons.visibility_outlined, size: 19),
                label: Text(_tr('View', 'Angalia')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: BorderSide(color: _brand),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // FAVOURITES
  // ------------------------------------------------------------

  Future<void> _toggleFavourite(RoommatePost post) async {
    try {
      final saved = await FavouritesService.toggleRoommateFavourite(post.id);

      if (!mounted) return;

      setState(() {
        if (saved) {
          _favIds.add(post.id);
        } else {
          _favIds.remove(post.id);
        }
      });

      _showMessage(saved
          ? _tr('Saved to favourites.', 'Imehifadhiwa kwa vipendwa.')
          : _tr('Removed from favourites.', 'Imeondolewa kwa vipendwa.'));
    } catch (_) {
      _showMessage(_tr('Unable to update favourites.',
          'Imeshindikana kusasisha vipendwa.'));
    }
  }

  // ------------------------------------------------------------
  // DETAILS DIALOG  (phone number is NOT displayed)
  // ------------------------------------------------------------

  Widget _detailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: _brand),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: _subtle, fontSize: 15, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _dialogOutlined({Color? color}) {
    final c = color ?? _brand;
    return OutlinedButton.styleFrom(
      foregroundColor: c,
      side: BorderSide(color: c.withValues(alpha: .4)),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Future<void> _showDetails(RoommatePost post) async {
    final isOwner = _ownerId.isNotEmpty && _ownerId == post.userId;
    final hasPhone = post.phone.trim().isNotEmpty;

    final budget = post.budget.isEmpty
        ? '-'
        : 'KES ${post.budget}'
        '${post.budgetPeriod.isEmpty ? '' : ' ${_periodLabel(post.budgetPeriod)}'}';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final saved = _favIds.contains(post.id);

            return AlertDialog(
              backgroundColor: _pageBg,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
              title: Text(
                post.name.isEmpty
                    ? _tr('Roommate request', 'Ombi la mwenzi wa chumba')
                    : _tr('${post.name} roommate request',
                    'Ombi la mwenzi wa chumba la ${post.name}'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.name.isNotEmpty)
                        _detailRow(Icons.person_outline,
                            '${_tr('Name', 'Jina')}: ${post.name}'),
                      _detailRow(Icons.school_outlined,
                          '${_tr('Campus', 'Chuo')}: ${post.campus.isEmpty ? '-' : post.campus}'),
                      if (post.hostelName.isNotEmpty)
                        _detailRow(Icons.home_work_outlined,
                            '${_tr('Hostel', 'Hosteli')}: ${post.hostelName}'),
                      if (post.area.isNotEmpty)
                        _detailRow(Icons.map_outlined,
                            '${_tr('Preferred area', 'Eneo unalopendelea')}: ${post.area}'),
                      _detailRow(Icons.payments_outlined,
                          '${_tr('Budget', 'Bajeti')}: $budget'),
                      if (post.gender.isNotEmpty)
                        _detailRow(Icons.people_outline,
                            '${_tr('Gender', 'Jinsia')}: ${_genderLabel(post.gender)}'),
                      if (post.accommodationType.isNotEmpty)
                        _detailRow(
                            Icons.home_outlined,
                            '${_tr('Accommodation type', 'Aina ya malazi')}: '
                                '${post.accommodationType}'),
                      if (post.preferences.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          post.preferences,
                          style: TextStyle(
                            color: _subtle,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),

                      // ---- CALL / WHATSAPP ----
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed:
                              hasPhone ? () => _call(post.phone) : null,
                              icon: const Icon(Icons.call, size: 20),
                              label: Text(_tr('Call', 'Piga')),
                              style: FilledButton.styleFrom(
                                backgroundColor: _brand,
                                foregroundColor: Colors.white,
                                padding:
                                const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: hasPhone
                                  ? () => _whatsApp(post.phone)
                                  : null,
                              icon: const Icon(Icons.chat, size: 20),
                              label: const Text('WhatsApp'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _kWhatsAppGreen,
                                foregroundColor: Colors.white,
                                padding:
                                const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ---- SAVE / REPORT ----
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await _toggleFavourite(post);
                                setDialogState(() {});
                              },
                              icon: Icon(
                                saved
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 20,
                                color: saved ? Colors.red : _brand,
                              ),
                              label: Text(saved
                                  ? _tr('Saved', 'Imehifadhiwa')
                                  : _tr('Save', 'Hifadhi')),
                              style: _dialogOutlined(),
                            ),
                          ),
                          if (!isOwner) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _reportPost(post);
                                },
                                icon: const Icon(Icons.flag_outlined,
                                    size: 20),
                                label: Text(_tr('Report', 'Ripoti')),
                                style: _dialogOutlined(
                                  color: _isDark
                                      ? Colors.orange.shade300
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ---- CLOSE / DELETE ----
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: _dialogOutlined(),
                              child: Text(_tr('Close', 'Funga')),
                            ),
                          ),
                          // Delete is only offered to the poster.
                          if (isOwner) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _confirmDelete(post);
                                },
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                label: Text(_tr('Delete', 'Futa')),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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

  // ------------------------------------------------------------
  // REPORT A POST
  // ------------------------------------------------------------

  Future<void> _reportPost(RoommatePost post) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ReportDialog(
        tr: _tr,
        brand: _brand,
        surface: _pageBg,
        textColor: _textColor,
        subtle: _subtle,
      ),
    );

    if (result == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final reported = prefs.getStringList(_reportedKey) ?? <String>[];

      if (reported.contains(post.id)) {
        _showMessage(_tr('You already reported this request.',
            'Tayari umeripoti ombi hili.'));
        return;
      }

      var deviceId = '';
      try {
        deviceId = await DeviceIdService.get();
      } catch (_) {}

      final reporterId = await loadOwnerId();

      // One report per device per post (deterministic id).
      final docId = 'roommate_${post.id}_${deviceId.isEmpty ? reporterId : deviceId}';

      await _firestore.collection(kReportsCollection).doc(docId).set({
        'kind': 'roommate_post',
        'targetCollection': kRoommateCollection,
        'targetId': post.id,
        'targetName': post.name,
        'targetOwnerId': post.userId,
        'reason': result['reason'] ?? 'other',
        'details': result['details'] ?? '',
        'deviceId': deviceId,
        'reporterId': reporterId,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      reported.add(post.id);
      await prefs.setStringList(_reportedKey, reported);

      _showMessage(_tr(
          'Thank you. Your report was sent for review.',
          'Asante. Ripoti yako imetumwa kukaguliwa.'));
    } catch (_) {
      _showMessage(_tr('Unable to send your report. Please try again.',
          'Imeshindikana kutuma ripoti yako. Tafadhali jaribu tena.'));
    }
  }

  // ------------------------------------------------------------
  // CALL / WHATSAPP (number is used but never displayed)
  // ------------------------------------------------------------

  String _internationalPhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('254')) return digits;
    if (digits.startsWith('0')) digits = digits.substring(1);

    return '254$digits';
  }

  Future<void> _call(String phone) async {
    try {
      final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
      if (!ok) {
        _showMessage(_tr('Unable to start the call.',
            'Imeshindikana kuanza simu.'));
      }
    } catch (_) {
      _showMessage(
          _tr('Unable to start the call.', 'Imeshindikana kuanza simu.'));
    }
  }

  Future<void> _whatsApp(String phone) async {
    try {
      final ok = await launchUrl(
        Uri.parse('https://wa.me/${_internationalPhone(phone)}'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        _showMessage(_tr('Unable to open WhatsApp.',
            'Imeshindikana kufungua WhatsApp.'));
      }
    } catch (_) {
      _showMessage(_tr(
          'Unable to open WhatsApp.', 'Imeshindikana kufungua WhatsApp.'));
    }
  }

  // ------------------------------------------------------------
  // POST DIALOG
  // ------------------------------------------------------------

  Future<void> _showPostDialog() async {
    final ownerId = await loadOwnerId();

    if (!mounted) return;
    _ownerId = ownerId;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _PostRoommateDialog(
          hostContext: context,
          tr: _tr,
          genderLabel: _genderLabel,
          periodLabel: _periodLabel,
          brand: _brand,
          surface: _pageBg,
          textColor: _textColor,
          subtle: _subtle,
          onSubmit: _postRequest,
        );
      },
    );
  }

  Future<bool> _postRequest(Map<String, dynamic> fields) async {
    try {
      final ownerId = await loadOwnerId();

      final name = fields['name']?.toString() ?? '';

      // Normalise at the source so filtering stays consistent.
      final campus = _prettyCampus(fields['campus']?.toString() ?? '');
      final accommodation =
      LabelNormalizer.display(fields['accommodationType']);
      final area = LabelNormalizer.display(fields['preferredArea']);

      await _firestore.collection(kRoommateCollection).add({
        ...fields,
        'campus': campus,
        'accommodationType': accommodation,
        'preferredArea': area,

        // --- schema used by the existing 'roommates' docs ---
        'fullName': name,
        'phoneNumber': fields['phone'],
        'campusName': campus,
        'universityCampus': campus,
        'genderPreference': fields['gender'],
        'roommatePreferences': fields['preferences'],
        'location': area,
        'title': '$name roommate request',
        'status': 'active',

        // --- shared fields ---
        'userId': ownerId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => _ownerId = ownerId);
        _showMessage(_tr('Roommate request posted successfully.',
            'Ombi la mwenzi wa chumba limewekwa kikamilifu.'));
        // Reload so the new post appears at the top.
        _refresh();
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------
  // DELETE (asks for the 4-digit delete code)
  // ------------------------------------------------------------

  Future<void> _confirmDelete(RoommatePost post) async {
    if (_ownerId.isEmpty || _ownerId != post.userId) return;

    final confirmed = await confirmDeleteWithCode(
      context,
      title: _tr('Delete request?', 'Ufute ombi?'),
      message: post.deleteCode.trim().isEmpty
          ? _tr('This request will be permanently removed.',
          'Ombi hili litaondolewa kabisa.')
          : _tr('Enter your 4-digit delete code to remove this request.',
          'Weka msimbo wako wa kufuta wa tarakibu 4 ili kuondoa ombi hili.'),
      storedCode: post.deleteCode,
    );

    if (!confirmed) return;

    try {
      await _firestore.collection(kRoommateCollection).doc(post.id).delete();

      _optionsCache = null;

      if (mounted) {
        setState(() => _posts.removeWhere((p) => p.id == post.id));
      }

      _showMessage(_tr('Request deleted.', 'Ombi limefutwa.'));
    } catch (_) {
      _showMessage(_tr('Unable to delete this request.',
          'Imeshindikana kufuta ombi hili.'));
    }
  }

  // ------------------------------------------------------------
  // EMPTY / ERROR / MESSAGE
  // ------------------------------------------------------------

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 45),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 54, color: _brand.withValues(alpha: .65)),
          const SizedBox(height: 14),
          Text(
            _tr('No roommate requests found',
                'Hakuna maombi ya wenzi wa chumba yaliyopatikana'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _tr(
              'Try relaxing your answers in the Roommate Search Assistant, or post a request yourself.',
              'Jaribu kupunguza majibu yako katika Msaidizi wa Kutafuta Mwenzi, au weka ombi mwenyewe.',
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
              _tr('Unable to load roommate requests.',
                  'Imeshindikana kupakia maombi ya wenzi wa chumba.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11)),
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

// ============================================================
// REPORT DIALOG - pick a reason + optional details
// ============================================================

class _ReportDialog extends StatefulWidget {
  final String Function(String en, String sw) tr;
  final Color brand;
  final Color surface;
  final Color textColor;
  final Color subtle;

  const _ReportDialog({
    required this.tr,
    required this.brand,
    required this.surface,
    required this.textColor,
    required this.subtle,
  });

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _details = TextEditingController();

  String _reason = '';
  String? _error;

  String _tr(String en, String sw) => widget.tr(en, sw);

  List<MapEntry<String, String>> get _reasons => [
    MapEntry('suspicious',
        _tr('Suspicious or scam', 'Inayotia shaka au ulaghai')),
    MapEntry('misleading',
        _tr('Misleading information', 'Taarifa za kupotosha')),
    MapEntry('inappropriate',
        _tr('Inappropriate content', 'Maudhui yasiyofaa')),
    MapEntry('fake',
        _tr('Fake or duplicate post', 'Chapisho bandia au lililorudiwa')),
    MapEntry('other', _tr('Other', 'Nyingine')),
  ];

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _send() {
    if (_reason.isEmpty) {
      setState(() => _error = _tr('Please choose a reason.',
          'Tafadhali chagua sababu.'));
      return;
    }

    Navigator.of(context).pop({
      'reason': _reason,
      'details': _details.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        _tr('Report this request', 'Ripoti ombi hili'),
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: widget.textColor,
        ),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tr('Why are you reporting this post?',
                    'Kwa nini unaripoti chapisho hili?'),
                style: TextStyle(color: widget.subtle, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final entry in _reasons)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _reason == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _reason == entry.key
                        ? widget.brand
                        : widget.subtle,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(color: widget.textColor),
                  ),
                  onTap: () => setState(() {
                    _reason = entry.key;
                    _error = null;
                  }),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                maxLines: 3,
                maxLength: 300,
                style: TextStyle(color: widget.textColor),
                decoration: InputDecoration(
                  labelText: _tr('More details (optional)',
                      'Maelezo zaidi (hiari)'),
                  labelStyle: TextStyle(color: widget.subtle),
                  alignLabelWithHint: true,
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.brand, width: 2),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_tr('Cancel', 'Ghairi')),
        ),
        FilledButton(
          onPressed: _send,
          style: FilledButton.styleFrom(
            backgroundColor: widget.brand,
            foregroundColor: Colors.white,
          ),
          child: Text(_tr('Send report', 'Tuma ripoti')),
        ),
      ],
    );
  }
}

// ============================================================
// Searchable bottom sheet used for campus / accommodation /
// location picking
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
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: widget.bodyText,
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

// ============================================================
// POST A ROOMMATE REQUEST - dialog with its own controllers
// (disposed properly) and live validation alerts.
// ============================================================

class _PostRoommateDialog extends StatefulWidget {
  final BuildContext hostContext;
  final String Function(String en, String sw) tr;
  final String Function(String value) genderLabel;
  final String Function(String value) periodLabel;
  final Color brand;
  final Color surface;
  final Color textColor;
  final Color subtle;
  final Future<bool> Function(Map<String, dynamic> fields) onSubmit;

  const _PostRoommateDialog({
    required this.hostContext,
    required this.tr,
    required this.genderLabel,
    required this.periodLabel,
    required this.brand,
    required this.surface,
    required this.textColor,
    required this.subtle,
    required this.onSubmit,
  });

  @override
  State<_PostRoommateDialog> createState() => _PostRoommateDialogState();
}

class _PostRoommateDialogState extends State<_PostRoommateDialog> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _campusController = TextEditingController();
  final _hostelController = TextEditingController();
  final _areaController = TextEditingController();
  final _budgetController = TextEditingController();
  final _accommodationController = TextEditingController();
  final _preferencesController = TextEditingController();
  final _codeController = TextEditingController();

  static const List<String> _periods = [
    'Per Month',
    'Per Semester',
    'Per Year',
  ];
  static const List<String> _genders = ['Male', 'Female', 'Other'];

  String _budgetPeriod = 'Per Month';
  String _gender = 'Male';

  bool _posting = false;
  String? _formError;

  String _tr(String en, String sw) => widget.tr(en, sw);

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _campusController.dispose();
    _hostelController.dispose();
    _areaController.dispose();
    _budgetController.dispose();
    _accommodationController.dispose();
    _preferencesController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ---- validators (shared helpers show localized messages) ----

  String? _required(String? v) => validateRequired(widget.hostContext, v);
  String? _phone(String? v) => validatePhone(widget.hostContext, v);
  String? _code(String? v) => validateDeleteCode(widget.hostContext, v);

  String? _budget(String? v) {
    final empty = validateRequired(widget.hostContext, v);
    if (empty != null) return empty;

    final amount = int.tryParse((v ?? '').trim());
    if (amount == null || amount <= 0) {
      return _tr('Enter a valid budget amount.',
          'Weka kiasi sahihi cha bajeti.');
    }
    return null;
  }

  // ---- field builders ----

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? hint,
    bool multiline = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintMaxLines: 3,
      hintStyle: TextStyle(
        color: widget.subtle.withValues(alpha: .6),
        fontSize: 13,
      ),
      labelStyle: TextStyle(color: widget.subtle),
      alignLabelWithHint: multiline,
      counterText: '',
      prefixIcon: Icon(icon, color: widget.brand),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: widget.brand, width: 2),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    int? maxLength,
    bool digitsOnly = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        maxLines: maxLines,
        style: TextStyle(color: widget.textColor),
        inputFormatters: [
          if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ],
        validator: validator,
        decoration: _decoration(
          label: label,
          icon: icon,
          hint: hint,
          multiline: maxLines > 1,
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String value,
    required List<String> items,
    required String Function(String) itemLabel,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        style: TextStyle(color: widget.textColor, fontSize: 16),
        decoration: _decoration(label: label, icon: icon),
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
            value: item,
            child: Text(itemLabel(item)),
          ),
        )
            .toList(),
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
      ),
    );
  }

  // ---- submit ----

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      final codeLength = _codeController.text.trim().length;

      setState(() {
        _formError = codeLength != 4
            ? _tr('The delete code must be exactly 4 digits.',
            'Msimbo wa kufuta lazima uwe tarakibu 4 kamili.')
            : _tr('Please fill in every required field correctly.',
            'Tafadhali jaza kila sehemu inayohitajika ipasavyo.');
      });
      return;
    }

    setState(() {
      _formError = null;
      _posting = true;
    });

    final ok = await widget.onSubmit({
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'campus': _campusController.text.trim(),
      'hostelName': _hostelController.text.trim(), // optional
      'preferredArea': _areaController.text.trim(), // optional
      'budget': int.parse(_budgetController.text.trim()),
      'budgetPeriod': _budgetPeriod,
      'gender': _gender,
      'accommodationType': _accommodationController.text.trim(),
      'preferences': _preferencesController.text.trim(),
      'deleteCode': _codeController.text.trim(),
    });

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _posting = false;
        _formError = _tr(
          'Could not post your request. Please try again.',
          'Haikuwezekana kuweka ombi lako. Tafadhali jaribu tena.',
        );
      });
    }
  }

  Widget _errorAlert(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: .5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: widget.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Post a Roommate Request',
                      'Posti Ombi la Mwenzi wa Chumba'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: widget.textColor,
                  ),
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _nameController,
                  label: _tr('Full Name', 'Jina Kamili'),
                  icon: Icons.person_outline,
                  capitalization: TextCapitalization.words,
                  validator: _required,
                ),
                _field(
                  controller: _phoneController,
                  label: _tr('Phone Number', 'Nambari ya Simu'),
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  digitsOnly: true,
                  validator: _phone,
                ),
                _field(
                  controller: _campusController,
                  label: _tr('Campus Name', 'Jina la Chuo'),
                  icon: Icons.school_outlined,
                  capitalization: TextCapitalization.words,
                  validator: _required,
                ),
                // Optional
                _field(
                  controller: _hostelController,
                  label: _tr('Hostel Name (optional)',
                      'Jina la Hosteli (hiari)'),
                  icon: Icons.home_work_outlined,
                  capitalization: TextCapitalization.words,
                ),
                // Optional
                _field(
                  controller: _areaController,
                  label: _tr('Preferred Area / Location (optional)',
                      'Eneo Unalopendelea (hiari)'),
                  icon: Icons.location_on_outlined,
                  capitalization: TextCapitalization.sentences,
                ),
                _field(
                  controller: _budgetController,
                  label: _tr('Budget (KES)', 'Bajeti (KES)'),
                  icon: Icons.payments_outlined,
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                  digitsOnly: true,
                  validator: _budget,
                ),
                _dropdown(
                  label: _tr('Budget Period', 'Kipindi cha Bajeti'),
                  icon: Icons.calendar_today_outlined,
                  value: _budgetPeriod,
                  items: _periods,
                  itemLabel: widget.periodLabel,
                  onChanged: (v) => setState(() => _budgetPeriod = v),
                ),
                _dropdown(
                  label: _tr('Your Gender', 'Jinsia Yako'),
                  icon: Icons.people_outline,
                  value: _gender,
                  items: _genders,
                  itemLabel: widget.genderLabel,
                  onChanged: (v) => setState(() => _gender = v),
                ),
                _field(
                  controller: _accommodationController,
                  label: _tr('Accommodation Type', 'Aina ya Malazi'),
                  icon: Icons.home_outlined,
                  hint: _tr('e.g. Bedsitter, single room, shared room',
                      'mfano Bedsitter, chumba kimoja, chumba cha kushiriki'),
                  capitalization: TextCapitalization.sentences,
                  validator: _required,
                ),
                _field(
                  controller: _preferencesController,
                  label: _tr('Roommate Preferences', 'Mapendeleo ya Mwenzi'),
                  icon: Icons.favorite_border,
                  hint: _tr(
                    'e.g. Tidy and quiet, non-smoker, fellow Christian, '
                        'studies at night, shares chores...',
                    'mfano Msafi na mtulivu, asiyevuta sigara, mwamini '
                        'mwenzangu, anasoma usiku, anashiriki kazi za nyumbani...',
                  ),
                  capitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  validator: _required,
                ),
                _field(
                  controller: _codeController,
                  label: _tr('4-Digit Delete Code',
                      'Msimbo wa Kufuta (Tarakimu 4)'),
                  icon: Icons.lock_outline,
                  hint: _tr('Keep this code. You need it to delete your post.',
                      'Hifadhi msimbo huu. Utauhitaji kufuta chapisho lako.'),
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  digitsOnly: true,
                  validator: _code,
                ),
                if (_formError != null) _errorAlert(_formError!),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                        _posting ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.brand,
                          side: BorderSide(color: widget.brand),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(_tr('Cancel', 'Ghairi')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _posting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: _posting
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Text(_tr('Post Request', 'Posti Ombi')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}