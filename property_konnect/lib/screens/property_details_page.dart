import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'app_settings.dart';
// UPDATED: app download banner + dialog for users without the app.
import 'app_download.dart';
// Provides FavouritesSignal (tells the Favourites page to refresh).
import 'favourites_page.dart';

// ============================================================
// PROPERTY DETAILS PAGE
//
// One page, three views (chosen automatically):
//
//  TENANT  - gallery (tap for full-screen zoom), details,
//            amenities, description, videos (in-app player),
//            "Add to favourites", Share, View on Google Maps,
//            property owner card (WhatsApp + Call only),
//            safety reminder, reviews & ratings, similar
//            properties, report suspicious listing.
//
//  OWNER   - live Views / Contacts / Favourites counts, status,
//            reviews (read only).
//
//  ADMIN   - everything + full owner details + Download.
//
// NEW IN THIS VERSION:
//  - REPORTS now save to the shared `reports` collection in the
//    SAME SHAPE as the rest of the app (matches the admin
//    console screenshot):
//      doc id: property_<targetId>_<deviceId>
//      kind: 'property'
//      targetCollection: 'properties'
//      targetId / targetName / targetOwnerId
//      reason / details
//      deviceId + reporterId (the reporting device)
//      status: 'open'
//      createdAt: server timestamp
//    One device can report a listing ONCE (doc id dedupes).
//  - Shared text now contains:
//      * Google Maps link
//      * a link that shows ALL photos and videos
//        (PropertyMediaPage, opened with  ?media=<id>)
//      * a link that opens the app on this property's details
//        page (opened with  ?property=<id>)
//  - PropertyLinks / PropertyDeepLink: build and read those links
//  - PropertyMediaPage: public page with every photo and video
//  - Images now work on Flutter web even when Firebase Storage
//    has no CORS rules (falls back to the browser's own <img>)
//  - Pull-to-refresh now ALSO reloads photos that failed
//  - A property opened from a link with only its id loads fully
//    (similar properties and owner contact reload after fetch)
//  - Videos open in the browser on Flutter web (video_player
//    does not run there)
//  - App download banner on the media page + dialog for users
//    who arrive from shared links without the app
// ============================================================

// ------------------------------------------------------------
// SHARE LINKS
//
// IMPORTANT: change this to the address where your Flutter web
// app is hosted (no trailing slash).
// ------------------------------------------------------------
const String kAppBaseUrl = 'https://property-konnect-cb4bc.web.app';

class PropertyLinks {
  /// Opens the app straight on the property's details page.
  static String details(String id) =>
      '$kAppBaseUrl/?property=${Uri.encodeQueryComponent(id)}';

  /// Opens a page that shows all photos and videos of the property.
  static String media(String id) =>
      '$kAppBaseUrl/?media=${Uri.encodeQueryComponent(id)}';
}

/// Reads an incoming web link and returns the page it points to.
///
/// In main.dart:
///   home: PropertyDeepLink.widgetFor(Uri.base) ?? <your normal home>,
class PropertyDeepLink {
  static Widget? widgetFor([Uri? uri]) {
    final u = uri ?? Uri.base;

    final params = <String, String>{...u.queryParameters};

    // Also support links where the query ended up after a '#'.
    final fragment = u.fragment;
    final q = fragment.indexOf('?');
    if (q != -1) {
      try {
        params.addAll(Uri.splitQueryString(fragment.substring(q + 1)));
      } catch (_) {}
    }

    final media = (params['media'] ?? '').trim();
    if (media.isNotEmpty) return PropertyMediaPage(propertyId: media);

    final property = (params['property'] ?? '').trim();
    if (property.isNotEmpty) return PropertyDetailsByIdPage(propertyId: property);

    return null;
  }
}

/// Property details opened from a link that only carries the id.
/// The details page loads everything else from Firestore.
class PropertyDetailsByIdPage extends StatelessWidget {
  final String propertyId;

  const PropertyDetailsByIdPage({super.key, required this.propertyId});

  @override
  Widget build(BuildContext context) {
    return PropertyDetailsPage(
      property: {'id': propertyId},
      isTenantView: true,
    );
  }
}

// ------------------------------------------------------------
// DEVICE ID
// ------------------------------------------------------------
class DeviceIdService {
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null && _cached!.isNotEmpty) return _cached!;

    var id = '';

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('device_id') ?? '';

      if (saved.isNotEmpty) {
        _cached = saved;
        return saved;
      }

      if (!kIsWeb) {
        if (defaultTargetPlatform == TargetPlatform.android) {
          id = await const AndroidId().getId() ?? '';
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          id = (await DeviceInfoPlugin().iosInfo).identifierForVendor ?? '';
        }
      }

      if (id.isEmpty) id = _randomId();

      await prefs.setString('device_id', id);
    } catch (_) {
      if (id.isEmpty) id = _randomId();
    }

    _cached = id;
    return id;
  }

  static String _randomId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return 'dev_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}

class PropertyDetailsPage extends StatefulWidget {
  final Map<String, dynamic> property;

  final bool isAdminView;

  /// Force the owner view. Normally not needed: the page detects
  /// the owner by comparing property['ownerId'] with the signed-in uid.
  final bool isOwnerView;

  /// Force the TENANT view (the public search page passes this).
  final bool isTenantView;

  const PropertyDetailsPage({
    super.key,
    required this.property,
    this.isAdminView = false,
    this.isOwnerView = false,
    this.isTenantView = false,
  });

  @override
  State<PropertyDetailsPage> createState() => _PropertyDetailsPageState();
}

class _PropertyDetailsPageState extends State<PropertyDetailsPage> {
  static const Duration _viewThrottle = Duration(minutes: 30);

  final PageController _pageController = PageController();
  int _imageIndex = 0;

  /// Bumped on every pull-to-refresh so failed / stale images reload.
  int _imageEpoch = 0;

  /// Working copy of the property. Starts as the map passed in, then
  /// is merged with the fresh Firestore document.
  late Map<String, dynamic> _data = Map<String, dynamic>.of(widget.property);

  bool _refreshFailed = false;
  bool _listingRemoved = false;

  // Device (used for favourites + reports + reviews, no sign-in needed)
  String _deviceId = '';

  // Favourites (tenant)
  bool _isFavourite = false;
  bool _checkingFavourite = true;
  bool _togglingFavourite = false;

  // Report (tenant)
  bool _reporting = false;

  // Download (admin)
  bool _downloading = false;

  // Owner contact
  bool _loadingOwner = true;
  bool _ownerLoadFailed = false;
  String _ownerName = '';
  String _ownerPhone = '';
  String _ownerWhatsapp = '';
  String _ownerEmail = '';

  // Reviews
  bool _loadingReviews = true;
  bool _reviewsFailed = false;
  bool _showAllReviews = false;
  bool _submittingReview = false;
  List<Map<String, dynamic>> _reviews = [];

  // Similar properties
  bool _loadingSimilar = true;
  bool _similarFailed = false;
  List<Map<String, dynamic>> _similar = [];
  String _similarKey = '';

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Map<String, dynamic> get _p => _data;

  String get _propertyId => _text(_p['id']);

  String get _ownerId {
    final fromProperty = _firstText(_p, [
      'ownerId',
      'ownerUid',
      'owner_id',
      'owner_uid',
      'landlordId',
      'uid',
      'userId',
      'user_id',
    ]);
    if (fromProperty.isNotEmpty) return fromProperty;

    final embedded = _embeddedOwner;
    return _firstText(embedded, ['uid', 'id', 'userId', 'user_id']);
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get _signedIn => _uid.isNotEmpty;

  bool get _isOwnerView =>
      !widget.isAdminView &&
          !widget.isTenantView &&
          (widget.isOwnerView ||
              (_uid.isNotEmpty && _ownerId.isNotEmpty && _ownerId == _uid));

  bool get _isTenantView =>
      !widget.isAdminView && (widget.isTenantView || (!_isOwnerView));

  /// The signed-in user is the owner of this listing (they must not
  /// review their own property).
  bool get _isOwnListing =>
      _signedIn && _ownerId.isNotEmpty && _ownerId == _uid;

  // ----------------------------------------------------------
  // SETTINGS HELPERS
  // ----------------------------------------------------------

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _brandDeep =>
      _isDark ? kBrandGreenOnDark : const Color(0xFF146C43);

  Color get _scaffold => _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _card => _isDark ? kDarkCard : Colors.white;

  Color get _cardBorder =>
      _isDark ? const Color(0xFF28352C) : const Color(0xFFE3ECE6);

  Color get _bodyText =>
      _isDark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);

  Color get _mutedText =>
      _isDark ? const Color(0xFFA9B8AF) : const Color(0xFF5B6B62);

  Color get _accentText =>
      _isDark ? Colors.blue.shade300 : Colors.blue.shade700;

  Color get _dangerText => _isDark ? Colors.red.shade300 : Colors.red.shade700;

  Color get _statSurface =>
      _isDark ? const Color(0xFF152219) : const Color(0xFFF1F8F4);

  Color get _adminSurface =>
      _isDark ? const Color(0xFF241F38) : const Color(0xFFEDE7F6);

  Color get _adminText =>
      _isDark ? const Color(0xFFC7B7F5) : const Color(0xFF5E35B1);

  Color get _verifySurface =>
      _isDark ? const Color(0xFF152533) : const Color(0xFFEAF5FF);

  Color get _safetySurface =>
      _isDark ? const Color(0xFF2A2412) : const Color(0xFFFFF8E1);

  Color get _safetyBorder =>
      _isDark ? const Color(0xFF5C4E1C) : const Color(0xFFFFE082);

  Color get _safetyAccent =>
      _isDark ? const Color(0xFFFFCA28) : const Color(0xFF8D6E00);

  Color get _dangerSurface =>
      _isDark ? const Color(0xFF3A1B1B) : const Color(0xFFFDECEC);

