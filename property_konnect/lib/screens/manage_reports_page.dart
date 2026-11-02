// ============================================================
// manage_reports_page.dart  (FULL UPDATED FILE)
//
// CHANGES IN THIS VERSION — matched to the REAL report documents
// in Firestore (collection `reports`), e.g. a roommate report:
//
//   createdAt         Timestamp
//   details           ""            (string)
//   deviceId          "dev_7a82..." (string)
//   kind              "roommate_post"
//   reason            "inappropriate"
//   reporterId        "device_1793..." (guest device or user uid)
//   status            "open"
//   targetCollection  "roommates"
//   targetId          "oBKiSbQYKR5lspn8SLny"
//   targetName        "MEGABRAIN TWO"
//   targetOwnerId     "kF5U8akVQrOfAXizWOo1a1Bczyp1"
//
//  1. "REPORT FROM" category now reads `targetCollection` FIRST,
//     then `kind`, then the older `source` / `type` fields, so
//     every report is placed under the right chip
//     (properties / roommates / student services / campus
//     communities / marketplace / services).
//  2. `status: "open"` is treated as UNRESOLVED (anything that is
//     not resolved/closed is unresolved). Reopening a report now
//     writes "open" to match what the app writes.
//  3. Reports only store `targetOwnerId` (no owner name), so the
//     OWNER NAME is now looked up from the `users` collection
//     (loaded once). Reporter names are looked up the same way
//     when `reporterId` is a real user id; guest device ids are
//     shown as "Guest device".
//  4. FRAUD SCAN FIX: the roommates listing collection is named
//     `roommates` (not `roommate_posts`) — the scan now reads it.
//  5. "Heavily reported account" now counts DISTINCT reporters
//     (by reporterId / deviceId), so one device cannot inflate
//     the count, and uses `targetOwnerId`.
//  6. Reasons are shown nicely ("inappropriate" -> "Inappropriate",
//     "fake_listing" -> "Fake listing").
//  7. The report card icon changes with the category; the detail
//     sheet now also shows Report from, Owner ID and Device ID.
//  8. Search also looks in kind, collection, owner id, device id
//     and details. An "Other" source chip appears only when there
//     are reports that match no known category.
//
// (Everything else — automated fraud scan, CSV downloads, search,
//  status chips, resolve / reopen / delete — is unchanged.)
//
// RECOMMENDED (backend, not this file):
//  - Once the data grows, move the scan into a scheduled
//    Firebase Cloud Function, process in batches and cache the
//    results; this page would then only read the cache.
//  - Enforce admin-only access on `reports` and `users` with
//    Firestore Security Rules / trusted backend — hiding buttons
//    in Flutter is NOT a permission control.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_settings.dart';
import 'download_helper.dart';

const String _kReportsCollection = 'reports';

/// "fake_listing" / "inappropriate" -> "Fake listing" / "Inappropriate".
String _prettyReason(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'[_\-]+'), ' ');
  if (cleaned.isEmpty) return cleaned;
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

class ManageReportsPage extends StatefulWidget {
  const ManageReportsPage({super.key});

  @override
  State<ManageReportsPage> createState() => _ManageReportsPageState();
}

