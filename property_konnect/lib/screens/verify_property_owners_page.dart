// ============================================================
// verify_property_owners_page.dart  (FULL UPDATED FILE)
//
// NEW IN THIS VERSION
//  1. KYC REVIEW CHECKLIST — clicking "Verify" now opens a
//     proper KYC review dialog (identity document, name match,
//     contact verification, duplicate review). Every required
//     item must be ticked before verification can proceed.
//  2. DUPLICATE DETECTION with SIMILARITY SCORE — exact matches
//     (national ID, email, phone — or name + phone / name + ID)
//     BLOCK verification with a detailed alert. A name-only
//     match is a POSSIBLE match: it is shown as a percentage
//     score inside the KYC dialog and must be reviewed, but it
//     no longer blocks on its own. Kenyan phone numbers are
//     normalized (07…, +254…, 254… all compare the same).
//     Where normalized lookup fields exist in Firestore
//     (normalizedEmail / normalizedPhone / normalizedNationalId)
//     targeted queries are used instead of scanning every owner.
//  3. ADS VERIFICATION HISTORY — every grant / extension / revocation
//     appends a permanent entry to the owner's
//     `adsVerificationHistory` array. The card shows how many
//     periods were granted and the current expiry.
//  4. ADS EXPIRY REMINDERS — the card shows "Expires in N day(s)"
//     and highlights in orange when a period ends within 7 days,
//     so the admin can remind / extend before it lapses.
//  5. PERMANENT DEACTIVATION HISTORY — deactivations and
//     reactivations append to a `deactivationHistory` array that
//     is NEVER deleted. Reactivation still clears the current
//     status fields, but the history remains for audit.
//  6. ADMIN AUDIT LOG — every administrative action (verify,
//     unverify, ads grant/revoke, deactivate, reactivate,
//     delete) is recorded in the shared `admin_audit_logs`
//     collection with the admin uid, admin name, action, reason,
//     previous status and new status. Logging is best-effort: a
//     logging failure never blocks the action itself.
//  7. WEB-SAFE EXPORTS — reports are shared from memory via
//     XFile.fromData (no dart:io / path_provider), so the page
//     compiles for Flutter Web as well as Android and iOS.
//     The string separators no longer use '*' multiplication.
//  8. REACTIVATION NOW RESTORES EACH PROPERTY'S TRUE PREVIOUS
//     STATE — deactivation saves previousIsActive /
//     previousAvailable / previousStatus / previousPropertyStatus,
//     and reactivation restores exactly those values (a property
//     that was already unavailable before stays unavailable).
//  9. STRICTER PDF DETECTION — only HTTPS URLs on trusted
//     Firebase Storage hosts with a .pdf path (or alt=media)
//     are treated as viewable PDFs. A bare token parameter is no
//     longer enough.
// 10. Owner name fallback now handles empty strings.
// 11. Deactivation / reactivation update the owner's PROPERTIES
//     FIRST and the owner doc LAST, so an owner is only flagged
//     after their listings are actually hidden. For very large
//     portfolios, moving these workflows into Cloud Functions is
//     still recommended (see the notes in the code).
//
// PREVIOUS FEATURES KEPT
//  - Verify / Unverify, duplicate blocking, timed Ads
//    verification with a preview, revoke-before-expiry,
//    deactivation reason prompt with audit fields, full account
//    removal (Firestore + properties + Auth via the
//    deleteUserAccount Cloud Function), owner list export,
//    in-app PDF viewer, search + status filter chips.
//  - ENGLISH ONLY; theme read from AppSettings.
// ============================================================
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';

enum OwnerFilter {
  all,
  verified,
  unverified,
  deactivated,
}

/// One duplicate candidate found during duplicate detection.
///
/// [score] is a 0–100 similarity score. [exact] is true for
/// STRONG duplicates (national ID, email, phone, or name+phone /
/// name+ID combinations) — these block verification. A name-only
/// match is NOT exact: it is a POSSIBLE match that must be
/// reviewed inside the KYC checklist but does not block.
typedef OwnerDuplicate = ({
Map<String, dynamic> other,
String otherId,
Set<String> fields,
int score,
bool exact,
});

class VerifyPropertyOwnersPage extends StatefulWidget {
  const VerifyPropertyOwnersPage({super.key});

  @override
  State<VerifyPropertyOwnersPage> createState() =>
      _VerifyPropertyOwnersPageState();
}

