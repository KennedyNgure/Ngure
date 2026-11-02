// ============================================================
// manage_tenant_reviews_page.dart  (FULL UPDATED FILE)
//
// NEW / CHANGED in this version
//  1. SEARCH — now also covers Property ID, Reviewer ID, the
//     review's status (visible / hidden) and the administrator
//     who moderated it (hiddenByName / unhiddenByName), plus
//     the hide reason.
//  2. HIDE REASON — hiding a review now requires a REASON
//     (text field in the hide dialog). The reason, the admin who
//     hid it and the date are stored on the review and shown in
//     the details dialog. Showing a review keeps the previous
//     hide reason in the moderation record.
//  3. PAGINATION — reviews are fetched 20 at a time with a
//     "Load more" footer instead of streaming the whole
//     collection. (Cursor-based startAfterDocument queries are
//     the next step at scale — see the notes at the bottom.)
//  4. PROPERTY NAVIGATION — an "Open Property" button loads the
//     reviewed property and opens its full details page (admin
//     view), making complaint investigation one tap.
//  5. DELETION — permanent deletion now needs a SECOND
//     confirmation ("Yes, delete forever"), and both dialogs
//     explicitly say hiding is reversible, deleting is not.
//  6. RESPONSIVE LAYOUT — on wide screens (tablets / desktop,
//     width > 700) each card switches to a horizontal layout:
//     reviewer column | comment | action column. Phones keep
//     the compact vertical layout.
//  7. ADMIN AUTHORIZATION — the page checks that the signed-in
//     user is an admin before rendering any actions
//     (convenience check). The real enforcement stays in the
//     Firestore Security Rules: non-admins cannot write
//     `reviews` no matter what a modified client does.
//  8. ERROR HANDLING — permission-denied, network failures and
//     "already deleted by another admin" each produce their
//     own clear message; documents are re-read before every
//     update / delete to detect concurrent changes.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_settings.dart';
import 'property_details_page.dart';

enum ReviewFilter {
  all,
  visible,
  hidden,
  lowRating,
}

/// ADMIN — MANAGE REVIEWS
///
/// Reads the Firestore collection `reviews` (live, paginated)
/// and lets the admin:
///   • search by reviewer, property, comment, IDs, status or
///     moderating admin
///   • filter: All / Visible / Hidden / Low rating (1-2 stars)
///   • view the full review (incl. moderation record)
///   • OPEN the reviewed property's details page
///   • HIDE a review with a required reason, and SHOW it again
///     — stamped with who did it and when
///   • DELETE a review permanently (double confirmation)
///
/// Expected review fields (all optional / tolerant):
///   userId, userName | reviewerName | name,
///   propertyId, propertyTitle | propertyName,
///   rating (number 1-5), comment | review | text,
///   createdAt (Timestamp), isHidden (bool), status ('hidden'),
///   hiddenAt / hiddenBy / hiddenByName / hideReason,
///   unhiddenAt / unhiddenBy / unhiddenByName
///
/// English only. Theme comes from AppSettings like the homepage.
class ManageTenantReviewsPage extends StatefulWidget {
  const ManageTenantReviewsPage({super.key});

  @override
  State<ManageTenantReviewsPage> createState() => _ManageReviewsPageState();
}