class _ManageReportsPageState extends State<ManageReportsPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  String _filter = 'pending'; // pending (unresolved) | resolved
  bool _working = false;

  // ---- SEARCH + "REPORT FROM" FILTER ----
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  String _sourceFilter = 'all'; // all | properties | roommates | ...

  // ---- USER NAME LOOKUP (users/{uid} -> display name) ----
  // Reports store only ids (targetOwnerId, reporterId), so names
  // are resolved from the users collection, loaded once.
  final Map<String, String> _userNames = {};

  // Automated fraud scan state.
  bool _scanning = false;
  final List<({String title, String detail, String reason})> _fraudFlags = [];
  bool _showFraudResults = false;

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _greenDeep =>
      _isDark ? kBrandGreenOnDark : const Color(0xFF146C43);

  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _pageBackground =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _mutedText => _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection(_kReportsCollection)
        .snapshots();
    _loadUserNames();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Loads id -> name for every user, once, so report cards can
  /// show the owner's / reporter's NAME instead of just an id.
  Future<void> _loadUserNames() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();

      final map = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        for (final key in const ['fullName', 'name', 'displayName']) {
          final value = data[key]?.toString().trim() ?? '';
          if (value.isNotEmpty) {
            map[doc.id] = value;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _userNames
          ..clear()
          ..addAll(map);
      });
    } catch (e) {
      debugPrint('REPORTS: could not load user names: $e');
    }
  }

  // ------------------------------------------------------------
  // DATA HELPERS
  // ------------------------------------------------------------

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _first(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _text(data[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Reports are created with status "open". Anything that is not
  /// resolved/closed counts as UNRESOLVED.
  String _statusOf(Map<String, dynamic> data) {
    final status = _text(data['status']).toLowerCase();
    return (status == 'resolved' || status == 'closed')
        ? 'resolved'
        : 'pending';
  }

  String _reasonOf(Map<String, dynamic> data) {
    final reason = _first(data, ['reason', 'category', 'title']);
    return reason.isEmpty
        ? _tr('No reason given', 'Hakuna sababu')
        : _prettyReason(reason);
  }

  String _propertyNameOf(Map<String, dynamic> data) =>
      _first(data, ['targetName', 'targetTitle', 'propertyTitle']);

  String _ownerIdOf(Map<String, dynamic> data) =>
      _first(data, ['targetOwnerId', 'ownerId', 'reportedUserId']);

  String _reporterIdOf(Map<String, dynamic> data) =>
      _first(data, ['reporterId', 'reportedBy', 'userId']);

  /// Owner NAME: from the report itself if present, otherwise
  /// looked up from users/{targetOwnerId}.
  String _ownerNameOf(Map<String, dynamic> data) {
    final direct =
    _first(data, ['ownerName', 'landlordName', 'reportedOwnerName']);
    if (direct.isNotEmpty) return direct;

    final id = _ownerIdOf(data);
    return id.isEmpty ? '' : (_userNames[id] ?? '');
  }

  /// Reporter NAME: from the report if present, otherwise looked
  /// up by reporterId. Guest device ids are not user accounts.
  String _reporterNameOf(Map<String, dynamic> data) {
    final direct = _first(data, ['reporterName', 'reportedByName']);
    if (direct.isNotEmpty) return direct;

    final id = _reporterIdOf(data);
    if (id.isEmpty) return '';
    if (_userNames.containsKey(id)) return _userNames[id]!;
    if (id.startsWith('device_') || id.startsWith('dev_')) {
      return _tr('Guest device', 'Kifaa cha mgeni');
    }
    return '';
  }

  String _formatDate(dynamic value) {
    if (value is! Timestamp) return '';
    return DateFormat.yMMMd().add_jm().format(value.toDate().toLocal());
  }

  DateTime _sortDate(Map<String, dynamic> data) {
    final value = data['createdAt'];
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  (String, Color, IconData) _statusInfo(String status) {
    switch (status) {
      case 'resolved':
        return (
        _tr('Resolved', 'Imetatuliwa'),
        Colors.green,
        Icons.check_circle
        );
      default:
        return (
        _tr('Unresolved', 'Hairudishiwi'),
        Colors.orange,
        Icons.pending
        );
    }
  }

  // ------------------------------------------------------------
  // "REPORT FROM" SOURCE HELPERS
  //
  // Real report documents carry:
  //   targetCollection : "roommates" | "properties" | ...
  //   kind             : "roommate_post" | "property" | ...
  // These are checked FIRST, then the older `source` / `type`.
  // Unknown values fall into 'other' (only shown under "All" and
  // the "Other" chip).
  // ------------------------------------------------------------

  String _normalizeSource(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'property':
      case 'properties':
        return 'properties';

      case 'roommate':
      case 'roommates':
      case 'roommate_post':
      case 'roommate_posts':
        return 'roommates';

      case 'student_service':
      case 'student_services':
        return 'student_services';

      case 'community':
      case 'communities':
      case 'campus_community':
      case 'campus_communities':
        return 'campus_communities';

      case 'listing':
      case 'marketplace':
      case 'marketplace_item':
      case 'comrade_marketplace':
      case 'comrade_marketplace_item':
      case 'item':
        return 'comrade_marketplace';

      case 'service':
      case 'services':
      case 'property_service':
      case 'property_services':
        return 'services';

      default:
        return 'other';
    }
  }

  String _sourceOf(Map<String, dynamic> data) {
    for (final key in const ['targetCollection', 'kind', 'source', 'type']) {
      final value = _text(data[key]);
      if (value.isEmpty) continue;

      final source = _normalizeSource(value);
      if (source != 'other') return source;
    }
    return 'other';
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'properties':
        return _tr('Property', 'Mali');
      case 'roommates':
        return _tr('Roommate post', 'Chapisho la mwenzi wa chumba');
      case 'student_services':
        return _tr('Student service', 'Huduma ya mwanafunzi');
      case 'campus_communities':
        return _tr('Campus community', 'Jumuiya ya chuo');
      case 'comrade_marketplace':
        return _tr('Marketplace', 'Soko la comrade');
      case 'services':
        return _tr('Service', 'Huduma');
      default:
        return _tr('Other', 'Nyingine');
    }
  }

  IconData _sourceIcon(String source) {
    switch (source) {
      case 'properties':
        return Icons.home_work_outlined;
      case 'roommates':
        return Icons.people_outline;
      case 'student_services':
        return Icons.school_outlined;
      case 'campus_communities':
        return Icons.groups_outlined;
      case 'comrade_marketplace':
        return Icons.storefront_outlined;
      case 'services':
        return Icons.home_repair_service_outlined;
      default:
        return Icons.flag_outlined;
    }
  }

  // ------------------------------------------------------------
  // FILTERING (status + source + search)
  // ------------------------------------------------------------

  bool _matchesSearch(String id, Map<String, dynamic> data) {
    if (_searchText.isEmpty) return true;

    final haystack = [
      id,
      _propertyNameOf(data),
      _ownerNameOf(data),
      _ownerIdOf(data),
      _reasonOf(data),
      _reporterNameOf(data),
      _reporterIdOf(data),
      _text(data['adminNote']),
      _text(data['details']),
      _text(data['kind']),
      _text(data['targetCollection']),
      _text(data['deviceId']),
      _first(data, ['targetId', 'propertyId']),
    ].join(' ').toLowerCase();

    return haystack.contains(_searchText.toLowerCase());
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs.where((doc) {
      if (_statusOf(doc.data()) != _filter) return false;
      if (_sourceFilter != 'all' &&
          _sourceOf(doc.data()) != _sourceFilter) {
        return false;
      }
      return _matchesSearch(doc.id, doc.data());
    }).toList()
      ..sort((a, b) =>
          _sortDate(b.data()).compareTo(_sortDate(a.data())));
  }

  // ============================================================
  // AUTOMATED FRAUD DETECTION
  // ============================================================
  //
  // A rule-based scan (NOT an AI model) across six listing
  // collections. Flags:
  //  1. Repeated images (same imageUrl used by many listings)
  //  2. Duplicated listing details (same title + description)
  //  3. Suspicious pricing (>300% or <40% of the MEDIAN price
  //     for the same type AND location)
  //  4. Duplicated owner account details (same normalized
  //     phone / email)
  //  5. Accounts with many user reports (>= 3 DISTINCT reporters)
  // ============================================================

  /// The six listing collections scanned, with their labels.
  /// NOTE: the roommates collection is named `roommates`.
  static const Map<String, String> _kScanTargets = {
    'properties': 'Properties',
    'roommates': 'Roommates',
    'student_services': 'Student services',
    'campus_communities': 'Campus communities',
    'comrade_marketplace': 'Marketplace',
    'property_services': 'Services',
  };

  /// Normalizes a Kenyan phone number so that 0712345678,
  /// +254712345678, 254712345678 and 712345678 are compared as
  /// the same value.
  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('254')) return digits;
    if (digits.startsWith('0') && digits.length == 10) {
      return '254${digits.substring(1)}';
    }
    if (digits.length == 9 &&
        (digits.startsWith('7') || digits.startsWith('1'))) {
      return '254$digits';
    }
    return digits;
  }

  Future<void> _runFraudScan() async {
    setState(() {
      _scanning = true;
      _fraudFlags.clear();
    });

    try {
      final firestore = FirebaseFirestore.instance;

      // ---------- Fetch the six listing collections ----------
      // Each collection is fetched independently; if one is
      // missing or unreadable the scan continues with the rest.
      final listings = <_ListingInfo>[];

      await Future.wait(_kScanTargets.entries.map((entry) async {
        try {
          final snap = await firestore.collection(entry.key).get();
          for (final doc in snap.docs) {
            listings.add(_ListingInfo.fromDoc(entry.key, doc.data()));
          }
        } catch (e) {
          debugPrint('FRAUD SCAN: skipped ${entry.key}: $e');
        }
      }));

      if (!mounted) return;

      final users = await firestore.collection('users').get();
      final reports = await firestore.collection('reports').get();

      if (!mounted) return;

      final usersById = <String, Map<String, dynamic>>{
        for (final d in users.docs) d.id: d.data(),
      };

      final flags = <({String title, String detail, String reason})>[];

      String label(_ListingInfo l) =>
          _kScanTargets[l.source] ?? l.source;

      // ---------- 1. Repeated images ----------
      final imageOwners = <String, Set<String>>{};
      for (final l in listings) {
        for (final url in l.images) {
          imageOwners.putIfAbsent(url, () => <String>{}).add(
            '${l.title.isEmpty ? l.source : l.title} (${label(l)})',
          );
        }
      }

      for (final entry in imageOwners.entries) {
        final names = entry.value.toList();
        if (names.length >= 3) {
          flags.add((
          title: _tr('Repeated images', 'Picha zinazorudiwa'),
          detail:
          '${names.length} listings use the same image '
              '(${names.take(3).join(', ')}${names.length > 3 ? '…' : ''})',
          reason: 'Same image URL used across ${names.length} listings',
          ));
        }
      }

      // ---------- 2. Duplicated listing details ----------
      final detailGroups = <String, List<String>>{};
      for (final l in listings) {
        if (l.title.isEmpty) continue;
        final key =
            '${l.title.toLowerCase()}|${l.description.toLowerCase()}';
        detailGroups
            .putIfAbsent(key, () => [])
            .add('${l.title} (${label(l)})');
      }

      for (final entry in detailGroups.entries) {
        if (entry.value.length >= 2) {
          flags.add((
          title: _tr('Duplicated listing', 'Tangazo lilionekana mara mbili'),
          detail:
          '"${entry.value.first}" — identical title + description '
              'in ${entry.value.length} posts',
          reason: 'Identical title + description across listings',
          ));
        }
      }

      // ---------- 3. Suspicious pricing ----------
      // Grouped by LOCATION + TYPE (a bedsitter in Kisumu is not
      // compared with a 3-bedroom in Nairobi) and judged against
      // the MEDIAN, which is resistant to outliers.
      final priceGroups = <String, List<_ListingInfo>>{};
      for (final l in listings) {
        if (l.price != null && l.location.isNotEmpty && l.type.isNotEmpty) {
          priceGroups
              .putIfAbsent(
              '${l.location.toLowerCase()}|${l.type.toLowerCase()}',
                  () => [])
              .add(l);
        }
      }

      for (final group in priceGroups.entries) {
        final items = group.value;
        if (items.length < 3) continue; // not enough data to judge

        final prices = items.map((l) => l.price!).toList()..sort();
        final mid = prices.length ~/ 2;
        final median = prices.length.isOdd
            ? prices[mid]
            : (prices[mid - 1] + prices[mid]) / 2;

        final location = items.first.location;
        final type = items.first.type;

        for (final l in items) {
          if (l.price! > median * 3) {
            flags.add((
            title: _tr('Suspicious high price', 'Bei ya juu ya kushangaza'),
            detail:
            '"${l.title}" (${label(l)}) at ${l.price!.toStringAsFixed(0)} '
                'vs median ${median.toStringAsFixed(0)} for $type in $location',
            reason:
            'Price is over 3x the median for the same type and location',
            ));
          } else if (l.price! < median * 0.4) {
            flags.add((
            title: _tr('Suspicious low price', 'Bei ya chini ya kushangaza'),
            detail:
            '"${l.title}" (${label(l)}) at ${l.price!.toStringAsFixed(0)} '
                'vs median ${median.toStringAsFixed(0)} for $type in $location',
            reason:
            'Price is under 40% of the median for the same type and location',
            ));
          }
        }
      }

      // ---------- 4. Duplicated owner account details ----------
      final phoneOwners = <String, Set<String>>{};
      final emailOwners = <String, Set<String>>{};

      for (final doc in users.docs) {
        final data = doc.data();
        // _text() always returns non-null, so use explicit
        // fallbacks instead of `??` (which could never run).
        final name = _first(data, ['name', 'fullName']).isNotEmpty
            ? _first(data, ['name', 'fullName'])
            : doc.id;
        final phone = _normalizePhone(_text(data['phone']));
        final email = _text(data['email']).toLowerCase();

        if (phone.isNotEmpty) {
          phoneOwners.putIfAbsent(phone, () => <String>{}).add(name);
        }
        if (email.isNotEmpty) {
          emailOwners.putIfAbsent(email, () => <String>{}).add(name);
        }
      }

      for (final entry in phoneOwners.entries) {
        if (entry.value.length >= 2) {
          flags.add((
          title: _tr('Duplicated owner accounts', 'Akaunti zinazofanana'),
          detail: 'Phone ${entry.key} used by: ${entry.value.join(', ')}',
          reason: 'Multiple accounts share the same phone number',
          ));
        }
      }

      for (final entry in emailOwners.entries) {
        if (entry.value.length >= 2) {
          flags.add((
          title: _tr('Duplicated owner accounts', 'Akaunti zinazofanana'),
          detail: 'Email ${entry.key} used by: ${entry.value.join(', ')}',
          reason: 'Multiple accounts share the same email',
          ));
        }
      }

      // ---------- 5. Accounts with many reports ----------
      // Counts DISTINCT reporters per reported owner (reporterId,
      // falling back to deviceId, then the report id), so one
      // device cannot inflate an account's count. Names come from
      // the users snapshot already fetched.
      final reportersByOwner = <String, Set<String>>{};
      for (final doc in reports.docs) {
        final data = doc.data();

        final target = _ownerIdOf(data);
        if (target.isEmpty) continue;

        final reporter = _reporterIdOf(data).isNotEmpty
            ? _reporterIdOf(data)
            : (_text(data['deviceId']).isNotEmpty
            ? _text(data['deviceId'])
            : doc.id);

        reportersByOwner.putIfAbsent(target, () => <String>{}).add(reporter);
      }

      for (final entry in reportersByOwner.entries) {
        final count = entry.value.length;
        if (count < 3) continue;

        final userData = usersById[entry.key];
        final ownerName = (userData != null &&
            _first(userData, ['name', 'fullName']).isNotEmpty)
            ? _first(userData, ['name', 'fullName'])
            : entry.key;

        flags.add((
        title: _tr('Heavily reported account', 'Akaunti yenye ripoti nyingi'),
        detail: '"$ownerName" has been reported by $count different users/devices',
        reason: 'Account has 3 or more reports from different reporters',
        ));
      }

      if (!mounted) return;
      setState(() {
        _fraudFlags.addAll(flags);
        _scanning = false;
        _showFraudResults = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('${_tr('Scan failed: ', 'Uchunguzi umeshindikana: ')}$e'),
        ),
      );
    }
  }

  /// Downloads the current fraud-scan flags as a CSV file.
  Future<void> _downloadFraudCsv() async {
    if (_fraudFlags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('There are no scan results to download.',
              'Hakuna matokeo ya uchunguzi ya kupakua.')),
        ),
      );
      return;
    }

    await DownloadHelper.downloadCsv(
      context: context,
      fileNamePrefix: 'fraud_scan',
      headers: [
        _tr('Flag', 'Bendera'),
        _tr('Details', 'Maelezo'),
        _tr('Reason', 'Sababu'),
      ],
      rows: [
        for (final flag in _fraudFlags)
          <dynamic>[flag.title, flag.detail, flag.reason],
      ],
    );
  }

  // ------------------------------------------------------------
  // ACTIONS
  // ------------------------------------------------------------

  Future<void> _openReport(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();

    final result = await showModalBottomSheet<({String action, String note})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportDetailSheet(
        data: data,
        reportId: doc.id,
        sourceLabel: _sourceLabel(_sourceOf(data)),
        ownerName: _ownerNameOf(data),
        reporterName: _reporterNameOf(data),
      ),
    );

    if (result == null || !mounted) return;

    if (result.action == 'delete') {
      await _deleteReport(doc);
      return;
    }

    await _setStatus(doc, result.action, result.note);
  }

  Future<void> _setStatus(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      String status,
      String note) async {
    setState(() => _working = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final admin = FirebaseAuth.instance.currentUser;
      final reopening = status == 'pending';

      await doc.reference.update({
        // The app creates reports as "open", so reopening writes
        // "open" (not "pending") to stay consistent.
        'status': reopening ? 'open' : status,
        'adminNote': note,
        'updatedAt': FieldValue.serverTimestamp(),
        'resolvedBy': reopening ? FieldValue.delete() : admin?.uid,
        'resolvedAt':
        reopening ? FieldValue.delete() : FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _green,
          content: Text(
            status == 'resolved'
                ? _tr('Report marked as resolved.',
                'Ripoti imewekwa kuwa imetatuliwa.')
                : _tr('Report reopened.', 'Ripoti imefunguliwa tena.'),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              '${_tr('Unable to update: ', 'Imeshindikana kusasisha: ')}$e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _resolveReport(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    await _setStatus(doc, 'resolved', '');
  }

  Future<void> _deleteReport(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_forever, color: Colors.red, size: 34),
        title: Text(_tr('Delete report?', 'Kufuta ripoti?')),
        content: Text(
          _tr(
            'Are you sure you want to delete report?',
            'Una uhakika unataka kufuta ripoti?',
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

    if (confirmed != true || !mounted) return;

    setState(() => _working = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      await doc.reference.delete();

      messenger.showSnackBar(
        SnackBar(content: Text(_tr('Report deleted.', 'Ripoti imefutwa.'))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('${_tr('Unable to delete: ', 'Imeshindikana kufuta: ')}$e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _downloadCsv(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('There are no reports to download.',
              'Hakuna ripoti za kupakua.')),
        ),
      );
      return;
    }

    final rows = docs.map((doc) {
      final data = doc.data();
      final (statusLabel, _, _) = _statusInfo(_statusOf(data));

      return <dynamic>[
        doc.id,
        _sourceLabel(_sourceOf(data)),
        _propertyNameOf(data),
        _ownerNameOf(data),
        _ownerIdOf(data),
        _reasonOf(data),
        _text(data['details']),
        _reporterNameOf(data),
        _reporterIdOf(data),
        statusLabel,
        _text(data['adminNote']),
        _formatDate(data['createdAt']),
      ];
    }).toList();

    await DownloadHelper.downloadCsv(
      context: context,
      fileNamePrefix: 'reports',
      headers: [
        'ID',
        _tr('Report from', 'Ripoti kutoka'),
        _tr('Property / item', 'Mali / bidhaa'),
        _tr('Owner', 'Mmiliki'),
        _tr('Owner ID', 'Kitambulisho cha mmiliki'),
        _tr('Reason', 'Sababu'),
        _tr('Details', 'Maelezo'),
        _tr('Reported by', 'Aliyeripoti'),
        _tr('Reporter ID', 'Kitambulisho cha mtoa ripoti'),
        _tr('Status', 'Hali'),
        _tr('Admin note', 'Maelezo ya msimamizi'),
        _tr('Reported on', 'Iliripotiwa'),
      ],
      rows: rows,
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final allDocs = [...?snapshot.data?.docs];

        final visible = _applyFilters(allDocs);

        final resolvedCount =
            allDocs.where((d) => _statusOf(d.data()) == 'resolved').length;
        final unresolvedCount = allDocs.length - resolvedCount;

        return Scaffold(
          backgroundColor: _pageBackground,
          appBar: AppBar(
            title: Text(_tr('Manage Reports', 'Simamia Ripoti')),
            backgroundColor: _green,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                tooltip: _tr('Download CSV', 'Pakua CSV'),
                icon: const Icon(Icons.download),
                onPressed:
                snapshot.hasData ? () => _downloadCsv(visible) : null,
              ),
            ],
          ),
          body: _buildBody(
              snapshot, allDocs, visible, resolvedCount, unresolvedCount),
        );
      },
    );
  }

  int _countSource(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String source) {
    return docs.where((d) => _sourceOf(d.data()) == source).length;
  }

  Widget _buildBody(
      AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> visible,
      int resolvedCount,
      int unresolvedCount,
      ) {
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${_tr('Unable to load reports.', 'Imeshindikana kupakia ripoti.')}\n${snapshot.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!snapshot.hasData) {
      return Center(child: CircularProgressIndicator(color: _green));
    }

    final otherCount = _countSource(allDocs, 'other');

    return Stack(
      children: [
        Column(
          children: [
            // ---------------- AUTOMATED FRAUD DETECTION ----------------
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: _buildFraudPanel(),
            ),

            // ---------------- SEARCH BAR ----------------
            _buildSearchBar(),

            // ---------------- STATUS FILTER CHIPS ----------------
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _filterChip(
                    'pending',
                    _tr('Unresolved', 'Hazijatatuliwa'),
                    unresolvedCount,
                  ),
                  _filterChip(
                    'resolved',
                    _tr('Resolved', 'Zimetatuliwa'),
                    resolvedCount,
                  ),
                ],
              ),
            ),

            // ---------------- "REPORT FROM" SOURCE CHIPS ----------------
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                children: [
                  _sourceChip(
                    'all',
                    _tr('All sources', 'Vyanzo vyote'),
                    allDocs.length,
                  ),
                  _sourceChip(
                    'properties',
                    _tr('Properties', 'Mali'),
                    _countSource(allDocs, 'properties'),
                  ),
                  _sourceChip(
                    'roommates',
                    _tr('Roommates', 'Wenzi wa chumba'),
                    _countSource(allDocs, 'roommates'),
                  ),
                  _sourceChip(
                    'student_services',
                    _tr('Student services', 'Huduma za wanafunzi'),
                    _countSource(allDocs, 'student_services'),
                  ),
                  _sourceChip(
                    'campus_communities',
                    _tr('Campus communities', 'Jumuiya za vyuo'),
                    _countSource(allDocs, 'campus_communities'),
                  ),
                  _sourceChip(
                    'comrade_marketplace',
                    _tr('Marketplace', 'Soko'),
                    _countSource(allDocs, 'comrade_marketplace'),
                  ),
                  _sourceChip(
                    'services',
                    _tr('Services', 'Huduma'),
                    _countSource(allDocs, 'services'),
                  ),
                  if (otherCount > 0)
                    _sourceChip(
                      'other',
                      _tr('Other', 'Nyingine'),
                      otherCount,
                    ),
                ],
              ),
            ),

            // ---------------- LIST ----------------
            Expanded(
              child: visible.isEmpty
                  ? _emptyState(allDocs.isEmpty)
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _reportCard(visible[i]),
              ),
            ),
          ],
        ),

        if (_working)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator(color: _green)),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------
  // SEARCH BAR
  // ------------------------------------------------------------

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _searchText = value.trim()),
        decoration: InputDecoration(
          hintText: _tr(
            'Search reports — property, owner, reason, reporter…',
            'Tafuta ripoti — mali, mmiliki, sababu, mtoa ripoti…',
          ),
          prefixIcon: Icon(Icons.search, color: _green),
          isDense: true,
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
            borderSide: BorderSide(color: _green, width: 1.5),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // AUTOMATED FRAUD DETECTION PANEL
  // ------------------------------------------------------------

  Widget _buildFraudPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.deepPurple.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_alt_outlined,
                  color: Colors.deepPurple, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr('Automated Fraud Detection',
                      'Ugunduzi wa Udanganyifu Otomatiki'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: _scanning ? null : _runFraudScan,
                icon: _scanning
                    ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.radar, size: 16),
                label: Text(_scanning
                    ? _tr('Scanning...', 'Inachunguza...')
                    : _tr('Review', 'Kagua')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _tr(
              'Rule-based scan of properties, roommates, student services, '
                  'campus communities, marketplace and service posts. Flags '
                  'repeated images, duplicated details, unusual pricing, '
                  'duplicated owner accounts and heavily reported accounts.',
              'Uchunguzi wa sheria kwenye mali, wenzi wa chumba, huduma za '
                  'wanafunzi, jumuiya za vyuo, soko na huduma. Inaonyesha '
                  'picha zinazorudiwa, maelezo yanayofanana, bei za '
                  'kushangaza, akaunti zinazofanana na akaunti zenye '
                  'ripoti nyingi.',
            ),
            style: TextStyle(fontSize: 11, color: _mutedText),
          ),

          // ---------------- RESULTS ----------------
          if (_showFraudResults) ...[
            const SizedBox(height: 10),
            if (_fraudFlags.isEmpty)
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _tr('No suspicious activity detected.',
                        'Hakuna shaka iliyopatikana.'),
                    style: TextStyle(
                        fontSize: 12, color: Colors.green),
                  ),
                ],
              )
            else ...[
              Text(
                '${_fraudFlags.length} ${_tr('flagged', 'zimepewa bendera')}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(height: 6),
              ..._fraudFlags.take(10).map((flag) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag, color: Colors.deepOrange, size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            flag.title,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            flag.detail,
                            style: TextStyle(
                                fontSize: 11.5, color: _mutedText),
                          ),
                          Text(
                            flag.reason,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: _mutedText,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
              if (_fraudFlags.length > 10)
                Text(
                  '${_fraudFlags.length - 10} more…',
                  style: TextStyle(fontSize: 11, color: _mutedText),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _downloadFraudCsv,
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(_tr('Download results', 'Pakua matokeo')),
                  ),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        setState(() => _showFraudResults = false),
                    child: Text(_tr('Hide results', 'Ficha matokeo')),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, int count) {
    final selected = _filter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label ($count)'),
        selected: selected,
        showCheckmark: false,
        selectedColor: _green,
        backgroundColor: _cardColor,
        side: BorderSide(color: selected ? _green : _cardBorder),
        labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _sourceChip(String value, String label, int count) {
    final selected = _sourceFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label ($count)'),
        selected: selected,
        showCheckmark: false,
        selectedColor: Colors.deepPurple,
        backgroundColor: _cardColor,
        side: BorderSide(
            color: selected ? Colors.deepPurple : _cardBorder),
        labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        onSelected: (_) => setState(() => _sourceFilter = value),
      ),
    );
  }

  Widget _emptyState(bool noReportsAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined, size: 54, color: _mutedText),
            const SizedBox(height: 12),
            Text(
              noReportsAtAll
                  ? _tr('No reports yet.', 'Bado hakuna ripoti.')
                  : _tr('No reports match your filters.',
                  'Hakuna ripoti zinazolingana.'),
              style: TextStyle(color: _mutedText, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // REPORT CARD — item name + owner name + category + reason,
  // with View / Resolve / Remove buttons.
  // ------------------------------------------------------------

  Widget _reportCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final (statusLabel, statusColor, statusIcon) =
    _statusInfo(_statusOf(data));

    final propertyName = _propertyNameOf(data);
    final ownerName = _ownerNameOf(data);
    final source = _sourceOf(data);
    final date = _formatDate(data['createdAt']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _sourceIcon(source),
                  color: Colors.red,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      propertyName.isEmpty
                          ? _reasonOf(data)
                          : propertyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: _greenDeep,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ownerName.isEmpty
                          ? _tr('Owner unknown', 'Mmiliki hajulikani')
                          : '${_tr('Owner', 'Mmiliki')}: $ownerName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: _mutedText),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_tr('Report from', 'Ripoti kutoka')}: '
                          '${_sourceLabel(source)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: _mutedText),
                    ),
                    if (propertyName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${_tr('Reason', 'Sababu')}: ${_reasonOf(data)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: _mutedText),
                      ),
                    ],
                    if (date.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: _mutedText),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(statusLabel, statusColor, statusIcon),
            ],
          ),
          const SizedBox(height: 10),

          // ------------ ACTION BUTTONS ------------
          Row(
            children: [
              Expanded(
                child: _reportButton(
                  label: _tr('View', 'Angalia'),
                  color: _green,
                  filled: false,
                  onPressed: () => _openReport(doc),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _reportButton(
                  label: _tr('Resolve', 'Tatua'),
                  color: _green,
                  filled: true,
                  onPressed:
                  _statusOf(data) == 'resolved' ? null : () => _resolveReport(doc),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _reportButton(
                  label: _tr('Remove', 'Ondoa'),
                  color: Colors.red,
                  filled: false,
                  onPressed: () => _deleteReport(doc),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reportButton({
    required String label,
    required Color color,
    required bool filled,
    VoidCallback? onPressed,
  }) {
    if (filled) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );
    }

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _statusPill(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LISTING INFO — a normalized snapshot of one listing from any
// of the six scanned collections, so the fraud checks can run
// the same rules over every source.
// ============================================================

class _ListingInfo {
  final String source; // Firestore collection name
  final String title;
  final String description;
  final List<String> images;
  final double? price;
  final String location;
  final String type;

  _ListingInfo({
    required this.source,
    required this.title,
    required this.description,
    required this.images,
    required this.price,
    required this.location,
    required this.type,
  });

  factory _ListingInfo.fromDoc(String source, Map<String, dynamic> data) {
    String first(List<String> keys) {
      for (final key in keys) {
        final value = data[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final images = <String>[];
    final rawImages = data['images'] ?? data['imageUrls'];
    if (rawImages is List) {
      for (final img in rawImages) {
        final url = img?.toString().trim() ?? '';
        if (url.isNotEmpty) images.add(url);
      }
    }
    final single = (data['imageUrl'] ?? '').toString().trim();
    if (single.isNotEmpty) images.add(single);

    double? price;
    final raw = data['price'] ?? data['rent'] ?? data['amount'];
    if (raw is num) {
      price = raw.toDouble();
    } else if (raw is String) {
      price = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
    }

    return _ListingInfo(
      source: source,
      title: first(['title', 'name']),
      description: first(['description', 'details']),
      images: images,
      price: price,
      location: first(['location', 'county', 'area', 'campus']),
      type: first(['type', 'category']),
    );
  }
}

// ============================================================
// REPORT DETAIL SHEET
// ============================================================

class _ReportDetailSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  final String reportId;

  /// Resolved by the page (the report only stores ids).
  final String sourceLabel;
  final String ownerName;
  final String reporterName;

  const _ReportDetailSheet({
    required this.data,
    required this.reportId,
    required this.sourceLabel,
    required this.ownerName,
    required this.reporterName,
  });

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  late final TextEditingController _noteController;

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _surface =>
      _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _border => _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _muted => _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(
      text: widget.data['adminNote']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _first(List<String> keys) {
    for (final key in keys) {
      final value = _text(widget.data[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _formatDate(dynamic value) {
    if (value is! Timestamp) return '';
    return DateFormat.yMMMd().add_jm().format(value.toDate().toLocal());
  }

  String get _status {
    final status = _text(widget.data['status']).toLowerCase();
    return (status == 'resolved' || status == 'closed')
        ? 'resolved'
        : 'pending';
  }

  void _finish(String action) {
    Navigator.pop(context, (action: action, note: _noteController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final reason = _first(['reason', 'category', 'title']);

    final rows = <(String, String)>[
      (_tr('Report from', 'Ripoti kutoka'), widget.sourceLabel),
      (_tr('Reason', 'Sababu'), reason.isEmpty ? '' : _prettyReason(reason)),
      (_tr('Details', 'Maelezo'),
      _first(['details', 'description', 'message'])),
      (_tr('Reported item', 'Kilichoripotiwa'),
      _first(['targetName', 'targetTitle', 'propertyTitle'])),
      (_tr('Item ID', 'Kitambulisho'), _first(['targetId', 'propertyId'])),
      (_tr('Owner', 'Mmiliki'), widget.ownerName),
      (_tr('Owner ID', 'Kitambulisho cha mmiliki'),
      _first(['targetOwnerId', 'ownerId', 'reportedUserId'])),
      (_tr('Reported by', 'Aliyeripoti'), widget.reporterName),
      (_tr('Reporter email', 'Barua pepe'), _first(['reporterEmail'])),
      (_tr('Reporter ID', 'Kitambulisho cha mwenye ripoti'),
      _first(['reporterId', 'reportedBy', 'userId'])),
      (_tr('Device ID', 'Kitambulisho cha kifaa'), _first(['deviceId'])),
      (_tr('Reported on', 'Iliripotiwa'), _formatDate(widget.data['createdAt'])),
      (_tr('Last action', 'Hatua ya mwisho'),
      _formatDate(widget.data['resolvedAt'])),
    ].where((row) => row.$2.isNotEmpty).toList();

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _tr('Report details', 'Maelezo ya ripoti'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(
                                rows[i].$1,
                                style: TextStyle(
                                    fontSize: 12.5, color: _muted),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                rows[i].$2,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i != rows.length - 1)
                        Divider(height: 1, color: _border),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _tr('Admin note (optional)',
                      'Maelezo ya msimamizi (si lazima)'),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _green, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_status == 'pending')
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _finish('resolved'),
                        icon: const Icon(Icons.check),
                        label: Text(_tr('Resolve', 'Tatua')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _finish('pending'),
                        icon: const Icon(Icons.restart_alt),
                        label: Text(_tr('Save note', 'Hifadhi maelezo')),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      side: BorderSide(color: _green),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _finish('pending'),
                    icon: const Icon(Icons.restart_alt),
                    label: Text(_tr('Reopen', 'Fungua tena')),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _finish('delete'),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(_tr('Delete report', 'Futa ripoti')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}