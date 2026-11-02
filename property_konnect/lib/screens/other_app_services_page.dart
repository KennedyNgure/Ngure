// ============================================================
// other_app_services_page.dart  (FULL UPDATED FILE)
//
// NEW / CHANGED in this version
//  1. COMRADE MARKETPLACE tab — admin can now review
//     comrade_marketplace posts too (title, campus, category,
//     condition, price, phone, seller name, imageUrls,
//     reportCount...).
//  2. SEARCH — now also covers phone, email / contact, owner
//     ID (userId / postedBy), seller name and verification
//     status ("verified" / "unverified" are searchable words).
//  3. FILTERING — new Verified / Unverified filter chips next
//     to the collection tabs.
//  4. CSV EXPORT — now includes Document ID, Posted By / Owner
//     ID, Posting date, Verification date, Ads Verified and
//     Moderation status (OK / Flagged with report count).
//  5. ADMIN AUTHORIZATION — the page checks that the signed-in
//     user is an admin before rendering actions. This is a
//     convenience check only: the real enforcement is Firestore
//     Security Rules (admin-only writes) plus Firebase
//     Authentication. A modified client cannot verify or
//     delete records even if it bypasses this screen.
//  6. ERROR STATE — the StreamBuilder distinguishes errors
//     from loading and shows a dedicated error message with a
//     RETRY button.
//  7. PAGINATION — posts are fetched 20 at a time with a
//     "Load more" footer, so the page no longer pulls entire
//     collections in one read. (At scale, move to
//     startAfterDocument cursors and server-side filtering —
//     see the backend notes at the bottom.)
//  8. STATE SAFEGUARDS —
//     - an in-flight guard set prevents duplicate Verify /
//       Unverify / Delete requests while one is running;
//     - before updating or deleting, the document is re-read
//       so already-changed or already-deleted posts produce a
//       clear message instead of a raw error;
//     - dialogs pop with `mounted` checks before snackbars.
//
// KNOWN LIMITATION (documented by design): search runs on the
// documents already loaded (the current page). With pagination
// the user may need "Load more" to reach older posts. Real
// server-side search belongs in a Cloud Function / Algolia —
// see the backend notes at the bottom of this file.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'details_dialog.dart';
import 'download_helper.dart';

/// Admin page for reviewing "other" community content:
///  - campus_communities
///  - student_services
///  - property_services
///  - comrade_marketplace
class OtherAppServicesPage extends StatefulWidget {
  const OtherAppServicesPage({super.key});

  @override
  State<OtherAppServicesPage> createState() => _OtherAppServicesPageState();
}

class _OtherAppServicesPageState extends State<OtherAppServicesPage> {
  String _filter = 'campus_communities';

  // Verification filter: all | verified | unverified.
  String _verificationFilter = 'all';

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  // PAGINATION — fetch in pages of 20; "Load more" grows limit.
  static const int _pageSize = 20;
  int _limit = _pageSize;

  // ERROR RETRY — bumping this rebuilds the stream.
  int _retryKey = 0;

  // IN-FLIGHT GUARD — doc ids with a verify/delete running.
  final Set<String> _busyDocIds = {};

  // ADMIN GUARD — checked once on open.
  late Future<Map<String, dynamic>?> _adminCheck;

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

