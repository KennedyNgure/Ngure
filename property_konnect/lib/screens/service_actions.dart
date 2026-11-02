// ============================================================
// service_actions.dart  (UPDATED FILE — shared by
// services_page.dart and favourites_page.dart)
//
// Contains:
//   - PropertyService            the service post model
//   - ServiceActions             phone / email / link validation
//                                + Call / WhatsApp / Email / Open
//                                link launchers (validate FIRST,
//                                then open)
//   - SearchMatcher              multi-term search ("cleaner Kisumu")
//   - ServiceBookmarks           save / remove / load bookmarked
//                                services (collection:
//                                `service_favorites`) — DEVICE ONLY,
//                                no sign-in / account involved
//   - ServiceContactButtons      the Call / WhatsApp / Email /
//                                Open link button row
//
// NO SIGN-IN ANYWHERE: bookmarks are keyed by the DEVICE ID
// ({serviceId}_{deviceId}), and service posts store the poster's
// device id in `userId` (see services_page.dart).
//
// REQUIRED in pubspec.yaml (add if missing), then `flutter pub get`
// and a FULL RESTART:
//   url_launcher: ^6.2.0
//
// ANDROID: for tel / mailto / https / WhatsApp launching on
// Android 11+, add inside <manifest> of
// android/app/src/main/AndroidManifest.xml:
//   <queries>
//     <intent><action android:name="android.intent.action.VIEW"/>
//       <data android:scheme="https"/></intent>
//     <intent><action android:name="android.intent.action.DIAL"/>
//       <data android:scheme="tel"/></intent>
//     <intent><action android:name="android.intent.action.SENDTO"/>
//       <data android:scheme="mailto"/></intent>
//   </queries>
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Provides DeviceIdService (the stable per-device identifier).
import 'property_details_page.dart' show DeviceIdService;

/// Translation callback: (English, Kiswahili) -> text.
typedef Translate = String Function(String en, String sw);

// ============================================================
// MODEL
// ============================================================

class PropertyService {
  final String id;
  final String title;
  final String category;
  final String location;
  final String description;

  /// Optional free-text price, e.g. "From KES 1,500 per trip".
  final String price;
  final String contact;
  final String email;

  /// OPTIONAL. May be ''.
  final String serviceLink;

  /// The DEVICE ID of the device that posted this service (no
  /// sign-in). Only that device can edit / delete the post.
  final String userId;
  final String postedBy;

  /// Legacy field. New posts no longer store a delete code
  /// (ownership is enforced by matching device ids + Firestore
  /// Security Rules).
  final String deleteCode;
  final bool adsVerified;
  final DateTime? createdAt;

  const PropertyService({
    required this.id,
    required this.title,
    required this.category,
    required this.location,
    required this.description,
    required this.contact,
    required this.email,
    required this.serviceLink,
    required this.userId,
    required this.postedBy,
    required this.adsVerified,
    required this.createdAt,
    this.price = '',
    this.deleteCode = '',
  });