class _VerifyPropertyOwnersPageState extends State<VerifyPropertyOwnersPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isBusy = false;
  String? _busyOwnerId;
  OwnerFilter _selectedFilter = OwnerFilter.all;
  String _searchQuery = '';

  // ----------------------------------------------------------
  // THEME — from AppSettings (same as the homepage)
  // ----------------------------------------------------------

  SettingsController get _settings => AppSettings.of(context);

  bool get _isDark => _settings.isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _scaffold => _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _card => _isDark ? kDarkCard : Colors.white;

  Color get _border =>
      _isDark ? const Color(0xFF28352C) : const Color(0xFFE3ECE6);

  Color get _bodyText =>
      _isDark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);

  Color get _mutedText =>
      _isDark ? const Color(0xFFA9B8AF) : const Color(0xFF5B6B62);

  Color get _errColor =>
      _isDark ? Colors.red.shade300 : Colors.red.shade700;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// FIXED: handles empty strings — fullName = " " no longer
  /// hides a valid `name` value.
  String _ownerName(Map<String, dynamic> data) {
    final fullName = data['fullName']?.toString().trim() ?? '';
    final name = data['name']?.toString().trim() ?? '';

    if (fullName.isNotEmpty) return fullName;
    if (name.isNotEmpty) return name;

    return 'Unnamed owner';
  }

  bool _isVerified(Map<String, dynamic> data) =>
      data['landlord_status']?.toString().toLowerCase() == 'verified';

  // ----------------------------------------------------------
  // DEACTIVATED DETECTION
  // ----------------------------------------------------------

  static const Set<String> _inactiveStatuses = {
    'deactivated',
    'inactive',
    'deleted',
    'disabled',
  };

  bool _isInactiveString(dynamic value) =>
      value != null &&
          _inactiveStatuses.contains(value.toString().toLowerCase());

  bool _isDeactivated(Map<String, dynamic> data) {
    if (data['isDeactivated'] == true) return true;
    if (data['isDeleted'] == true || data['deleted'] == true) {
      return true;
    }
    if (data['isActive'] == false || data['active'] == false) {
      return true;
    }
    if (_isInactiveString(data['accountStatus'])) return true;
    if (_isInactiveString(data['status'])) return true;
    if (data['deactivatedAt'] != null) return true;

    return false;
  }

  // ----------------------------------------------------------
  // ADS VERIFICATION — TIMED
  // ----------------------------------------------------------

  DateTime? _adsStop(Map<String, dynamic> data) {
    final value = data['adsStop'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  bool _isAdsVerified(Map<String, dynamic> data) {
    final value = data['adsverification'] ?? data['adsVerification'];

    final enabled = value == true ||
        value?.toString().toLowerCase() == 'verified';

    if (!enabled) return false;

    final stop = _adsStop(data);
    if (stop != null && stop.isBefore(DateTime.now())) {
      return false; // window expired
    }

    return true;
  }

  bool _isAdsExpired(Map<String, dynamic> data) {
    final value = data['adsverification'] ?? data['adsVerification'];

    final enabled = value == true ||
        value?.toString().toLowerCase() == 'verified';

    if (!enabled) return false;

    final stop = _adsStop(data);
    return stop != null && stop.isBefore(DateTime.now());
  }

  /// Days left in the current ads window (null = no stop date).
  int? _adsDaysLeft(Map<String, dynamic> data) {
    final stop = _adsStop(data);
    if (stop == null) return null;
    return stop.difference(DateTime.now()).inDays;
  }

  /// Reminder threshold (days) before an ads period expires.
  static const int _adsReminderDays = 7;

  /// Number of ads periods in the owner's permanent history.
  int _adsHistoryCount(Map<String, dynamic> data) {
    final history = data['adsVerificationHistory'];
    return history is List ? history.length : 0;
  }

  /// Number of deactivation / reactivation events in the owner's
  /// permanent history.
  int _deactivationHistoryCount(Map<String, dynamic> data) {
    final history = data['deactivationHistory'];
    return history is List ? history.length : 0;
  }

  String _formatValue(dynamic value) {
    if (value == null) return '—';

    if (value is Timestamp) {
      return value.toDate().toLocal().toString().split('.').first;
    }

    if (value is DateTime) {
      return value.toLocal().toString().split('.').first;
    }

    if (value is Map) {
      return value.entries
          .map((e) => '${e.key}: ${_formatValue(e.value)}')
          .join('\n');
    }

    if (value is List) {
      return value.map(_formatValue).join(', ');
    }

    return value.toString();
  }

  // ==========================================================
  // NORMALIZATION (duplicates + lookups)
  // ==========================================================

  String _normalize(String? value) =>
      value?.toString().trim().toLowerCase() ?? '';

  String _digitsOnly(String? value) =>
      _normalize(value).replaceAll(RegExp(r'[^0-9]'), '');

  /// Normalizes a Kenyan phone number to the form 2547XXXXXXXX so
  /// 0712345678, +254712345678, 254712345678 and
  /// 712345678 all compare identically.
  String _normalizeKePhone(String? value) {
    var digits = _digitsOnly(value);

    if (digits.isEmpty) return '';

    // 0712345678 / 0110123456 -> 254XXXXXXXX
    if (digits.startsWith('0')) {
      digits = '254${digits.substring(1)}';
    } else if (digits.length == 9 && digits.startsWith('7')) {
      digits = '254$digits';
    } else if (digits.length == 9 && digits.startsWith('1')) {
      // 01xx numbers without the leading 0.
      digits = '254$digits';
    }

    return digits;
  }

  // ==========================================================
  // DUPLICATE DETECTION — with similarity score and
  // exact vs possible classification.
  //
  // Scoring weights (sum capped at 100):
  //   national ID   60   (strongest signal)
  //   email         45
  //   phone         35
  //   full name     25
  //
  // EXACT (blocks verification):
  //   - national ID match
  //   - email match
  //   - phone match
  //   - name + phone match
  //   - name + national ID match
  //
  // POSSIBLE (review in the KYC dialog, does NOT block):
  //   - name-only match
  // ==========================================================

  static const int _weightNationalId = 60;
  static const int _weightEmail = 45;
  static const int _weightPhone = 35;
  static const int _weightName = 25;

  /// Reads every owner doc once (fallback path when normalized
  /// lookup fields are not backfilled yet).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchAllOwners() {
    return _db
        .collection('users')
        .where('role', whereIn: ['owner', 'property_owner'])
        .get()
        .then((snapshot) => snapshot.docs);
  }

  /// NEW: targeted duplicate lookups. If the owner docs store the
  /// normalized lookup fields (normalizedEmail, normalizedPhone,
  /// normalizedNationalId) the detector queries ONLY the
  /// matching docs instead of downloading every owner. If those
  /// fields are missing the query simply returns nothing and the
  /// full scan fallback still runs — so the page works with or
  /// without backfilled data.
  Future<Set<String>> _targetedDuplicateIds(
      Map<String, dynamic> data) async {
    final ids = <String>{};

    final email = _normalize(data['email']);
    final phone = _normalizeKePhone(
        data['phoneNumber']?.toString() ?? data['phone']?.toString());
    final nationalId = _normalize(
        data['nationalId']?.toString() ?? data['idNumber']?.toString());

    Future<void> tryQuery(String field, String value) async {
      if (value.isEmpty) return;

      try {
        final snapshot = await _db
            .collection('users')
            .where(field, isEqualTo: value)
            .get();

        for (final doc in snapshot.docs) {
          final role = doc.data()['role']?.toString().toLowerCase();
          if (role == 'owner' || role == 'property_owner') {
            ids.add(doc.id);
          }
        }
      } on FirebaseException catch (e) {
        // Missing field / no index yet — fall back to the full
        // scan silently.
        debugPrint('TARGETED DUPLICATE QUERY SKIPPED ($field): ${e.code}');
      }
    }

    await Future.wait([
      tryQuery('normalizedEmail', email),
      tryQuery('normalizedPhone', phone),
      tryQuery('normalizedNationalId', nationalId),
    ]);

    return ids;
  }

  Future<List<OwnerDuplicate>> _findDuplicateOwners(
      String ownerId,
      Map<String, dynamic> data,
      ) async {
    // Try the cheap targeted lookups first; if the normalized
    // fields are not populated nothing is found there, so ALSO
    // fall back to one full scan of owners. (Once normalized
    // fields are backfilled, the scan can be removed entirely.)
    final docs = await _fetchAllOwners();

    final thisName = _normalize(_ownerName(data));
    final thisEmail = _normalize(data['email']?.toString());
    final thisPhone = _normalizeKePhone(
        data['phoneNumber']?.toString() ?? data['phone']?.toString());
    final thisId = _normalize(
        data['nationalId']?.toString() ?? data['idNumber']?.toString());

    final duplicates = <OwnerDuplicate>[];

    for (final doc in docs) {
      if (doc.id == ownerId) continue;

      final other = doc.data();

      final otherName = _normalize(_ownerName(other));
      final otherEmail = _normalize(other['email']?.toString());
      final otherPhone = _normalizeKePhone(
          other['phoneNumber']?.toString() ?? other['phone']?.toString());
      final otherId = _normalize(
          other['nationalId']?.toString() ?? other['idNumber']?.toString());

      final fields = <String>{};

      final nameMatch = thisName.isNotEmpty && thisName == otherName;
      final emailMatch =
          thisEmail.isNotEmpty && thisEmail == otherEmail;
      final phoneMatch =
          thisPhone.length >= 9 && thisPhone == otherPhone;
      final idMatch = thisId.isNotEmpty && thisId == otherId;

      if (nameMatch) fields.add('name');
      if (emailMatch) fields.add('email');
      if (phoneMatch) fields.add('phone');
      if (idMatch) fields.add('ID number');

      if (fields.isEmpty) continue;

      // Similarity score — stronger identity signals weigh more.
      var score = 0;
      if (idMatch) score += _weightNationalId;
      if (emailMatch) score += _weightEmail;
      if (phoneMatch) score += _weightPhone;
      if (nameMatch) score += _weightName;
      if (score > 100) score = 100;

      // Exact = a strong duplicate. A name-only match is merely
      // POSSIBLE and does not block verification on its own.
      final exact = idMatch ||
          emailMatch ||
          phoneMatch ||
          (nameMatch && phoneMatch) ||
          (nameMatch && idMatch);

      duplicates.add((
      other: other,
      otherId: doc.id,
      fields: fields,
      score: score,
      exact: exact,
      ));
    }

    // Strongest matches first.
    duplicates.sort((a, b) => b.score.compareTo(a.score));

    return duplicates;
  }

  Future<void> _showDuplicateAlert(
      String ownerName,
      List<OwnerDuplicate> duplicates,
      ) async {
    final line = List.filled(40, '=').join();
    final buffer = StringBuffer();

    for (var i = 0; i < duplicates.length; i++) {
      final d = duplicates[i];
      final otherName = _ownerName(d.other);
      final otherEmail = d.other['email']?.toString() ?? '';
      final otherPhone = (d.other['phoneNumber']?.toString() ??
          d.other['phone']?.toString() ??
          '');

      buffer
        ..writeln('Account ${i + 1}: $otherName')
        ..writeln('  Name: $otherName')
        ..writeln('  Email: $otherEmail')
        ..writeln('  Phone: $otherPhone')
        ..writeln('  Matching details: ${d.fields.join(', ')}')
        ..writeln('  Similarity score: ${d.score}%')
        ..writeln('  Classification: ${d.exact ? 'EXACT match' : 'Possible match'}')
        ..writeln();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: Icon(Icons.content_copy, color: _errColor, size: 42),
        title: Text(
          'Exact duplicate details found',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _errColor,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This owner cannot be verified because their national ID, '
                    'email or phone matches another owner account:',
                style: TextStyle(color: _bodyText, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SelectableText(
                buffer.toString().trim(),
                style: TextStyle(
                  color: _bodyText,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ADMIN AUDIT LOG — every administrative action is recorded
  // permanently in the shared `admin_audit_logs` collection.
  // Logging is BEST-EFFORT: a failure never blocks the action.
  // ==========================================================

  Future<void> _logAdminAction({
    required String action,
    required String ownerId,
    required String ownerName,
    String? reason,
    String? details,
    String? previousStatus,
    String? newStatus,
  }) async {
    try {
      final admin = await _currentAdminInfo();

      await _db.collection('admin_audit_logs').add({
        'ownerId': ownerId,
        'ownerName': ownerName,
        'action': action,
        'reason': reason ?? '',
        'details': details ?? '',
        'previousStatus': previousStatus ?? '',
        'newStatus': newStatus ?? '',
        'performedBy': admin.uid,
        'performedByName': admin.name,
        'performedByRole': 'admin',
        'performedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('AUDIT LOG WRITE ERROR: $e');
    }
  }

  /// Reads the currently signed-in admin's uid and name, used
  /// to record WHO performed every administrative action.
  Future<({String uid, String name})> _currentAdminInfo() async {
    final user = FirebaseAuth.instance.currentUser;

    final uid = user?.uid ?? 'unknown-admin';
    var name = user?.email ?? 'Admin';

    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();

      final storedName = (data?['fullName'] ??
          data?['name'] ??
          data?['displayName'])
          ?.toString()
          .trim() ??
          '';

      if (storedName.isNotEmpty) name = storedName;
    } catch (e) {
      debugPrint('ADMIN INFO LOAD ERROR: $e');
    }

    return (uid: uid, name: name);
  }

  // ==========================================================
  // KYC REVIEW CHECKLIST — shown when "Verify" is pressed.
  //
  // Every required item must be ticked before "Verify Owner"
  // becomes available. Possible duplicate matches (name-only)
  // are listed here and MUST be reviewed and acknowledged.
  // ==========================================================

  Future<bool> _showKycChecklistDialog({
    required String name,
    required Map<String, dynamic> data,
    required List<OwnerDuplicate> possibleMatches,
  }) async {
    final checks = <String, bool>{
      'Identity document provided and legible': false,
      'Name on the document matches the account name': false,
      'National ID number looks valid and consistent': false,
      'Phone number reachable / contact verified': false,
      'Email address verified': false,
      'Duplicate check reviewed': possibleMatches.isEmpty,
    };

    if (possibleMatches.isNotEmpty) {
      checks['Possible duplicate matches reviewed and cleared'] = false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final allRequiredTicked =
            checks.values.every((checked) => checked);

            return AlertDialog(
              backgroundColor: _card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              icon: Icon(Icons.fact_check_outlined,
                  color: _brand, size: 42),
              title: Text(
                'KYC review — $name',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _bodyText,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
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
                        'Confirm each identity and contact verification '
                            'item before verifying this owner. All items are '
                            'required.',
                        style: TextStyle(
                          color: _mutedText,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...checks.keys.map((label) {
                        return CheckboxListTile(
                          value: checks[label],
                          dense: true,
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: _brand,
                          title: Text(
                            label,
                            style: TextStyle(
                              color: _bodyText,
                              fontSize: 13.5,
                            ),
                          ),
                          onChanged: (value) {
                            setDialogState(() => checks[label] = value ?? false);
                          },
                        );
                      }),
                      if (possibleMatches.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'POSSIBLE MATCHES (name only) — these do '
                                    'not block verification, but you must '
                                    'review them:',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final d in possibleMatches)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• ${_ownerName(d.other)} — '
                                        '${d.fields.join(', ')} '
                                        '(${d.score}% similarity, possible match)',
                                    style: TextStyle(
                                      color: _bodyText,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(88, 44),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(130, 44),
                    backgroundColor: _brand,
                  ),
                  onPressed: allRequiredTicked
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('Verify Owner'),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  // ----------------------------------------------------------
  // SEARCH AND FILTERS
  // ----------------------------------------------------------

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterOwners(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> owners,
      ) {
    final query = _searchQuery.trim().toLowerCase();

    return owners.where((doc) {
      final data = doc.data();
      final verified = _isVerified(data);
      final deactivated = _isDeactivated(data);

      final matchesFilter = switch (_selectedFilter) {
        OwnerFilter.all => true,
        OwnerFilter.verified => verified && !deactivated,
        OwnerFilter.unverified => !verified && !deactivated,
        OwnerFilter.deactivated => deactivated,
      };

      if (!matchesFilter) return false;
      if (query.isEmpty) return true;

      final searchableFields = [
        doc.id,
        data['fullName'],
        data['name'],
        data['email'],
        data['phoneNumber'],
        data['phone'],
        data['nationalId'],
        data['idNumber'],
      ];

      return searchableFields.any(
            (value) =>
        value != null && value.toString().toLowerCase().contains(query),
      );
    }).toList();
  }

  String _filterLabel(OwnerFilter filter) {
    switch (filter) {
      case OwnerFilter.all:
        return 'All';
      case OwnerFilter.verified:
        return 'Verified';
      case OwnerFilter.unverified:
        return 'Unverified';
      case OwnerFilter.deactivated:
        return 'Deactivated';
    }
  }

  Widget _searchAndDownloadBar(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> owners,
      ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                style: TextStyle(
                  color: _bodyText,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search name, email, phone or ID...',
                  hintStyle: TextStyle(
                    color: _mutedText,
                    fontSize: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: _mutedText,
                    size: 22,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    tooltip: 'Clear search',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: _mutedText,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                      : null,
                  filled: true,
                  fillColor: _card,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _brand),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () => _downloadOwnersList(owners),
              icon: const Icon(Icons.download, size: 20),
              label: const Text(
                'Export',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> owners,
      ) {
    int count(OwnerFilter filter) {
      return owners.where((doc) {
        final data = doc.data();
        final verified = _isVerified(data);
        final deactivated = _isDeactivated(data);

        switch (filter) {
          case OwnerFilter.all:
            return true;
          case OwnerFilter.verified:
            return verified && !deactivated;
          case OwnerFilter.unverified:
            return !verified && !deactivated;
          case OwnerFilter.deactivated:
            return deactivated;
        }
      }).length;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: OwnerFilter.values.map((filter) {
            final selected = _selectedFilter == filter;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  '${_filterLabel(filter)} (${count(filter)})',
                  style: const TextStyle(fontSize: 13),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                selected: selected,
                selectedColor: _brand.withValues(alpha: 0.18),
                backgroundColor: _card,
                side: BorderSide(
                  color: selected ? _brand : _border,
                ),
                labelStyle: TextStyle(
                  color: selected ? _brand : _bodyText,
                  fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) {
                  setState(() => _selectedFilter = filter);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // SHARED ACTION HANDLER
  // ----------------------------------------------------------

  Future<void> _runAction(
      String ownerId,
      Future<void> Function() action,
      ) async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _busyOwnerId = ownerId;
    });

    try {
      await action();
    } catch (e) {
      _showSnack('Operation failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyOwnerId = null;
        });
      }
    }
  }

  // ----------------------------------------------------------
  // OWNER VERIFICATION — duplicate check + KYC checklist.
  //
  //   1. Detect duplicates. EXACT matches (national ID, email,
  //      phone, name+phone, name+ID) BLOCK verification.
  //   2. POSSIBLE matches (name only) do not block — they are
  //      listed inside the KYC checklist for review.
  //   3. The KYC checklist must be fully ticked before the owner
  //      is verified.
  //   4. The action is recorded in admin_audit_logs.
  // ----------------------------------------------------------

  Future<void> _verifyOwner(
      String ownerId,
      String name,
      Map<String, dynamic> data,
      ) async {
    await _runAction(ownerId, () async {
      final duplicates = await _findDuplicateOwners(ownerId, data);

      final exactMatches =
      duplicates.where((d) => d.exact).toList();
      final possibleMatches =
      duplicates.where((d) => !d.exact).toList();

      // STEP 1 — exact duplicates block verification.
      if (exactMatches.isNotEmpty) {
        if (mounted) {
          await _showDuplicateAlert(name, exactMatches);
        }
        return; // NOT verified.
      }

      // STEP 2 — KYC review checklist (possible matches are
      // reviewed here, but do not block on their own).
      if (mounted) {
        final kycPassed = await _showKycChecklistDialog(
          name: name,
          data: data,
          possibleMatches: possibleMatches,
        );

        if (!kycPassed) return; // cancelled or incomplete.
      }

      await _db.collection('users').doc(ownerId).update({
        'landlord_status': 'verified',
        'landlordVerifiedAt': FieldValue.serverTimestamp(),

        // Backfill the normalized lookup fields so future
        // duplicate checks can use targeted queries instead of
        // scanning every owner.
        'normalizedEmail': _normalize(data['email']?.toString()),
        'normalizedPhone': _normalizeKePhone(
            data['phoneNumber']?.toString() ?? data['phone']?.toString()),
        'normalizedNationalId': _normalize(
            data['nationalId']?.toString() ??
                data['idNumber']?.toString()),
      });

      await _logAdminAction(
        action: 'verify_owner',
        ownerId: ownerId,
        ownerName: name,
        details: possibleMatches.isNotEmpty
            ? 'Verified after reviewing ${possibleMatches.length} '
            'possible name-only match(es).'
            : 'KYC checklist completed.',
        previousStatus: 'unverified',
        newStatus: 'verified',
      );

      _showSnack('$name has been verified.');
    });
  }

  Future<void> _unverifyOwner(
      String ownerId,
      String name,
      ) async {
    await _runAction(ownerId, () async {
      await _db.collection('users').doc(ownerId).update({
        'landlord_status': 'unverified',
        'landlordVerifiedAt': FieldValue.delete(),
      });

      await _logAdminAction(
        action: 'unverify_owner',
        ownerId: ownerId,
        ownerName: name,
        previousStatus: 'verified',
        newStatus: 'unverified',
      );

      _showSnack('$name is now unverified.');
    });
  }

  // ==========================================================
  // ADS VERIFICATION — TIMED, with permanent history
  // ==========================================================

  /// Updates every property first, then the owner doc, so the
  /// owner flag only flips after their listings actually moved.
  /// (For very large portfolios, move this into a Cloud
  /// Function for atomic, retry-safe processing.)
  Future<void> _updateOwnerAndProperties(
      String ownerId,
      Map<String, dynamic> fields,
      ) async {
    final properties = await _db
        .collection('properties')
        .where('ownerId', isEqualTo: ownerId)
        .get();

    final refs = properties.docs.map((d) => d.reference).toList();

    for (var start = 0; start < refs.length; start += 450) {
      final end =
      (start + 450 < refs.length) ? start + 450 : refs.length;

      final batch = _db.batch();

      for (var i = start; i < end; i++) {
        batch.update(refs[i], fields);
      }

      await batch.commit();
    }

    await _db.collection('users').doc(ownerId).update(fields);
  }

  /// Shows the "Set ads verification period" pop-up.
  ///
  /// Returns the expiry date ONLY when the admin presses
  /// "Verify Ads". Pressing "Cancel" (or anything else that
  /// closes the dialog) returns null, so nothing is verified.
  Future<DateTime?> _showAdsPeriodDialog(String name) async {
    int unitIndex = 0; // 0 = days, 1 = weeks, 2 = months
    int amount = 30;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final now = DateTime.now();
            final stopPreview = unitIndex == 0
                ? now.add(Duration(days: amount))
                : unitIndex == 1
                ? now.add(Duration(days: amount * 7))
                : DateTime(now.year, now.month + amount, now.day,
                now.hour, now.minute);

            final fmt = DateFormat.yMMMd().add_jm();

            return AlertDialog(
              backgroundColor: _card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              icon: Icon(Icons.campaign_outlined,
                  color: _brand, size: 42),
              title: Text(
                'Set ads verification period',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How long should ads verification stay active for $name?',
                      style: TextStyle(color: _bodyText, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Duration',
                      style: TextStyle(
                        color: _brand,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            foregroundColor: _brand,
                            side: BorderSide(color: _brand),
                          ),
                          onPressed: amount > 1
                              ? () => setDialogState(() => amount--)
                              : null,
                          child: const Icon(Icons.remove),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '$amount',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: _bodyText,
                              ),
                            ),
                          ),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            foregroundColor: _brand,
                            side: BorderSide(color: _brand),
                          ),
                          onPressed: amount < 365
                              ? () => setDialogState(() => amount++)
                              : null,
                          child: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text('Days'),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text('Weeks'),
                        ),
                        ButtonSegment(
                          value: 2,
                          label: Text('Months'),
                        ),
                      ],
                      selected: {unitIndex},
                      onSelectionChanged: (selection) {
                        setDialogState(() => unitIndex = selection.first);
                      },
                    ),
                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _brand.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _brand.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Starts: ${fmt.format(now)}',
                            style: TextStyle(
                              color: _bodyText,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Expires: ${fmt.format(stopPreview)}',
                            style: TextStyle(
                              color: _brand,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'After this period, the ads-verified status automatically reverts to unverified.',
                      style: TextStyle(
                        color: _mutedText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                // CANCEL — closes the pop-up and returns false,
                // so NO ads verification happens.
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(88, 44),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),

                // VERIFY ADS — the ONLY button that returns true.
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(110, 44),
                    backgroundColor: _brand,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Verify Ads'),
                ),
              ],
            );
          },
        );
      },
    );

    // Cancelled (or dismissed): stop here, verify nothing.
    if (confirmed != true) return null;

    final now = DateTime.now();
    switch (unitIndex) {
      case 0:
        return now.add(Duration(days: amount));
      case 1:
        return now.add(Duration(days: amount * 7));
      default:
        return DateTime(
            now.year, now.month + amount, now.day, now.hour, now.minute);
    }
  }

  Future<void> _grantAdsVerification(
      String ownerId,
      String name,
      Map<String, dynamic> data,
      ) async {
    final stop = await _showAdsPeriodDialog(name);

    if (stop == null) return; // cancelled

    final admin = await _currentAdminInfo();
    final isExtension = _isAdsVerified(data);

    await _runAction(ownerId, () async {
      final start = DateTime.now();

      await _updateOwnerAndProperties(ownerId, {
        'adsverification': true,
        'adsStart': Timestamp.fromDate(start),
        'adsStop': Timestamp.fromDate(stop),
        'adsVerifiedAt': FieldValue.serverTimestamp(),

        // PERMANENT HISTORY — never deleted, shows every period
        // that was granted or extended.
        'adsVerificationHistory': FieldValue.arrayUnion([
          {
            'action': isExtension ? 'extended' : 'granted',
            'start': Timestamp.fromDate(start),
            'stop': Timestamp.fromDate(stop),
            'grantedBy': admin.uid,
            'grantedByName': admin.name,
            // NOTE: serverTimestamp() CANNOT be nested inside
            // arrayUnion — Firestore rejects it with
            // "Invalid data. FieldValue.serverTimestamp() can
            // only be used with set() and update()". Use a
            // client timestamp inside array entries instead.
            'grantedAt': Timestamp.fromDate(DateTime.now()),
          }
        ]),
      });

      await _logAdminAction(
        action: isExtension ? 'ads_verification_extended' : 'ads_verification_granted',
        ownerId: ownerId,
        ownerName: name,
        details: 'Ads verification active until '
            '${DateFormat.yMMMd().format(stop)}.',
        previousStatus: isExtension ? 'ads-verified (previous period)' : 'ads-not-verified',
        newStatus: 'ads-verified',
      );

      _showSnack(
        'Ads verification enabled for $name until ${DateFormat.yMMMd().format(stop)}.',
      );
    });
  }

  Future<void> _revokeAdsVerification(
      String ownerId,
      String name,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: const Icon(Icons.campaign_outlined,
            color: Colors.orange, size: 42),
        title: Text(
          'Revoke ads verification?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _bodyText,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Disable ads verification for $name now, before its expiry date?',
          textAlign: TextAlign.center,
          style: TextStyle(color: _bodyText, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(88, 44),
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(110, 44),
              backgroundColor: Colors.orange,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final admin = await _currentAdminInfo();

    await _runAction(ownerId, () async {
      await _updateOwnerAndProperties(ownerId, {
        'adsverification': false,
        'adsStart': FieldValue.delete(),
        'adsStop': FieldValue.delete(),

        // PERMANENT HISTORY — the revocation is recorded too.
        'adsVerificationHistory': FieldValue.arrayUnion([
          {
            'action': 'revoked',
            'revokedBy': admin.uid,
            'revokedByName': admin.name,
            // Client timestamp — see note on grantedAt above.
            'revokedAt': Timestamp.fromDate(DateTime.now()),
          }
        ]),
      });

      await _logAdminAction(
        action: 'ads_verification_revoked',
        ownerId: ownerId,
        ownerName: name,
        previousStatus: 'ads-verified',
        newStatus: 'ads-not-verified',
      );

      _showSnack('Ads verification disabled for $name.');
    });
  }

  // ==========================================================
  // DEACTIVATE / REACTIVATE — reason prompt + PERMANENT history
  // ==========================================================

  /// Preset deactivation reasons.
  static const String _otherReasonLabel = 'Other (write a reason)';

  static const List<String> _deactivationReasons = [
    'Duplicate account',
    'Suspicious or fraudulent activity',
    'Owner requested deactivation',
    'Violation of platform policies',
    'Inactive account',
    _otherReasonLabel,
  ];

  /// A simple selectable reason tile (replaces RadioListTile,
  /// whose groupValue API is deprecated after Flutter 3.32).
  Widget _reasonTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: selected
                ? _brand.withValues(alpha: 0.10)
                : _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _brand : _border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? _brand : _mutedText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: _bodyText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The REASON dialog shown when the admin taps "Deactivate".
  /// Returns the chosen reason (with optional note appended),
  /// or null if cancelled.
  Future<String?> _showDeactivationReasonDialog(String name) async {
    final reasonController = TextEditingController();

    int? selected;
    String? error;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final isOther = selected != null &&
                _deactivationReasons[selected!] == _otherReasonLabel;

            return AlertDialog(
              backgroundColor: _card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              icon: const Icon(Icons.help_outline,
                  color: Colors.orange, size: 42),
              title: Text(
                'Reason for deactivating $name',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _bodyText,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select the reason why this owner is being deactivated. This is recorded on their account and kept in the permanent deactivation history.',
                      style: TextStyle(
                          color: _bodyText, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(_deactivationReasons.length, (i) {
                      return _reasonTile(
                        label: _deactivationReasons[i],
                        selected: selected == i,
                        onTap: () {
                          setDialogState(() {
                            selected = i;
                            error = null;
                          });
                        },
                      );
                    }),
                    if (isOther) ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: reasonController,
                        maxLines: 2,
                        textCapitalization:
                        TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Write the reason',
                          border: const OutlineInputBorder(),
                          errorText: error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(88, 44),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(110, 44),
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () {
                    if (selected == null) {
                      setDialogState(() {
                        error = 'Select a reason first';
                      });
                      return;
                    }

                    final isOtherChoice =
                        _deactivationReasons[selected!] == _otherReasonLabel;

                    final note = reasonController.text.trim();

                    if (isOtherChoice && note.isEmpty) {
                      setDialogState(() {
                        error = 'Please write the reason';
                      });
                      return;
                    }

                    final base = _deactivationReasons[selected!];

                    Navigator.pop(
                      dialogContext,
                      isOtherChoice
                          ? note
                          : (note.isNotEmpty ? '$base — $note' : base),
                    );
                  },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();

    return result;
  }

  Map<String, dynamic> _reactivationFields(
      Map<String, dynamic> data,
      ) {
    final fields = <String, dynamic>{
      'isDeactivated': false,
      'accountStatus': 'active',
      'deactivatedAt': FieldValue.delete(),

      // Clear the CURRENT deactivation status. The permanent
      // deactivationHistory array is NOT touched — the full
      // record of every deactivation / reactivation survives.
      'deactivatedBy': FieldValue.delete(),
      'deactivatedByName': FieldValue.delete(),
      'deactivatedByRole': FieldValue.delete(),
      'deactivationReason': FieldValue.delete(),
    };

    if (data.containsKey('isActive')) fields['isActive'] = true;
    if (data.containsKey('active')) fields['active'] = true;
    if (data.containsKey('isDeleted')) fields['isDeleted'] = false;
    if (data.containsKey('deleted')) fields['deleted'] = false;
    if (_isInactiveString(data['status'])) {
      fields['status'] = 'active';
    }

    return fields;
  }

  /// DEACTIVATE all the owner's properties — each property's
  /// CURRENT state is saved first so reactivation can restore
  /// exactly what was there before (a property that was already
  /// unavailable does NOT come back as available).
  Future<void> _deactivateOwnerProperties(
      String ownerId, {
        Map<String, dynamic> audit = const {},
      }) async {
    final now = FieldValue.serverTimestamp();

    final properties = await _db
        .collection('properties')
        .where('ownerId', isEqualTo: ownerId)
        .get();

    final docs = properties.docs;

    for (var start = 0; start < docs.length; start += 450) {
      final end =
      (start + 450 < docs.length) ? start + 450 : docs.length;

      final batch = _db.batch();

      for (var i = start; i < end; i++) {
        final data = docs[i].data();

        batch.update(docs[i].reference, {
          'isDeactivated': true,
          'isActive': false,
          'available': false,
          'status': 'inactive',
          'property_status': 'inactive',

          // FIXED: save the FULL previous state, not just the
          // two status strings.
          'previousStatus': data['status'] ?? 'active',
          'previousPropertyStatus':
          data['property_status'] ?? 'unverified',
          'previousIsActive': data['isActive'] ?? true,
          'previousAvailable': data['available'] ?? true,
          'deactivatedAt': now,
          'updatedAt': now,
          ...audit,
        });
      }

      await batch.commit();
    }
  }

  /// REACTIVATE all the owner's properties, restoring each
  /// listing to the exact state it had BEFORE the owner was
  /// deactivated (using the previous* values saved above). A
  /// property that was already unavailable before the
  /// deactivation STAYS unavailable.
  Future<void> _reactivateOwnerProperties(
      String ownerId, {
        Map<String, dynamic> auditClear = const {},
      }) async {
    final now = FieldValue.serverTimestamp();

    final properties = await _db
        .collection('properties')
        .where('ownerId', isEqualTo: ownerId)
        .get();

    final docs = properties.docs;

    for (var start = 0; start < docs.length; start += 450) {
      final end =
      (start + 450 < docs.length) ? start + 450 : docs.length;

      final batch = _db.batch();

      for (var i = start; i < end; i++) {
        final data = docs[i].data();

        // Restore only what was actually saved; fall back to
        // sensible defaults for older records that were
        // deactivated before the previous* fields existed.
        final previousStatus =
            data['previousStatus']?.toString() ?? 'active';
        final previousPropertyStatus =
            data['previousPropertyStatus']?.toString() ?? 'verified';
        final previousIsActive = data['previousIsActive'] ?? true;
        final previousAvailable = data['previousAvailable'] ?? true;

        batch.update(docs[i].reference, {
          'isDeactivated': false,
          'isActive': previousIsActive == true,
          'available': previousAvailable == true,
          'status': previousStatus,
          'property_status': previousPropertyStatus,
          'previousStatus': FieldValue.delete(),
          'previousPropertyStatus': FieldValue.delete(),
          'previousIsActive': FieldValue.delete(),
          'previousAvailable': FieldValue.delete(),
          'deactivatedAt': FieldValue.delete(),
          'updatedAt': now,
          ...auditClear,
        });
      }

      await batch.commit();
    }
  }

  Future<void> _toggleDeactivation(
      String ownerId,
      String name,
      bool currentlyDeactivated,
      Map<String, dynamic> data,
      ) async {
    // DEACTIVATION requires a reason FIRST.
    String? reason;
    String adminUid = '';
    String adminName = '';

    if (!currentlyDeactivated) {
      reason = await _showDeactivationReasonDialog(name);

      if (reason == null) return; // cancelled — nothing happens.

      final admin = await _currentAdminInfo();
      adminUid = admin.uid;
      adminName = admin.name;
    } else {
      // Reactivation: record who reactivated the owner.
      final admin = await _currentAdminInfo();
      adminUid = admin.uid;
      adminName = admin.name;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: Text(
          currentlyDeactivated ? 'Reactivate owner?' : 'Deactivate owner?',
          style: TextStyle(color: _bodyText),
        ),
        content: Text(
          currentlyDeactivated
              ? 'Are you sure you want to reactivate $name? '
              'Their details will be retained.'
              : 'Are you sure you want to deactivate $name?\n\n'
              'Reason: $reason\n\n'
              'Their details will be retained, and ALL their '
              'properties will be hidden from tenants until '
              'reactivation.',
          style: TextStyle(color: _bodyText, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(88, 44),
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(110, 44),
              backgroundColor:
              currentlyDeactivated ? _brand : Colors.orange,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              currentlyDeactivated ? 'Reactivate' : 'Deactivate',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _runAction(ownerId, () async {
      // PROPERTIES FIRST, OWNER LAST — the owner is only flagged
      // after their listings have actually moved. (For fully
      // atomic behaviour across large portfolios, move this
      // whole workflow into a Cloud Function.)
      if (currentlyDeactivated) {
        await _reactivateOwnerProperties(
          ownerId,
          auditClear: {
            'deactivatedBy': FieldValue.delete(),
            'deactivatedByName': FieldValue.delete(),
            'deactivatedByRole': FieldValue.delete(),
            'deactivationReason': FieldValue.delete(),
          },
        );

        await _db.collection('users').doc(ownerId).update({
          ..._reactivationFields(data),
          'reactivatedBy': adminUid,
          'reactivatedByName': adminName,
          'reactivatedByRole': 'admin',
          'reactivatedAt': FieldValue.serverTimestamp(),

          // PERMANENT HISTORY — a reactivation entry is appended
          // and the old entries are never removed.
          'deactivationHistory': FieldValue.arrayUnion([
            {
              'type': 'reactivated',
              'by': adminUid,
              'byName': adminName,
              'byRole': 'admin',
              // Client timestamp — serverTimestamp() is not
              // allowed inside arrayUnion entries.
              'at': Timestamp.fromDate(DateTime.now()),
            }
          ]),
        });
      } else {
        await _deactivateOwnerProperties(
          ownerId,
          audit: {
            'deactivatedBy': adminUid,
            'deactivatedByName': adminName,
            'deactivatedByRole': 'admin',
            'deactivationReason': reason,
          },
        );

        await _db.collection('users').doc(ownerId).update({
          'isDeactivated': true,
          'isActive': false,
          'accountStatus': 'deactivated',
          'status': 'deactivated',
          'deactivatedAt': FieldValue.serverTimestamp(),

          // Admin audit trail (current status).
          'deactivatedBy': adminUid,
          'deactivatedByName': adminName,
          'deactivatedByRole': 'admin',
          'deactivationReason': reason,

          // PERMANENT HISTORY — every deactivation is kept
          // forever, even after reactivation.
          'deactivationHistory': FieldValue.arrayUnion([
            {
              'type': 'deactivated',
              'reason': reason ?? '',
              'by': adminUid,
              'byName': adminName,
              'byRole': 'admin',
              // Client timestamp — serverTimestamp() is not
              // allowed inside arrayUnion entries.
              'at': Timestamp.fromDate(DateTime.now()),
            }
          ]),
        });
      }

      await _logAdminAction(
        action: currentlyDeactivated ? 'reactivate_owner' : 'deactivate_owner',
        ownerId: ownerId,
        ownerName: name,
        reason: reason,
        previousStatus: currentlyDeactivated ? 'deactivated' : 'active',
        newStatus: currentlyDeactivated ? 'active' : 'deactivated',
      );

      _showSnack(
        currentlyDeactivated
            ? '$name has been reactivated.'
            : '$name has been deactivated.',
      );
    });
  }

  // ==========================================================
  // DELETE OWNER — FULL ACCOUNT REMOVAL
  //
  // The audit log entry is written FIRST so the deletion is
  // always recorded, even if a later step fails. For a fully
  // atomic workflow (properties + Firestore + Storage + Auth
  // in one server-side transaction), move this whole sequence
  // into a Cloud Function that validates the admin caller.
  // ==========================================================

  Future<void> _deleteOwner(
      String ownerId,
      String name,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: Icon(Icons.person_remove, color: _errColor, size: 42),
        title: Text(
          "Remove owner's account?",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _errColor,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: Text(
          "Are you sure you want to remove $name's account? "
              'This PERMANENTLY deletes their account details, '
              'ALL properties they have listed, and their '
              'ability to sign in. This action cannot be undone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _bodyText, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(88, 46),
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(110, 46),
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove Account'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Record the deletion in the audit log BEFORE any data is
    // removed, so the trail survives every failure mode.
    await _logAdminAction(
      action: 'delete_owner',
      ownerId: ownerId,
      ownerName: name,
      previousStatus: 'active',
      newStatus: 'deleted',
    );

    await _runAction(ownerId, () async {
      // STEP 1 — DELETE ALL THE OWNER'S PROPERTIES.
      final properties = await _db
          .collection('properties')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      final propRefs =
      properties.docs.map((d) => d.reference).toList();

      for (var start = 0; start < propRefs.length; start += 450) {
        final end = (start + 450 < propRefs.length)
            ? start + 450
            : propRefs.length;

        final batch = _db.batch();

        for (var i = start; i < end; i++) {
          batch.delete(propRefs[i]);
        }

        await batch.commit();
      }

      // STEP 2 — DELETE THE FIRESTORE USER DOCUMENT.
      await _db.collection('users').doc(ownerId).delete();

      // STEP 3 — DELETE THE FIREBASE AUTH ACCOUNT via the
      // deleteUserAccount Cloud Function.
      try {
        await FirebaseFunctions.instanceFor(
          region: 'us-central1',
        )
            .httpsCallable('deleteUserAccount')
            .call({'uid': ownerId});
      } on FirebaseFunctionsException catch (e) {
        debugPrint('DELETE AUTH ACCOUNT ERROR: ${e.code} ${e.message}');

        _showSnack(
          'Account data deleted, but the sign-in account could '
              'not be removed. Deploy the deleteUserAccount '
              'Cloud Function to complete removal.',
        );
        return;
      }

      _showSnack("$name's account has been completely removed.");
    });
  }

  // ----------------------------------------------------------
  // DOWNLOAD FILTERED OWNER LIST
  //
  // WEB-SAFE: the report is generated in memory and shared via
  // XFile.fromData — no dart:io, so this compiles for Flutter
  // Web as well as Android and iOS.
  // ----------------------------------------------------------

  Future<void> _downloadOwnersList(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> owners,
      ) async {
    if (owners.isEmpty) {
      _showSnack('There are no owners to export.');
      return;
    }

    try {
      final thick = List.filled(40, '=').join();
      final thin = List.filled(40, '-').join();

      final buffer = StringBuffer()
        ..writeln('PROPERTY OWNERS REPORT')
        ..writeln('Generated: ${DateTime.now()}')
        ..writeln('Filter: ${_filterLabel(_selectedFilter)}')
        ..writeln('Search: $_searchQuery')
        ..writeln('Total owners: ${owners.length}')
        ..writeln(thick)
        ..writeln();

      for (final doc in owners) {
        final data = doc.data();
        final adsDaysLeft = _adsDaysLeft(data);

        buffer
          ..writeln('Name: ${_ownerName(data)}')
          ..writeln('Document ID: ${doc.id}')
          ..writeln('Email: ${data['email'] ?? ''}')
          ..writeln(
            'Phone: ${data['phoneNumber'] ?? data['phone'] ?? ''}',
          )
          ..writeln(
            'Owner status: ${data['landlord_status'] ?? 'unverified'}',
          )
          ..writeln('Ads verified: ${_isAdsVerified(data)}')
          ..writeln('Ads history entries: ${_adsHistoryCount(data)}')
          ..writeln(
            adsDaysLeft != null && _isAdsVerified(data)
                ? 'Ads expires in: $adsDaysLeft day(s)'
                : 'Ads expires in: —',
          )
          ..writeln('Deactivated: ${_isDeactivated(data)}')
          ..writeln(
            'Deactivation history entries: '
                '${_deactivationHistoryCount(data)}',
          )
          ..writeln(
            'Deactivated by: ${data['deactivatedByName'] ?? ''} '
                '(${data['deactivatedByRole'] ?? ''})',
          )
          ..writeln(
            'Deactivation reason: ${data['deactivationReason'] ?? ''}',
          )
          ..writeln(thin)
          ..writeln();
      }

      final fileName =
          'property_owners_${DateTime.now().millisecondsSinceEpoch}.txt';

      await _shareTextReport(
        buffer.toString(),
        fileName: fileName,
        subject: 'Property owners report',
        text: 'Property owners report',
      );
    } catch (e) {
      _showSnack('Could not export owners: $e');
    }
  }

  /// Shares a text report from memory — works on mobile AND web
  /// (no dart:io / File needed).
  Future<void> _shareTextReport(
      String content, {
        required String fileName,
        required String subject,
        required String text,
      }) async {
    final bytes = Uint8List.fromList(content.codeUnits);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: fileName,
            mimeType: 'text/plain',
          ),
        ],
        subject: subject,
        text: text,
      ),
    );
  }

  // ----------------------------------------------------------
  // PDF DETECTION — STRICT.
  //
  // Only HTTPS URLs on trusted Firebase Storage hosts count as
  // viewable PDFs, and the URL must actually look like a PDF
  // (.pdf path or alt=media). A bare token parameter is no
  // longer enough, and stored mimeType metadata is respected
  // when present.
  // ----------------------------------------------------------

  static const List<String> _trustedStorageHostSuffixes = [
    'firebasestorage.googleapis.com',
    'storage.googleapis.com',
    'storage.cloud.google.com',
  ];

  bool _isTrustedStorageHost(String host) {
    final lower = host.toLowerCase();

    // Firebase Storage download URLs use regional hosts such as
    // africasouth1.firebasestorage.googleapis.com.
    for (final suffix in _trustedStorageHostSuffixes) {
      if (lower == suffix || lower.endsWith('.$suffix')) return true;
    }

    return false;
  }

  /// Returns true when a stored document field explicitly says
  /// the file is a PDF (mimeType == 'application/pdf').
  bool _hasPdfMime(String key, String value) {
    final lowerKey = key.toLowerCase();
    if (lowerKey.contains('mimetype') || lowerKey.contains('mime_type')) {
      return value.trim().toLowerCase() == 'application/pdf';
    }
    return false;
  }

  bool _isPdfUrl(String value, {String? mimeType}) {
    final uri = Uri.tryParse(value.trim());

    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return false;
    }

    // Restrict to trusted storage hosts.
    if (!_isTrustedStorageHost(uri.host)) return false;

    // Explicit stored MIME type wins when available.
    if (mimeType != null && mimeType.isNotEmpty) {
      return mimeType.trim().toLowerCase() == 'application/pdf';
    }

    final lowerPath = uri.path.toLowerCase();

    return lowerPath.endsWith('.pdf') ||
        uri.queryParameters['alt'] == 'media' &&
            lowerPath.contains('.pdf');
  }

  void _collectPdfUrls(
      Map<String, dynamic> data,
      List<MapEntry<String, String>> results, {
        String prefix = '',
      }) {
    for (final entry in data.entries) {
      final key =
      prefix.isEmpty ? entry.key : '$prefix.${entry.key}';

      final value = entry.value;

      if (value is String) {
        final lowerKey = key.toLowerCase();

        // Skip mimeType fields themselves — they are not URLs.
        if (lowerKey.contains('mimetype') || lowerKey.contains('mime_type')) {
          continue;
        }

        final looksLikeDocument =
            lowerKey.contains('pdf') ||
                lowerKey.contains('document') ||
                lowerKey.contains('nationalid') ||
                lowerKey.contains('national_id') ||
                lowerKey.contains('identity') ||
                lowerKey.contains('idcard') ||
                lowerKey.contains('id_card') ||
                lowerKey.contains('verificationfile');

        // Look for a sibling mimeType field to validate against.
        String? mimeType;
        final mimeKey = data.keys.firstWhere(
              (k) => k.toLowerCase() == '${entry.key.toLowerCase()}mimetype',
          orElse: () => '',
        );
        if (mimeKey.isNotEmpty) {
          mimeType = data[mimeKey]?.toString();
        }

        if (looksLikeDocument && _isPdfUrl(value, mimeType: mimeType)) {
          results.add(MapEntry(key, value.trim()));
        }
      } else if (value is Map) {
        _collectPdfUrls(
          Map<String, dynamic>.from(value),
          results,
          prefix: key,
        );
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          final item = value[i];

          if (item is String &&
              _isPdfUrl(item) &&
              (key.toLowerCase().contains('document') ||
                  key.toLowerCase().contains('pdf') ||
                  key.toLowerCase().contains('file'))) {
            results.add(MapEntry('$key[$i]', item.trim()));
          } else if (item is Map) {
            _collectPdfUrls(
              Map<String, dynamic>.from(item),
              results,
              prefix: '$key[$i]',
            );
          }
        }
      }
    }
  }

  // ----------------------------------------------------------
  // IN-APP PDF VIEWER
  // ----------------------------------------------------------

  Future<void> _viewPdf(String title, String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        uri.scheme != 'https' ||
        !_isTrustedStorageHost(uri.host)) {
      _showSnack('Invalid or untrusted PDF URL.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: _card,
        insetPadding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 900,
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.picture_as_pdf,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _bodyText,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: Icon(Icons.close, color: _bodyText),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: _border),
              Expanded(
                child: SfPdfViewer.network(
                  url,
                  canShowScrollHead: true,
                  canShowScrollStatus: true,
                  onDocumentLoadFailed: (details) {
                    _showSnack('Unable to load PDF: ${details.description}');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // CONTACT OWNER — WhatsApp and phone call buttons in the
  // View Owner details pop-up. Kenyan numbers are normalized
  // (07…, +254…, 254…, 7…) so wa.me always gets 254XXXXXXXX.
  // ----------------------------------------------------------

  String _displayPhoneOf(Map<String, dynamic> data) =>
      (data['phoneNumber']?.toString().trim().isNotEmpty == true
          ? data['phoneNumber'].toString()
          : data['phone']?.toString() ?? '')
          .trim();

  /// Opens WhatsApp chat with the owner (falls back to
  /// wa.me, which offers to open the app or WhatsApp Web).
  Future<void> _contactOwnerViaWhatsApp(String phone) async {
    final normalized = _normalizeKePhone(phone);

    if (normalized.isEmpty) {
      _showSnack('This owner has no phone number saved.');
      return;
    }

    final message = Uri.encodeComponent(
      'Hello! This is PropertyKonnect support regarding your '
          'property owner account.',
    );

    final url = Uri.parse('https://wa.me/$normalized?text=$message');

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showSnack('Could not open WhatsApp.');
    }
  }

  /// Starts a phone call to the owner via the device dialer.
  Future<void> _callOwner(String phone) async {
    if (phone.trim().isEmpty) {
      _showSnack('This owner has no phone number saved.');
      return;
    }

    final url = Uri.parse('tel:${phone.trim()}');

    try {
      await launchUrl(url);
    } catch (_) {
      _showSnack('Could not open the dialer.');
    }
  }

  // ----------------------------------------------------------
  // VIEW OWNER DETAILS
  // ----------------------------------------------------------

  Future<void> _viewOwner(
      String ownerId,
      Map<String, dynamic> data,
      ) async {
    final details = Map<String, dynamic>.from(data);
    details['firestoreDocumentId'] = ownerId;

    final phone = _displayPhoneOf(data);

    final pdfs = <MapEntry<String, String>>[];
    _collectPdfUrls(details, pdfs);

    final seenUrls = <String>{};
    final uniquePdfs = pdfs.where((entry) {
      return seenUrls.add(entry.value);
    }).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        insetPadding: const EdgeInsets.all(12),
        title: Text(
          'Property owner details',
          style: TextStyle(
            color: _bodyText,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...details.entries.map((entry) {
                  final key = entry.key.toLowerCase();

                  final isDocumentField =
                      key.contains('pdf') ||
                          key.contains('document') ||
                          key.contains('verificationfile');

                  if (isDocumentField &&
                      entry.value is String &&
                      _isPdfUrl(entry.value as String)) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: TextStyle(
                            color: _brand,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        SelectableText(
                          _formatValue(entry.value),
                          style: TextStyle(
                            color: _bodyText,
                            fontSize: 14,
                          ),
                        ),
                        Divider(color: _border),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
                Text(
                  'Uploaded documents',
                  style: TextStyle(
                    color: _bodyText,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (uniquePdfs.isEmpty)
                  Text(
                    'No PDFs found. Check the document fields and stored mimeType in this owner’s Firestore record.',
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 13,
                    ),
                  )
                else
                  ...uniquePdfs.map((entry) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: _border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        minVerticalPadding: 10,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        leading: const Icon(
                          Icons.picture_as_pdf,
                          color: Colors.red,
                        ),
                        title: Text(
                          entry.key,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _bodyText,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          'Tap to view PDF',
                          style: TextStyle(
                            color: _mutedText,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.visibility_outlined,
                          color: _brand,
                          size: 22,
                        ),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _viewPdf(entry.key, entry.value);
                        },
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          // WHATSAPP — direct chat with the owner.
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              foregroundColor:
              const Color(0xFF25D366).withValues(alpha: 1),
              side: const BorderSide(color: Color(0xFF25D366)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _contactOwnerViaWhatsApp(phone);
            },
            icon: const Icon(Icons.chat_bubble, size: 18),
            label: const Text(
              'WhatsApp',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),

          // CALL — opens the device dialer.
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              foregroundColor: _brand,
              side: BorderSide(color: _brand),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _callOwner(phone);
            },
            icon: const Icon(Icons.call, size: 18),
            label: const Text(
              'Call',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),

          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(88, 46),
            ),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 14),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 46),
              backgroundColor: _brand,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _downloadOwnerDetails(ownerId, details);
            },
            icon: const Icon(
              Icons.download,
              size: 20,
              color: Colors.white,
            ),
            label: const Text(
              'Download',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // DOWNLOAD OWNER DETAILS — web-safe, from memory.
  // ----------------------------------------------------------

  Future<void> _downloadOwnerDetails(
      String ownerId,
      Map<String, dynamic> details,
      ) async {
    try {
      final thick = List.filled(40, '=').join();

      final buffer = StringBuffer()
        ..writeln('PROPERTY OWNER DETAILS')
        ..writeln(thick)
        ..writeln('Document ID: $ownerId')
        ..writeln();

      for (final entry in details.entries) {
        buffer
          ..writeln('${entry.key}: ${_formatValue(entry.value)}')
          ..writeln();
      }

      final safeId = ownerId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      await _shareTextReport(
        buffer.toString(),
        fileName: 'owner_details_$safeId.txt',
        subject: 'Property owner details',
        text: 'Property owner details: $ownerId',
      );
    } catch (e) {
      _showSnack('Could not export owner details: $e');
    }
  }

  // ----------------------------------------------------------
  // STATUS CHIPS + ACTION BUTTON
  // ----------------------------------------------------------

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: filled ? Colors.white : color,
        backgroundColor: filled ? color : Colors.transparent,
        disabledForegroundColor: _mutedText.withValues(alpha: 0.7),
        disabledBackgroundColor:
        _isDark ? Colors.white.withValues(alpha: 0.04) : null,
        side: BorderSide(
          color: onPressed == null
              ? _border
              : color.withValues(alpha: 0.8),
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // ADS EXPIRY REMINDER BANNER — owners whose ads window ends
  // within the reminder threshold, so the admin can remind or
  // extend before it lapses.
  // ----------------------------------------------------------

  Widget _adsExpiryReminderBanner(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allOwners,
      ) {
    final expiring = allOwners.where((doc) {
      final data = doc.data();
      if (!_isAdsVerified(data)) return false;
      final days = _adsDaysLeft(data);
      return days != null && days >= 0 && days <= _adsReminderDays;
    }).toList();

    if (expiring.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.notification_important_outlined,
              color: Colors.orange.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ads verification expires within $_adsReminderDays day(s) for '
                  '${expiring.length} owner(s): '
                  '${expiring.map((d) => _ownerName(d.data())).join(', ')}. '
                  'Send a reminder or extend their period.',
              style: TextStyle(
                color: _bodyText,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // OWNER CARD
  // ----------------------------------------------------------

  Widget _ownerCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();
    final name = _ownerName(data);
    final email = data['email']?.toString() ?? '';
    final phone = data['phoneNumber']?.toString() ??
        data['phone']?.toString() ??
        '';

    final verified = _isVerified(data);
    final adsVerified = _isAdsVerified(data);
    final adsExpired = _isAdsExpired(data);
    final deactivated = _isDeactivated(data);
    final disabled = _isBusy;

    final isSelf = FirebaseAuth.instance.currentUser?.uid == doc.id;

    final adsStop = _adsStop(data);
    final adsStopText = adsStop != null
        ? DateFormat.yMMMd().format(adsStop)
        : null;

    final adsDaysLeft = _adsDaysLeft(data);
    final adsExpiringSoon = adsVerified &&
        adsDaysLeft != null &&
        adsDaysLeft >= 0 &&
        adsDaysLeft <= _adsReminderDays;

    final adsHistoryCount = _adsHistoryCount(data);
    final deactivationHistoryCount = _deactivationHistoryCount(data);

    // Audit trail info shown on the card when deactivated.
    final deactivatedByName =
        data['deactivatedByName']?.toString() ?? '';
    final deactivatedByRole =
        data['deactivatedByRole']?.toString() ?? '';
    final deactivationReason =
        data['deactivationReason']?.toString() ?? '';

    return Card(
      color: _card,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: deactivated
              ? Colors.red.withValues(alpha: 0.5)
              : _border,
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
                CircleAvatar(
                  radius: 22,
                  backgroundColor: deactivated
                      ? Colors.grey
                      : verified
                      ? _brand
                      : _border,
                  child: Icon(
                    Icons.person,
                    size: 24,
                    color: verified && !deactivated
                        ? Colors.white
                        : _mutedText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _bodyText,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _mutedText,
                            fontSize: 13,
                          ),
                        ),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          style: TextStyle(
                            color: _mutedText,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isBusy && _busyOwnerId == doc.id)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _statusChip(
                  deactivated
                      ? 'Deactivated'
                      : verified
                      ? 'Owner verified'
                      : 'Unverified',
                  deactivated
                      ? Colors.red
                      : verified
                      ? _brand
                      : Colors.orange,
                ),
                if (adsVerified) ...[
                  _statusChip(
                    adsStopText != null
                        ? 'Ads verified until $adsStopText'
                        : 'Ads verified',
                    _brand,
                  ),
                  // EXPIRY REMINDER — highlighted when the window
                  // ends within the reminder threshold.
                  if (adsDaysLeft != null)
                    _statusChip(
                      'Expires in $adsDaysLeft day(s)'
                          '${adsExpiringSoon ? ' — remind owner' : ''}',
                      adsExpiringSoon ? Colors.orange : _mutedText,
                    ),
                ] else if (adsExpired)
                  _statusChip('Ads expired', Colors.red)
                else
                  _statusChip('Ads not verified', _mutedText),

                // ADS HISTORY — how many periods are on record.
                if (adsHistoryCount > 0)
                  _statusChip(
                    'Ads history: $adsHistoryCount',
                    Colors.blue,
                  ),

                // DEACTIVATION HISTORY — permanent record count.
                if (deactivationHistoryCount > 0)
                  _statusChip(
                    'Deactivation history: $deactivationHistoryCount',
                    Colors.blue,
                  ),
              ],
            ),

            // Audit info — who + why.
            if (deactivated) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (deactivatedByName.isNotEmpty)
                      Text(
                        'Deactivated by: $deactivatedByName'
                            '${deactivatedByRole.isNotEmpty ? ' ($deactivatedByRole)' : ''}',
                        style: TextStyle(
                          color: _mutedText,
                          fontSize: 11.5,
                        ),
                      ),
                    if (deactivationReason.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Reason: $deactivationReason',
                        style: TextStyle(
                          color: _mutedText,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Row 1: View | Verify
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    label: 'View',
                    icon: Icons.visibility_outlined,
                    color: _brand,
                    onPressed: disabled
                        ? null
                        : () => _viewOwner(doc.id, data),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    label: verified ? 'Unverify' : 'Verify (KYC)',
                    icon: Icons.verified_outlined,
                    color: verified ? Colors.orange : _brand,
                    filled: true,
                    onPressed: disabled || deactivated
                        ? null
                        : () => verified
                        ? _unverifyOwner(doc.id, name)
                        : _verifyOwner(doc.id, name, data),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Row 2: Ads | Activate / Deactivate
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    label: adsVerified ? 'Ads Unverify' : 'Ads Verify',
                    icon: Icons.campaign_outlined,
                    color: adsVerified ? Colors.orange : Colors.blue,
                    onPressed: disabled || deactivated
                        ? null
                        : () => adsVerified
                        ? _revokeAdsVerification(doc.id, name)
                        : _grantAdsVerification(doc.id, name, data),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    label: deactivated ? 'Activate' : 'Deactivate',
                    icon: deactivated
                        ? Icons.check_circle_outline
                        : Icons.block,
                    color: Colors.orange,
                    onPressed: disabled
                        ? null
                        : () => _toggleDeactivation(
                      doc.id,
                      name,
                      deactivated,
                      data,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Row 3: Delete (full width, blocked for self)
            SizedBox(
              width: double.infinity,
              child: _actionButton(
                label: isSelf ? 'Delete (your account)' : 'Delete Account',
                icon: Icons.person_remove_outlined,
                color: Colors.red,
                onPressed: disabled || isSelf
                    ? null
                    : () => _deleteOwner(doc.id, name),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // PAGE BUILD
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffold,
      appBar: AppBar(
        title: const Text('Verify Property Owners'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('users')
            .where(
          'role',
          whereIn: ['owner', 'property_owner'],
        )
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error loading owners: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _bodyText),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: _brand),
            );
          }

          final allOwners = snapshot.data?.docs ?? [];
          final owners = _filterOwners(allOwners);

          return Column(
            children: [
              _searchAndDownloadBar(owners),
              _filterBar(allOwners),
              _adsExpiryReminderBanner(allOwners),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${owners.length} owner(s) found',
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: owners.isEmpty
                    ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No owners match your search or filter.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _mutedText),
                    ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: owners.length,
                  itemBuilder: (context, index) =>
                      _ownerCard(owners[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}