  Color get _starColor =>
      _isDark ? const Color(0xFFFFCA28) : const Color(0xFFF9A825);

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  // ----------------------------------------------------------
  // INIT
  // ----------------------------------------------------------

  @override
  void initState() {
    super.initState();

    if (_isTenantView) {
      _initTenant();
      _loadOwnerContact();
      _loadSimilar();
    } else if (widget.isAdminView) {
      _checkingFavourite = false;
      _loadOwnerContact();
    } else {
      _checkingFavourite = false;
      _loadingOwner = false;
    }

    _loadReviews();
    _refreshProperty();
  }

  Future<void> _initTenant() async {
    _deviceId = await DeviceIdService.get();
    await _loadFavouriteState();
    // Record that a tenant actually opened this listing.
    await _recordView();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // REFRESH PROPERTY FROM FIRESTORE
  // ----------------------------------------------------------

  Future<void> _refreshProperty() async {
    if (_propertyId.isEmpty) return;

    try {
      final doc = await _firestore.collection('properties').doc(_propertyId).get();

      if (!mounted) return;

      if (!doc.exists) {
        setState(() {
          _listingRemoved = true;
          _refreshFailed = false;
        });
        return;
      }

      final fresh = doc.data();

      if (fresh == null) return;

      final previousOwnerId = _ownerId;

      setState(() {
        // Keep the embedded `owner` map and the id from the search page.
        _data = {
          ..._data,
          ...fresh,
          'id': _propertyId,
        };
        _listingRemoved = false;
        _refreshFailed = false;
      });

      // Contact details may have changed on the listing.
      if ((_isTenantView || widget.isAdminView) &&
          (_ownerId != previousOwnerId || _hasContactFieldsOnListing())) {
        _loadOwnerContact();
      }

      // Opened from a link with only the id: the county / area are only
      // known now, so load the similar properties again.
      if (_isTenantView && _similarKeyNow() != _similarKey) {
        setState(() {
          _loadingSimilar = true;
          _similarFailed = false;
        });
        _loadSimilar();
      }
    } catch (e) {
      debugPrint('Property refresh failed: $e');
      if (!mounted) return;
      setState(() => _refreshFailed = true);
    }
  }

  bool _hasContactFieldsOnListing() => _firstText(_p, [
    'ownerPhone',
    'contactPhone',
    'landlordPhone',
    'ownerWhatsapp',
    'whatsapp',
  ]).isNotEmpty;

  Future<void> _refreshAll() async {
    // Changing the epoch gives every image a new key, so photos that
    // failed (or were cached badly) are downloaded again.
    if (mounted) setState(() => _imageEpoch++);

    await Future.wait([
      _refreshProperty(),
      _loadReviews(),
      if (_isTenantView) _loadSimilar(),
    ]);
  }

  // ----------------------------------------------------------
  // DATA HELPERS
  // ----------------------------------------------------------

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _text(data[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic> get _embeddedOwner {
    final owner = _p['owner'];
    if (owner is Map<String, dynamic>) return owner;
    return const {};
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];

    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<String> _imagesOf(Map<String, dynamic> map) {
    final urls = <String>[];

    for (final url in [
      ..._stringList(map['images']),
      ..._stringList(map['unitImages']),
      if (_text(map['mainImage']).isNotEmpty) _text(map['mainImage']),
      if (_text(map['image']).isNotEmpty) _text(map['image']),
    ]) {
      if (!urls.contains(url)) urls.add(url);
    }

    return urls;
  }

  List<String> _images() => _imagesOf(_p);

  List<String> _videos() => _stringList(_p['videos']);

  List<String> _amenities() {
    final value = _p['amenities'];

    if (value is List) return _stringList(value);

    return _text(value)
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _formatNumber(num value) {
    final isWhole = value == value.roundToDouble();
    final text = isWhole ? value.round().toString() : value.toStringAsFixed(2);
    final parts = text.split('.');

    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
    );

    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  String _formatDate(dynamic value) {
    if (value is! Timestamp) return '';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final date = value.toDate().toLocal();

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _title() {
    final title = _text(_p['title']);
    return title.isEmpty ? _tr('Property', 'Mali') : title;
  }

  String _locationOf(Map<String, dynamic> map) {
    final loc = map['location'];
    final saved = loc is String ? loc.trim() : '';

    if (saved.isNotEmpty) return saved;

    return [
      _text(map['area']),
      _text(map['subCounty']),
      _text(map['county']),
    ].where((item) => item.isNotEmpty).join(', ');
  }

  String _locationText() => _locationOf(_p);

  String _priceOf(Map<String, dynamic> map) {
    final display = _text(map['priceDisplay']);
    if (display.isNotEmpty) return display;

    final price = map['price'];

    if (price is num) {
      final isSale = _text(map['purpose']) == 'sale';

      var text = 'KES ${_formatNumber(price)}';

      if (!isSale) {
        text += _text(map['paymentCycle']) == 'per_semester'
            ? ' ${_tr('per semester', 'kwa muhula')}'
            : ' ${_tr('per month', 'kwa mwezi')}';
      }

      return text;
    }

    final asText = _text(price);

    return asText.isEmpty
        ? _tr('Price available on request', 'Bei inapatikana kwa ombi')
        : asText;
  }

  String _priceText() => _priceOf(_p);

  bool get _isVerified => _text(_p['property_status']) == 'verified';

  (String, Color, IconData) _statusInfo(String status) {
    switch (status) {
      case 'approved':
      case 'active':
        return (_tr('Active', 'Hai'), Colors.green, Icons.check_circle);
      case 'pending':
        return (_tr('Pending', 'Inasubiri'), Colors.orange, Icons.pending);
      case 'rejected':
        return (_tr('Rejected', 'Imekataliwa'), Colors.red, Icons.cancel);
      case 'rented':
        return (_tr('Rented', 'Imepangwa'), Colors.blue, Icons.key);
      case 'sold':
        return (_tr('Sold', 'Imeuzwa'), Colors.purple, Icons.sell);
      default:
        return (
        status.isEmpty ? _tr('Unknown', 'Haijulikani') : status,
        Colors.grey,
        Icons.info_outline,
        );
    }
  }

  (String, Color, IconData) _verificationInfo() {
    if (_isVerified) {
      return (_tr('Verified', 'Imethibitishwa'), _brand, Icons.verified);
    }

    if (_text(_p['status']) == 'rejected') {
      return (_tr('Rejected', 'Imekataliwa'), Colors.red, Icons.cancel);
    }

    return (
    _tr('Pending', 'Inasubiri'),
    Colors.orange,
    Icons.hourglass_top_rounded,
    );
  }

  List<(String, String)> _detailEntries({required bool extended}) {
    final isSale = _text(_p['purpose']) == 'sale';

    final entries = <(String, String)>[
      (
      _tr('Purpose', 'Madhumuni'),
      isSale ? _tr('For Sale', 'Ya Kuuza') : _tr('For Rent', 'Ya Kupangisha'),
      ),
      (_tr('Property type', 'Aina ya mali'), _text(_p['type'])),
      (_tr('Category', 'Kategoria'), _text(_p['category'])),
      (
      _tr('Accommodation type', 'Aina ya makazi'),
      _text(_p['accommodationType'] ?? _p['unitDetails']),
      ),
      (
      _tr('Number of units', 'Idadi ya vitengo'),
      _text(_p['numberOfUnits']),
      ),
      (_tr('Campus', 'Chuo'), _text(_p['campusName'])),
      (_tr('County', 'Kaunti'), _text(_p['county'])),
      (_tr('Sub-county', 'Kaunti ndogo'), _text(_p['subCounty'])),
      (_tr('Estate / Area', 'Mtaa / Eneo'), _text(_p['area'])),
      (_tr('Listed on', 'Imewekwa tarehe'), _formatDate(_p['createdAt'])),
    ];

    if (extended) {
      final (statusLabel, _, _) = _statusInfo(_text(_p['status']));
      final (verifyLabel, _, _) = _verificationInfo();

      final photos = _images().length;
      final videos = _videos().length;

      entries.addAll([
        (_tr('Listing status', 'Hali ya orodha'), statusLabel),
        (_tr('Verification', 'Uthibitisho'), verifyLabel),
        (_tr('Photos', 'Picha'), photos > 0 ? '$photos' : ''),
        (_tr('Videos', 'Video'), videos > 0 ? '$videos' : ''),
        (_tr('Last updated', 'Imesasishwa'), _formatDate(_p['updatedAt'])),
      ]);

      if (widget.isAdminView) {
        entries.add((_tr('Property ID', 'Kitambulisho cha mali'), _propertyId));
      }
    }

    return entries.where((entry) => entry.$2.isNotEmpty).toList();
  }

  // ----------------------------------------------------------
  // OWNER CONTACT
  // ----------------------------------------------------------

  Future<void> _loadOwnerContact() async {
    final admin = widget.isAdminView;

    var name = _firstText(_p, [
      'ownerName',
      'landlordName',
      'ownerFullName',
    ]);
    var phone = _firstText(_p, [
      'ownerPhone',
      'contactPhone',
      'landlordPhone',
      'phone',
      'phoneNumber',
      'mobile',
    ]);
    var whatsapp = _firstText(_p, [
      'ownerWhatsapp',
      'whatsapp',
      'whatsappNumber',
      'whatsapp_number',
      'waNumber',
    ]);
    var email = _firstText(_p, [
      'ownerEmail',
      'email',
      'contactEmail',
    ]);

    final embedded = _embeddedOwner;
    if (embedded.isNotEmpty) {
      if (name.isEmpty) {
        name = _firstText(embedded, [
          'fullName',
          'name',
          'displayName',
          'username',
        ]);
      }
      if (phone.isEmpty) {
        phone = _firstText(embedded, [
          'phone',
          'phoneNumber',
          'phone_number',
          'mobile',
        ]);
      }
      if (whatsapp.isEmpty) {
        whatsapp = _firstText(embedded, [
          'whatsapp',
          'whatsappNumber',
          'whatsapp_number',
          'waNumber',
        ]);
      }
      if (email.isEmpty) {
        email = _firstText(embedded, ['email']);
      }
    }

    final needsProfile = name.isEmpty ||
        phone.isEmpty ||
        (admin && (email.isEmpty || whatsapp.isEmpty));

    var failed = false;

    if (needsProfile && _ownerId.isNotEmpty) {
      try {
        final doc = await _firestore.collection('users').doc(_ownerId).get();
        final data = doc.data();

        if (data != null) {
          if (name.isEmpty) {
            name = _firstText(data, [
              'fullName',
              'name',
              'displayName',
              'username',
            ]);
          }
          if (phone.isEmpty) {
            phone = _firstText(data, [
              'phone',
              'phoneNumber',
              'phone_number',
              'mobile',
            ]);
          }
          if (whatsapp.isEmpty) {
            whatsapp = _firstText(data, [
              'whatsapp',
              'whatsappNumber',
              'whatsapp_number',
              'waNumber',
            ]);
          }
          if (email.isEmpty) {
            email = _firstText(data, ['email']);
          }
        }
      } catch (e) {
        failed = true;
        debugPrint(
          'Owner contact load FAILED for users/$_ownerId — check '
              'Firestore rules for the "users" collection. Error: $e',
        );
      }
    }

    if (!mounted) return;

    setState(() {
      _ownerName = name;
      _ownerPhone = phone;
      _ownerWhatsapp = whatsapp;
      _ownerEmail = email;
      _ownerLoadFailed = failed;
      _loadingOwner = false;
    });
  }

  String _normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return '';
    if (digits.startsWith('254')) return digits;
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length == 9) return '254$digits';

    return digits;
  }

  String get _whatsappDigits =>
      _normalizePhone(_ownerWhatsapp.isNotEmpty ? _ownerWhatsapp : _ownerPhone);

  String get _callDigits =>
      _normalizePhone(_ownerPhone.isNotEmpty ? _ownerPhone : _ownerWhatsapp);

  // ----------------------------------------------------------
  // CLICK LOGGING + VIEW TRACKING
  // ----------------------------------------------------------

  /// Returns true when the event was written.
  Future<bool> _logClick(String kind, {String? contactType}) async {
    if (_propertyId.isEmpty || !_isTenantView) return false;

    try {
      final deviceId =
      _deviceId.isNotEmpty ? _deviceId : await DeviceIdService.get();

      await _firestore.collection('property_views').add({
        'kind': kind,
        if (contactType != null) 'contactType': contactType,
        'propertyId': _propertyId,
        'deviceId': deviceId,
        'userId': _uid.isNotEmpty ? _uid : 'guest',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      // Non-critical: never block the user's action.
      debugPrint('Click log "$kind" failed (check property_views rules): $e');
      return false;
    }
  }

  /// Writes ONE `view` event when a tenant opens the listing. The same
  /// device is only counted again after [_viewThrottle], so refreshes
  /// and re-opening do not inflate the numbers.
  Future<void> _recordView() async {
    if (_propertyId.isEmpty) return;

    SharedPreferences? prefs;
    final key = 'last_view_$_propertyId';
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(key) ?? 0;

      if (now - last < _viewThrottle.inMilliseconds) return;
    } catch (_) {
      // Could not read the throttle: count the view anyway.
    }

    final written = await _logClick('view');

    if (written && prefs != null) {
      try {
        await prefs.setInt(key, now);
      } catch (_) {}
    }
  }

  // ----------------------------------------------------------
  // CONTACT ACTIONS
  // ----------------------------------------------------------

  Future<void> _openWhatsApp() async {
    final digits = _whatsappDigits;
    if (digits.isEmpty) return;

    _logClick('contact', contactType: 'whatsapp');

    final message = widget.isAdminView
        ? _tr(
      'Hello, this is the PropertyKonnect admin regarding your listing "${_title()}".',
      'Habari, huyu ni msimamizi wa PropertyKonnect kuhusu orodha yako "${_title()}".',
    )
        : _tr(
      'Hello, I am interested in your property "${_title()}" listed on PropertyKonnect.',
      'Habari, navutiwa na mali yako "${_title()}" iliyoorodheshwa kwenye PropertyKonnect.',
    );

    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
    );

    await _launch(uri);
  }

  Future<void> _callOwner() async {
    final digits = _callDigits;
    if (digits.isEmpty) return;

    _logClick('contact', contactType: 'phone');

    await _launch(Uri(scheme: 'tel', path: '+$digits'));
  }

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!ok) _showSnack(_cannotOpenMessage());
    } catch (_) {
      _showSnack(_cannotOpenMessage());
    }
  }

