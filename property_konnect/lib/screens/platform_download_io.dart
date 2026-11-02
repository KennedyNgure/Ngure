import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Android / iOS / desktop implementation — writes a temp file
/// then hands it to the OS share sheet, where the user can choose
/// "Save to Files" / Drive / etc.
Future<void> platformSaveFile({
  required BuildContext context,
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');

  await file.writeAsString(
    mimeType.contains('csv') ? '\uFEFF$content' : content,
  );

  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      subject: fileName,
    ),
  );

  if (!context.mounted) return;

  if (result.status == ShareResultStatus.success ||
      result.status == ShareResultStatus.dismissed) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF146C43),
        content: Text(
          'File ready — choose where to save it.',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}