// ============================================================
// DOWNLOAD HELPER (all-in-one)
// ------------------------------------------------------------
// The single download system for the whole app.
//
// Produces a REAL downloadable file (not a clipboard copy) and
// works on Flutter WEB as well as mobile/desktop:
//
//   - Web:     browser download via Blob + <a download>
//              (in platform_download_web.dart — no package needed)
//   - Mobile / desktop: temp file + OS share sheet
//              (in platform_download_io.dart — needs
//               share_plus + path_provider)
//
// Everything shared lives here:
//   - formatFieldValue : human-readable values for screen + file
//   - labelFromKey     : pretty labels for screen + file
//   - DownloadHelper   : CSV, full-record TXT, curated TXT
//
// This file intentionally does NOT depend on the `printing` or
// `pdf` packages — the old MissingPluginException came from
// `printing.sharePdf` not being rebuilt on Windows. Every page
// (admin lists, landlord view popups, property details) now
// uses this one helper instead.
//
// platform_download.dart is the tiny conditional-import shim:
//
//   export 'platform_download_web.dart'  if (dart.library.html)
//   export 'platform_download_io.dart'   if (dart.library.io)
//   export 'platform_download_stub.dart' otherwise
// ============================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'platform_download.dart';

/// Shared value formatter used by BOTH the on-screen details
/// dialogs and every download path (txt + csv), so the file
/// always shows exactly what the user sees on screen.
///
/// - Firestore Timestamp / DateTime -> 9/10/2026 style date
/// - bool                            -> Yes / No
/// - Map (e.g. payment details)     -> key: value, key: value
/// - List                           -> comma separated
/// - null / empty                   -> [ifEmpty]
String formatFieldValue(dynamic value, {String ifEmpty = ''}) {
  if (value == null) return ifEmpty;

  if (value is Timestamp) {
    final d = value.toDate();
    return '${d.day}/${d.month}/${d.year}';
  }

  if (value is DateTime) {
    return '${value.day}/${value.month}/${value.year}';
  }

  if (value is bool) {
    return value ? 'Yes' : 'No';
  }

  if (value is Map) {
    if (value.isEmpty) return ifEmpty;
    return value.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }

  if (value is List) {
    if (value.isEmpty) return ifEmpty;
    return value.map((e) => e.toString()).join(', ');
  }

  final text = value.toString();
  return text.isEmpty ? ifEmpty : text;
}

/// Shared label prettifier: 'landlord_status' / 'landlordStatus'
/// -> 'Landlord status'. Also used by the details dialogs so the
/// downloaded labels match the on-screen ones.
String labelFromKey(String key) {
  final withSpaces = key.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m.group(1)} ${m.group(2)}',
  );
  final spaced = withSpaces.replaceAll('_', ' ');
  if (spaced.isEmpty) return spaced;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

class DownloadHelper {
  DownloadHelper._();

  // ----------------------------------------------------------
  // CSV
  // ----------------------------------------------------------

  /// Escapes a single CSV field. Values are first run through
  /// [formatFieldValue] so Firestore Timestamps, bools and maps
  /// are exported in human-readable form, matching the UI.
  static String csvField(dynamic value) {
    final text = formatFieldValue(value);
    if (text.contains(',') ||
        text.contains('"') ||
        text.contains('\n')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  /// Builds one CSV file from a list of rows and a header row,
  /// then downloads it. Used by admin list pages.
  static Future<void> downloadCsv({
    required BuildContext context,
    required String fileNamePrefix,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(csvField).join(','));

    for (final row in rows) {
      buffer.writeln(row.map(csvField).join(','));
    }

    await _saveFile(
      context: context,
      fileNamePrefix: fileNamePrefix,
      extension: 'csv',
      content: buffer.toString(),
      mimeType: 'text/csv',
    );
  }

  // ----------------------------------------------------------
  // FULL-RECORD TXT (raw Firestore document)
  // ----------------------------------------------------------

  /// Downloads a single record as a readable .txt file — used
  /// by "view details" popups for a one-item download.
  ///
  /// Every value goes through [formatFieldValue] with the same
  /// 'Not provided' fallback the on-screen dialog uses, so the
  /// downloaded details read exactly like the popup.
  static Future<void> downloadDetailsText({
    required BuildContext context,
    required String fileNamePrefix,
    required Map<String, dynamic> details,
  }) async {
    final buffer = StringBuffer();

    final keys = details.keys.toList()..sort();

    for (final key in keys) {
      final label = labelFromKey(key);
      final text = formatFieldValue(details[key], ifEmpty: '');
      if (text.trim().isEmpty) continue;
      buffer.writeln('$label: $text');
    }

    await _saveFile(
      context: context,
      fileNamePrefix: fileNamePrefix,
      extension: 'txt',
      content: buffer.toString(),
      mimeType: 'text/plain',
    );
  }

  // ----------------------------------------------------------
  // CURATED TXT (pre-built "label: value" lines)
  // ----------------------------------------------------------

  /// Downloads a curated set of sections as a .txt file. Used by
  /// pages that build their own friendly sections (e.g. the
  /// property details page) instead of dumping the raw Firestore
  /// document.
  ///
  /// [sections] is an ordered list of records with a `heading`
  /// and a list of `(label, value)` lines. Empty sections and
  /// empty values are skipped automatically.
  static Future<void> downloadCuratedText({
    required BuildContext context,
    required String fileNamePrefix,
    required List<({String heading, List<(String, String)> lines})>
    sections,
  }) async {
    final buffer = StringBuffer();

    for (final section in sections) {
      final lines = section.lines
          .where((line) => line.$2.trim().isNotEmpty)
          .toList();

      if (lines.isEmpty) continue;

      if (buffer.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln();
      }

      buffer
        ..writeln(section.heading.toUpperCase())
        ..writeln('=' * section.heading.length);

      for (final line in lines) {
        buffer.writeln('${line.$1}: ${line.$2}');
      }
    }

    await _saveFile(
      context: context,
      fileNamePrefix: fileNamePrefix,
      extension: 'txt',
      content: buffer.toString(),
      mimeType: 'text/plain',
    );
  }

  // ----------------------------------------------------------
  // SAVE
  // ----------------------------------------------------------

  static Future<void> _saveFile({
    required BuildContext context,
    required String fileNamePrefix,
    required String extension,
    required String content,
    required String mimeType,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safePrefix = fileNamePrefix
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final fileName = '${safePrefix}_$timestamp.$extension';

      await platformSaveFile(
        context: context,
        fileName: fileName,
        content: content,
        mimeType: mimeType,
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }
}