  String _cannotOpenMessage() => _tr(
    'Could not open this on your device.',
    'Imeshindikana kufungua hii kwenye kifaa chako.',
  );

  void _showSnack(
      String message, {
        String? actionLabel,
        VoidCallback? onAction,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(label: actionLabel, onPressed: onAction)
              : null,
        ),
      );
  }

  // ----------------------------------------------------------
  // GOOGLE MAPS
  // ----------------------------------------------------------

  double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// Finds coordinates on the listing under any common spelling.
  (double, double)? _coords() {
    bool valid(double? lat, double? lng) =>
        lat != null &&
            lng != null &&
            lat >= -90 &&
            lat <= 90 &&
            lng >= -180 &&
            lng <= 180 &&
            !(lat == 0 && lng == 0);

    for (final key in [
      'location',
      'geoPoint',
      'geopoint',
      'coordinates',
      'coords',
      'position',
      'latLng',
      'locationGeo',
      'gps',
    ]) {
      final v = _p[key];

      if (v is GeoPoint && valid(v.latitude, v.longitude)) {
        return (v.latitude, v.longitude);
      }

      if (v is Map) {
        final lat = _num(v['latitude'] ?? v['lat']);
        final lng = _num(v['longitude'] ?? v['lng'] ?? v['lon'] ?? v['long']);
        if (valid(lat, lng)) return (lat!, lng!);
      }
    }

    final lat = _num(_p['latitude'] ?? _p['lat']);
    final lng = _num(_p['longitude'] ?? _p['lng'] ?? _p['lon'] ?? _p['long']);

    if (valid(lat, lng)) return (lat!, lng!);

    return null;
  }

  bool get _canOpenMap => _coords() != null || _locationText().isNotEmpty;

  Uri _mapUri() {
    final coords = _coords();

    if (coords != null) {
      return Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${coords.$1},${coords.$2}',
      );
    }

    final query = Uri.encodeComponent('${_locationText()}, Kenya');

    return Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
  }

  Future<void> _openMap() async {
    _logClick('map_click');
    await _launch(_mapUri());
  }

  // ----------------------------------------------------------
  // SHARE
  // ----------------------------------------------------------

  String _buildShareText() {
    final b = StringBuffer();

    b.writeln(_title());
    b.writeln(_priceText());
    if (_locationText().isNotEmpty) b.writeln(_locationText());

    if (_canOpenMap) {
      b.writeln();
      b.writeln(_tr('Location on map:', 'Mahali kwenye ramani:'));
      b.writeln(_mapUri().toString());
    }

    if (_propertyId.isNotEmpty) {
      final hasMedia = _images().isNotEmpty || _videos().isNotEmpty;

      if (hasMedia) {
        b.writeln();
        b.writeln(
          _tr(
            'See all photos and videos:',
            'Tazama picha na video zote:',
          ),
        );
        b.writeln(PropertyLinks.media(_propertyId));
      }

      b.writeln();
      b.writeln(
        _tr(
          'Open this property in the app:',
          'Fungua mali hii kwenye programu:',
        ),
      );
      b.writeln(PropertyLinks.details(_propertyId));
    }

    b.writeln();
    b.write(
      _tr(
        'Found on PropertyKonnect.',
        'Imepatikana kwenye PropertyKonnect.',
      ),
    );

    return b.toString();
  }

  Future<void> _shareProperty() async {
    _logClick('share');

    try {
      await Share.share(_buildShareText(), subject: _title());
    } catch (_) {
      _showSnack(
        _tr(
          'Could not open the share menu.',
          'Imeshindikana kufungua menyu ya kushiriki.',
        ),
      );
    }
  }

  // ----------------------------------------------------------
  // FULL-SCREEN GALLERY + VIDEO PLAYER
  // ----------------------------------------------------------

  Future<void> _openFullScreenGallery(List<String> images, int index) async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenGallery(
          images: images,
          initialIndex: index,
          retryLabel: _tr('Tap to retry', 'Gusa kujaribu tena'),
          errorLabel: _tr('Could not load this photo', 'Imeshindikana kupakia picha hii'),
        ),
      ),
    );

    if (result != null && _pageController.hasClients) {
      _pageController.jumpToPage(result);
    }
  }

  // UPDATED: video_player does not work on Flutter web, so on the
  // web the video is opened in the browser instead.
  Future<void> _openVideo(String url, int number) async {
    if (kIsWeb) {
      await _launch(Uri.parse(url));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VideoPlayerPage(
          url: url,
          title: '${_tr('Video', 'Video')} $number',
          errorLabel: _tr(
            'This video could not be played.',
            'Video hii imeshindwa kuchezwa.',
          ),
          retryLabel: _tr('Retry', 'Jaribu tena'),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // FAVOURITES
  // ----------------------------------------------------------

  String get _favouriteDocId => '${_propertyId}_$_deviceId';

  Future<void> _loadFavouriteState() async {
    if (_propertyId.isEmpty || _deviceId.isEmpty) {
      if (mounted) setState(() => _checkingFavourite = false);
      return;
    }

    try {
      final doc =
      await _firestore.collection('favorites').doc(_favouriteDocId).get();

      if (mounted) {
        setState(() {
          _isFavourite = doc.exists;
          _checkingFavourite = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkingFavourite = false);
    }
  }

  Future<void> _toggleFavourite() async {
    if (_togglingFavourite || _propertyId.isEmpty) return;

    setState(() => _togglingFavourite = true);

    try {
      if (_deviceId.isEmpty) _deviceId = await DeviceIdService.get();

      final docRef = _firestore.collection('favorites').doc(_favouriteDocId);

      if (_isFavourite) {
        await docRef.delete();
        _logClick('favourite_remove');

        if (!mounted) return;

        setState(() => _isFavourite = false);
        FavouritesSignal.notify();
        _showSnack(
          _tr('Removed from favourites.', 'Imeondolewa kwa vipendwa.'),
        );
      } else {
        await docRef.set({
          'propertyId': _propertyId,
          'deviceId': _deviceId,
          'userId': _uid.isNotEmpty ? _uid : 'guest',
          'createdAt': FieldValue.serverTimestamp(),
        });
        _logClick('favourite_add');

        if (!mounted) return;

        setState(() => _isFavourite = true);
        FavouritesSignal.notify();
        _showSnack(
          _tr('Added to favourites.', 'Imeongezwa kwa vipendva.'),
        );
      }
    } catch (_) {
      _showSnack(
        _tr(
          'Could not update favourites.',
          'Imeshindikana kusasisha vipendva.',
        ),
        actionLabel: _tr('Retry', 'Jaribu tena'),
        onAction: _toggleFavourite,
      );
    } finally {
      if (mounted) setState(() => _togglingFavourite = false);
    }
  }

  // ----------------------------------------------------------
  // REVIEWS & RATINGS
  // ----------------------------------------------------------

  Map<String, dynamic>? get _myReview {
    if (_deviceId.isEmpty) return null;

    for (final r in _reviews) {
      if (_text(r['deviceId']) == _deviceId) return r;
    }

    return null;
  }

  double get _averageRating {
    if (_reviews.isEmpty) return 0;

    final total = _reviews.fold<double>(
      0,
          (sum, r) => sum + ((r['rating'] is num) ? (r['rating'] as num).toDouble() : 0),
    );

    return total / _reviews.length;
  }

  Future<void> _loadReviews() async {
    if (_propertyId.isEmpty) {
      if (mounted) setState(() => _loadingReviews = false);
      return;
    }

    try {
      if (_deviceId.isEmpty) _deviceId = await DeviceIdService.get();

      final snap = await _firestore
          .collection('reviews')
          .where('propertyId', isEqualTo: _propertyId)
          .limit(100)
          .get();

      final list = snap.docs.map((d) => {...d.data(), 'docId': d.id}).toList();

      // Newest first (sorted here so no composite index is needed).
      list.sort((a, b) {
        final ta = a['createdAt'];
        final tb = b['createdAt'];
        final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
        final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
        return mb.compareTo(ma);
      });

      if (!mounted) return;

      setState(() {
        _reviews = list;
        _reviewsFailed = false;
        _loadingReviews = false;
      });
    } catch (e) {
      debugPrint('Reviews load failed (check "reviews" rules): $e');
      if (!mounted) return;
      setState(() {
        _reviewsFailed = true;
        _loadingReviews = false;
      });
    }
  }

  void _retryReviews() {
    setState(() {
      _loadingReviews = true;
      _reviewsFailed = false;
    });
    _loadReviews();
  }

  Future<void> _openReviewDialog() async {
    if (_submittingReview || _propertyId.isEmpty) return;

    if (_deviceId.isEmpty) _deviceId = await DeviceIdService.get();

    final existing = _myReview;

    var rating = existing?['rating'] is num
        ? (existing!['rating'] as num).toInt().clamp(0, 5)
        : 0;

    final commentController =
    TextEditingController(text: _text(existing?['comment']));

    final user = FirebaseAuth.instance.currentUser;

    final nameController = TextEditingController(
      text: _text(existing?['reviewerName']).isNotEmpty
          ? _text(existing?['reviewerName'])
          : (user?.displayName ?? ''),
    );

    if (!mounted) return;

    final result = await showDialog<({int rating, String comment, String name})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              backgroundColor: _card,
              title: Text(
                existing == null
                    ? _tr('Rate this property', 'Kadiria mali hii')
                    : _tr('Edit your review', 'Hariri maoni yako'),
                style: TextStyle(color: _bodyText),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(
                        'Share your experience to help other tenants.',
                        'Shiriki uzoefu wako kuwasaidia wapangaji wengine.',
                      ),
                      style: TextStyle(color: _mutedText, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            iconSize: 36,
                            onPressed: () => setDialogState(() => rating = i),
                            icon: Icon(
                              i <= rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: _starColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: _tr(
                          'Your name (optional)',
                          'Jina lako (si lazima)',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: commentController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: _tr(
                          'Your experience (optional)',
                          'Uzoefu wako (si lazima)',
                        ),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_tr('Cancel', 'Ghairi')),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: rating == 0
                      ? null
                      : () {
                    Navigator.pop(dialogContext, (
                    rating: rating,
                    comment: commentController.text.trim(),
                    name: nameController.text.trim(),
                    ));
                  },
                  child: Text(_tr('Submit', 'Wasilisha')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    await _submitReview(result.rating, result.comment, result.name);
  }

  Future<void> _submitReview(int rating, String comment, String name) async {
    setState(() => _submittingReview = true);

    try {
      if (_deviceId.isEmpty) _deviceId = await DeviceIdService.get();

      final user = FirebaseAuth.instance.currentUser;

      await _firestore
          .collection('reviews')
          .doc('${_propertyId}_$_deviceId')
          .set({
        'propertyId': _propertyId,
        'propertyTitle': _title(),
        'ownerId': _ownerId,
        'rating': rating,
        'comment': comment,
        'reviewerName': name.isEmpty ? '' : name,
        'deviceId': _deviceId,
        'userId': user?.uid ?? 'guest',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _logClick('review');

      _showSnack(
        _tr('Thank you for your review.', 'Asante kwa maoni yako.'),
      );

      await _loadReviews();
    } catch (_) {
      _showSnack(
        _tr(
          'Could not submit your review.',
          'Imeshindikana kuwasilisha maoni yako.',
        ),
        actionLabel: _tr('Retry', 'Jaribu tena'),
        onAction: () => _submitReview(rating, comment, name),
      );
    } finally {
      if (mounted) setState(() => _submittingReview = false);
    }
  }

  Future<void> _deleteMyReview() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: Text(
          _tr('Delete your review?', 'Futa maoni yako?'),
          style: TextStyle(color: _bodyText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Delete', 'Futa')),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _firestore
          .collection('reviews')
          .doc('${_propertyId}_$_deviceId')
          .delete();

      await _loadReviews();
    } catch (_) {
      _showSnack(
        _tr('Could not delete your review.', 'Imeshindikana kufuta maoni yako.'),
        actionLabel: _tr('Retry', 'Jaribu tena'),
        onAction: _deleteMyReview,
      );
    }
  }

  // ----------------------------------------------------------
  // SIMILAR PROPERTIES
  // ----------------------------------------------------------

  String _similarKeyNow() => '${_text(_p['county'])}|${_text(_p['area'])}';

  Future<void> _loadSimilar() async {
    final county = _text(_p['county']);
    final area = _text(_p['area']);

    _similarKey = _similarKeyNow();

    if (_propertyId.isEmpty || (county.isEmpty && area.isEmpty)) {
      if (mounted) setState(() => _loadingSimilar = false);
      return;
    }

    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('properties')
          .where('property_status', isEqualTo: 'verified');

      query = county.isNotEmpty
          ? query.where('county', isEqualTo: county)
          : query.where('area', isEqualTo: area);

      final snap = await query.limit(40).get();

      const hidden = {'rented', 'sold', 'rejected', 'pending'};

      final scored = <(int, Map<String, dynamic>)>[];

      for (final doc in snap.docs) {
        if (doc.id == _propertyId) continue;

        final data = doc.data();

        if (hidden.contains(_text(data['status']))) continue;

        var score = 0;
        if (area.isNotEmpty && _text(data['area']) == area) score += 4;
        if (_text(_p['subCounty']).isNotEmpty &&
            _text(data['subCounty']) == _text(_p['subCounty'])) {
          score += 2;
        }
        if (_text(data['type']) == _text(_p['type'])) score += 2;
        if (_text(data['purpose']) == _text(_p['purpose'])) score += 1;

        scored.add((score, {...data, 'id': doc.id}));
      }

      scored.sort((a, b) => b.$1.compareTo(a.$1));

      if (!mounted) return;

      setState(() {
        _similar = scored.take(8).map((e) => e.$2).toList();
        _similarFailed = false;
        _loadingSimilar = false;
      });
    } catch (e) {
      debugPrint('Similar properties load failed: $e');
      if (!mounted) return;
      setState(() {
        _similarFailed = true;
        _loadingSimilar = false;
      });
    }
  }

  void _retrySimilar() {
    setState(() {
      _loadingSimilar = true;
      _similarFailed = false;
    });
    _loadSimilar();
  }

  void _openSimilar(Map<String, dynamic> property) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailsPage(
          property: property,
          isTenantView: true,
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // REPORT SUSPICIOUS LISTING
  //
  // UPDATED: saves to the shared `reports` collection in the same
  // shape as the rest of the app:
  //   doc id: property_<targetId>_<deviceId>
  //   kind: 'property', targetCollection: 'properties',
  //   targetId / targetName / targetOwnerId,
  //   reason / details, deviceId + reporterId (this device),
  //   status: 'open', createdAt.
  // One device can report a listing ONCE — the doc id dedupes.
  // ----------------------------------------------------------

  Future<void> _reportProperty() async {
    if (_reporting) return;

    _logClick('report_click');

    const reasons = <(String, String)>[
      ('Suspected scam', 'Inashukiwa kuwa ulaghai'),
      ('Asking for money before viewing', 'Wanaomba pesa kabla ya kutembelea'),
      ('Fake or misleading photos', 'Picha za uongo au zinazopotosha'),
      ('Wrong price or details', 'Bei au maelezo yasiyo sahihi'),
      ('Property already taken', 'Mali tayari imechukuliwa'),
      ('Other', 'Nyingine'),
    ];

    var selected = reasons.first.$1;

    final detailsController = TextEditingController();

    final result = await showDialog<({String reason, String details})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              backgroundColor: _card,
              title: Text(
                _tr('Report this listing?', 'Ripoti orodha hii?'),
                style: TextStyle(color: _bodyText),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(
                        'If this listing or its details look suspicious, tell us why so it can be reviewed.',
                        'Kama orodha hii au maelezo yake yanaonekana ya shaka, tuambie sababu ili ikaguliwe.',
                      ),
                      style: TextStyle(color: _mutedText, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: reasons.map((reason) {
                        final isSelected = selected == reason.$1;

                        return ChoiceChip(
                          label: Text(_tr(reason.$1, reason.$2)),
                          selected: isSelected,
                          showCheckmark: false,
                          selectedColor: _brand,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : _bodyText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) {
                            setDialogState(() => selected = reason.$1);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: detailsController,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: _tr(
                          'More details (optional)',
                          'Maelezo zaidi (si lazima)',
                        ),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_tr('Cancel', 'Ghairi')),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(dialogContext, (
                    reason: selected,
                    details: detailsController.text.trim(),
                    ));
                  },
                  child: Text(_tr('Report', 'Ripoti')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    await _submitReport(result.reason, result.details);
  }

  Future<void> _submitReport(String reason, String details) async {
    if (_propertyId.isEmpty) return;

    setState(() => _reporting = true);

    try {
      if (_deviceId.isEmpty) _deviceId = await DeviceIdService.get();

      // property_<targetId>_<deviceId> — one report per device.
      final docRef = _firestore
          .collection('reports')
          .doc('property_${_propertyId}_$_deviceId');

      try {
        final existing = await docRef.get();

        if (existing.exists) {
          _showSnack(
            _tr(
              'You have already reported this listing. Thank you.',
              'Umeshairipoti orodha hii. Asante.',
            ),
          );
          return;
        }
      } catch (_) {
        // Could not check: try to submit anyway.
      }

      await docRef.set({
        'kind': 'property',
        'targetCollection': 'properties',
        'targetId': _propertyId,
        'targetName': _title(),
        'targetOwnerId': _ownerId,
        'reason': reason,
        'details': details,
        'deviceId': _deviceId,
        'reporterId': _deviceId,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSnack(
        _tr(
          'Thank you. Your report has been submitted for review.',
          'Asante. Ripoti yako imewasilishwa kwa ukaguzi.',
        ),
      );
    } on FirebaseException catch (e) {
      _showSnack(
        e.code == 'permission-denied'
            ? _tr(
          'We could not submit your report. You may have already reported this listing.',
          'Hatukuweza kuwasilisha ripoti yako. Huenda umeshairipoti orodha hii.',
        )
            : _tr(
          'Could not submit your report. Please try again.',
          'Imeshindikana kuwasilisha ripoti. Tafadhali jaribu tena.',
        ),
      );
    } catch (_) {
      _showSnack(
        _tr(
          'Could not submit your report. Please try again.',
          'Imeshindikana kuwasilisha ripoti. Tafadhali jaribu tena.',
        ),
      );
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  // ----------------------------------------------------------
  // ADMIN: DOWNLOAD
  // ----------------------------------------------------------

  String _buildDownloadText() {
    final b = StringBuffer();

    b.writeln('PROPERTYKONNECT - PROPERTY DETAILS');
    b.writeln('=' * 40);
    b.writeln(_title());
    b.writeln('Price: ${_priceText()}');
    if (_locationText().isNotEmpty) b.writeln('Location: ${_locationText()}');
    final coords = _coords();
    if (coords != null) b.writeln('Coordinates: ${coords.$1}, ${coords.$2}');
    b.writeln();

    b.writeln('PROPERTY DETAILS');
    b.writeln('-' * 40);
    for (final entry in _detailEntries(extended: true)) {
      b.writeln('${entry.$1}: ${entry.$2}');
    }
    b.writeln();

    final amenities = _amenities();
    if (amenities.isNotEmpty) {
      b.writeln('AMENITIES');
      b.writeln('-' * 40);
      b.writeln(amenities.join(', '));
      b.writeln();
    }

    b.writeln('DESCRIPTION');
    b.writeln('-' * 40);
    final description = _text(_p['description']);
    b.writeln(description.isEmpty ? 'No description provided.' : description);
    b.writeln();

    b.writeln('OWNER DETAILS');
    b.writeln('-' * 40);
    b.writeln('Name: ${_ownerName.isEmpty ? '-' : _ownerName}');
    b.writeln('Phone: ${_ownerPhone.isEmpty ? '-' : _ownerPhone}');
    b.writeln('WhatsApp: ${_ownerWhatsapp.isEmpty ? '-' : _ownerWhatsapp}');
    b.writeln('Email: ${_ownerEmail.isEmpty ? '-' : _ownerEmail}');
    b.writeln('Owner ID: ${_ownerId.isEmpty ? '-' : _ownerId}');
    b.writeln();

    if (_propertyId.isNotEmpty) {
      b.writeln('LINKS');
      b.writeln('-' * 40);
      b.writeln('Property page: ${PropertyLinks.details(_propertyId)}');
      b.writeln('All photos and videos: ${PropertyLinks.media(_propertyId)}');
      b.writeln();
    }

    if (_reviews.isNotEmpty) {
      b.writeln('REVIEWS');
      b.writeln('-' * 40);
      b.writeln(
        'Average: ${_averageRating.toStringAsFixed(1)} / 5 (${_reviews.length} reviews)',
      );
      b.writeln();
    }

    final images = _images();
    final videos = _videos();

    if (images.isNotEmpty) {
      b.writeln('PHOTOS');
      b.writeln('-' * 40);
      for (var i = 0; i < images.length; i++) {
        b.writeln('${i + 1}. ${images[i]}');
      }
      b.writeln();
    }

    if (videos.isNotEmpty) {
      b.writeln('VIDEOS');
      b.writeln('-' * 40);
      for (var i = 0; i < videos.length; i++) {
        b.writeln('${i + 1}. ${videos[i]}');
      }
    }

    return b.toString();
  }

  Future<void> _saveDetailsFile() async {
    if (_downloading) return;

    setState(() => _downloading = true);

    try {
      final dir = await getTemporaryDirectory();

      final safeName = _title()
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');

      final file = File(
        '${dir.path}/${safeName.isEmpty ? 'property' : safeName}_details.txt',
      );

      await file.writeAsString(_buildDownloadText());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: _title(),
      );
    } catch (_) {
      _showSnack(
        _tr(
          'Could not create the download file.',
          'Imeshindikana kutengeneza faili la kupakua.',
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showDownloadSheet() {
    final images = _images();
    final videos = _videos();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('Download', 'Pakua'),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: _bodyText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _saveDetailsFile();
                      },
                      icon: const Icon(Icons.description_outlined),
                      label: Text(
                        _tr(
                          'Property + owner details (.txt)',
                          'Maelezo ya mali + mmiliki (.txt)',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (images.isNotEmpty || videos.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      _tr(
                        'Photos and videos (tap to open and save)',
                        'Picha na video (gusa kufungua na kuhifadhi)',
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _mutedText,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (var i = 0; i < images.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.image_outlined, color: _brand),
                      title: Text(
                        '${_tr('Photo', 'Picha')} ${i + 1}',
                        style: TextStyle(color: _bodyText),
                      ),
                      trailing: Icon(Icons.download_outlined, color: _brand),
                      onTap: () => _launch(Uri.parse(images[i])),
                    ),
                  for (var i = 0; i < videos.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.videocam_outlined, color: _brand),
                      title: Text(
                        '${_tr('Video', 'Video')} ${i + 1}',
                        style: TextStyle(color: _bodyText),
                      ),
                      trailing: Icon(Icons.download_outlined, color: _brand),
                      onTap: () => _launch(Uri.parse(videos[i])),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------
  // BUILD
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final admin = widget.isAdminView;
    final tenant = _isTenantView;

    final amenities = _amenities();
    final description = _text(_p['description']);
    final entries = _detailEntries(extended: !tenant);

    return Scaffold(
      backgroundColor: _scaffold,
      appBar: AppBar(
        title: Text(_tr('Property Details', 'Maelezo ya Mali')),
        actions: [
          IconButton(
            tooltip: _tr('Share', 'Shiriki'),
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareProperty,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _brand,
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _gallery(_images()),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (admin) ...[
                      _banner(
                        icon: Icons.admin_panel_settings_outlined,
                        background: _adminSurface,
                        color: _adminText,
                        text: _tr('Admin view', 'Mwonekano wa msimamizi'),
                        bold: true,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ---------------- REFRESH PROBLEMS ----------------
                    if (_listingRemoved) ...[
                      _banner(
                        icon: Icons.info_outline,
                        background: _dangerSurface,
                        color: _dangerText,
                        text: _tr(
                          'This listing is no longer available.',
                          'Orodha hii haipatikani tena.',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else if (_refreshFailed) ...[
                      _retryBanner(
                        _tr(
                          'Could not load the latest details. You may be seeing older information.',
                          'Imeshindikana kupakia maelezo mapya. Huenda unaona taarifa za zamani.',
                        ),
                        _refreshProperty,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ---------------- TITLE / LOCATION / PRICE ----------------
                    Text(
                      _title(),
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: _bodyText,
                      ),
                    ),
                    if (_locationText().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, color: _mutedText),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _locationText(),
                              style: TextStyle(color: _mutedText),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      _priceText(),
                      style: TextStyle(
                        color: _accentText,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_reviews.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _stars(_averageRating, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            '${_averageRating.toStringAsFixed(1)} (${_reviews.length})',
                            style: TextStyle(
                              color: _mutedText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ---------------- ACTIONS: MAP + SHARE ----------------
                    const SizedBox(height: 14),
                    _actionRow(),

                    // ---------------- OWNER / ADMIN: STATUS + COUNTS ----------------
                    if (!tenant) ..._ownerSection(),

                    // ---------------- TENANT: VERIFIED + FAVOURITE ----------------
                    if (tenant) ...[
                      if (_isVerified) ...[
                        const SizedBox(height: 16),
                        _banner(
                          icon: Icons.verified,
                          background: _verifySurface,
                          color: _accentText,
                          text: _tr(
                            'This listing has passed the verification stages required for public display.',
                            'Orodha hii imepita awamu za uthibitisho zinazohitajika ili ionekane kwa umma.',
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _favouriteButton(),
                    ],

                    // ---------------- DETAILS ----------------
                    const SizedBox(height: 24),
                    _sectionTitle(_tr('Property details', 'Maelezo ya mali')),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _cardBorder),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < entries.length; i++) ...[
                            _infoRow(entries[i].$1, entries[i].$2),
                            if (i != entries.length - 1)
                              Divider(height: 1, color: _cardBorder),
                          ],
                        ],
                      ),
                    ),

                    // ---------------- AMENITIES ----------------
                    if (amenities.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _sectionTitle(_tr('Amenities', 'Huduma')),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: amenities
                            .map(
                              (item) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _brand.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: 13,
                                color: _brand,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                            .toList(),
                      ),
                    ],

                    // ---------------- DESCRIPTION ----------------
                    const SizedBox(height: 22),
                    _sectionTitle(_tr('About this property', 'Kuhusu mali hii')),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _cardBorder),
                      ),
                      child: Text(
                        description.isEmpty
                            ? _tr(
                          'No description provided.',
                          'Hakuna maelezo yaliyowekwa.',
                        )
                            : description,
                        style: TextStyle(color: _mutedText, height: 1.6),
                      ),
                    ),

                    // ---------------- VIDEOS ----------------
                    if (_videos().isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _sectionTitle(_tr('Videos', 'Video')),
                      _videosStrip(),
                    ],

                    // ---------------- ADMIN: OWNER DETAILS + DOWNLOAD ----------------
                    if (admin) ...[
                      const SizedBox(height: 24),
                      _sectionTitle(
                        _tr('Listed by (owner details)',
                            'Imewekwa na (maelezo ya mmiliki)'),
                      ),
                      _adminOwnerCard(),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _downloading ? null : _showDownloadSheet,
                          icon: _downloading
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                            CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.download_outlined),
                          label: Text(
                            _tr('Download', 'Pakua'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _brand,
                            side: BorderSide(color: _brand),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],

                    // ---------------- TENANT: OWNER + SAFETY ----------------
                    if (tenant) ...[
                      const SizedBox(height: 24),
                      _sectionTitle(_tr('Property owner', 'Mmiliki wa mali')),
                      _ownerCard(),
                      const SizedBox(height: 24),
                      _safetyReminder(),
                    ],

                    // ---------------- REVIEWS (all views) ----------------
                    const SizedBox(height: 24),
                    _sectionTitle(
                      _tr('Reviews and ratings', 'Maoni na ukadiriaji'),
                    ),
                    _reviewsSection(),

                    // ---------------- SIMILAR + REPORT (tenant) ----------------
                    if (tenant) ...[
                      _similarSection(),
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton.icon(
                          onPressed: _reporting ? null : _reportProperty,
                          icon: Icon(Icons.flag_outlined, color: _dangerText),
                          label: Text(
                            _tr(
                              'Report suspicious listing',
                              'Ripoti orodha ya shaka',
                            ),
                            style: TextStyle(color: _dangerText),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // ACTION ROW (map + share)
  // ----------------------------------------------------------

  Widget _actionRow() {
    return Row(
      children: [
        if (_canOpenMap) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _openMap,
              icon: const Icon(Icons.map_outlined, size: 20),
              label: Text(
                _tr('View on map', 'Tazama ramani'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accentText,
                side: BorderSide(color: _accentText),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _shareProperty,
            icon: const Icon(Icons.share_outlined, size: 20),
            label: Text(
              _tr('Share', 'Shiriki'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brand,
              side: BorderSide(color: _brand),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // VIDEOS STRIP
  // ----------------------------------------------------------

  Widget _videosStrip() {
    final videos = _videos();

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openVideo(videos[i], i + 1),
            child: Container(
              width: 150,
              decoration: BoxDecoration(
                color: _isDark ? const Color(0xFF0F1A13) : const Color(0xFF1C2B24),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_tr('Video', 'Video')} ${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------
  // REVIEWS SECTION
  // ----------------------------------------------------------

  Widget _reviewsSection() {
    if (_loadingReviews) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(color: _brand),
      );
    }

    if (_reviewsFailed) {
      return _retryBanner(
        _tr(
          'Could not load reviews.',
          'Imeshindikana kupakia maoni.',
        ),
        _retryReviews,
      );
    }

    final canWrite = _isTenantView && !_isOwnListing;
    final mine = _myReview;
    final visible = _showAllReviews ? _reviews : _reviews.take(3).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_reviews.isEmpty)
            Text(
              _tr(
                'No reviews yet.',
                'Bado hakuna maoni.',
              ),
              style: TextStyle(color: _mutedText),
            )
          else ...[
            Row(
              children: [
                Text(
                  _averageRating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: _bodyText,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stars(_averageRating, size: 20),
                    const SizedBox(height: 2),
                    Text(
                      '${_reviews.length} ${_reviews.length == 1 ? _tr('review', 'maoni') : _tr('reviews', 'maoni')}',
                      style: TextStyle(fontSize: 12.5, color: _mutedText),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final review in visible) ...[
              Divider(height: 22, color: _cardBorder),
              _reviewTile(review),
            ],
            if (_reviews.length > 3)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      setState(() => _showAllReviews = !_showAllReviews),
                  child: Text(
                    _showAllReviews
                        ? _tr('Show fewer', 'Onyesha chache')
                        : _tr(
                      'Show all ${_reviews.length} reviews',
                      'Onyesha maoni yote ${_reviews.length}',
                    ),
                    style: TextStyle(color: _brand),
                  ),
                ),
              ),
          ],
          if (canWrite) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _submittingReview ? null : _openReviewDialog,
                icon: _submittingReview
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.rate_review_outlined, size: 20),
                label: Text(
                  mine == null
                      ? _tr('Write a review', 'Andika maoni')
                      : _tr('Edit your review', 'Hariri maoni yako'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: BorderSide(color: _brand),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewTile(Map<String, dynamic> review) {
    final rating = review['rating'] is num ? (review['rating'] as num).toDouble() : 0.0;
    final name = _text(review['reviewerName']);
    final comment = _text(review['comment']);
    final date = _formatDate(review['createdAt']);
    final isMine =
        _deviceId.isNotEmpty && _text(review['deviceId']) == _deviceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name.isEmpty ? _tr('Anonymous', 'Asiyejulikana') : name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _bodyText,
                ),
              ),
            ),
            if (date.isNotEmpty)
              Text(date, style: TextStyle(fontSize: 12, color: _mutedText)),
          ],
        ),
        const SizedBox(height: 3),
        _stars(rating, size: 16),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(comment, style: TextStyle(color: _mutedText, height: 1.5)),
        ],
        if (isMine && _isTenantView)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _deleteMyReview,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: _dangerText,
              ),
              child: Text(_tr('Delete', 'Futa')),
            ),
          ),
      ],
    );
  }

  Widget _stars(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : (rating >= i - 0.5
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded),
            size: size,
            color: _starColor,
          ),
      ],
    );
  }

  // ----------------------------------------------------------
  // SIMILAR PROPERTIES SECTION
  // ----------------------------------------------------------

  Widget _similarSection() {
    if (_loadingSimilar) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: LinearProgressIndicator(color: _brand),
      );
    }

    if (_similarFailed) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: _retryBanner(
          _tr(
            'Could not load similar properties.',
            'Imeshindikana kupakia mali zinazofanana.',
          ),
          _retrySimilar,
        ),
      );
    }

    if (_similar.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(_tr('Similar properties', 'Mali zinazofanana')),
          SizedBox(
            height: 236,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _similar.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _similarCard(_similar[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _similarCard(Map<String, dynamic> property) {
    final images = _imagesOf(property);
    final title = _text(property['title']);
    final location = _locationOf(property);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openSimilar(property),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: images.isEmpty
                  ? Container(
                color: _isDark
                    ? const Color(0xFF202B23)
                    : Colors.grey.shade200,
                child: Icon(Icons.image_outlined, color: _mutedText, size: 36),
              )
                  : _RetryImage(
                url: images.first,
                height: 120,
                compact: true,
                reloadToken: _imageEpoch,
                background:
                _isDark ? const Color(0xFF202B23) : Colors.grey.shade200,
                foreground: _mutedText,
                retryLabel: _tr('Retry', 'Jaribu tena'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? _tr('Property', 'Mali') : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _bodyText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _priceOf(property),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _accentText,
                      fontSize: 13.5,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: _mutedText),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // OWNER / ADMIN SECTION
  // ----------------------------------------------------------

  List<Widget> _ownerSection() {
    final status = _text(_p['status']);

    final (statusLabel, statusColor, statusIcon) = _statusInfo(status);
    final (verifyLabel, verifyColor, verifyIcon) = _verificationInfo();

    return [
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _pill(statusLabel, statusColor, statusIcon),
          _pill(verifyLabel, verifyColor, verifyIcon),
        ],
      ),
      if (status == 'pending') ...[
        const SizedBox(height: 14),
        _banner(
          icon: Icons.hourglass_top_rounded,
          background: _safetySurface,
          color: _safetyAccent,
          text: widget.isAdminView
              ? _tr(
            'This listing is waiting for admin review.',
            'Orodha hii inasubiri ukaguzi wa msimamizi.',
          )
              : _tr(
            'This listing is waiting for admin review. Tenants cannot see it until it is approved.',
            'Orodha hii inasubiri ukaguzi wa msimamizi. Wapangaji hawawezi kuiona hadi iidhinishwe.',
          ),
        ),
      ],
      if (status == 'rejected') ...[
        const SizedBox(height: 14),
        _banner(
          icon: Icons.cancel_outlined,
          background: _dangerSurface,
          color: _dangerText,
          text: widget.isAdminView
              ? _tr(
            'This listing was rejected.',
            'Orodha hii ilikataliwa.',
          )
              : _tr(
            'This listing was rejected, so tenants cannot see it. Review the details, correct them and submit it again.',
            'Orodha hii ilikataliwa, kwa hivyo wapangaji hawawezi kuiona. Kagua maelezo, yarekebishe na uiwasilishe tena.',
          ),
        ),
      ],
      const SizedBox(height: 22),
      _sectionTitle(_tr('Property analytics', 'Uchambuzi wa mali')),
      _statsRow(),
    ];
  }

  Widget _statsRow() {
    if (_propertyId.isEmpty) return const SizedBox.shrink();

    final admin = widget.isAdminView;

    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.visibility_outlined,
            label: _tr('Views', 'Mitazamo'),
            stream: _firestore
                .collection('property_views')
                .where('propertyId', isEqualTo: _propertyId)
                .where('kind', isEqualTo: 'view')
                .snapshots(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            icon: Icons.phone_in_talk_outlined,
            label: _tr('Contacts', 'Mawasiliano'),
            stream: _firestore
                .collection('property_views')
                .where('propertyId', isEqualTo: _propertyId)
                .where('kind', isEqualTo: 'contact')
                .snapshots(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            icon: Icons.favorite_outline,
            label: _tr('Favourites', 'Vipendva'),
            stream: _firestore
                .collection('favorites')
                .where('propertyId', isEqualTo: _propertyId)
                .snapshots(),
          ),
        ),
        if (admin) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              icon: Icons.flag_outlined,
              label: _tr('Reports', 'Ripoti'),
              stream: _firestore
                  .collection('reports')
                  .where('targetId', isEqualTo: _propertyId)
                  .snapshots(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _statSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          final failed = snapshot.hasError;
          final count = snapshot.data?.docs.length ?? 0;

          return Column(
            children: [
              Icon(icon, size: 20, color: _brandDeep),
              const SizedBox(height: 4),
              Text(
                failed ? '–' : '$count',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _brandDeep,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: _mutedText),
              ),
            ],
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------
  // TENANT: FAVOURITE BUTTON
  // ----------------------------------------------------------

  Widget _favouriteButton() {
    final label = _isFavourite
        ? _tr('Remove from favourites', 'Ondoa kwa vipendva')
        : _tr('Add to favourites', 'Ongeza kwa vipendva');

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed:
        (_checkingFavourite || _togglingFavourite) ? null : _toggleFavourite,
        style: OutlinedButton.styleFrom(
          foregroundColor: _brand,
          backgroundColor:
          _isFavourite ? _brand.withValues(alpha: 0.12) : null,
          side: BorderSide(color: _brand),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // CONTACT BUTTONS
  // ----------------------------------------------------------

  Widget _contactButtons() {
    final hasWhatsapp = _whatsappDigits.isNotEmpty;
    final hasCall = _callDigits.isNotEmpty;

    if (_loadingOwner) return LinearProgressIndicator(color: _brand);

    if (!hasWhatsapp && !hasCall) {
      if (_ownerLoadFailed) {
        return _retryBanner(
          _tr(
            'Could not load the owner’s contact details.',
            'Imeshindikana kupakia mawasiliano ya mmiliki.',
          ),
              () {
            setState(() {
              _loadingOwner = true;
              _ownerLoadFailed = false;
            });
            _loadOwnerContact();
          },
        );
      }

      return Text(
        _tr(
          'The owner has not added contact details for this listing yet.',
          'Mmiliki bado hajaweka mawasiliano kwa orodha hii.',
        ),
        style: TextStyle(color: _mutedText, height: 1.4),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: hasWhatsapp ? _openWhatsApp : null,
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1FA85A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: hasCall ? _callOwner : null,
            icon: const Icon(Icons.call_outlined),
            label: Text(_tr('Call', 'Piga simu')),
            style: FilledButton.styleFrom(
              backgroundColor:
              _isDark ? Colors.blue.shade400 : Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // TENANT: OWNER CARD
  // ----------------------------------------------------------

  Widget _ownerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _brand.withValues(alpha: 0.12),
                child: Icon(Icons.person_outline, color: _brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ownerName.isEmpty
                          ? _tr('Property owner', 'Mmiliki wa mali')
                          : _ownerName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _bodyText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr(
                        'Contact the owner directly',
                        'Wasiliana na mmiliki moja kwa moja',
                      ),
                      style: TextStyle(fontSize: 12.5, color: _mutedText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _contactButtons(),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // ADMIN: OWNER CARD
  // ----------------------------------------------------------

  Widget _adminOwnerCard() {
    final rows = <(String, String)>[
      (_tr('Name', 'Jina'), _ownerName),
      (_tr('Phone', 'Simu'), _ownerPhone),
      ('WhatsApp', _ownerWhatsapp),
      (_tr('Email', 'Barua pepe'), _ownerEmail),
      (_tr('Owner ID', 'Kitambulisho cha mmiliki'), _ownerId),
    ].where((row) => row.$2.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _adminText.withValues(alpha: 0.14),
                child: Icon(Icons.person_outline, color: _adminText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _ownerName.isEmpty
                      ? _tr('Property owner', 'Mmiliki wa mali')
                      : _ownerName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _bodyText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingOwner)
            LinearProgressIndicator(color: _brand)
          else if (rows.isNotEmpty) ...[
            for (var i = 0; i < rows.length; i++) ...[
              _infoRow(rows[i].$1, rows[i].$2),
              if (i != rows.length - 1) Divider(height: 1, color: _cardBorder),
            ],
          ],
          const SizedBox(height: 14),
          _contactButtons(),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // TENANT: SAFETY REMINDER
  // ----------------------------------------------------------

  Widget _safetyReminder() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _safetySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _safetyBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: _safetyAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr('Safety reminder', 'Kumbuka la usalama'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: _safetyAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _tr(
              'Before sending money, personally tour the property and make sure you are comfortable with the transaction and its details.',
              'Kabla ya kutuma pesa, tembelea mali mwenyewe na uhakikishe una raha na muamala na maelezo yake.',
            ),
            style: TextStyle(height: 1.5, color: _bodyText),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(
              'Never share your M-Pesa PIN, and do not pay a deposit to someone you have not met.',
              'Usishiriki PIN yako ya M-Pesa, na usilipe amana kwa mtu ambaye hujakutana naye.',
            ),
            style: TextStyle(height: 1.5, color: _bodyText),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // GALLERY (tap to open full screen)
  // ----------------------------------------------------------

  Widget _gallery(List<String> images) {
    if (images.isEmpty) return _placeholder();

    final index = _imageIndex.clamp(0, images.length - 1);

    return SizedBox(
      height: 270,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _imageIndex = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openFullScreenGallery(images, i),
              child: _RetryImage(
                url: images[i],
                height: 270,
                reloadToken: _imageEpoch,
                background:
                _isDark ? const Color(0xFF202B23) : Colors.grey.shade200,
                foreground: _mutedText,
                retryLabel: _tr('Tap to retry', 'Gusa kujaribu tena'),
                errorLabel: _tr(
                  'Could not load this photo',
                  'Imeshindikana kupakia picha hii',
                ),
              ),
            ),
          ),
          if (images.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _arrowButton(Icons.chevron_left, () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                }),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _arrowButton(Icons.chevron_right, () {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                }),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${index + 1}/${images.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
          Positioned(
            left: 12,
            bottom: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _arrowButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: double.infinity,
      height: 270,
      color: _isDark ? const Color(0xFF202B23) : Colors.grey.shade200,
      child: Center(
        child: Icon(Icons.image_outlined, size: 60, color: _mutedText),
      ),
    );
  }

  // ----------------------------------------------------------
  // SMALL WIDGETS
  // ----------------------------------------------------------

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
          color: _bodyText,
        ),
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required Color background,
    required Color color,
    required String text,
    bool bold = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: bold ? color : _bodyText,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A message with a Retry button, used for every failed request.
  Widget _retryBanner(String text, VoidCallback onRetry) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _dangerSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: _dangerText),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: _bodyText, height: 1.4),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              _tr('Retry', 'Jaribu tena'),
              style: TextStyle(
                color: _dangerText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: _mutedText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _bodyText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PROPERTY MEDIA PAGE
// Opened from the "See all photos and videos" link in a shared
// message (?media=<propertyId>). Shows every photo (tap for full
// screen) and every video (tap to play), and a button that opens
// the full property details page.
// ============================================================
class PropertyMediaPage extends StatefulWidget {
  final String propertyId;

  const PropertyMediaPage({super.key, required this.propertyId});

  @override
  State<PropertyMediaPage> createState() => _PropertyMediaPageState();
}

class _PropertyMediaPageState extends State<PropertyMediaPage> {
  bool _loading = true;
  bool _failed = false;
  bool _removed = false;
  int _epoch = 0;
  Map<String, dynamic> _data = {};

  bool get _isDark => AppSettings.of(context).isDark;
  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;
  Color get _scaffold => _isDark ? kPageBackgroundDark : kPageBackgroundLight;
  Color get _bodyText =>
      _isDark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);
  Color get _mutedText =>
      _isDark ? const Color(0xFFA9B8AF) : const Color(0xFF5B6B62);
  Color get _tileBackground =>
      _isDark ? const Color(0xFF202B23) : Colors.grey.shade200;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _epoch++;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .get();

      if (!mounted) return;

      if (!doc.exists || doc.data() == null) {
        setState(() {
          _removed = true;
          _loading = false;
        });
        return;
      }

      setState(() {
        _data = {...doc.data()!, 'id': doc.id};
        _removed = false;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Media page load failed: $e');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  List<String> _list(dynamic value) {
    if (value is! List) return [];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _images() {
    final urls = <String>[];

    for (final url in [
      ..._list(_data['images']),
      ..._list(_data['unitImages']),
      if ((_data['mainImage']?.toString().trim() ?? '').isNotEmpty)
        _data['mainImage'].toString().trim(),
      if ((_data['image']?.toString().trim() ?? '').isNotEmpty)
        _data['image'].toString().trim(),
    ]) {
      if (!urls.contains(url)) urls.add(url);
    }

    return urls;
  }

  List<String> _videos() => _list(_data['videos']);

  void _openPhoto(List<String> images, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenGallery(
          images: images,
          initialIndex: index,
          retryLabel: _tr('Tap to retry', 'Gusa kujaribu tena'),
          errorLabel: _tr(
            'Could not load this photo',
            'Imeshindikana kupakia picha hii',
          ),
        ),
      ),
    );
  }

  // UPDATED: video_player does not work on Flutter web, so on the
  // web the video is opened in the browser instead.
  void _openVideo(String url, int number) {
    if (kIsWeb) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VideoPlayerPage(
          url: url,
          title: '${_tr('Video', 'Video')} $number',
          errorLabel: _tr(
            'This video could not be played.',
            'Video hii imeshindwa kuchezwa.',
          ),
          retryLabel: _tr('Retry', 'Jaribu tena'),
        ),
      ),
    );
  }

  void _openDetails() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailsPage(
          property: {..._data, 'id': widget.propertyId},
          isTenantView: true,
        ),
      ),
    );
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.bold,
        color: _bodyText,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final images = _images();
    final videos = _videos();
    final title = (_data['title']?.toString().trim() ?? '');

    return Scaffold(
      backgroundColor: _scaffold,
      appBar: AppBar(
        title: Text(
          title.isEmpty ? _tr('Photos and videos', 'Picha na video') : title,
        ),
      ),
      body: RefreshIndicator(
        color: _brand,
        onRefresh: _load,
        child: _loading
            ? ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(color: _brand),
              ),
            ),
          ],
        )
            : (_failed || _removed)
            ? ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(30),
          children: [
            const SizedBox(height: 60),
            Icon(
              _removed ? Icons.info_outline : Icons.error_outline,
              size: 52,
              color: _mutedText,
            ),
            const SizedBox(height: 12),
            Text(
              _removed
                  ? _tr(
                'This listing is no longer available.',
                'Orodha hii haipatikani tena.',
              )
                  : _tr(
                'Could not load the photos and videos.',
                'Imeshindikana kupakia picha na video.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: _bodyText),
            ),
            if (_failed)
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_tr('Retry', 'Jaribu tena')),
              ),
          ],
        )
            : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openDetails,
                icon: const Icon(Icons.home_work_outlined),
                label: Text(
                  _tr(
                    'View full property details',
                    'Tazama maelezo kamili ya mali',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            // UPDATED: app download banner for users without the app.
            const SizedBox(height: 10),
            const AppDownloadBanner(),
            if (images.isEmpty && videos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text(
                  _tr(
                    'This listing has no photos or videos yet.',
                    'Orodha hii bado haina picha wala video.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _mutedText),
                ),
              ),
            if (images.isNotEmpty) ...[
              _title('${_tr('Photos', 'Picha')} (${images.length})'),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: images.length,
                gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openPhoto(images, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _RetryImage(
                      url: images[i],
                      height: double.infinity,
                      compact: true,
                      reloadToken: _epoch,
                      background: _tileBackground,
                      foreground: _mutedText,
                      retryLabel: _tr('Retry', 'Jaribu tena'),
                    ),
                  ),
                ),
              ),
            ],
            if (videos.isNotEmpty) ...[
              _title('${_tr('Videos', 'Video')} (${videos.length})'),
              for (var i = 0; i < videos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openVideo(videos[i], i + 1),
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        color: _isDark
                            ? const Color(0xFF0F1A13)
                            : const Color(0xFF1C2B24),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_tr('Video', 'Video')} ${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// RETRY IMAGE
// Network image with a loading spinner and a retry button when
// the download fails.
//
// WEB: Firebase Storage needs CORS rules for Flutter web to read
// image bytes. Until those are set, `WebHtmlElementStrategy.fallback`
// makes the browser load the image with its own <img> tag, which
// does not need CORS, so the photos still show.
//
// `reloadToken` changes on pull-to-refresh so the image is fetched
// again.
// ============================================================
class _RetryImage extends StatefulWidget {
  final String url;
  final double? height;
  final BoxFit fit;
  final bool compact;
  final Color background;
  final Color foreground;
  final String retryLabel;
  final String errorLabel;
  final int reloadToken;

  const _RetryImage({
    required this.url,
    required this.background,
    required this.foreground,
    required this.retryLabel,
    this.height,
    this.fit = BoxFit.cover,
    this.compact = false,
    this.errorLabel = '',
    this.reloadToken = 0,
  });

  @override
  State<_RetryImage> createState() => _RetryImageState();
}

class _RetryImageState extends State<_RetryImage> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.url,
      key: ValueKey('${widget.url}#$_attempt#${widget.reloadToken}'),
      width: double.infinity,
      height: widget.height,
      fit: widget.fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;

        final total = progress.expectedTotalBytes;

        return Container(
          color: widget.background,
          alignment: Alignment.center,
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: total != null ? progress.cumulativeBytesLoaded / total : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        return Container(
          width: double.infinity,
          height: widget.height,
          color: widget.background,
          alignment: Alignment.center,
          child: widget.compact
              ? IconButton(
            tooltip: widget.retryLabel,
            onPressed: () => setState(() => _attempt++),
            icon: Icon(Icons.refresh, color: widget.foreground),
          )
              : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  size: 44, color: widget.foreground),
              if (widget.errorLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.errorLabel,
                  style: TextStyle(color: widget.foreground, fontSize: 13),
                ),
              ],
              TextButton.icon(
                onPressed: () => setState(() => _attempt++),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(widget.retryLabel),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// FULL-SCREEN GALLERY
// Swipe between photos, pinch to zoom, double-tap to zoom in/out.
// Swiping is paused while a photo is zoomed so you can pan it.
// ============================================================
class _FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String retryLabel;
  final String errorLabel;

  const _FullScreenGallery({
    required this.images,
    required this.initialIndex,
    required this.retryLabel,
    required this.errorLabel,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _controller =
  PageController(initialPage: widget.initialIndex);

  late int _index = widget.initialIndex;
  bool _zoomed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_index);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_index + 1} / ${widget.images.length}'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(_index),
          ),
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          physics: _zoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          onPageChanged: (i) => setState(() {
            _index = i;
            _zoomed = false;
          }),
          itemBuilder: (_, i) => _ZoomableImage(
            url: widget.images[i],
            retryLabel: widget.retryLabel,
            errorLabel: widget.errorLabel,
            onZoomChanged: (zoomed) {
              if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
            },
          ),
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  final String url;
  final String retryLabel;
  final String errorLabel;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomableImage({
    required this.url,
    required this.retryLabel,
    required this.errorLabel,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _transform = TransformationController();
  Offset _doubleTapPosition = Offset.zero;
  int _attempt = 0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.01;

  void _toggleZoom() {
    if (_isZoomed) {
      _transform.value = Matrix4.identity();
      widget.onZoomChanged(false);
      return;
    }

    const scale = 2.5;
    final p = _doubleTapPosition;

    final m = Matrix4.diagonal3Values(scale, scale, 1);
    m.setTranslationRaw(-p.dx * (scale - 1), -p.dy * (scale - 1), 0);

    _transform.value = m;
    widget.onZoomChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapPosition = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        onInteractionEnd: (_) => widget.onZoomChanged(_isZoomed),
        child: Center(
          child: Image.network(
            widget.url,
            key: ValueKey('${widget.url}#$_attempt'),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;

              final total = progress.expectedTotalBytes;

              return Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  value: total != null
                      ? progress.cumulativeBytesLoaded / total
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stack) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 56,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.errorLabel,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _attempt++),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: Text(
                      widget.retryLabel,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// IN-APP VIDEO PLAYER
// Play / pause, scrub, mute, replay, buffering spinner and a
// retry button when the video fails to load.
// (Used on Android / iOS only; on the web, videos open in the
// browser instead — video_player does not support Flutter web.)
// ============================================================
class _VideoPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  final String errorLabel;
  final String retryLabel;

  const _VideoPlayerPage({
    required this.url,
    required this.title,
    required this.errorLabel,
    required this.retryLabel,
  });

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _error = false;
  bool _showControls = true;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final old = _controller;
    _controller = null;
    await old?.dispose();

    if (mounted) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;

    try {
      await controller.initialize();

      if (!mounted || _controller != controller) return;

      controller.addListener(_onTick);
      await controller.setVolume(_muted ? 0 : 1);
      await controller.play();

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Video failed to load: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _onTick() {
    if (!mounted) return;

    final c = _controller;

    if (c != null && c.value.hasError && !_error) {
      setState(() => _error = true);
      return;
    }

    setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;

    if (c.value.isPlaying) {
      await c.pause();
    } else {
      final v = c.value;

      if (v.duration > Duration.zero && v.position >= v.duration) {
        await c.seekTo(Duration.zero);
      }

      await c.play();
    }
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;

    _muted = !_muted;
    await c.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');

    return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final c = _controller;

    if (_error || c == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white70, size: 56),
            const SizedBox(height: 10),
            Text(
              widget.errorLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _init,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: Text(
                widget.retryLabel,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    final value = c.value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          if (value.isBuffering)
            const CircularProgressIndicator(color: Colors.white),
          if (_showControls) ...[
            IconButton(
              iconSize: 68,
              color: Colors.white,
              onPressed: _togglePlay,
              icon: Icon(
                value.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VideoProgressIndicator(
                      c,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _fmt(value.position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _fmt(value.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          color: Colors.white,
                          onPressed: _toggleMute,
                          icon: Icon(
                            _muted ? Icons.volume_off : Icons.volume_up,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}