  // ------------------------------------------------------------
  // ADMIN GUARD
  //
  // Convenience check only. The user's `users` doc must say
  // admin (role == 'admin' or isAdmin == true). Missing doc /
  // read failure → still render; the Firestore Security Rules
  // are the real enforcement on every write.
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
      return null; // cannot tell → let rules decide
    }
  }

  bool _isAdminData(Map<String, dynamic>? data) {
    if (data == null) return true;
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    if (role == 'admin') return true;
    if (data['isAdmin'] == true) return true;
    if (role.isNotEmpty) return false;
    if (data.containsKey('isAdmin') && data['isAdmin'] == false) {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _adminCheck = _fetchAdminUser();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _collectionName {
    switch (_filter) {
      case 'student_services':
        return 'student_services';
      case 'property_services':
      // FIX: services_page.dart posts into the
      // property_services collection, so the admin tab must
      // read the same one.
        return 'property_services';
      case 'comrade_marketplace':
        return 'comrade_marketplace';
      case 'campus_communities':
      default:
        return 'campus_communities';
    }
  }

  String get _filterLabel {
    switch (_filter) {
      case 'student_services':
        return _tr('Student Services', 'Huduma za Wanafunzi');
      case 'property_services':
        return _tr('Property Services', 'Huduma za Mali');
      case 'comrade_marketplace':
        return _tr('Comrade Marketplace', 'Soko la Makomarido');
      default:
        return _tr('Campus Communities', 'Jumuiya za Kampus');
    }
  }

  // ------------------------------------------------------------
  // FIELD EXTRACTION — works for all four collections,
  // including comrade_marketplace (area, condition, price,
  // phone, sellerName, reportCount...).
  // ------------------------------------------------------------

  String _titleOf(Map<String, dynamic> d) =>
      (d['title'] ?? d['name'] ?? 'Untitled').toString();

  String _subtitleOf(Map<String, dynamic> d) => (d['campus'] ??
      d['category'] ??
      d['type'] ??
      d['condition'] ??
      '')
      .toString();

  String _campusOf(Map<String, dynamic> d) =>
      (d['campus'] ?? d['area'] ?? d['location'] ?? '').toString();

  String _categoryOf(Map<String, dynamic> d) =>
      (d['category'] ?? d['condition'] ?? d['type'] ?? '').toString();

  String _ownerIdOf(Map<String, dynamic> d) =>
      (d['userId'] ?? d['postedBy'] ?? d['ownerId'] ?? '').toString();

  String _contactOf(Map<String, dynamic> d) =>
      (d['phone'] ?? d['contact'] ?? d['email'] ?? '').toString();

  bool _adsVerifiedOf(Map<String, dynamic> d) => d['adsVerified'] == true;

  int _reportCountOf(Map<String, dynamic> d) {
    final raw = d['reportCount'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  DateTime? _postedAtOf(Map<String, dynamic> d) {
    final raw = d['createdAt'] ?? d['postedAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  DateTime? _adsVerifiedAtOf(Map<String, dynamic> d) {
    final raw = d['adsVerifiedAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
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
  // ADS VERIFY / UNVERIFY — with in-flight guard and
  // already-changed / already-deleted detection.
  // ------------------------------------------------------------

  Future<void> _toggleAdsVerified(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    // Prevent duplicate concurrent requests.
    if (_busyDocIds.contains(doc.id)) return;
    _busyDocIds.add(doc.id);

    try {
      final data = doc.data();
      final currentlyVerified = _adsVerifiedOf(data);
      final title = _titleOf(data);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          icon: Icon(
            currentlyVerified
                ? Icons.verified_user
                : Icons.verified_outlined,
            color: _green,
            size: 34,
          ),
          title: Text(
            currentlyVerified
                ? _tr('Un-verify this ad?', 'Ondoa uthibitisho?')
                : _tr('Ads Verify this post?',
                'Thibitisha chapisho hiki?'),
          ),
          content: Text(
            currentlyVerified
                ? _tr(
              '"$title" will no longer show as Ads Verified and '
                  'will lose its top position.',
              '"$title" haitaonyeshwa kama imethibitishwa na '
                  'hatapotea nafasi yake ya juu.',
            )
                : _tr(
              '"$title" will show a green "Ads Verified" badge and '
                  'will always appear FIRST to all users.',
              '"$title" itaonyesha alama ya kijani ya '
                  '"Imethibitishwa" na daima itaonekana MWANZO kwa '
                  'watumiaji wote.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_tr('Cancel', 'Ghairi')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                currentlyVerified
                    ? _tr('Unverify', 'Ondoa')
                    : _tr('Ads Verify', 'Thibitisha'),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Re-read: catch already-deleted or already-changed docs.
      final fresh = await doc.reference.get();
      if (!fresh.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_tr(
                  'This post was already deleted.',
                  'Chapisho hiki kimefutwa tayari.')),
            ),
          );
        }
        return;
      }

      final freshVerified = _adsVerifiedOf(fresh.data() ?? {});
      if (freshVerified != currentlyVerified) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_tr(
                  'This post was already updated by another admin.',
                  'Chapisho hiki kimesasishwa na msimamizi mwingine '
                      'tayari.')),
            ),
          );
        }
        return;
      }

      await doc.reference.update({
        'adsVerified': !currentlyVerified,
        'adsVerifiedAt': FieldValue.serverTimestamp(),
      });

      // Best-effort audit entry (never blocks the action).
      await _logAdminAction(
        action: currentlyVerified
            ? 'unverify_ads_${_collectionName}'
            : 'verify_ads_${_collectionName}',
        ownerId: _ownerIdOf(fresh.data() ?? {}),
        ownerName: _titleOf(fresh.data() ?? {}),
        details:
        'Ads verification ${currentlyVerified ? 'removed from' : 'granted to'} '
            '"$title" (${doc.id}) in $_collectionName.',
        newStatus: currentlyVerified ? 'not ads verified' : 'ads verified',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _green,
          content: Text(
            currentlyVerified
                ? _tr('Ads verification removed.',
                'Uthibitisho wa tangazo umefutwa.')
                : _tr('Post is now Ads Verified.',
                'Chapisho sasa kimethibitishwa.'),
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      if (e.code == 'not-found' || e.code == 'permission-denied') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(_tr(
                'This post no longer exists or you lack permission.',
                'Chapisho hiki hakipo tena au huna ruhusa.')),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              '${_tr('Failed to update: ', 'Imeshindikana kusasisha: ')}$e'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              '${_tr('Failed to update: ', 'Imeshindikana kusasisha: ')}$e'),
        ),
      );
    } finally {
      _busyDocIds.remove(doc.id);
    }
  }

  // ------------------------------------------------------------
  // VIEW
  // ------------------------------------------------------------

  void _viewService(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    showDetailsDialog(
      context: context,
      title: _titleOf(data),
      data: {'id': doc.id, ...data},
      downloadFileNamePrefix:
      '${_collectionName}_${_titleOf(data).replaceAll(RegExp(r'\s+'), '_')}',
      hiddenFields: const {'id'},
    );
  }

  // ------------------------------------------------------------
  // REMOVE — with in-flight guard, image cleanup (best-effort),
  // audit entry (best-effort) and already-deleted detection.
  // ------------------------------------------------------------

  Future<void> _removeService(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    // Prevent duplicate concurrent requests.
    if (_busyDocIds.contains(doc.id)) return;
    _busyDocIds.add(doc.id);

    try {
      final data = doc.data();
      final title = _titleOf(data);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          icon: const Icon(Icons.delete_forever,
              color: Colors.red, size: 34),
          title: Text(_tr('Delete this post?', 'Kufuta chapisho hiki?')),
          content: Text(
            _tr(
              'Are you sure you want to delete "$title"? '
                  'This action cannot be undone.',
              'Una uhakika unataka kufuta "$title"? '
                  'Hatua hii haiwezi kurudishwa.',
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

      // Re-read: catch already-deleted docs.
      final fresh = await doc.reference.get();
      if (!fresh.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_tr('This post was already deleted.',
                  'Chapisho hiki kimefutwa tayari.')),
            ),
          );
        }
        return;
      }

      // Best-effort image cleanup (comrade_marketplace posts
      // store imageUrls; other collections may store images).
      await _deleteImages(data);

      // Best-effort audit entry BEFORE the delete.
      await _logAdminAction(
        action: 'delete_${_collectionName}_post',
        ownerId: _ownerIdOf(data),
        ownerName: (data['sellerName'] ?? data['postedBy'] ?? title)
            .toString(),
        reason: 'Removed by admin from Other Services',
        details:
        'Post "$title" (${doc.id}) permanently deleted from '
            '$_collectionName.',
        previousStatus: (data['status'] ?? '').toString(),
      );

      await doc.reference.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _green,
          content: Text(_tr('Post deleted.', 'Chapisho kimefutwa.')),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      if (e.code == 'not-found') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr('This post was already deleted.',
                'Chapisho hiki kimefutwa tayari.')),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              '${_tr('Failed to delete: ', 'Imeshindikana kufuta: ')}$e'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              '${_tr('Failed to delete: ', 'Imeshindikana kufuta: ')}$e'),
        ),
      );
    } finally {
      _busyDocIds.remove(doc.id);
    }
  }

  /// Deletes every image URL stored on the post from Firebase
  /// Storage. Never throws — cleanup is best-effort.
  Future<void> _deleteImages(Map<String, dynamic> data) async {
    final urls = <String>[];

    for (final key in ['imageUrls', 'images', 'image_urls', 'photos']) {
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
        // Missing file or no permission — skip.
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
  // DOWNLOAD — CSV now includes Document ID, Owner ID,
  // Posting date, Verification date, Ads Verified and
  // Moderation status.
  // ------------------------------------------------------------

  Future<void> _downloadList(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
          Text(_tr('Nothing to download.', 'Hakuna cha kupakua.')),
        ),
      );
      return;
    }

    await DownloadHelper.downloadCsv(
      context: context,
      fileNamePrefix: _collectionName,
      headers: [
        'Document ID',
        'Title',
        'Campus / Area',
        'Category / Condition',
        'Location',
        'Price',
        'Contact',
        'Owner / Seller ID',
        'Posted By',
        'Posting Date',
        'Ads Verified',
        'Verification Date',
        'Moderation Status',
        'Status',
      ],
      rows: docs.map((doc) {
        final d = doc.data();
        final postedAt = _postedAtOf(d);
        final verifiedAt = _adsVerifiedAtOf(d);
        final reports = _reportCountOf(d);

        return [
          doc.id,
          d['title'] ?? d['name'],
          d['campus'] ?? d['area'],
          d['category'] ?? d['condition'] ?? d['type'],
          d['location'] ?? d['meetingPlace'],
          d['price'],
          d['phone'] ?? d['contact'] ?? d['email'],
          (d['userId'] ?? d['postedBy'] ?? d['ownerId'] ?? '').toString(),
          d['postedBy'] ?? d['sellerName'] ?? d['userId'],
          postedAt != null ? _formatDate(postedAt) : '',
          _adsVerifiedOf(d) ? 'YES' : 'NO',
          verifiedAt != null ? _formatDate(verifiedAt) : '',
          reports > 0 ? 'FLAGGED ($reports reports)' : 'OK',
          d['status'] ?? '',
        ];
      }).toList(),
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _adminCheck,
      builder: (context, adminSnap) {
        // Only block when we positively know the user is NOT an
        // admin. Missing data → rules still enforce everything.
        if (adminSnap.hasData && !_isAdminData(adminSnap.data)) {
          return Scaffold(
            backgroundColor: _pageBackground,
            appBar: AppBar(
              title: Text(_tr('Other Services', 'Huduma Nyingine')),
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
            title: Text(_tr('Other Services', 'Huduma Nyingine')),
            backgroundColor: _green,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(_collectionName)
                    .limit(_limit)
                    .snapshots(),
                builder: (context, snapshot) {
                  return IconButton(
                    tooltip: _tr('Download list', 'Pakua orodha'),
                    icon: const Icon(Icons.download),
                    onPressed: snapshot.hasData
                        ? () => _downloadList(
                        _filtered(snapshot.data!.docs))
                        : null,
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // ---------------- SEARCH ----------------
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _query = value.trim()),
                  decoration: InputDecoration(
                    hintText: _tr(
                        'Search by name, campus, phone, seller, '
                            'verified...',
                        'Tafuta kwa jina, kampus, simu, muuzaji, '
                            'imethibitishwa...'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
                    filled: true,
                    fillColor: _cardColor,
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 0),
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
                      borderSide:
                      BorderSide(color: _green, width: 1.5),
                    ),
                  ),
                ),
              ),

              // ---------------- COLLECTION CHIPS ----------------
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip('campus_communities',
                        _tr('Campus Communities', 'Jumuiya za Kampus')),
                    _chip('student_services',
                        _tr('Student Services', 'Huduma za Wanafunzi')),
                    _chip('property_services',
                        _tr('Property Services', 'Huduma za Mali')),
                    _chip('comrade_marketplace',
                        _tr('Comrade Marketplace', 'Soko la Wanafunzi')),
                  ],
                ),
              ),

              // ---------------- VERIFIED / UNVERIFIED FILTERS ---
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _verificationChip('all', _tr('All', 'Zote')),
                    _verificationChip(
                        'verified', _tr('Ads Verified', 'Imethibitishwa')),
                    _verificationChip(
                        'unverified', _tr('Not Verified', 'Hajathibitishwa')),
                    _verificationChip(
                        'flagged', _tr('Flagged', 'Zinazoripotiwa')),
                  ],
                ),
              ),

              // ---------------- LIST ----------------
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  // Paginated stream: only the first `_limit`
                  // documents; "Load more" grows it.
                  stream: FirebaseFirestore.instance
                      .collection(_collectionName)
                      .limit(_limit)
                      .snapshots(),
                  builder: (context, snapshot) {
                    // ERROR STATE — dedicated screen with retry.
                    if (snapshot.hasError) {
                      return _buildErrorState();
                    }

                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(color: _green),
                      );
                    }

                    final docs = _filtered(snapshot.data!.docs);

                    // If the page came back full there may be
                    // more documents beyond the current limit.
                    final mayHaveMore =
                        snapshot.data!.docs.length >= _limit;

                    if (docs.isEmpty && !mayHaveMore) {
                      return Center(
                        child: Text(
                          _tr('No posts found.', 'Hakuna machapisho.'),
                          style: TextStyle(
                              color: _mutedText, fontSize: 15),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                      itemCount: docs.length + (mayHaveMore ? 1 : 0),
                      separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        // "Load more" footer.
                        if (i == docs.length) {
                          return Padding(
                            padding:
                            const EdgeInsets.only(top: 6, bottom: 10),
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
                                  'Load more posts', 'Pakua machapisho zaidi')),
                            ),
                          );
                        }

                        return _serviceCard(docs[i]);
                      },
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

  Widget _buildErrorState() {
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
              _tr('Could not load posts', 'Machapisho hayakupatikana'),
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
  // FILTERING — collection, verification and search.
  //
  // NOTE: search runs on the loaded page only. Once the
  // collections grow, move filtering server-side (see header).
  // ------------------------------------------------------------

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtered(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    var result = docs;

    // 1. Verification / moderation filter.
    if (_verificationFilter != 'all') {
      result = result.where((doc) {
        final d = doc.data();
        final verified = _adsVerifiedOf(d);
        switch (_verificationFilter) {
          case 'verified':
            return verified;
          case 'unverified':
            return !verified;
          case 'flagged':
            return _reportCountOf(d) > 0;
          default:
            return true;
        }
      }).toList();
    }

    // 2. Search — now includes phone, contact / email, owner
    //    ID, seller name and the verification status itself.
    final query = _query.toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((doc) {
        final d = doc.data();
        final haystack = [
          doc.id,
          d['name'],
          d['title'],
          d['campus'],
          d['area'],
          d['category'],
          d['condition'],
          d['type'],
          d['location'],
          d['meetingPlace'],
          d['description'],
          d['phone'],
          d['contact'],
          d['email'],
          d['postedBy'],
          d['sellerName'],
          d['userId'],
          d['ownerId'],
          // Verification status is searchable too: "verified"
          // finds ads-verified posts.
          _adsVerifiedOf(d)
              ? 'verified ads verified imethibitishwa'
              : 'unverified hajathibitishwa',
        ].join(' ').toLowerCase();
        return haystack.contains(query);
      }).toList();
    }

    // 3. Ads-verified posts first.
    final verified =
    result.where((doc) => _adsVerifiedOf(doc.data())).toList();
    final unverified =
    result.where((doc) => !_adsVerifiedOf(doc.data())).toList();

    return [...verified, ...unverified];
  }

  Widget _chip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
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
        onSelected: (_) => setState(() {
          _filter = value;
          _query = '';
          _searchController.clear();
          _limit = _pageSize; // reset pagination for the new tab
        }),
      ),
    );
  }

  Widget _verificationChip(String value, String label) {
    final selected = _verificationFilter == value;
    final color = switch (value) {
      'verified' => _green,
      'unverified' =>
      _isDark ? Colors.orange.shade300 : Colors.orange.shade800,
      'flagged' => _isDark ? Colors.red.shade300 : Colors.red.shade700,
      _ => _green,
    };

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: color,
        backgroundColor: _cardColor,
        side: BorderSide(color: selected ? color : _cardBorder),
        labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        onSelected: (_) => setState(() {
          _verificationFilter = value;
        }),
      ),
    );
  }

  Widget _verifiedBadge({bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _green.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: compact ? 12 : 13, color: _green),
          const SizedBox(width: 4),
          Text(
            _tr('Ads Verified', 'Imethibitishwa'),
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: _green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final adsVerified = _adsVerifiedOf(data);
    final reports = _reportCountOf(data);
    final isMarketplace = _filter == 'comrade_marketplace';
    final busy = _busyDocIds.contains(doc.id);

    final price = data['price'];
    final String? priceText = price == null
        ? null
        : 'KES ${price.toString()}'
        + (isMarketplace ? '' : '');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: adsVerified
              ? _green.withValues(alpha: 0.55)
              : _cardBorder,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMarketplace
                      ? Icons.storefront_outlined
                      : Icons.miscellaneous_services_outlined,
                  color: _green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleOf(data),
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
                      [
                        _subtitleOf(data),
                        if (priceText != null) priceText,
                      ]
                          .where((line) => line.trim().isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                      TextStyle(fontSize: 12.5, color: _mutedText),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _campusOf(data),
                        _contactOf(data),
                      ]
                          .where((line) => line.trim().isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                      TextStyle(fontSize: 11.5, color: _mutedText),
                    ),
                  ],
                ),
              ),
              if (adsVerified) ...[
                const SizedBox(width: 8),
                _verifiedBadge(compact: true),
              ],
            ],
          ),

          // Flagged posts show their report count.
          if (reports > 0) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _tr('Flagged — $reports report(s)',
                      'Imeripotiwa — ripoti $reports'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _isDark
                        ? Colors.red.shade300
                        : Colors.red.shade700,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // ---- ADS VERIFY row (disabled while busy) ----
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
              onPressed: busy ? null : () => _toggleAdsVerified(doc),
              icon: Icon(
                adsVerified ? Icons.verified : Icons.verified_outlined,
                size: 15,
              ),
              label: Text(
                adsVerified
                    ? _tr('Verified ✓ (tap to unverify)',
                    'Imethibitishwa ✓ (bonyeza kutoa)')
                    : _tr('Ads Verify', 'Thibitisha Tangazo'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ---- View / Remove row (disabled while busy) ----
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: BorderSide(color: _green),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _viewService(doc),
                  icon: const Icon(Icons.visibility, size: 15),
                  label: Text(
                    _tr('View', 'Angalia'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: busy ? null : () => _removeService(doc),
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: Text(
                    _tr('Remove', 'Ondoa'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BACKEND RECOMMENDATIONS (not this file)
//
//  1. ADMIN AUTHORIZATION — enforce admin-only writes on
//     campus_communities, student_services, property_services,
//     comrade_marketplace and admin_audit_logs in the Firestore
//     Security Rules (already the case in your rules). For
//     stronger identity, mint an `admin` custom claim via the
//     Firebase Admin SDK and check `request.auth.token.admin`
//     in the rules instead of reading the users doc.
//  2. AT SCALE — replace the growing-limit pagination with
//     startAfterDocument cursors and server-side where() filters,
//     or move search to a Cloud Function / Algolia so records
//     beyond the loaded page are findable.
//  3. DELETION — full cleanup of a deleted post (favourites,
//     reports, chat references) should ultimately be owned by a
//     Cloud Function; the image cleanup here is best-effort.
// ============================================================