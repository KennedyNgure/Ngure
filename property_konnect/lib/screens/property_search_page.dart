// ============================================================
// property_search_page.dart  (FULL UPDATED FILE)
// Verified owner+property listings only; ads-verified shown
// first; logs a view (per user) when a listing is opened.
// Search Assistant wizard collects purpose, type, location, and price
// order. Filters are applied only when the final search button is pressed.
//
// UPDATED (Material / ListTile fix):
//  - The Search Assistant card is a Container with a light-green
//    background (_brandSoft) and a 22 px border radius. The tiles
//    inside it (e.g. the SwitchListTile "within 15 km" option)
//    were painted UNDER that coloured Container, so their ink /
//    selected colours were hidden and corners were not clipped.
//    The content is now wrapped in:
//      Material(
//        color: Colors.transparent,
//        borderRadius: BorderRadius.circular(22),
//        clipBehavior: Clip.antiAlias,
//        child: ...
//      )
//    exactly like the recommended fix.
//
// UPDATED (Ranch / Land fix):
//  - CACHED FIRESTORE STREAM: the stream is created ONCE
//    (late final _propertiesStream). Before, build() created a
//    new stream on every setState, so every wizard tap (e.g.
//    selecting "Ranch") flashed the page blank / reloading.
//  - FIELD-NAME FIX: listings are saved with `subCounty`
//    (capital C) — the filter now reads BOTH `subcounty` and
//    `subCounty` (and `type` as well as `propertyType`).
//  - TOLERANT MATCHING: purpose accepts sale/sell/buy/for
//    sale; category falls back to `type`; subtype (e.g.
//    "Ranch") matches `subtype`, `type` or `propertyType`
//    case-insensitively, with a contains-fallback.
//
// UPDATED (error fix):
//  - PropertyDetailsPage takes a `property` map (with 'id'
//    inside it), not `propertyId`. The card now opens it with
//    PropertyDetailsPage(property: {...data, 'id': id}).
//
// UPDATED (wizard step fix):
//  - Selecting a property TYPE no longer jumps automatically
//    to the location step. The step only advances when the
//    Next button is clicked, and Next validates first.
//
// UPDATED (correct property details):
//  - The card reads the `availability` string saved on the
//    listing and shows an Available / Unavailable badge.
//
// UPDATED (hide unavailable listings):
//  - Listings whose availability resolves to "unavailable"
//    (string `availability` field, or boolean `available`
//    fallback) are now COMPLETELY HIDDEN from the results,
//    the same way deactivated listings are hidden.
//
// UPDATED (owner details from Firestore):
//  - The listing is linked to its owner by the owner's uid
//    (saved on the listing under `ownerId` / `ownerUid` /
//    `uid` / `userId`). When a listing card is tapped:
//      1. the owner's doc is fetched from the `users`
//         collection in Firestore,
//      2. the card's owner row shows the owner's name / phone
//         from that doc (FutureBuilder, cached per uid),
//      3. the whole owner map is passed INSIDE the property
//         map (key `owner`) to PropertyDetailsPage — the page
//         reads it with property['owner'] and can show the
//         owner's name, phone and email without re-fetching.
//    Owner docs that are deactivated / deleted are treated
//    as not found (null), so deactivated owners never appear.
//
// REQUIRED in pubspec.yaml (add if missing), then run
// `flutter pub get` and do a FULL RESTART (not hot reload):
//   http: ^1.2.0
// ============================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'app_settings.dart';
import 'data.dart';
import 'property_details_page.dart';
import 'registration_page.dart';

class PropertySearchPage extends StatefulWidget {
  final String? initialPurpose;
  final String? initialCategory;
  final String? initialSubtype;

  const PropertySearchPage({
    super.key,
    this.initialPurpose,
    this.initialCategory,
    this.initialSubtype,
  });

  @override
  State<PropertySearchPage> createState() => _PropertySearchPageState();
}

class _PropertySearchPageState extends State<PropertySearchPage> {
  late String selectedPurpose;

  // '' means "not chosen yet" — there is no "All" option any more.
  String selectedCategory = '';
  String selectedSubtype = '';
  String selectedCounty = '';
  String selectedSubcounty = '';

  // ------------------------------------------------------------
  // CACHED FIRESTORE STREAM — created ONCE. Never create a new
  // stream inside build(): every setState would restart the
  // snapshot and flash the page blank (this was the Ranch bug).
  // ------------------------------------------------------------
  static const int _initialBatchSize = 30;
  static const int _batchIncrement = 30;
  int _fetchLimit = _initialBatchSize;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _propertiesStream;

  Stream<QuerySnapshot<Map<String, dynamic>>> _createPropertiesStream() =>
      FirebaseFirestore.instance
          .collection('properties')
          .where('property_status', isEqualTo: 'verified')
          .limit(_fetchLimit)
          .snapshots();

  // ------------------------------------------------------------
  // OWNER CACHE — uid -> owner data fetched from `users`.
  // Avoids re-fetching the same owner doc for every card.
  // ------------------------------------------------------------
  final Map<String, Map<String, dynamic>?> _ownerCache = {};
  final Map<String, Future<Map<String, dynamic>?>> _ownerFutures = {};

  // ------------------------------------------------------------
  // WIZARD STATE
  // ------------------------------------------------------------

  int wizardStep = 0; // 0..3
  static const int wizardStepCount = 4;

  String selectedPriceOrder = 'none'; // none, lowest, highest
  bool onlyCoordinatesWithin15Km = false;

  // Snapshot of the last explicitly applied search. Draft edits above
  // never affect results until Find matching properties is pressed.
  String _appliedPurpose = '';
  String _appliedCategory = '';
  String _appliedSubtype = '';
  String _appliedCounty = '';
  String _appliedSubcounty = '';
  String _appliedPriceOrder = 'none';
  bool _appliedUseCurrentLocation = false;
  bool _appliedOnlyCoordinatesWithin15Km = false;
  double? _appliedLat;
  double? _appliedLng;

  // GPS "use current location"
  bool isLocating = false;
  bool useCurrentLocation = false;
  double? currentLat;
  double? currentLng;
  static const double nearRadiusKm = 15;

  // Reverse-geocoded details for the current location.
  String? gpsCounty;
  String? gpsSubcounty;
  String? gpsWard;
  String? gpsArea;
  bool isResolvingAddress = false;
  bool gpsFromNearest = false; // some details came from a nearby listing

  // Listings currently loaded (used for the nearest-listing fallback).
  List<Map<String, dynamic>> _knownProperties = [];

  bool wizardApplied = false;

  SettingsController get _settings => AppSettings.of(context);

  bool get _isDark => _settings.isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _brandDeep =>
      _isDark ? kBrandGreenOnDark : const Color(0xFF146C43);

