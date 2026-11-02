import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Flutter WEB implementation — real browser download using a
/// Blob and a hidden <a download> link. No path_provider needed.
Future<void> platformSaveFile({
  required BuildContext context,
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final body = utf8.encode(content);

  // UTF-8 BOM so Excel opens CSV files with correct characters.
  final bytes = Uint8List.fromList(
    mimeType.contains('csv') ? <int>[0xEF, 0xBB, 0xBF, ...body] : body,
  );

  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );

  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();

  web.URL.revokeObjectURL(url);

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      backgroundColor: Color(0xFF146C43),
      content: Text(
        'Download started.',
        style: TextStyle(color: Colors.white),
      ),
    ),
  );
}