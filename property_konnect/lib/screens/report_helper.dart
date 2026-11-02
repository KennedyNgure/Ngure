// ============================================================
// report_helper.dart  (NEW SHARED FILE)
//
// One place that saves a report in EXACTLY the same format the
// roommate reports use in Firestore (collection `reports`):
//
//   createdAt         Timestamp (server)
//   details           ""  (optional text typed by the reporter)
//   deviceId          "dev_7a82..."        (DeviceIdService)
//   kind              "roommate_post" | "campus_community" |
//                     "marketplace_item" | "property_service"
//   reason            "Scam or fraud" ...
//   reporterId        signed-in uid, else the local owner id
//                     ("device_1793..._e4cb...")
//   status            "open"
//   targetCollection  "roommates" | "campus_communities" |
//                     "comrade_marketplace" | "property_services"
//   targetId          the listing's document id
//   targetName        the listing's title / name
//   targetOwnerId     the listing's userId (the poster)
//
// Document id:  {kind}_{targetId}_{deviceId}
//   -> one device can report a listing only ONCE.
//
// The `reportCount` counter on the listing is bumped in its OWN
// try block: if Firestore rules deny that update, the report
// itself is still saved.
//
// The Manage Reports page reads `targetCollection` / `kind` to
// put each report under the right "Report from" chip.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'post_helpers.dart';
import 'property_details_page.dart' show DeviceIdService;

enum ReportOutcome {
  sent,
  alreadyReported,
  ownListing,
  cancelled,
  denied,
  failed,
}

class ReportHelper {
  ReportHelper._();

  // ------------------------------------------------------------
  // REASONS (English value saved to Firestore, Swahili label)
  // ------------------------------------------------------------

  static const List<(String, String)> communityReasons = [
    ('Misleading information', 'Taarifa za kupotosha'),
    ('Scam or fraud', 'Udanganyifu'),
    ('Inappropriate content', 'Maudhui yasiyofaa'),
    ('Spam or duplicate', 'Tangazo la mara kwa mara'),
    ('Other', 'Nyingine'),
  ];

  static const List<(String, String)> marketplaceReasons = [
    ('Misleading information', 'Taarifa za kupotosha'),
    ('Scam or fraud', 'Udanganyifu'),
    ('Suspicious seller', 'Muuzaji wa kutiliwa shaka'),
    ('Fake or stolen photos', 'Picha bandia au zilizoibwa'),
    ('Inappropriate content', 'Maudhui yasiyofaa'),
    ('Other', 'Nyingine'),
  ];

  static const List<(String, String)> serviceReasons = [
    ('Scam or fraud', 'Udanganyifu'),
    ('Wrong or fake contact details', 'Maelezo ya mawasiliano si sahihi'),
    ('Inappropriate content', 'Maudhui yasiyofaa'),
    ('Spam or duplicate post', 'Tangazo la mara kwa mara'),
    ('Other', 'Sababu nyingine'),
  ];

  // ------------------------------------------------------------
  // MAIN ENTRY — asks for a reason, saves the report, shows the
  // result message itself (auto-dismissing SnackBar).
  // ------------------------------------------------------------

  static Future<ReportOutcome> report(
      BuildContext context, {
        required String kind,
        required String targetCollection,
        required String targetId,
        required String targetName,
        required String targetOwnerId,
        required List<(String, String)> reasons,
      }) async {
    final isSw = AppSettings.of(context).languageCode == 'sw';
    String tr(String en, String sw) => isSw ? sw : en;

    void snack(String message) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
    }

    final firestore = FirebaseFirestore.instance;

    // ---------- Who is reporting? ----------
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    var localId = '';
    try {
      localId = await loadOwnerId();
    } catch (_) {}

    var deviceId = '';
    try {
      deviceId = await DeviceIdService.get();
    } catch (_) {}

    if (!context.mounted) return ReportOutcome.cancelled;

    if (deviceId.isEmpty && uid.isEmpty && localId.isEmpty) {
      snack(tr('Could not identify this device. Please try again.',
          'Imeshindikana kutambua kifaa hiki. Tafadhali jaribu tena.'));
      return ReportOutcome.failed;
    }

    // Owners cannot report their own listing.
    if (targetOwnerId.isNotEmpty &&
        (targetOwnerId == uid || targetOwnerId == localId)) {
      return ReportOutcome.ownListing;
    }