  Color get _brandSoft =>
      _isDark ? const Color(0xFF152219) : const Color(0xFFEAF7EF);

  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) =>
      _settings.languageCode == 'sw' ? sw : en;

  @override
  void initState() {
    super.initState();
    _propertiesStream = _createPropertiesStream();

    selectedPurpose = widget.initialPurpose ?? 'Rent';

    final category = widget.initialCategory;
    if (category != null &&
        PropertyCategories.categoriesFor(selectedPurpose)
            .contains(category)) {
      selectedCategory = category;

      final subtype = widget.initialSubtype;
      if (subtype != null &&
          PropertyCategories.subtypesFor(selectedPurpose, category)
              .contains(subtype)) {
        selectedSubtype = subtype;
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _changePurpose(String purpose) {
    setState(() {
      selectedPurpose = purpose;
      selectedCategory = '';
      selectedSubtype = '';
      useCurrentLocation = false;
    });
  }

  void _changeCategory(String category) {
    setState(() {
      selectedCategory = category;
      selectedSubtype = '';
    });
  }

  void _changeCounty(String county) {
    setState(() {
      selectedCounty = county;
      selectedSubcounty = '';
      // Manual county selection overrides GPS mode.
      useCurrentLocation = false;
    });
  }

  // ------------------------------------------------------------
  // WIZARD — helpers
  // ------------------------------------------------------------

  String get _stepTitle {
    switch (wizardStep) {
      case 0:
        return _tr('What do you need?', 'Unahitaji nini?');
      case 1:
        return _tr('Type of property', 'Aina ya mali');
      case 2:
        return _tr('Where?', 'Wapi?');
      case 3:
        return _tr('Budget & size', 'Bajeti & ukubwa');
      default:
        return '';
    }
  }

  bool get _isLastStep => wizardStep == wizardStepCount - 1;

  // ------------------------------------------------------------
  // STEP VALIDATION — the wizard only advances when the Next
  // button is clicked, and only if the current step is complete.
  // ------------------------------------------------------------

  String? _stepValidationMessage() {
    switch (wizardStep) {
      case 1: // Type of property
        if (selectedCategory.isEmpty) {
          return _tr(
            'Please pick a property category first.',
            'Tafadhali chagua aina ya mali kwanza.',
          );
        }
        final subtypes = PropertyCategories.subtypesFor(
          selectedPurpose,
          selectedCategory,
        );
        if (subtypes.isNotEmpty && selectedSubtype.isEmpty) {
          return _tr(
            'Please choose which one exactly before continuing.',
            'Tafadhali chagua ni ipi hasa kabla ya kuendelea.',
          );
        }
        return null;
      default:
        return null;
    }
  }

  void _nextStep() {
    FocusScope.of(context).unfocus();

    final message = _stepValidationMessage();
    if (message != null) {
      _showSnack(message);
      return;
    }

    if (wizardStep < wizardStepCount - 1) {
      setState(() => wizardStep++);
    }
  }

  void _previousStep() {
    FocusScope.of(context).unfocus();
    if (wizardStep > 0) {
      setState(() => wizardStep--);
    }
  }

  void _resetWizard() {
    setState(() {
      wizardStep = 0;
      selectedPriceOrder = 'none';
      onlyCoordinatesWithin15Km = false;
      useCurrentLocation = false;
      currentLat = null;
      currentLng = null;
      gpsCounty = null;
      gpsSubcounty = null;
      gpsWard = null;
      gpsArea = null;
      isResolvingAddress = false;
      gpsFromNearest = false;
      selectedCounty = '';
      selectedSubcounty = '';
      selectedCategory = '';
      selectedSubtype = '';
      wizardApplied = false;
      _appliedPurpose = '';
      _appliedCategory = '';
      _appliedSubtype = '';
      _appliedCounty = '';
      _appliedSubcounty = '';
      _appliedPriceOrder = 'none';
      _appliedUseCurrentLocation = false;
      _appliedOnlyCoordinatesWithin15Km = false;
      _appliedLat = null;
      _appliedLng = null;
    });
  }

  // ------------------------------------------------------------
  // GPS — use current location + reverse geocoding for
  // county / subcounty / ward / area details.
  // ------------------------------------------------------------

  Future<void> _useCurrentLocation() async {
    setState(() => isLocating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack(_tr('Please enable location services.',
            'Tafadhali washa huduma za eneo.'));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack(_tr(
            'Location permission denied. Pick a county instead.',
            'Ruhusa ya eneo imekataliwa. Chagua kaunti badala yake.'));
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (!mounted) return;

      setState(() {
        currentLat = position.latitude;
        currentLng = position.longitude;
        useCurrentLocation = true;
        // GPS overrides manual selection.
        selectedCounty = '';
        selectedSubcounty = '';
        gpsCounty = null;
        gpsSubcounty = null;
        gpsWard = null;
        gpsArea = null;
      });

      _showSnack(_tr(
          'Using your current location.', 'Tunatumia eneo lako la sasa.'));

      // Resolve the address details (awaited so the spinner and
      // the final details are always consistent).
      await _resolveCurrentAddress();
    } catch (_) {
      _showSnack(_tr(
          'Unable to get your location.', 'Imeshindikana kupata eneo lako.'));
    } finally {
      if (mounted) {
        setState(() => isLocating = false);
      }
    }
  }

  /// Reverse-geocode the current coordinates into county,
  /// subcounty, ward and area.
  void _cancelCurrentLocation() {
    setState(() {
      useCurrentLocation = false;
      currentLat = null;
      currentLng = null;
      gpsCounty = null;
      gpsSubcounty = null;
      gpsWard = null;
      gpsArea = null;
      gpsFromNearest = false;
      isResolvingAddress = false;
      onlyCoordinatesWithin15Km = false;
    });
    _showSnack(_tr(
      'Current location cancelled. Pick a county or area instead.',
      'Matumizi ya eneo la sasa yameghairiwa. Chagua kaunti au eneo mwenyewe.',
    ));
  }

  Future<void> _resolveCurrentAddress() async {
    final lat = currentLat;
    final lng = currentLng;
    if (lat == null || lng == null) return;

    setState(() {
      isResolvingAddress = true;
      gpsFromNearest = false;
    });

    var address = await _lookupAddress(lat, lng);
    address = _applyOfficialNames(address);

    // Last resort: borrow what is still missing from the nearest
    // verified listing (within 30 km).
    var usedNearest = false;
    if (!address.isComplete) {
      final nearest = _nearestListingAddress(lat, lng);
      if (nearest != null) {
        final merged = address.merge(nearest);
        usedNearest = merged.signature != address.signature;
        address = _applyOfficialNames(merged);
      }
    }

    if (!mounted) return;

    setState(() {
      gpsCounty = address.county;
      gpsSubcounty = address.subcounty;
      gpsWard = address.ward;
      gpsArea = address.area;
      gpsFromNearest = usedNearest;
      isResolvingAddress = false;
    });
  }

  /// Asks the online services, most detailed first, and merges what
  /// each one returns until every field is filled.
  Future<_GpsAddress> _lookupAddress(double lat, double lng) async {
    var result = const _GpsAddress();

    // Nominatim: exact spot first, then the nearest named place.
    for (final zoom in const [18, 14]) {
      if (zoom != 18) {
        // Nominatim fair-use: at most about 1 request per second.
        await Future.delayed(const Duration(milliseconds: 1100));
      }

      final found = await _reverseWithNominatim(lat, lng, zoom: zoom);
      if (found != null) result = result.merge(found);
      if (result.isComplete) return result;
    }

    // Second provider for anything still missing.
    final backup = await _reverseWithBigDataCloud(lat, lng);
    if (backup != null) result = result.merge(backup);

    return result;
  }

  /// OpenStreetMap Nominatim. On Android/iOS a descriptive
  /// User-Agent is REQUIRED; browsers set their own.
  Future<_GpsAddress?> _reverseWithNominatim(
      double lat,
      double lng, {
        required int zoom,
      }) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'zoom': zoom.toString(),
        'addressdetails': '1',
        'accept-language': 'en',
      });

      final response = await http.get(
        uri,
        headers: {
          if (!kIsWeb) 'User-Agent': 'PropertyKonnect/1.0 (Flutter app)',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      final raw = decoded['address'];
      if (raw is! Map) return null;
      final a = raw.map((k, v) => MapEntry(k.toString(), v?.toString()));

      String? pick(List<String> keys) {
        for (final key in keys) {
          final value = _nonEmpty(a[key]);
          if (value != null) return value;
        }
        return null;
      }

      return _GpsAddress(
        // In Kenya, OSM "state" is usually "<Name> County".
        county: _cleanName(pick(['state', 'region'])),
        // OSM "county" is usually the sub-county in Kenya.
        subcounty: _cleanName(
          pick(['county', 'state_district', 'city_district', 'city', 'town']),
        ),
        ward: pick(['suburb', 'village', 'town', 'city_district', 'quarter']),
        area: pick([
          'neighbourhood',
          'hamlet',
          'road',
          'residential',
          'amenity',
          'building',
          'locality',
        ]),
      );
    } catch (_) {
      return null;
    }
  }

  /// BigDataCloud free client-side reverse geocoding (no key).
  Future<_GpsAddress?> _reverseWithBigDataCloud(double lat, double lng) async {
    try {
      final uri = Uri.https(
        'api.bigdatacloud.net',
        '/data/reverse-geocode-client',
        {
          'latitude': lat.toString(),
          'longitude': lng.toString(),
          'localityLanguage': 'en',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      // Administrative areas below county level, from large to small.
      final below = <MapEntry<int, String>>[];
      final info = decoded['localityInfo'];
      if (info is Map && info['administrative'] is List) {
        for (final entry in info['administrative'] as List) {
          if (entry is! Map) continue;
          final level = int.tryParse(entry['adminLevel']?.toString() ?? '');
          final name = _nonEmpty(entry['name']?.toString());
          if (level != null && name != null && level > 4) {
            below.add(MapEntry(level, name));
          }
        }
        below.sort((a, b) => a.key.compareTo(b.key));
      }

      return _GpsAddress(
        county: _cleanName(
            _nonEmpty(decoded['principalSubdivision']?.toString())),
        subcounty: _cleanName(below.isNotEmpty ? below[0].value : null),
        ward: _cleanName(below.length > 1 ? below[1].value : null),
        area: _nonEmpty(decoded['locality']?.toString()) ??
            _nonEmpty(decoded['city']?.toString()),
      );
    } catch (_) {
      return null;
    }
  }

  // ---- Official Kenya names (from data.dart) ----

  String? _officialCounty(String? name) {
    if (name == null) return null;
    final lower = name.toLowerCase();

    for (final county in KenyaLocation.counties) {
      if (county.toLowerCase() == lower) return county;
    }
    for (final county in KenyaLocation.counties) {
      final c = county.toLowerCase();
      if (lower.contains(c) || c.contains(lower)) return county;
    }
    return name;
  }

  String? _countyOfSubcounty(String subcounty) {
    final lower = subcounty.toLowerCase();

    for (final county in KenyaLocation.counties) {
      for (final s in KenyaLocation.subcountiesOf(county)) {
        if (s.toLowerCase() == lower) return county;
      }
    }
    return null;
  }

  String _officialSubcounty(String county, String subcounty) {
    final lower = subcounty.toLowerCase();
    final options = KenyaLocation.subcountiesOf(county);

    for (final s in options) {
      if (s.toLowerCase() == lower) return s;
    }
    for (final s in options) {
      final o = s.toLowerCase();
      if (o.length >= 4 && (lower.contains(o) || o.contains(lower))) return s;
    }
    return subcounty;
  }

  _GpsAddress _applyOfficialNames(_GpsAddress a) {
    var county = _officialCounty(a.county);
    var subcounty = a.subcounty;

    county ??= subcounty == null ? null : _countyOfSubcounty(subcounty);

    if (county != null && subcounty != null) {
      subcounty = _officialSubcounty(county, subcounty);
    }

    return _GpsAddress(
      county: county,
      subcounty: subcounty,
      ward: a.ward,
      area: a.area,
    );
  }

  /// Details of the closest verified listing (within 30 km) that
  /// has map coordinates.
  _GpsAddress? _nearestListingAddress(double lat, double lng) {
    Map<String, dynamic>? best;
    var bestMeters = double.infinity;

    for (final data in _knownProperties) {
      final pLat = double.tryParse(data['latitude']?.toString() ?? '');
      final pLng = double.tryParse(data['longitude']?.toString() ?? '');
      if (pLat == null || pLng == null) continue;

      final meters = Geolocator.distanceBetween(lat, lng, pLat, pLng);
      if (meters < bestMeters) {
        bestMeters = meters;
        best = data;
      }
    }

    if (best == null || bestMeters > 30000) return null;

    return _GpsAddress(
      county: _cleanName(_nonEmpty(best['county']?.toString())),
      subcounty: _cleanName(_nonEmpty(
          best['subCounty']?.toString() ?? best['subcounty']?.toString())),
      ward: _nonEmpty(best['ward']?.toString()),
      area: _nonEmpty(best['location']?.toString()),
    );
  }

  /// "Kisumu County" -> "Kisumu", "Kisumu West Sub-county" ->
  /// "Kisumu West".
  String? _cleanName(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceAll(
      RegExp(r'\s+(sub[\s-]?county|county|ward)$', caseSensitive: false),
      '',
    )
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  // ------------------------------------------------------------
  // PARSING HELPERS — price / bedrooms / coordinates
  // ------------------------------------------------------------

  double? _parsePrice(dynamic value) {
    if (value == null) return null;

    if (value is num) return value.toDouble();

    // Strip "KES", commas, spaces etc. from string prices.
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty || cleaned == '.') return null;

    return double.tryParse(cleaned);
  }

  double? _distanceKm(Map<String, dynamic> data) {
    final lat = double.tryParse(data['latitude']?.toString() ?? '');
    final lng = double.tryParse(data['longitude']?.toString() ?? '');

    if (lat == null ||
        lng == null ||
        currentLat == null ||
        currentLng == null) {
      return null;
    }

    return Geolocator.distanceBetween(
      currentLat!,
      currentLng!,
      lat,
      lng,
    ) /
        1000.0;
  }

  // ------------------------------------------------------------
  // WIZARD — APPLY (Find matching properties)
  // ------------------------------------------------------------

  void _applyWizard() {
    FocusScope.of(context).unfocus();
    setState(() {
      _appliedPurpose = selectedPurpose;
      _appliedCategory = selectedCategory;
      _appliedSubtype = selectedSubtype;
      _appliedCounty = selectedCounty;
      _appliedSubcounty = selectedSubcounty;
      _appliedPriceOrder = selectedPriceOrder;
      _appliedUseCurrentLocation = useCurrentLocation;
      _appliedOnlyCoordinatesWithin15Km =
          useCurrentLocation && onlyCoordinatesWithin15Km;
      _appliedLat = currentLat;
      _appliedLng = currentLng;
      wizardApplied = true;
    });

    _showSnack(
      _tr('Applying your search answers...',
          'Ninaweka majibu yako ya utafutaji...'),
    );
  }

  String get _wizardSummary {
    final parts = <String>[];
    final purpose = wizardApplied ? _appliedPurpose : selectedPurpose;
    final category = wizardApplied ? _appliedCategory : selectedCategory;
    final subtype = wizardApplied ? _appliedSubtype : selectedSubtype;
    final county = wizardApplied ? _appliedCounty : selectedCounty;
    final subcounty = wizardApplied ? _appliedSubcounty : selectedSubcounty;
    final gpsActive = wizardApplied ? _appliedUseCurrentLocation : useCurrentLocation;
    final priceOrder = wizardApplied ? _appliedPriceOrder : selectedPriceOrder;
    final strictRadius = wizardApplied
        ? _appliedOnlyCoordinatesWithin15Km
        : onlyCoordinatesWithin15Km;

    parts.add(purpose == 'Rent'
        ? _tr('For rent', 'Kupanga')
        : _tr('For sale', 'Kuuza'));

    if (category.isNotEmpty) parts.add(category);
    if (subtype.isNotEmpty) parts.add(subtype);

    if (gpsActive) {
      final place = [
        ?gpsArea,
        ?gpsWard,
        ?gpsSubcounty,
        ?gpsCounty,
      ].join(', ');
      parts.add(place.isEmpty ? _tr('Near me', 'Karibu nami') : place);
    } else {
      if (county.isNotEmpty) parts.add(county);
      if (subcounty.isNotEmpty) parts.add(subcounty);
    }

    if (priceOrder == 'lowest') {
      parts.add(_tr('Lowest price first', 'Bei ya chini kwanza'));
    } else if (priceOrder == 'highest') {
      parts.add(_tr('Highest price first', 'Bei ya juu kwanza'));
    }
    if (gpsActive && strictRadius) {
      parts.add(_tr('Coordinates within 15 km', 'Viungo vya eneo ndani ya km 15'));
    }

    return parts.join(' · ');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ------------------------------------------------------------
  // DEACTIVATED / UNAVAILABLE PROPERTY DETECTION
  // ------------------------------------------------------------

  static const Set<String> _inactiveStatuses = {
    'deactivated',
    'inactive',
    'deleted',
    'disabled',
  };

  bool _isDeactivatedProperty(Map<String, dynamic> data) {
    if (data['isDeactivated'] == true) return true;
    if (data['isDeleted'] == true || data['deleted'] == true) return true;
    if (data['deactivatedAt'] != null) return true;
    if (data['isActive'] == false) return true;

    final status = data['status']?.toString().toLowerCase();
    if (status != null && _inactiveStatuses.contains(status)) return true;

    final propertyStatus = data['property_status']?.toString().toLowerCase();
    if (propertyStatus != null && _inactiveStatuses.contains(propertyStatus)) {
      return true;
    }

    return false;
  }

  /// NEW: unavailable listings are hidden completely — the same
  /// as deactivated ones. Availability comes from the saved
  /// `availability` string ("available" / "unavailable") with a
  /// boolean `available` fallback. A missing field means we
  /// keep showing the listing (never hide on missing data).
  bool _isUnavailableProperty(Map<String, dynamic> data) {
    return _availabilityOf(data) == 'unavailable';
  }

  bool _isAdsVerified(Map<String, dynamic> data) {
    // Ads verification is time-boxed.
    if (data['adsverification'] != true &&
        data['adsVerification'] != 'verified') {
      return false;
    }

    final now = DateTime.now();

    final start = _asDateTime(data['adsStart']);
    final stop = _asDateTime(data['adsStop']);

    if (stop != null && now.isAfter(stop)) return false;
    if (start != null && now.isBefore(start)) return false;

    return true;
  }

  DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  // ------------------------------------------------------------
  // VIEW LOGGING — one doc per property + user (no double count)
  // ------------------------------------------------------------

  Future<void> _logView(String propertyId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || propertyId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('property_views')
          .doc('${propertyId}_view_$uid')
          .set({
        'kind': 'view',
        'propertyId': propertyId,
        'userId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Already counted for this user — ignore.
    }
  }

  // ------------------------------------------------------------
  // TOLERANT FIELD READERS
  // ------------------------------------------------------------

  String _fieldOf(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _nonEmpty(data[key]?.toString());
      if (value != null) return value;
    }
    return '';
  }

  String _purposeOf(Map<String, dynamic> data) =>
      _fieldOf(data, ['purpose', 'listingPurpose', 'intent']).toLowerCase();

  String _categoryOf(Map<String, dynamic> data) =>
      _fieldOf(data, ['category', 'type', 'propertyType', 'property_type']);

  String _typeOf(Map<String, dynamic> data) =>
      _fieldOf(data, ['subtype', 'type', 'propertyType', 'property_type',
        'unitType', 'accommodationType']);

  String _subcountyOf(Map<String, dynamic> data) =>
      _fieldOf(data, ['subCounty', 'subcounty', 'sub_county',
        'subCountyName']);

  String _countyOf(Map<String, dynamic> data) =>
      _fieldOf(data, ['county', 'countyName']);

  String _locationOf(Map<String, dynamic> data) =>
      _fieldOf(data, ['location', 'area', 'town', 'estate']);

  /// The saved `availability` string lowercased, or '' when not
  /// saved. Falls back to the boolean `available` field.
  String _availabilityOf(Map<String, dynamic> data) {
    final saved = _fieldOf(data, ['availability', 'availabilityStatus'])
        .toLowerCase();

    if (saved == 'available' || saved == 'unavailable') return saved;

    if (data['available'] == true) return 'available';
    if (data['available'] == false) return 'unavailable';

    return saved; // '' or a custom value
  }

  // ------------------------------------------------------------
  // OWNER LINKING — the uid of the user who owns the listing.
  // Read every spelling a flow might have saved.
  // ------------------------------------------------------------

  String _ownerIdOf(Map<String, dynamic> data) =>
      _fieldOf(data, [
        'ownerId',
        'ownerUid',
        'owner_id',
        'owner_uid',
        'owner',
        'uid',
        'userId',
        'user_id',
        'landlordId',
      ]);

  /// Fetches the owner's doc from the `users` collection by uid.
  /// Results are cached per uid (also the in-flight future, so
  /// many cards of the same owner share ONE Firestore read).
  /// Deactivated / deleted owners resolve to null.
  Future<Map<String, dynamic>?> _ownerFuture(String ownerId) {
    if (_ownerCache.containsKey(ownerId)) {
      return Future.value(_ownerCache[ownerId]);
    }
    return _ownerFutures.putIfAbsent(ownerId, () async {
      Map<String, dynamic>? result;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .get();

        if (doc.exists) {
          final data = doc.data()!;
          final accountStatus =
              data['accountStatus']?.toString().toLowerCase() ?? '';
          final userStatus =
              data['status']?.toString().toLowerCase() ?? '';

          final deactivated = data['isDeactivated'] == true ||
              data['isActive'] == false ||
              accountStatus == 'deactivated' ||
              accountStatus == 'deleted' ||
              userStatus == 'deactivated' ||
              userStatus == 'deleted';

          result = deactivated ? null : {...data, 'id': doc.id};
        }
      } catch (_) {
        result = null;
      }
      _ownerCache[ownerId] = result;
      return result;
    });
  }

  String _ownerNameOf(Map<String, dynamic> owner) =>
      _fieldOf(owner, ['name', 'fullName', 'displayName', 'username']);

  String _ownerPhoneOf(Map<String, dynamic> owner) =>
      _fieldOf(owner, ['phone', 'phoneNumber', 'mobile', 'telephone']);

  // (Owner email can be read on the details page from
  //  property['owner']['email'].)

  // ------------------------------------------------------------
  // FILTERS
  // ------------------------------------------------------------

  bool _matchesFilters(Map<String, dynamic> data) {
    if (_isDeactivatedProperty(data) || _isUnavailableProperty(data)) {
      return false;
    }

    // Before the user applies a search, show all verified/available
    // properties. Draft wizard values do not affect this list.
    final purposeChoice = wizardApplied ? _appliedPurpose : '';
    final categoryChoice = wizardApplied ? _appliedCategory : '';
    final subtypeChoice = wizardApplied ? _appliedSubtype : '';
    final countyChoice = wizardApplied ? _appliedCounty : '';
    final subcountyChoice = wizardApplied ? _appliedSubcounty : '';
    final useGps = wizardApplied && _appliedUseCurrentLocation;
    final strictRadius = wizardApplied && _appliedOnlyCoordinatesWithin15Km;

    final purpose = _purposeOf(data);
    final category = _categoryOf(data).toLowerCase();
    final type = _typeOf(data).toLowerCase();
    final county = _countyOf(data).toLowerCase();
    final subcounty = _subcountyOf(data).toLowerCase();
    final location = _locationOf(data).toLowerCase();

    bool purposeMatch = true;
    if (purposeChoice.isNotEmpty) {
      if (purposeChoice == 'Rent') {
        purposeMatch = purpose.isEmpty || const {
          'rent', 'rental', 'for rent', 'to let', 'letting'
        }.contains(purpose);
      } else {
        purposeMatch = purpose.isEmpty || const {
          'buy', 'sale', 'sell', 'for sale', 'selling'
        }.contains(purpose);
      }
    }

    final categoryMatch = categoryChoice.isEmpty ||
        category == categoryChoice.toLowerCase() ||
        type == categoryChoice.toLowerCase();

    final wanted = subtypeChoice.toLowerCase();
    final subtypeMatch = wanted.isEmpty || type == wanted || category == wanted ||
        (wanted.length >= 4 &&
            (type.contains(wanted) || wanted.contains(type)));

    bool locationMatch = true;
    if (useGps) {
      final lat = double.tryParse(data['latitude']?.toString() ?? '');
      final lng = double.tryParse(data['longitude']?.toString() ?? '');
      final hasCoordinates = lat != null && lng != null &&
          _appliedLat != null && _appliedLng != null;
      if (strictRadius) {
        // Strict mode excludes listings without coordinates.
        if (!hasCoordinates) {
          locationMatch = false;
        } else {
          final km = Geolocator.distanceBetween(
            _appliedLat!, _appliedLng!, lat!, lng!,
          ) / 1000.0;
          locationMatch = km <= nearRadiusKm;
        }
      } else if (hasCoordinates) {
        final km = Geolocator.distanceBetween(
          _appliedLat!, _appliedLng!, lat!, lng!,
        ) / 1000.0;
        locationMatch = km <= nearRadiusKm;
      }
    } else if (countyChoice.isNotEmpty) {
      final wantedCounty = countyChoice.toLowerCase();
      final wantedSub = subcountyChoice.toLowerCase();
      locationMatch = county == wantedCounty || county.contains(wantedCounty) ||
          location.contains(wantedCounty);
      if (locationMatch && wantedSub.isNotEmpty) {
        locationMatch = subcounty.contains(wantedSub) ||
            subcounty == wantedSub || location.contains(wantedSub);
      }
    }

    return purposeMatch && categoryMatch && subtypeMatch && locationMatch;
  }

  double? _appliedDistanceKm(Map<String, dynamic> data) {
    final lat = double.tryParse(data['latitude']?.toString() ?? '');
    final lng = double.tryParse(data['longitude']?.toString() ?? '');
    if (lat == null || lng == null || _appliedLat == null || _appliedLng == null) {
      return null;
    }
    return Geolocator.distanceBetween(_appliedLat!, _appliedLng!, lat, lng) / 1000.0;
  }

  /// Listings with GPS coordinates come first when "near me"
  /// is active, sorted by distance.
  int _nearbyRank(Map<String, dynamic> data) {
    if (!(wizardApplied && _appliedUseCurrentLocation)) return 0;
    final km = _appliedDistanceKm(data);
    if (km == null) return 2; // No coordinates → last.
    return km <= nearRadiusKm ? 0 : 1;
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr('Find Properties', 'Tafuta Mali'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _propertiesStream, // CACHED — see field above.
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _errorState(snapshot.error.toString());
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return Center(
              child: CircularProgressIndicator(color: _brand),
            );
          }

          final documents = snapshot.data?.docs ?? [];

          // Remembered for the "nearest listing" location fallback.
          _knownProperties = documents
              .map((d) => d.data())
              .where((d) =>
          !_isDeactivatedProperty(d) && !_isUnavailableProperty(d))
              .toList();

          final filtered = documents
              .where((document) => _matchesFilters(document.data()))
              .toList();

          // ---- NEAREST FIRST when GPS is active ----
          if (wizardApplied && _appliedUseCurrentLocation) {
            filtered.sort((a, b) {
              final rankA = _nearbyRank(a.data());
              final rankB = _nearbyRank(b.data());
              if (rankA != rankB) return rankA.compareTo(rankB);
              final distA = _appliedDistanceKm(a.data()) ?? double.infinity;
              final distB = _appliedDistanceKm(b.data()) ?? double.infinity;
              return distA.compareTo(distB);
            });
          }

          // ---- ADS-VERIFIED FIRST ----
          final adsVerified =
          filtered.where((d) => _isAdsVerified(d.data())).toList();
          final notAdsVerified =
          filtered.where((d) => !_isAdsVerified(d.data())).toList();
          final sorted = [...adsVerified, ...notAdsVerified];
          if (wizardApplied && _appliedPriceOrder == 'lowest') {
            sorted.sort((a, b) =>
                (_parsePrice(a.data()['price']) ?? double.infinity)
                    .compareTo(_parsePrice(b.data()['price']) ?? double.infinity));
          } else if (wizardApplied && _appliedPriceOrder == 'highest') {
            sorted.sort((a, b) =>
                (_parsePrice(b.data()['price']) ?? -1)
                    .compareTo(_parsePrice(a.data()['price']) ?? -1));
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              _buildListPropertyPrompt(),
              _buildWizardSection(),
              _buildResultHeader(sorted.length),
              if (sorted.isEmpty)
                _emptyState()
              else
                ...sorted.map(
                      (document) => _propertyCard(
                    document.id,
                    document.data(),
                  ),
                ),
              if (documents.length >= _fetchLimit)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _fetchLimit += _batchIncrement;
                      _propertiesStream = _createPropertiesStream();
                    }),
                    icon: const Icon(Icons.expand_more),
                    label: Text(_tr('Load more properties', 'Pakia mali zaidi')),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildListPropertyPrompt() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: _brandSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brand.withValues(alpha: .25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegistrationPage()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Icon(Icons.add_home_work_outlined, color: _brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tr(
                      'Do you want to list your property here? Tap to get started.',
                      'Unataka kuweka mali yako hapa? Gonga kuanza.',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _bodyText,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: _brand),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // STEP-BY-STEP SEARCH ASSISTANT
  //
  // FIX: the light-green rounded Container now wraps its content
  // in a transparent, clipped Material so the ListTile-based
  // widgets inside it (SwitchListTile) paint their ink and
  // selected colours ABOVE the Container's background, with the
  // 22 px corners clipped.
  // ============================================================

  Widget _buildWizardSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _brandSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _brand.withValues(alpha: .2)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- HEADER ----------------
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _brand,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.travel_explore, color: Colors.white),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr('Search Assistant', 'Msaidizi wa Utafutaji'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tr('Answer a few questions for precise results',
                              'Jibu maswali machache kwa matokeo sahihi'),
                          style: TextStyle(
                            fontSize: 11,
                            color: _mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _resetWizard,
                    child: Text(_tr('Reset', 'Anza upya')),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // ---------------- PROGRESS BARS ----------------
              Row(
                children: [
                  for (int i = 0; i < wizardStepCount; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 6,
                        decoration: BoxDecoration(
                          color: i <= wizardStep
                              ? _brand
                              : _brand.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    if (i < wizardStepCount - 1) const SizedBox(width: 5),
                  ],
                ],
              ),

              const SizedBox(height: 6),

              Text(
                _tr('Step ${wizardStep + 1} of $wizardStepCount',
                    'Hatua ${wizardStep + 1} kati ya $wizardStepCount'),
                style: TextStyle(fontSize: 11, color: _mutedText),
              ),

              const SizedBox(height: 14),

              // ---------------- STEP TITLE ----------------
              Text(
                _stepTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              // ---------------- STEP CONTENT ----------------
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _wizardStepContent(),
              ),

              const SizedBox(height: 16),

              // ---------------- APPLIED SUMMARY ----------------
              if (wizardApplied && _wizardSummary.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _brand.withValues(alpha: .3)),
                  ),
                  child: Text(
                    _wizardSummary,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _bodyText,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ---------------- NAVIGATION BUTTONS ----------------
              Row(
                children: [
                  if (wizardStep > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _previousStep,
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: Text(_tr('Back', 'Nyuma')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brand,
                          side: BorderSide(color: _brand.withValues(alpha: .5)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  if (wizardStep > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: wizardStep > 0 ? 2 : 1,
                    child: _isLastStep
                        ? ElevatedButton.icon(
                      onPressed: _applyWizard,
                      icon: const Icon(Icons.travel_explore),
                      label: Text(
                        _tr('Find matching properties',
                            'Tafuta mali zinazofaa'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    )
                        : ElevatedButton.icon(
                      onPressed: _nextStep,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text(_tr('Next', 'Endelea')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // WIZARD STEP CONTENT
  // ------------------------------------------------------------

  Widget _wizardStepContent() {
    switch (wizardStep) {
      case 0:
        return _stepPurpose();
      case 1:
        return _stepType();
      case 2:
        return _stepLocation();
      case 3:
        return _stepBudget();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepPurpose() {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('Are you looking to rent or to buy?',
              'Unatafuta kupanga au kununua?'),
          style: TextStyle(fontSize: 13, color: _mutedText),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _wizardChoiceCard(
                selected: selectedPurpose == 'Rent',
                icon: Icons.key_rounded,
                label: _tr('Rent a place', 'Panga makazi'),
                onTap: () {
                  // Only selects — Next moves on.
                  _changePurpose('Rent');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _wizardChoiceCard(
                selected: selectedPurpose == 'Buy',
                icon: Icons.shopping_cart_outlined,
                label: _tr('Buy a property', 'Nunua mali'),
                onTap: () {
                  _changePurpose('Buy');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepType() {
    final categories = PropertyCategories.categoriesFor(selectedPurpose);

    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedCategory.isEmpty)
          Text(
            _tr('Pick the category that fits best.',
                'Chagua aina inayofaa zaidi.'),
            style: TextStyle(fontSize: 13, color: _mutedText),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in categories)
              _wizardChip(
                label: category,
                selected: selectedCategory == category,
                onTap: () {
                  _changeCategory(category);
                },
              ),
          ],
        ),
        if (selectedCategory.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            _tr('Which one exactly?', 'Ipini hasa?'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final subtype in PropertyCategories.subtypesFor(
                selectedPurpose,
                selectedCategory,
              ))
                _wizardChip(
                  label: subtype,
                  selected: selectedSubtype == subtype,
                  onTap: () => setState(() {
                    selectedSubtype = subtype;
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _stepLocation() {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- Use current location ----
        OutlinedButton.icon(
          onPressed: isLocating ? null : _useCurrentLocation,
          icon: isLocating
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.my_location, size: 18),
          label: Text(_tr('Use my current location',
              'Tumia eneo langu la sasa')),
          style: OutlinedButton.styleFrom(
            foregroundColor: useCurrentLocation ? Colors.white : _brand,
            backgroundColor:
            useCurrentLocation ? _brand : Colors.transparent,
            side: BorderSide(color: _brand),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),

        if (useCurrentLocation) ...[
          const SizedBox(height: 12),
          _gpsDetailsCard(),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _cancelCurrentLocation,
              icon: const Icon(Icons.close, size: 17),
              label: Text(_tr('Cancel location and pick area manually',
                  'Ghairi eneo na uchague eneo mwenyewe')),
              style: TextButton.styleFrom(foregroundColor: _brand),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: onlyCoordinatesWithin15Km,
            onChanged: (value) => setState(() {
              onlyCoordinatesWithin15Km = value;
            }),
            title: Text(_tr('Only show properties with coordinates within 15 km',
                'Onyesha mali zenye viungo vya eneo ndani ya km 15')),
            subtitle: Text(_tr('Listings without coordinates are excluded when enabled.',
                'Mali zisizo na viungo vya eneo hazitaonyeshwa ikiwashwa.'),
                style: TextStyle(fontSize: 12, color: _mutedText)),
            activeColor: _brand,
          ),
        ] else ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _tr('or pick the area yourself:',
                      'au chagua eneo wewe mwenyewe:'),
                  style: TextStyle(fontSize: 12.5, color: _mutedText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _tapPickerField(
            label: _tr('County', 'Kaunti'),
            value: selectedCounty,
            placeholder: _tr('Tap to select county',
                'Bonyeza kuchagua kaunti'),
            onTap: _pickCounty,
          ),
          const SizedBox(height: 10),
          _tapPickerField(
            label: _tr('Sub-county', 'Kaunti ndogo'),
            value: selectedSubcounty,
            placeholder: selectedCounty.isEmpty
                ? _tr('Select a county first', 'Chagua kaunti kwanza')
                : _tr('Tap to select sub-county',
                'Bonyeza kuchagua kaunti ndogo'),
            onTap: selectedCounty.isEmpty ? null : _pickSubcounty,
          ),
        ],
      ],
    );
  }

  Widget _stepBudget() {
    return Column(
      key: const ValueKey(3),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('Sort by price', 'Panga kulingana na bei'),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _bodyText),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _wizardChip(
              label: _tr('Default order', 'Mpangilio wa kawaida'),
              selected: selectedPriceOrder == 'none',
              onTap: () => setState(() => selectedPriceOrder = 'none'),
            ),
            _wizardChip(
              label: _tr('Lowest price', 'Bei ya chini'),
              selected: selectedPriceOrder == 'lowest',
              onTap: () => setState(() => selectedPriceOrder = 'lowest'),
            ),
            _wizardChip(
              label: _tr('Highest price', 'Bei ya juu'),
              selected: selectedPriceOrder == 'highest',
              onTap: () => setState(() => selectedPriceOrder = 'highest'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _tr('Your choice is applied when you press “Find matching properties”.',
              'Chaguo lako litatumika ukibonyeza “Tafuta mali zinazofaa”.'),
          style: TextStyle(fontSize: 12, color: _mutedText),
        ),
      ],
    );
  }

  Widget _wizardChoiceCard({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: selected ? _brand : _cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _brand : _cardBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: selected ? Colors.white : _brand),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _bodyText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wizardChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _brand : _cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _brand : _cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : _bodyText,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // TAPPABLE PICKER FIELDS (county / subcounty)
  // ------------------------------------------------------------

  Widget _tapPickerField({
    required String label,
    required String value,
    required String placeholder,
    required VoidCallback? onTap,
  }) {
    final hasValue = value.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: _brand),
          filled: true,
          fillColor: _isDark ? const Color(0xFF22301F) : Colors.white,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _brand, width: 1.6),
          ),
          suffixIcon: Icon(Icons.arrow_drop_down, color: _brand),
        ),
        child: Text(
          hasValue ? value : placeholder,
          style: TextStyle(
            fontSize: 14,
            color: hasValue ? _bodyText : _mutedText,
          ),
        ),
      ),
    );
  }

  Future<void> _pickCounty() async {
    final result = await _searchableSheet(
      title: _tr('Select county', 'Chagua kaunti'),
      items: KenyaLocation.counties,
    );

    if (result != null && result.isNotEmpty) {
      _changeCounty(result);
    }
  }

  Future<void> _pickSubcounty() async {
    if (selectedCounty.isEmpty) return;

    final result = await _searchableSheet(
      title: _tr('Select sub-county', 'Chagua kaunti ndogo'),
      items: KenyaLocation.subcountiesOf(selectedCounty),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        selectedSubcounty = result;
      });
    }
  }

  /// Searchable bottom sheet used by the county / subcounty
  /// pickers.
  Future<String?> _searchableSheet({
    required String title,
    required List<String> items,
  }) {
    final searchController = TextEditingController();
    var shown = items;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: TextField(
                      controller: searchController,
                      onChanged: (query) {
                        setSheetState(() {
                          final q = query.trim().toLowerCase();
                          shown = q.isEmpty
                              ? items
                              : items
                              .where((i) =>
                              i.toLowerCase().contains(q))
                              .toList();
                        });
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: _tr('Search...', 'Tafuta...'),
                        filled: true,
                        fillColor: _isDark
                            ? const Color(0xFF22301F)
                            : const Color(0xFFF1F3F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        for (final item in shown)
                          ListTile(
                            dense: true,
                            title: Text(item),
                            onTap: () => Navigator.pop(sheetContext, item),
                          ),
                        if (shown.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _tr('Nothing found', 'Hakuna kilichopatikana'),
                              style: TextStyle(color: _mutedText),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ------------------------------------------------------------
  // GPS DETAILS CARD
  // ------------------------------------------------------------

  Widget _gpsDetailsCard() {
    if (isResolvingAddress) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _brand.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _tr('Getting location details...',
                    'Ninapata maelezo ya eneo...'),
                style: TextStyle(fontSize: 13, color: _bodyText),
              ),
            ),
          ],
        ),
      );
    }

    final rows = <MapEntry<IconData, String>>[
      if (gpsArea != null) MapEntry(Icons.place_outlined, gpsArea!),
      if (gpsWard != null) MapEntry(Icons.holiday_village_outlined, gpsWard!),
      if (gpsSubcounty != null)
        MapEntry(Icons.location_city, gpsSubcounty!),
      if (gpsCounty != null)
        MapEntry(Icons.map_outlined, gpsCounty!),
    ];

    if (rows.isEmpty) {
      return _gpsDetailsCardPlaceholder();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brand.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              children: [
                Icon(rows[i].key, size: 16, color: _brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rows[i].value,
                    style: TextStyle(fontSize: 13, color: _bodyText),
                  ),
                ),
              ],
            ),
          ],
          if (gpsFromNearest) ...[
            const SizedBox(height: 6),
            Text(
              _tr('Some details approximated from a nearby listing.',
                  'Baadhi ya maelezo yamekadiriwa kutoka mali karibu.'),
              style: TextStyle(fontSize: 10.5, color: _mutedText),
            ),
          ],
        ],
      ),
    );
  }

  Widget _gpsDetailsCardPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _tr('Using your current location for "near me" results.',
            'Tunatumia eneo lako la sasa kwa matokeo "karibu nami".'),
        style: TextStyle(fontSize: 12.5, color: _mutedText),
      ),
    );
  }

  // ------------------------------------------------------------
  // RESULT HEADER / EMPTY / ERROR STATES
  // ------------------------------------------------------------

  Widget _buildResultHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          Icon(Icons.home_work_outlined, size: 18, color: _brand),
          const SizedBox(width: 7),
          Text(
            '$count ${_tr('properties found', 'mali zimepatikana')}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.travel_explore, size: 54, color: _mutedText),
          const SizedBox(height: 12),
          Text(
            _tr('No properties match your answers yet.',
                'Hakuna mali inayolingana na majibu yako bado.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedText),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _resetWizard,
            child: Text(_tr('Start a new search', 'Anza utafutaji mpya')),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 46, color: _mutedText),
            const SizedBox(height: 12),
            Text(
              _tr('Could not load properties.',
                  'Imeshindikana kupakia mali.'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _mutedText),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // PROPERTY CARD — opens details + logs the view.
  // Owner details are fetched from Firestore (`users` doc of
  // the listing's owner uid), shown on the card and passed to
  // PropertyDetailsPage as `owner`.
  // ------------------------------------------------------------

  Widget _propertyCard(String id, Map<String, dynamic> data) {
    final images = (data['images'] as List?)?.cast<String>() ??
        (data['unitImages'] as List?)?.cast<String>() ??
        const <String>[];

    final title = _nonEmpty(data['title']?.toString()) ??
        _tr('Property', 'Mali');
    final type = _typeOf(data);
    final category = _categoryOf(data);
    final county = _countyOf(data);
    final subcounty = _subcountyOf(data);
    final area = _fieldOf(data, ['area', 'location', 'town']);

    final price = _parsePrice(data['price']);
    final priceText = price == null
        ? _tr('Ask for price', 'Uliza bei')
        : 'KES ${_formatPrice(price)}';

    final distanceText = (wizardApplied && _appliedUseCurrentLocation) ? _appliedDistanceKm(data) : null;

    // Availability (string first, boolean fallback). Since
    // unavailable listings are now hidden, this is normally
    // "available"; kept for custom values.
    final availability = _availabilityOf(data);
    final bool isAvailable = availability == 'available';

    // ---- OWNER LINK ----
    final ownerId = _ownerIdOf(data);

    return GestureDetector(
      onTap: () async {
        _logView(id);

        // Fetch the owner's details from Firestore before opening
        // the details page, and pass them along as `owner`.
        Map<String, dynamic>? owner;
        if (ownerId.isNotEmpty) {
          try {
            owner = await _ownerFuture(ownerId);
          } catch (_) {
            owner = null;
          }
        }

        if (!mounted) return;
        // FIX: PropertyDetailsPage does not define an `owner`
        // named parameter, so the owner map is passed INSIDE the
        // property map as `owner`. Read it on the details page
        // with property['owner'] (name / phone / email inside).
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PropertyDetailsPage(
              // FIX: force the TENANT view from public search, so a
              // signed-in owner tapping their own listing still
              // sees the tenant view, not the owner dashboard.
              isTenantView: true,
              property: {
                ...data,
                'id': id,
                if (owner != null) 'owner': owner,
              },
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isDark ? .2 : .04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- IMAGE ----
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: images.isEmpty
                  ? Container(
                height: 160,
                color: _brandSoft,
                child: Icon(
                  Icons.landscape_outlined,
                  size: 44,
                  color: _brand,
                ),
              )
                  : Image.network(
                images.first,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 160,
                  color: _brandSoft,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 40,
                    color: _brand,
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- ADS BADGE ----
                  if (_isAdsVerified(data))
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _brand.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 12, color: _brand),
                          const SizedBox(width: 4),
                          Text(
                            _tr('Ads Verified', 'Imethibitishwa'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _brand,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ---- TITLE + TYPE ----
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [if (type.isNotEmpty) type, if (category.isNotEmpty) category]
                        .join(' · '),
                    style: TextStyle(fontSize: 12.5, color: _mutedText),
                  ),
                  const SizedBox(height: 8),

                  // ---- LOCATION ----
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: _brand),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            if (area.isNotEmpty) area,
                            if (subcounty.isNotEmpty) subcounty,
                            if (county.isNotEmpty) county,
                          ].join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                          TextStyle(fontSize: 12, color: _mutedText),
                        ),
                      ),
                      if (distanceText != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${distanceText.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _brand,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // ---- OWNER ROW (from Firestore `users`) ----
                  if (ownerId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    FutureBuilder<Map<String, dynamic>?>(
                      future: _ownerFuture(ownerId),
                      builder: (context, ownerSnapshot) {
                        if (ownerSnapshot.connectionState !=
                            ConnectionState.done) {
                          return Row(
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _tr('Loading owner...',
                                    'Ninapata mmiliki...'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _mutedText,
                                ),
                              ),
                            ],
                          );
                        }

                        final owner = ownerSnapshot.data;
                        if (owner == null) return const SizedBox.shrink();

                        final ownerName = _ownerNameOf(owner);
                        final ownerPhone = _ownerPhoneOf(owner);
                        if (ownerName.isEmpty && ownerPhone.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 13, color: _brand),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                [
                                  if (ownerName.isNotEmpty) ownerName,
                                  if (ownerPhone.isNotEmpty) ownerPhone,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _bodyText,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 10),

                  // ---- PRICE + AVAILABILITY BADGE ----
                  Row(
                    children: [
                      Text(
                        priceText,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _brandDeep,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _brand.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _brand.withValues(alpha: .35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: 12, color: _brand),
                            const SizedBox(width: 4),
                            Text(_tr('Verified listing', 'Tangazo limethibitishwa'),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _brand)),
                          ],
                        ),
                      ),
                      if (availability == 'available' || availability == 'unavailable') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isAvailable ? _brand.withValues(alpha: .1) : Colors.red.withValues(alpha: _isDark ? .25 : .1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isAvailable ? _tr('Available', 'Inapatikana') : _tr('Unavailable', 'Haipatikani'),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                color: isAvailable ? _brand : (_isDark ? Colors.red.shade300 : Colors.red.shade700)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    if (price >= 1000000) {
      final m = price / 1000000;
      return m == m.roundToDouble()
          ? '${m.toInt()}M'
          : '${m.toStringAsFixed(1)}M';
    }
    return price.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
    );
  }
}

// ============================================================
// _GpsAddress — immutable container for reverse-geocoded
// details, with merge helpers.
// ============================================================

@immutable
class _GpsAddress {
  final String? county;
  final String? subcounty;
  final String? ward;
  final String? area;

  const _GpsAddress({
    this.county,
    this.subcounty,
    this.ward,
    this.area,
  });

  bool get isComplete =>
      county != null && subcounty != null && ward != null && area != null;

  String get signature => '$county|$subcounty|$ward|$area';

  _GpsAddress merge(_GpsAddress other) {
    String? keep(String? mine, String? theirs) =>
        (mine == null || mine.isEmpty) ? theirs : mine;

    return _GpsAddress(
      county: keep(county, other.county),
      subcounty: keep(subcounty, other.subcounty),
      ward: keep(ward, other.ward),
      area: keep(area, other.area),
    );
  }
}