  factory PropertyService.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};
    final timestamp = data['createdAt'];

    return PropertyService(
      id: document.id,
      title: (data['title'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      location: (data['location'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      price: (data['price'] ?? '').toString(),
      contact: (data['contact'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      serviceLink: (data['serviceLink'] ?? '').toString(),
      userId: (data['userId'] ?? '').toString(),
      postedBy: (data['postedBy'] ?? '').toString(),
      deleteCode: (data['deleteCode'] ?? '').toString(),
      adsVerified: data['adsVerified'] == true,
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

// ============================================================
// VALIDATION + LAUNCHERS
// ============================================================

class ServiceActions {
  ServiceActions._();

  // ---------------- PHONE ----------------

  /// Returns the phone in international form WITHOUT '+'
  /// (e.g. 0712345678 -> 254712345678) or null when invalid.
  static String? normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    String national;

    if (digits.length == 10 &&
        (digits.startsWith('07') || digits.startsWith('01'))) {
      national = digits.substring(1);
    } else if (digits.length == 12 && digits.startsWith('254')) {
      national = digits.substring(3);
    } else if (digits.length == 9) {
      national = digits;
    } else {
      return null;
    }

    if (national.length != 9 ||
        !(national.startsWith('7') || national.startsWith('1'))) {
      return null;
    }

    return '254$national';
  }

  static bool isValidPhone(String raw) => normalizePhone(raw) != null;

  // ---------------- EMAIL ----------------

  static bool isValidEmail(String raw) {
    return RegExp(r'^[^\s@]+@[^\s@]+.[^\s@]{2,}$').hasMatch(raw.trim());
  }

  // ---------------- LINK ----------------

  /// Accepts "https://...", "http://..." or a bare "example.com/..."
  /// (https:// is added). Returns null when it is not a valid
  /// web link.
  static Uri? normalizeLink(String raw) {
    var text = raw.trim();

    if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;

    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null) return null;

    if (uri.scheme != 'https' && uri.scheme != 'http') return null;

    final host = uri.host;
    if (host.isEmpty ||
        !host.contains('.') ||
        host.startsWith('.') ||
        host.endsWith('.')) {
      return null;
    }

    return uri;
  }

  /// Form validator: the link is OPTIONAL, but when something is
  /// typed it must be a valid web link.
  static String? validateOptionalLink(String? value, Translate tr) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    return normalizeLink(text) == null
        ? tr(
      'Enter a valid link, e.g. https://chat.whatsapp.com/...',
      'Weka kiungo sahihi, mfano https://chat.whatsapp.com/...',
    )
        : null;
  }

  // ---------------- LAUNCH ----------------

  static Future<bool> _launch(
      Uri uri, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
    try {
      return await launchUrl(uri, mode: mode);
    } catch (e) {
      debugPrint('Launch error: $e');
      return false;
    }
  }

  /// CALL — validates the phone number first.
  static Future<void> call(
      String contact, {
        required Translate tr,
        required void Function(String message) onMessage,
      }) async {
    final phone = normalizePhone(contact);

    if (phone == null) {
      onMessage(tr(
        'This phone number is not valid, so the call was not started.',
        'Nambari hii ya simu si sahihi, kwa hivyo simu haikupigwa.',
      ));
      return;
    }

    final ok = await _launch(Uri(scheme: 'tel', path: '+$phone'));

    if (!ok) {
      onMessage(tr(
        'Could not open the phone app.',
        'Imeshindikana kufungua programu ya simu.',
      ));
    }
  }

  /// WHATSAPP — validates the phone number first.
  static Future<void> whatsApp(
      String contact,
      String serviceTitle, {
        required Translate tr,
        required void Function(String message) onMessage,
      }) async {
    final phone = normalizePhone(contact);

    if (phone == null) {
      onMessage(tr(
        'This phone number is not valid, so WhatsApp was not opened.',
        'Nambari hii ya simu si sahihi, kwa hivyo WhatsApp haikufunguliwa.',
      ));
      return;
    }

    final uri = Uri.https('wa.me', '/$phone', {
      'text': 'Hello, I saw your service "$serviceTitle" on PropertyKonnect '
          'and I would like to know more.',
    });

    final ok = await _launch(uri, mode: LaunchMode.externalApplication);

    if (!ok) {
      onMessage(tr(
        'Could not open WhatsApp.',
        'Imeshindikana kufungua WhatsApp.',
      ));
    }
  }

  /// EMAIL — validates the address first.
  static Future<void> email(
      String address,
      String serviceTitle, {
        required Translate tr,
        required void Function(String message) onMessage,
      }) async {
    final email = address.trim();

    if (!isValidEmail(email)) {
      onMessage(tr(
        'This email address is not valid, so the email was not opened.',
        'Barua pepe hii si sahihi, kwa hivyo barua pepe haikufunguliwa.',
      ));
      return;
    }

    final subject = Uri.encodeComponent('Enquiry about: $serviceTitle');
    final ok = await _launch(Uri.parse('mailto:$email?subject=$subject'));

    if (!ok) {
      onMessage(tr(
        'Could not open the email app.',
        'Imeshindikana kufungua programu ya barua pepe.',
      ));
    }
  }

  /// OPEN LINK — validates the link first.
  static Future<void> openLink(
      String link, {
        required Translate tr,
        required void Function(String message) onMessage,
      }) async {
    final uri = normalizeLink(link);

    if (uri == null) {
      onMessage(tr(
        'This service link is not a valid web link, so it was not opened.',
        'Kiungo hiki cha huduma si kiungo sahihi cha wavuti, kwa hivyo hakikufunguliwa.',
      ));
      return;
    }

    final ok = await _launch(uri, mode: LaunchMode.externalApplication);

    if (!ok) {
      onMessage(tr(
        'Could not open the link.',
        'Imeshindikana kufungua kiungo.',
      ));
    }
  }

  // ---------------- CATEGORY ICON ----------------

  static IconData categoryIcon(String category) {
    final value = category.toLowerCase();

    if (value.contains('moving')) return Icons.local_shipping_outlined;
    if (value.contains('clean')) return Icons.cleaning_services_outlined;
    if (value.contains('paint')) return Icons.format_paint_outlined;
    if (value.contains('plumb') || value.contains('electric')) {
      return Icons.electrical_services_outlined;
    }
    if (value.contains('furniture')) return Icons.chair_outlined;
    if (value.contains('internet') || value.contains('tv')) {
      return Icons.wifi_outlined;
    }
    if (value.contains('security') || value.contains('cctv')) {
      return Icons.security_outlined;
    }
    if (value.contains('house') || value.contains('agent')) {
      return Icons.home_work_outlined;
    }
    if (value.contains('legal')) return Icons.gavel_outlined;
    if (value.contains('repair')) return Icons.build_outlined;

    return Icons.miscellaneous_services_outlined;
  }
}

// ============================================================
// MULTI-TERM SEARCH
//
// "cleaner Kisumu" is split into two terms. EVERY term must be
// found somewhere in the combined text of the post (title,
// category, location, description ...) — they do NOT have to be
// in the same field. A light stem lets "cleaner" match
// "Cleaning Services", "movers" match "Moving", etc.
// ============================================================

class SearchMatcher {
  SearchMatcher._();

  static List<String> terms(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[\s,]+'))
        .where((term) => term.isNotEmpty)
        .toList();
  }

  static String _stem(String term) {
    if (term.length > 5 && term.endsWith('ers')) {
      return term.substring(0, term.length - 3);
    }
    if (term.length > 4 && term.endsWith('er')) {
      return term.substring(0, term.length - 2);
    }
    if (term.length > 5 && term.endsWith('ing')) {
      return term.substring(0, term.length - 3);
    }
    if (term.length > 3 && term.endsWith('s')) {
      return term.substring(0, term.length - 1);
    }
    return term;
  }

  static bool matches(String haystack, String query) {
    final text = haystack.toLowerCase();

    for (final term in terms(query)) {
      final stem = _stem(term);

      final found =
          text.contains(term) || (stem.length >= 3 && text.contains(stem));

      if (!found) return false;
    }

    return true;
  }
}

// ============================================================
// SERVICE BOOKMARKS  (collection: service_favorites)
//
// DEVICE ONLY — no sign-in, no accounts.
//
// Document id  : {serviceId}_{deviceId}
// Fields       : serviceId, deviceId, createdAt
// ============================================================

class ServiceBookmarks {
  ServiceBookmarks._();

  /// Bumped whenever a bookmark is added/removed, so open pages
  /// can refresh.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void notify() => changes.value++;

  static const String _collection = 'service_favorites';

  static Future<Set<String>> loadIds() async {
    final ids = <String>{};

    try {
      final deviceId = await DeviceIdService.get();

      final snap = await FirebaseFirestore.instance
          .collection(_collection)
          .where('deviceId', isEqualTo: deviceId)
          .get();

      for (final doc in snap.docs) {
        final id = doc.data()['serviceId']?.toString() ?? '';
        if (id.isNotEmpty) ids.add(id);
      }
    } catch (e) {
      debugPrint('Service bookmarks load error: $e');
    }

    return ids;
  }

  static Future<void> add(String serviceId) async {
    final deviceId = await DeviceIdService.get();

    await FirebaseFirestore.instance
        .collection(_collection)
        .doc('${serviceId}_$deviceId')
        .set({
      'serviceId': serviceId,
      'deviceId': deviceId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    notify();
  }

  static Future<void> remove(String serviceId) async {
    final deviceId = await DeviceIdService.get();

    final snap = await FirebaseFirestore.instance
        .collection(_collection)
        .where('deviceId', isEqualTo: deviceId)
        .where('serviceId', isEqualTo: serviceId)
        .get();

    await Future.wait(
      snap.docs.map((doc) => doc.reference.delete()),
    );

    notify();
  }
}

// ============================================================
// CONTACT BUTTONS — Call | WhatsApp | Email | Open link
//
// The phone number and email are NOT shown as text; only the
// buttons are. Every button validates its value before opening.
// The Open link button only appears when the post has a link.
// ============================================================

class ServiceContactButtons extends StatelessWidget {
  const ServiceContactButtons({
    super.key,
    required this.service,
    required this.brand,
    required this.tr,
    required this.onMessage,
    this.compact = false,
  });

  final PropertyService service;
  final Color brand;
  final Translate tr;
  final void Function(String message) onMessage;
  final bool compact;

  Widget _button(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: compact ? 16 : 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: brand,
        side: BorderSide(color: brand),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity:
        compact ? VisualDensity.compact : VisualDensity.standard,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        textStyle: TextStyle(
          fontSize: compact ? 12.5 : 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (service.contact.trim().isNotEmpty)
        _button(
          Icons.call_outlined,
          tr('Call', 'Piga simu'),
              () => ServiceActions.call(
            service.contact,
            tr: tr,
            onMessage: onMessage,
          ),
        ),
      if (service.contact.trim().isNotEmpty)
        _button(
          Icons.chat_outlined,
          'WhatsApp',
              () => ServiceActions.whatsApp(
            service.contact,
            service.title,
            tr: tr,
            onMessage: onMessage,
          ),
        ),
      if (service.email.trim().isNotEmpty)
        _button(
          Icons.email_outlined,
          tr('Email', 'Barua pepe'),
              () => ServiceActions.email(
            service.email,
            service.title,
            tr: tr,
            onMessage: onMessage,
          ),
        ),
      if (service.serviceLink.trim().isNotEmpty)
        _button(
          Icons.open_in_new,
          tr('Open link', 'Fungua kiungo'),
              () => ServiceActions.openLink(
            service.serviceLink,
            tr: tr,
            onMessage: onMessage,
          ),
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }
}