class _ManageReviewsPageState extends State<ManageTenantReviewsPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isBusy = false;
  String? _busyReviewId;
  ReviewFilter _selectedFilter = ReviewFilter.all;
  String _searchQuery = '';

  // PAGINATION — fetch in pages of 20; "Load more" grows limit.
  static const int _pageSize = 20;
  int _limit = _pageSize;

  // ADMIN GUARD — checked once on open.
  late Future<Map<String, dynamic>?> _adminCheck;

  // ----------------------------------------------------------
  // THEME — from AppSettings
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

  // ----------------------------------------------------------
  // ADMIN GUARD
  //
  // Convenience check only. Missing users doc / read failure →
  // still render the page; the Firestore Security Rules are the
  // real enforcement on every review write.
  // ----------------------------------------------------------

  Future<Map<String, dynamic>?> _fetchAdminUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return null;

    try {
      final snap = await _db
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

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ----------------------------------------------------------
  // ERROR HANDLING — friendly messages per failure type.
  // ----------------------------------------------------------

  void _showActionError(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          _showSnack('You do not have admin permission for this action. '
              'Ask a super admin to check your account.');
          return;
        case 'unavailable':
        case 'network-request-failed':
          _showSnack('Network error — check your connection and try again.');
          return;
        case 'not-found':
        case 'cancelled':
          _showSnack('This review was already deleted by another admin. '
              'The list will update automatically.');
          return;
      }
    }
    _showSnack('Operation failed: $e');
  }

  /// Re-reads the review to detect "already deleted / changed by
  /// another admin" BEFORE updating. Returns false if the action
  /// should be aborted (message already shown).
  Future<bool> _reviewStillExists(
      String reviewId,
      Map<String, dynamic> data,
      ) async {
    final fresh = await _db.collection('reviews').doc(reviewId).get();

    if (!fresh.exists) {
      _showSnack('This review was already deleted by another admin.');
      return false;
    }

    final freshHidden = _isHidden(fresh.data() ?? {});
    if (freshHidden != _isHidden(data)) {
      _showSnack('This review was already moderated by another admin.');
      return false;
    }

    return true;
  }

  // ----------------------------------------------------------
  // FIELD HELPERS
  // ----------------------------------------------------------

  String _reviewerName(Map<String, dynamic> d) =>
      (d['userName'] ?? d['reviewerName'] ?? d['name'] ?? 'Anonymous')
          .toString();

  String _propertyTitle(Map<String, dynamic> d) =>
      (d['propertyTitle'] ?? d['propertyName'] ?? 'Unknown property')
          .toString();

  String _comment(Map<String, dynamic> d) =>
      (d['comment'] ?? d['review'] ?? d['text'] ?? '').toString();

  String _propertyIdOf(Map<String, dynamic> d) =>
      (d['propertyId'] ?? '').toString();

  String _hideReasonOf(Map<String, dynamic> d) =>
      (d['hideReason'] ?? d['hiddenReason'] ?? '').toString();

  double _rating(Map<String, dynamic> d) {
    final value = d['rating'];
    if (value is num) return value.toDouble().clamp(0, 5).toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _createdAt(Map<String, dynamic> d) {
    final value = d['createdAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  bool _isHidden(Map<String, dynamic> d) =>
      d['isHidden'] == true ||
          d['status']?.toString().toLowerCase() == 'hidden';

  bool _isLow(Map<String, dynamic> d) => _rating(d) > 0 && _rating(d) <= 2;

  String _dateText(DateTime? date) =>
      date == null ? '—' : DateFormat.yMMMd().add_jm().format(date);

  // ----------------------------------------------------------
  // SEARCH + FILTER
  // ----------------------------------------------------------

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterReviews(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> reviews,
      ) {
    final query = _searchQuery.trim().toLowerCase();

    return reviews.where((doc) {
      final d = doc.data();

      final matchesFilter = switch (_selectedFilter) {
        ReviewFilter.all => true,
        ReviewFilter.visible => !_isHidden(d),
        ReviewFilter.hidden => _isHidden(d),
        ReviewFilter.lowRating => _isLow(d),
      };

      if (!matchesFilter) return false;
      if (query.isEmpty) return true;

      // Search now covers Property ID, Reviewer ID, the review
      // status and the moderating admin, plus the hide reason.
      final searchable = [
        doc.id,
        _reviewerName(d),
        _propertyTitle(d),
        _comment(d),
        _propertyIdOf(d),
        d['userId'],
        _isHidden(d) ? 'hidden' : 'visible',
        d['hiddenByName'],
        d['unhiddenByName'],
        _hideReasonOf(d),
      ];

      return searchable.any(
            (v) => v != null && v.toString().toLowerCase().contains(query),
      );
    }).toList();
  }

  String _filterLabel(ReviewFilter filter) {
    switch (filter) {
      case ReviewFilter.all:
        return 'All';
      case ReviewFilter.visible:
        return 'Visible';
      case ReviewFilter.hidden:
        return 'Hidden';
      case ReviewFilter.lowRating:
        return 'Low rating';
    }
  }

  int _filterCount(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> reviews,
      ReviewFilter filter,
      ) {
    return reviews.where((doc) {
      final d = doc.data();
      switch (filter) {
        case ReviewFilter.all:
          return true;
        case ReviewFilter.visible:
          return !_isHidden(d);
        case ReviewFilter.hidden:
          return _isHidden(d);
        case ReviewFilter.lowRating:
          return _isLow(d);
      }
    }).length;
  }

  // ----------------------------------------------------------
  // ACTION HANDLER
  // ----------------------------------------------------------

  Future<void> _runAction(
      String reviewId,
      Future<void> Function() action,
      ) async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _busyReviewId = reviewId;
    });

    try {
      await action();
    } catch (e) {
      _showActionError(e);
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyReviewId = null;
        });
      }
    }
  }

  Future<({String uid, String name})> _currentAdminInfo() async {
    final user = FirebaseAuth.instance.currentUser;

    final uid = user?.uid ?? 'unknown-admin';
    var name = user?.email ?? 'Admin';

    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();

      name = (data?['fullName'] ??
          data?['name'] ??
          data?['displayName'] ??
          user?.email ??
          'Admin')
          .toString();
    } catch (e) {
      debugPrint('ADMIN INFO LOAD ERROR: $e');
    }

    return (uid: uid, name: name);
  }

  // ----------------------------------------------------------
  // HIDE (with required reason) / SHOW
  // ----------------------------------------------------------

  Future<void> _toggleHidden(
      String reviewId,
      Map<String, dynamic> data,
      ) async {
    final hidden = _isHidden(data);

    if (hidden) {
      // ---- SHOW — reversible, no reason needed ----
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: Icon(
            Icons.visibility_outlined,
            color: _brand,
            size: 42,
          ),
          title: Text(
            'Show this review?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _bodyText,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          content: Text(
            'The review will be visible to tenants again. This is '
                'fully reversible.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _bodyText, height: 1.4),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                  minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(110, 44),
                backgroundColor: _brand,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Show'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      await _runAction(reviewId, () async {
        if (!await _reviewStillExists(reviewId, data)) return;

        final admin = await _currentAdminInfo();

        await _db.collection('reviews').doc(reviewId).update({
          'isHidden': false,
          'status': 'visible',
          'unhiddenBy': admin.uid,
          'unhiddenByName': admin.name,
          'unhiddenAt': FieldValue.serverTimestamp(),
        });

        _showSnack('Review is now visible.');
      });
      return;
    }

    // ---- HIDE — reason REQUIRED for accountability ----
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: Icon(
          Icons.visibility_off_outlined,
          color: Colors.orange,
          size: 42,
        ),
        title: Text(
          'Hide this review?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _bodyText,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The review will no longer be shown to tenants. It is '
                  'KEPT in the database and can be shown again at any '
                  'time — hiding is reversible.',
              style: TextStyle(color: _bodyText, height: 1.4),
            ),
            const SizedBox(height: 14),
            Text(
              'Reason (required)',
              style: TextStyle(
                color: _brand,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: reasonController,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                hintText: 'e.g. Off-topic, offensive language, '
                    'suspected fake review...',
                filled: true,
                fillColor: _scaffold,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _border),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(110, 44),
              backgroundColor: Colors.orange,
            ),
            onPressed: () {
              // Reason is mandatory — no empty hides.
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a reason for hiding '
                        'this review.'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Hide'),
          ),
        ],
      ),
    );

    final reason = reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true || reason.isEmpty) return;

    await _runAction(reviewId, () async {
      if (!await _reviewStillExists(reviewId, data)) return;

      final admin = await _currentAdminInfo();

      await _db.collection('reviews').doc(reviewId).update({
        'isHidden': true,
        'status': 'hidden',
        'hideReason': reason,
        'hiddenAt': FieldValue.serverTimestamp(),
        'hiddenBy': admin.uid,
        'hiddenByName': admin.name,
        'hiddenByRole': 'admin',
      });

      _showSnack('Review has been hidden.');
    });
  }

  // ----------------------------------------------------------
  // DELETE — DOUBLE confirmation, hides suggested first.
  // ----------------------------------------------------------

  Future<void> _deleteReview(
      String reviewId,
      Map<String, dynamic> data,
      ) async {
    // ---- First confirmation ----
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: Icon(Icons.delete_outline, color: _errColor, size: 42),
        title: Text(
          'Delete this review?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _errColor,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: Text(
          'The review by ${_reviewerName(data)} will be PERMANENTLY '
              'deleted. This action cannot be undone.\n\n'
              'If you only want to remove it from tenants, use Hide '
              'instead — hiding is reversible, deleting is not.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _bodyText, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(88, 46)),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(110, 46),
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (firstConfirm != true) return;

    // ---- Second (final) confirmation ----
    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: Icon(Icons.warning_amber_rounded,
            color: _errColor, size: 42),
        title: Text(
          'Are you absolutely sure?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _errColor,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: Text(
          'This is the LAST step. The review by '
              '${_reviewerName(data)} will be gone forever and cannot '
              'be recovered.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _bodyText, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(88, 46)),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(110, 46),
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, delete forever'),
          ),
        ],
      ),
    );

    if (finalConfirm != true) return;

    await _runAction(reviewId, () async {
      if (!await _reviewStillExists(reviewId, data)) return;

      final admin = await _currentAdminInfo();

      // Best-effort audit entry BEFORE the delete.
      try {
        await _db.collection('admin_audit_logs').add({
          'ownerId': _propertyIdOf(data),
          'ownerName': _propertyTitle(data),
          'action': 'delete_review',
          'reason': 'Review permanently deleted by admin',
          'details': 'Review ${_reviewerName(data)} ("${_comment(data)}") '
              'on ${_propertyTitle(data)} deleted ($reviewId).',
          'previousStatus': _isHidden(data) ? 'hidden' : 'visible',
          'newStatus': 'deleted',
          'performedBy': admin.uid,
          'performedByName': admin.name,
          'performedByRole': 'admin',
          'performedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Best-effort audit log — never block the main action.
      }

      await _db.collection('reviews').doc(reviewId).delete();
      _showSnack('Review has been deleted.');
    });
  }

  // ----------------------------------------------------------
  // OPEN PROPERTY — loads the reviewed property and opens its
  // details page (admin view) so complaints are one tap away.
  // ----------------------------------------------------------

  Future<void> _openProperty(Map<String, dynamic> data) async {
    final propertyId = _propertyIdOf(data);

    if (propertyId.isEmpty) {
      _showSnack('This review does not reference a property ID.');
      return;
    }

    setState(() {
      _isBusy = true;
      _busyReviewId = propertyId;
    });

    try {
      final snap = await _db.collection('properties').doc(propertyId).get();

      if (!mounted) return;

      if (!snap.exists) {
        _showSnack('The property "$propertyId" no longer exists — it may '
            'have been deleted.');
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PropertyDetailsPage(
            property: {'id': propertyId, ...snap.data()!},
            isAdminView: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showActionError(e);
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyReviewId = null;
        });
      }
    }
  }

  // ----------------------------------------------------------
  // VIEW
  // ----------------------------------------------------------

  Future<void> _viewReview(
      String reviewId,
      Map<String, dynamic> data,
      ) async {
    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _brand,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 3),
            SelectableText(
              value.isEmpty ? '—' : value,
              style: TextStyle(color: _bodyText, fontSize: 14, height: 1.4),
            ),
            Divider(color: _border),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        insetPadding: const EdgeInsets.all(12),
        title: Text(
          'Review details',
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
                row('Reviewer', _reviewerName(data)),
                row('Property', _propertyTitle(data)),
                row('Rating', '${_rating(data).toStringAsFixed(1)} / 5'),
                row('Comment', _comment(data)),
                row('Date', _dateText(_createdAt(data))),
                row('Status', _isHidden(data) ? 'Hidden' : 'Visible'),
                if (_isHidden(data)) ...[
                  row('Hidden by', data['hiddenByName']?.toString() ?? ''),
                  row('Hidden at', _dateText(
                      data['hiddenAt'] is Timestamp
                          ? (data['hiddenAt'] as Timestamp).toDate()
                          : null)),
                  row('Hide reason', _hideReasonOf(data)),
                ],
                if (!_isHidden(data) &&
                    (data['unhiddenByName']?.toString().isNotEmpty ??
                        false)) ...[
                  row('Last shown by', data['unhiddenByName'].toString()),
                ],
                row('Review ID', reviewId),
                row('Reviewer ID', data['userId']?.toString() ?? ''),
                row('Property ID', _propertyIdOf(data)),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          // Investigate directly from the details dialog.
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _brand,
              side: BorderSide(color: _brand.withValues(alpha: 0.8)),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _openProperty(data);
            },
            icon: const Icon(Icons.home_work_outlined, size: 18),
            label: const Text('Open Property'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(100, 46),
              backgroundColor: _brand,
            ),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // WIDGETS
  // ----------------------------------------------------------

  Widget _stars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating > i && rating < i + 1;

        return Icon(
          filled
              ? Icons.star_rounded
              : half
              ? Icons.star_half_rounded
              : Icons.star_outline_rounded,
          size: 18,
          color: Colors.amber.shade600,
        );
      }),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
        side: BorderSide(
          color: onPressed == null ? _border : color.withValues(alpha: 0.8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: SizedBox(
        height: 48,
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          style: TextStyle(color: _bodyText, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search reviewer, property, comment, ID, '
                'status, admin...',
            hintStyle: TextStyle(color: _mutedText, fontSize: 12),
            prefixIcon: Icon(Icons.search, color: _mutedText, size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
              tooltip: 'Clear search',
              constraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              icon: Icon(Icons.close, size: 20, color: _mutedText),
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
    );
  }

  Widget _filterBar(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> reviews,
      ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ReviewFilter.values.map((filter) {
            final selected = _selectedFilter == filter;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  '${_filterLabel(filter)} '
                      '(${_filterCount(reviews, filter)})',
                  style: const TextStyle(fontSize: 13),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                selected: selected,
                selectedColor: _brand.withValues(alpha: 0.18),
                backgroundColor: _card,
                side: BorderSide(color: selected ? _brand : _border),
                labelStyle: TextStyle(
                  color: selected ? _brand : _bodyText,
                  fontWeight: selected
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                onSelected: (_) => setState(() => _selectedFilter = filter),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // REVIEW CARD — responsive:
  //   • narrow (< 700px): compact vertical phone layout
  //   • wide (>= 700px): horizontal tablet / desktop layout
  //     (reviewer column | comment | action column)
  // ----------------------------------------------------------

  Widget _reviewCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      bool isWide,
      ) {
    final data = doc.data();

    final name = _reviewerName(data);
    final property = _propertyTitle(data);
    final comment = _comment(data);
    final rating = _rating(data);
    final hidden = _isHidden(data);
    final disabled = _isBusy;
    final hasProperty = _propertyIdOf(data).isNotEmpty;

    final Widget reviewerColumn = Column(
      crossAxisAlignment: isWide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: hidden ? Colors.grey : _brand,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _bodyText,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    property,
                    maxLines: isWide ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _mutedText, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (_isBusy && _busyReviewId == doc.id)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _stars(rating),
            const SizedBox(width: 8),
            Text(
              rating.toStringAsFixed(1),
              style: TextStyle(
                color: _bodyText,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (!isWide) ...[
              const Spacer(),
              Text(
                _dateText(_createdAt(data)),
                style: TextStyle(color: _mutedText, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ],
    );

    final Widget moderationRow = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _statusChip(
          hidden ? 'Hidden' : 'Visible',
          hidden ? Colors.orange : _brand,
        ),
        if (_isLow(data)) _statusChip('Low rating', Colors.red),
      ],
    );

    final Widget actionButtons = Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionButton(
                label: 'View',
                icon: Icons.visibility_outlined,
                color: _brand,
                onPressed:
                disabled ? null : () => _viewReview(doc.id, data),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                label: hidden ? 'Show' : 'Hide',
                icon: hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.orange,
                onPressed:
                disabled ? null : () => _toggleHidden(doc.id, data),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                label: 'Open Property',
                icon: Icons.home_work_outlined,
                color: _brand,
                onPressed: (disabled || !hasProperty)
                    ? null
                    : () => _openProperty(data),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                label: 'Delete',
                icon: Icons.delete_outline,
                color: Colors.red,
                onPressed:
                disabled ? null : () => _deleteReview(doc.id, data),
              ),
            ),
          ],
        ),
      ],
    );

    // ---------------- WIDE (tablet / desktop) ----------------
    if (isWide) {
      return Card(
        color: _card,
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: hidden
                ? Colors.orange.withValues(alpha: 0.5)
                : _border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reviewer + rating column.
              SizedBox(
                width: 260,
                child: reviewerColumn,
              ),
              const SizedBox(width: 14),
              VerticalDivider(
                width: 14,
                thickness: 1,
                color: _border,
              ),

              // Comment + moderation middle.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (comment.isNotEmpty)
                      Text(
                        comment,
                        style: TextStyle(
                          color: _bodyText,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      _dateText(_createdAt(data)),
                      style:
                      TextStyle(color: _mutedText, fontSize: 11.5),
                    ),
                    const SizedBox(height: 8),
                    moderationRow,
                    if (hidden && _hideReasonOf(data).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Reason: ${_hideReasonOf(data)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _mutedText,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Action column.
              const SizedBox(width: 14),
              SizedBox(
                width: 250,
                child: actionButtons,
              ),
            ],
          ),
        ),
      );
    }

    // ---------------- NARROW (phone) ----------------
    return Card(
      color: _card,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: hidden ? Colors.orange.withValues(alpha: 0.5) : _border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            reviewerColumn,
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                comment,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _bodyText,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 10),
            moderationRow,
            const SizedBox(height: 12),
            actionButtons,
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
    return FutureBuilder<Map<String, dynamic>?>(
      future: _adminCheck,
      builder: (context, adminSnap) {
        // Only block when we positively know the user is NOT an
        // admin. Missing data → rules still enforce everything.
        if (adminSnap.hasData && !_isAdminData(adminSnap.data)) {
          return Scaffold(
            backgroundColor: _scaffold,
            appBar: AppBar(title: const Text('Manage Reviews')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 70, color: _mutedText),
                    const SizedBox(height: 12),
                    Text(
                      'Admin access only.',
                      style: TextStyle(
                        color: _mutedText,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _scaffold,
          appBar: AppBar(
            title: const Text('Manage Reviews'),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // Paginated stream: only the first `_limit` reviews;
            // "Load more" grows the limit.
            stream: _db.collection('reviews').limit(_limit).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final code =
                (snapshot.error is FirebaseException)
                    ? (snapshot.error as FirebaseException).code
                    : '';

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_outlined,
                            size: 60, color: _mutedText),
                        const SizedBox(height: 12),
                        Text(
                          code == 'permission-denied'
                              ? 'You do not have permission to read '
                              'reviews. Sign in with an admin account.'
                              : code == 'unavailable' ||
                              code == 'network-request-failed'
                              ? 'Network error — check your connection.'
                              : 'Error loading reviews: ${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _bodyText),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _brand,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => setState(() {
                            _limit = _pageSize; // rebuild stream
                          }),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: _brand),
                );
              }

              // Newest first (sorted here so no Firestore index
              // is needed).
              final List<QueryDocumentSnapshot<Map<String, dynamic>>>
              allReviews =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                snapshot.data?.docs ?? [],
              )..sort((a, b) {
                final da = _createdAt(a.data());
                final db = _createdAt(b.data());

                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;

                return db.compareTo(da);
              });

              final List<QueryDocumentSnapshot<Map<String, dynamic>>>
              reviews = _filterReviews(allReviews);

              // If the page came back full there may be more
              // reviews beyond the current limit.
              final mayHaveMore =
                  snapshot.data!.docs.length >= _limit;

              return LayoutBuilder(
                builder: (context, constraints) {
                  // RESPONSIVE — horizontal card layout from
                  // 700px (tablets / desktop).
                  final isWide = constraints.maxWidth >= 700;

                  return Column(
                    children: [
                      _searchBar(),
                      _filterBar(allReviews),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${reviews.length} review(s) found',
                            style:
                            TextStyle(color: _mutedText, fontSize: 12),
                          ),
                        ),
                      ),
                      Expanded(
                        child: reviews.isEmpty && !mayHaveMore
                            ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No reviews match your search or filter.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _mutedText),
                            ),
                          ),
                        )
                            : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount:
                          reviews.length + (mayHaveMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            // "Load more" footer.
                            if (index == reviews.length) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 12,
                                ),
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _brand,
                                    side: BorderSide(color: _brand),
                                    minimumSize:
                                    const Size(0, 48),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _limit += _pageSize;
                                    });
                                  },
                                  icon: const Icon(Icons.expand_more),
                                  label: const Text(
                                      'Load more reviews'),
                                ),
                              );
                            }

                            return _reviewCard(
                                reviews[index], isWide);
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================
// BACKEND RECOMMENDATIONS (not this file)
//
//  1. ADMIN AUTHORIZATION — keep admin-only writes on `reviews`
//     in the Firestore Security Rules (the client-side check
//     here is convenience only). For stronger identity, mint an
//     `admin` custom claim via the Firebase Admin SDK and check
//     `request.auth.token.admin` in the rules.
//  2. AT SCALE — replace the growing-limit pagination with
//     startAfterDocument cursors (orderBy createdAt) so reads
//     stay constant-cost, and consider moving search
//     server-side (Cloud Function / Algolia) since the local
//     search only covers the loaded page.
//  3. TENANT-SIDE — remember tenant pages must filter hidden
//     reviews: `where('isHidden', '!=', true)` or equivalent.
// ============================================================