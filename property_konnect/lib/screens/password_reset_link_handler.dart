
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/reset_password_page.dart';

class PasswordResetLinkHandler {
  PasswordResetLinkHandler._();

  static final PasswordResetLinkHandler instance =
  PasswordResetLinkHandler._();

  final AppLinks _appLinks = AppLinks();

  StreamSubscription<Uri>? _subscription;
  String? _lastOpenedCode;

  Future<void> start(GlobalKey<NavigatorState> navigatorKey) async {
    // Handle links that launch the app from a closed state.
    try {
      final initialUri = await _appLinks.getInitialLink();

      if (initialUri != null) {
        _openIfPasswordReset(initialUri, navigatorKey);
      }
    } catch (_) {
      // A missing or unreadable initial link should not block app startup.
    }

    // Handle links tapped while the app is already running.
    _subscription ??= _appLinks.uriLinkStream.listen(
          (uri) => _openIfPasswordReset(uri, navigatorKey),
      onError: (_) {
        // Keep the app running if the platform link stream errors.
      },
    );
  }

  void _openIfPasswordReset(
      Uri uri,
      GlobalKey<NavigatorState> navigatorKey,
      ) {
    // Some links may wrap the actual action link in a query parameter.
    Uri actualUri = uri;

    for (var i = 0; i < 3; i++) {
      final nested = actualUri.queryParameters['link'] ??
          actualUri.queryParameters['deep_link_id'];

      if (nested == null) break;

      final parsed = Uri.tryParse(nested);
      if (parsed == null) break;

      actualUri = parsed;
    }

    final mode = actualUri.queryParameters['mode'];
    final code = actualUri.queryParameters['oobCode'];

    if (mode != 'resetPassword' || code == null || code.isEmpty) {
      return;
    }

    // Avoid opening the same reset screen twice for the same code.
    if (_lastOpenedCode == code) return;
    _lastOpenedCode = code;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = navigatorKey.currentState;

      if (navigator == null) {
        _lastOpenedCode = null;
        return;
      }

      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ResetPasswordPage(oobCode: code),
        ),
      );
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