    final reporterId =
    uid.isNotEmpty ? uid : (localId.isNotEmpty ? localId : deviceId);
    final deviceKey = deviceId.isNotEmpty ? deviceId : reporterId;

    final ref = firestore
        .collection('reports')
        .doc('${kind}_${targetId}_$deviceKey');

    // ---------- Already reported? (best effort) ----------
    try {
      final existing = await ref.get();
      if (existing.exists) {
        snack(tr('You have already reported this listing.',
            'Umesha ripoti chapisho hili.'));
        return ReportOutcome.alreadyReported;
      }
    } catch (_) {
      // Reads may be restricted by rules — the write below still
      // dedupes through the same document id.
    }

    if (!context.mounted) return ReportOutcome.cancelled;

    // ---------- Ask for the reason ----------
    final picked = await _askReason(
      context,
      reasons: reasons,
      isSw: isSw,
      targetName: targetName,
    );

    if (picked == null || !context.mounted) return ReportOutcome.cancelled;

    // ---------- Save the report ----------
    try {
      await ref.set({
        'createdAt': FieldValue.serverTimestamp(),
        'details': picked.details,
        'deviceId': deviceKey,
        'kind': kind,
        'reason': picked.reason,
        'reporterId': reporterId,
        'status': 'open',
        'targetCollection': targetCollection,
        'targetId': targetId,
        'targetName': targetName,
        'targetOwnerId': targetOwnerId,
      });
    } on FirebaseException catch (e) {
      debugPrint('REPORT SAVE ERROR: ${e.code} ${e.message}');
      snack(
        e.code == 'permission-denied'
            ? tr(
          'Could not send the report. You may have already reported this listing.',
          'Imeshindikana kutuma ripoti. Huenda umesha ripoti chapisho hili.',
        )
            : tr('Could not send the report. Please try again.',
            'Imeshindikana kutuma ripoti. Tafadhali jaribu tena.'),
      );
      return e.code == 'permission-denied'
          ? ReportOutcome.denied
          : ReportOutcome.failed;
    } catch (e) {
      debugPrint('REPORT SAVE ERROR: $e');
      snack(tr('Could not send the report. Please try again.',
          'Imeshindikana kutuma ripoti. Tafadhali jaribu tena.'));
      return ReportOutcome.failed;
    }

    // ---------- Best-effort counter on the listing ----------
    try {
      await firestore
          .collection(targetCollection)
          .doc(targetId)
          .update({'reportCount': FieldValue.increment(1)});
    } catch (_) {}

    snack(tr('Thanks. This listing has been reported.',
        'Asante. Chapisho hili limeripotiwa.'));

    return ReportOutcome.sent;
  }

  // ------------------------------------------------------------
  // REASON DIALOG (RadioGroup — no deprecated groupValue params)
  // ------------------------------------------------------------

  static Future<({String reason, String details})?> _askReason(
      BuildContext context, {
        required List<(String, String)> reasons,
        required bool isSw,
        required String targetName,
      }) async {
    String tr(String en, String sw) => isSw ? sw : en;

    final detailsController = TextEditingController();
    var selected = reasons.first.$1;

    final result = await showDialog<({String reason, String details})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              icon: Icon(Icons.flag_outlined,
                  color: Colors.orange.shade700, size: 32),
              title: Text(
                tr('Report listing', 'Ripoti chapisho'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      targetName.trim().isEmpty
                          ? tr('Why are you reporting this listing?',
                          'Kwa nini unaripoti chapisho hili?')
                          : tr(
                        'Why are you reporting "$targetName"?',
                        'Kwa nini unaripoti "$targetName"?',
                      ),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<String>(
                      groupValue: selected,
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selected = value);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (en, sw) in reasons)
                            RadioListTile<String>(
                              value: en,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                tr(en, sw),
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: detailsController,
                      maxLines: 2,
                      maxLength: 300,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: tr('More details (optional)',
                            'Maelezo zaidi (si lazima)'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr('Cancel', 'Ghairi')),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    (
                    reason: selected,
                    details: detailsController.text.trim(),
                    ),
                  ),
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(tr('Report', 'Ripoti')),
                ),
              ],
            );
          },
        );
      },
    );

    detailsController.dispose();

    return result;
  }
}