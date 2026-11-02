import 'package:flutter/material.dart';

/// Fallback for unsupported platforms.
Future<void> platformSaveFile({
  required BuildContext context,
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  throw UnsupportedError('Downloads are not supported on this platform.');
}