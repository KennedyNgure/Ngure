import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';

// ============================================================
// SHARED HELPERS for the posting pages:
//   - student_services_page.dart
//   - campus_communities_page.dart
//   - servicespage.dart
//
// Pass the PAGE'S context (State.context) to these helpers, not a
// dialog's builder context.
// ============================================================

String trOf(BuildContext context, String en, String sw) =>
    AppSettings.of(context).languageCode == 'sw' ? sw : en;

// ------------------------------------------------------------
// OWNER ID — signed-in uid, or a random id stored on this device.
// Only the owner of a post sees its Delete button.
// ------------------------------------------------------------

Future<String> loadOwnerId() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) return user.uid;

  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('pk_device_owner_id');

  if (id == null || id.isEmpty) {
    final random = Random.secure();
    final suffix = List.generate(
      12,
          (_) => random.nextInt(16).toRadixString(16),
    ).join();
    id = 'device_${DateTime.now().millisecondsSinceEpoch}_$suffix';
    await prefs.setString('pk_device_owner_id', id);
  }

  return id;
}

// ------------------------------------------------------------
// LINKS
//
// The link field accepts anything (WhatsApp / Telegram group link,
// website, app name...). It is only openable when it looks like a
// web address.
// ------------------------------------------------------------

Uri? linkToUri(String raw) {
  final link = raw.trim();

  if (link.isEmpty || link.contains(' ')) return null;

  final withScheme = RegExp(r'^https?://', caseSensitive: false).hasMatch(link)
      ? link
      : 'https://$link';

  final uri = Uri.tryParse(withScheme);

  if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
    return null;
  }

  return uri;
}

Future<bool> openLink(String raw) async {
  final uri = linkToUri(raw);

  if (uri == null) return false;

  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// "Open link" button; renders nothing when the link is not a web address.
Widget openLinkButton(BuildContext context, String link, Color brand) {
  if (linkToUri(link) == null) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand,
          side: BorderSide(color: brand),
        ),
        onPressed: () async {
          final opened = await openLink(link);

          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  trOf(
                    context,
                    'Could not open the link.',
                    'Imeshindikana kufungua kiungo.',
                  ),
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.open_in_new, size: 17),
        label: Text(trOf(context, 'Open link', 'Fungua kiungo')),
      ),
    ),
  );
}

// ------------------------------------------------------------
// VALIDATORS
// ------------------------------------------------------------

String? validateRequired(BuildContext context, String? value) {
  if (value == null || value.trim().isEmpty) {
    return trOf(context, 'This field is required', 'Sehemu hii inahitajika');
  }
  return null;
}

String? validatePhone(BuildContext context, String? value) {
  final text = value?.trim() ?? '';

  if (text.isEmpty) {
    return trOf(context, 'Phone number is required',
        'Nambari ya simu inahitajika');
  }

  if (!RegExp(r'^\d{10}$').hasMatch(text)) {
    return trOf(
      context,
      'Enter exactly 10 digits (numbers only)',
      'Weka tarakimu 10 kamili (nambari tu)',
    );
  }

  return null;
}

String? validateEmail(BuildContext context, String? value) {
  final text = value?.trim() ?? '';

  if (text.isEmpty) {
    return trOf(context, 'Email is required', 'Barua pepe inahitajika');
  }

  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
    return trOf(context, 'Enter a valid email address',
        'Weka barua pepe sahihi');
  }

  return null;
}

String? validateDeleteCode(BuildContext context, String? value) {
  final text = value?.trim() ?? '';

  if (text.isEmpty) {
    return trOf(context, 'Delete code is required',
        'Msimbo wa kufuta unahitajika');
  }

  if (!RegExp(r'^\d{4}$').hasMatch(text)) {
    return trOf(
      context,
      'Delete code must be exactly 4 digits',
      'Msimbo wa kufuta lazima uwe tarakimu 4',
    );
  }

  return null;
}

// ------------------------------------------------------------
// FORM TEXT FIELD
// ------------------------------------------------------------

Widget postTextField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  required String? Function(String?) validator,
  String? hint,
  int? hintMaxLines,
  String? helper,
  TextInputType? keyboardType,
  TextCapitalization capitalization = TextCapitalization.none,
  int maxLines = 1,
  int? maxLength,
  bool digitsOnly = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters:
      digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintMaxLines: hintMaxLines,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: Icon(icon),
        counterText: maxLength == null ? null : '',
        alignLabelWithHint: maxLines > 1,
      ),
    ),
  );
}

// ------------------------------------------------------------
// DELETE WITH 4-DIGIT CODE
//
// Returns true when the user confirmed (and, for posts that have a
// delete code, typed the right one). Older posts created before the
// delete code existed have no code, so they only ask for confirmation.
//
// The controller is intentionally not disposed manually: disposing
// right after a dialog closes can throw during the closing animation.
// ------------------------------------------------------------

Future<bool> confirmDeleteWithCode(
    BuildContext context, {
      required String title,
      required String message,
      required String storedCode,
    }) async {
  final controller = TextEditingController();
  final needsCode = storedCode.trim().isNotEmpty;

  String? error;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (builderContext, setDialogState) {
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (needsCode) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: trOf(
                        context,
                        '4-digit delete code',
                        'Msimbo wa kufuta wa tarakimu 4',
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                      counterText: '',
                      errorText: error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(trOf(context, 'Cancel', 'Ghairi')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (needsCode) {
                    final entered = controller.text.trim();

                    if (!RegExp(r'^\d{4}$').hasMatch(entered)) {
                      setDialogState(() {
                        error = trOf(
                          context,
                          'Enter exactly 4 digits.',
                          'Weka tarakimu 4 kamili.',
                        );
                      });
                      return;
                    }

                    if (entered != storedCode.trim()) {
                      setDialogState(() {
                        error = trOf(
                          context,
                          'Incorrect delete code.',
                          'Msimbo wa kufuta si sahihi.',
                        );
                      });
                      return;
                    }
                  }

                  Navigator.of(dialogContext).pop(true);
                },
                child: Text(trOf(context, 'Delete', 'Futa')),
              ),
            ],
          );
        },
      );
    },
  );

  return result == true;
}