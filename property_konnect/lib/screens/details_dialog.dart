import 'package:flutter/material.dart';

import 'download_helper.dart';

/// Shows a popup with every field of [data] listed out, plus a
/// download button that saves those details as a real file.
///
/// Used by "view" buttons on landlord/owner and roommate-post
/// admin lists.
///
/// Display and download now share [formatFieldValue] and
/// [labelFromKey] (from download_helper.dart), so the downloaded
/// file always reads exactly like the on-screen popup — e.g.
/// dates like "2/10/2026" instead of raw Firestore
/// "Timestamp(seconds=..., nanoseconds=...)".
Future<void> showDetailsDialog({
  required BuildContext context,
  required String title,
  required Map<String, dynamic> data,
  required String downloadFileNamePrefix,
  List<String>? fieldOrder,
  Set<String>? hiddenFields,
}) {
  final hidden = hiddenFields ?? {'id'};

  final keys = fieldOrder ??
      (data.keys.toList()..sort());

  return showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in keys)
                  if (!hidden.contains(key) &&
                      data.containsKey(key))
                    _DetailRow(
                      label: labelFromKey(key),
                      value: formatFieldValue(
                        data[key],
                        ifEmpty: 'Not provided',
                      ),
                    ),
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download'),
            onPressed: () {
              DownloadHelper.downloadDetailsText(
                context: dialogContext,
                fileNamePrefix: downloadFileNamePrefix,
                details: data,
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF146C43),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}