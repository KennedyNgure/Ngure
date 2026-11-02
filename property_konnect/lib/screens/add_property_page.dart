import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'data.dart';
import 'app_settings.dart';

// ============================================================
// LIMITS
//
// The same limits MUST be enforced by the Firebase Security
// Rules (see firebase_rules.txt) — the app checks below only
// give friendly, early feedback.
// ============================================================

const int _kMaxImages = 5;
const int _kMaxVideos = 2;
const int _kMaxVideoMb = 50;

/// Photos: size, dimensions and formats.
const int _kMaxImageMb = 10;
const int _kMinImageShortSide = 480;
const int _kMinImageLongSide = 640;
const int _kMaxImageLongSide = 12000;

/// Videos: allowed file extensions.
const Set<String> _kVideoExtensions = {'mp4', 'mov', 'webm', '3gp', 'm4v'};

/// Prices (KES). Must be > 0 and no more than these ceilings.
const double _kMaxRentPrice = 10000000; // 10 million per period
const double _kMaxSalePrice = 5000000000; // 5 billion

/// Roles allowed to create / edit listings. Keep this list
/// identical to the one in the Firestore + Storage rules.
const Set<String> _kOwnerRoles = {
  'owner',
  'property_owner',
  'landlord',
  'landlady',
  'agent',
  'bnb_owner',
};

// ============================================================
// PROPERTY CATEGORIES
//
// Step 1: Purpose  (For Rent / For Sale)
// Step 2: Category (depends on purpose)
// Step 3: Type     (depends on category)
// ============================================================

const Map<String, List<String>> _kRentCategories = {
  'Residential': ['Apartment', 'House', 'Studio', 'Hostel'],
  'Commercial': ['Shop', 'Office', 'Warehouse'],
  'Short Stay': ['Airbnb', 'Guest House', 'Hotel'],
};

const Map<String, List<String>> _kSaleCategories = {
  'Land': ['Residential Plot', 'Agricultural Land', 'Ranch'],
  'Commercial': ['Shop', 'Office', 'Warehouse'],
};

// ============================================================
// HOSTEL INFORMATION OPTIONS  (value stored, English, Kiswahili)
// ============================================================

const List<(String, String, String)> _kGenderOptions = [
  ('male', 'Male only', 'Wavulana pekee'),
  ('female', 'Female only', 'Wasichana pekee'),
  ('mixed', 'Mixed (male & female)', 'Mchanganyiko (wavulana na wasichana)'),
];

const List<(String, String)> _kSharedFacilities = [
  ('Shared kitchen', 'Jiko la pamoja'),
  ('Shared bathrooms', 'Bafu za pamoja'),
  ('Shared toilets', 'Vyoo vya pamoja'),
  ('Common room', 'Chumba cha pamoja'),
  ('Study area', 'Eneo la kusomea'),
  ('Laundry area', 'Eneo la kufulia'),
  ('Dining area', 'Eneo la kulia'),
  ('WiFi lounge', 'Ukumbi wa WiFi'),
];

const String _kAmenitiesHint =
    'e.g. WiFi, Water Supply, Electricity, Backup Generator, Borehole, '
    'Parking, Security Guard, CCTV, Fenced Compound, Gated Compound, '
    'Lift, Balcony, Furnished, Tiled Floors, Hot Shower, Kitchen, '
    'Shared Kitchen, Laundry Area, Study Area, Common Room, DSTV, '
    'Swimming Pool, Gym, Garbage Collection, Playground';

const String _kExtraDetailsHint =
    "e.g. Deposit is one month's rent. Water and garbage fees are included. "
    'Tenants can move in from the 1st of next month. '
    '5 minutes walk from the main gate, near the matatu stage. '
    'No pets allowed.';

const String _kSaleDescriptionHint =
    'e.g. Prime 50x100 residential plot in a gated community. '
    'Fully fenced with a ready title deed. '
    'Gravel access road, electricity and water at the boundary. '
    '10 minutes drive from the town centre.';

const String _kPaymentCycleHint =
    'e.g. Per Month, Per Year, One-off, Per Week';

// ============================================================
// FORM STEPS
// ============================================================

enum _StepId { basics, location, pricing, features, media, preview }

// ============================================================
// MONEY HELPERS
// ============================================================

/// "1234567" -> "1,234,567"
String _groupThousands(String digits) {
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;

    buffer.write(digits[i]);

    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }

  return buffer.toString();
}

/// 12500 -> "12,500"   12500.5 -> "12,500.50"
String _formatAmount(double value) {
  final fixed = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  final dot = fixed.indexOf('.');

  final whole = dot == -1 ? fixed : fixed.substring(0, dot);
  final fraction = dot == -1 ? '' : fixed.substring(dot);

  return '${_groupThousands(whole)}$fraction';
}

/// Formats the price as the owner types: 12500 -> 12,500
/// (digits and one decimal point, max 2 decimals).
class _CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final raw = newValue.text.replaceAll(',', '');

    if (raw.isEmpty) return const TextEditingValue();

    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(raw)) return oldValue;

    final dot = raw.indexOf('.');

    var whole = dot == -1 ? raw : raw.substring(0, dot);
    final fraction = dot == -1 ? '' : raw.substring(dot);

    whole = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    if (whole.isEmpty) whole = '0';

    if (whole.length > 12) return oldValue;

    final text = '${_groupThousands(whole)}$fraction';

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ============================================================
// MEDIA ITEMS
// ============================================================

/// One photo in the ordered gallery. The FIRST item is the cover.
class _PhotoItem {
  _PhotoItem.remote(this.url)
      : file = null,
        bytes = null,
        extension = 'jpg';

  _PhotoItem.local({
    required this.file,
    required this.bytes,
    required this.extension,
  }) : url = null;

  final String? url;
  final XFile? file;
  final Uint8List? bytes;
  final String extension;

  /// Stable key for the reorderable list.
  final Key key = UniqueKey();

  bool get isRemote => url != null;
}

class _VideoItem {
  _VideoItem.remote(this.url)
      : file = null,
        extension = 'mp4',
        sizeBytes = 0;

  _VideoItem.local({
    required this.file,
    required this.extension,
    required this.sizeBytes,
  }) : url = null;

  final String? url;
  final XFile? file;
  final String extension;
  final int sizeBytes;

  final Key key = UniqueKey();

  bool get isRemote => url != null;
}

// ============================================================
// PAGE
// ============================================================

class AddPropertyPage extends StatefulWidget {
  final String? propertyId;
  final Map<String, dynamic>? initialData;
  final bool readOnly;

  const AddPropertyPage({
    super.key,
    this.propertyId,
    this.initialData,
    this.readOnly = false,
  });

  bool get isEditing => propertyId != null;

  @override
  State<AddPropertyPage> createState() => _AddPropertyPageState();
}

class _AddPropertyPageState extends State<AddPropertyPage> {
  final _formKey = GlobalKey<FormState>();

  final ScrollController _scrollController = ScrollController();

  final titleController = TextEditingController();
  final areaController = TextEditingController();
  final priceController = TextEditingController();
  final accommodationTypeController = TextEditingController();
  final numberOfUnitsController = TextEditingController();
  final amenitiesController = TextEditingController();
  final extraDetailsController = TextEditingController();

  // ------------------------------------------------------------
  // SALE PROPERTY DESCRIPTION
  // ------------------------------------------------------------

  final saleDescriptionController = TextEditingController();

  // ------------------------------------------------------------
  // HOSTEL INFORMATION
  // ------------------------------------------------------------

  final campusNameController = TextEditingController();
  final roomCapacityController = TextEditingController();

  String? genderPreference;

  final Set<String> _sharedFacilities = {};

  // ------------------------------------------------------------
  // CUSTOM PAYMENT CYCLE (non-hostel property types)
  // ------------------------------------------------------------

  final paymentCycleController = TextEditingController();

  // ------------------------------------------------------------
  // PICKER FORM FIELD KEYS (county / sub-county)
  // ------------------------------------------------------------

  final GlobalKey<FormFieldState<String>> _countyFieldKey =
  GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _subCountyFieldKey =
  GlobalKey<FormFieldState<String>>();

  // ------------------------------------------------------------
  // PROPERTY SETTINGS
  // ------------------------------------------------------------

  String purpose = 'rent';

  late String selectedCategory;
  late String propertyType;

  String? selectedCounty;
  String? selectedSubCounty;
  String paymentCycle = 'monthly';

  bool isLoading = false;

  /// Shown next to the spinner while saving ("Uploading photo 2/4").
  String? _uploadStatus;

  // ------------------------------------------------------------
  // WIZARD STATE
  // ------------------------------------------------------------

  int _step = 0;

  /// Furthest step the owner has reached — the step circles let
  /// them jump back to any step up to this one.
  int _maxStep = 0;

  // ------------------------------------------------------------
  // ACCESS CHECK (role + ownership, verified against Firestore)
  // ------------------------------------------------------------

  bool _accessChecking = true;
  String? _accessError;

  // ------------------------------------------------------------
  // MEDIA — ordered galleries. Photo index 0 is the COVER photo.
  // ------------------------------------------------------------

  final List<_PhotoItem> _photos = [];
  final List<_VideoItem> _videos = [];

  final ImagePicker _picker = ImagePicker();

  // ============================================================
  // THEME + LANGUAGE
  // ============================================================

  SettingsController get _settings => AppSettings.of(context);

  bool get _isDark => _settings.isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _pageBackground =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade200 : Colors.grey.shade800;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _hintText =>
      _isDark ? Colors.grey.shade500 : Colors.grey.shade500;

  Color get _okColor =>
      _isDark ? Colors.green.shade300 : Colors.green.shade700;

  Color get _warnColor =>
      _isDark ? Colors.orange.shade300 : Colors.orange.shade800;

  Color get _errColor =>
      _isDark ? Colors.red.shade300 : Colors.red.shade700;

  Color get _fieldFill =>
      _isDark ? const Color(0xFF22301F) : const Color(0xFFEAF7EF);

  /// Bilingual helper — English / Kiswahili, live from settings.
  String _tr(String en, String sw) =>
      _settings.languageCode == 'sw' ? sw : en;

  bool get _isReadOnly => widget.readOnly;

  bool get _isForSale => purpose == 'sale';

  bool get _isHostel => propertyType == 'Hostel';

  /// Only Hostel uses the fixed dropdown (monthly / per semester).
  bool get _usesPaymentCycleDropdown => _isHostel;

  // ------------------------------------------------------------
  // CATEGORIES FOR THE CURRENT PURPOSE
  // ------------------------------------------------------------

  Map<String, List<String>> get _categoriesForPurpose =>
      _isForSale ? _kSaleCategories : _kRentCategories;

  List<String> get _availableCategories =>
      _categoriesForPurpose.keys.toList();

  List<String> get _availableTypes =>
      _categoriesForPurpose[selectedCategory] ?? const [];

  // ------------------------------------------------------------
  // STEPS (the "Features" step does not exist for sale listings)
  // ------------------------------------------------------------

  List<_StepId> get _steps => [
    _StepId.basics,
    _StepId.location,
    _StepId.pricing,
    if (!_isForSale) _StepId.features,
    _StepId.media,
    _StepId.preview,
  ];

  _StepId get _currentStep => _steps[_step.clamp(0, _steps.length - 1)];

  String _stepTitle(_StepId id) {
    switch (id) {
      case _StepId.basics:
        return _tr('Property type', 'Aina ya mali');
      case _StepId.location:
        return _tr('Location', 'Eneo');
      case _StepId.pricing:
        return _isForSale
            ? _tr('Price & details', 'Bei na maelezo')
            : _tr('Price & units', 'Bei na vitengo');
      case _StepId.features:
        return _isHostel
            ? _tr('Hostel & amenities', 'Hosteli na huduma')
            : _tr('Amenities', 'Huduma');
      case _StepId.media:
        return _tr('Photos & videos', 'Picha na video');
      case _StepId.preview:
        return _tr('Review & list', 'Kagua na weka');
    }
  }

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    selectedCategory = _availableCategories.first;
    propertyType = _availableTypes.first;

    _populateFromExistingProperty();

    if (_isReadOnly) {
      _accessChecking = false;
    } else {
      // _tr() needs the inherited AppSettings, which is not
      // available inside initState — run after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runAccessCheck();
      });
    }
  }

  void _populateFromExistingProperty() {
    final data = widget.initialData;

    if (data == null) return;

    // ----------------------------------------------------------
    // PURPOSE
    // ----------------------------------------------------------

    final savedPurpose = data['purpose']?.toString().toLowerCase();

    if (savedPurpose == 'sale') {
      purpose = 'sale';
    } else if (savedPurpose == 'rent') {
      purpose = 'rent';
    }

    // ----------------------------------------------------------
    // CATEGORY + TYPE
    // ----------------------------------------------------------

    final type = data['type']?.toString();

    final savedCategory = data['category']?.toString();

    if (savedCategory != null &&
        _availableCategories.contains(savedCategory)) {
      selectedCategory = savedCategory;
    }

    if (type != null && _availableTypes.contains(type)) {
      propertyType = type;
    } else {
      propertyType = _availableTypes.first;
    }

    // ----------------------------------------------------------
    // TEXT FIELDS
    // ----------------------------------------------------------

    titleController.text = data['title']?.toString() ?? '';

    areaController.text = data['area']?.toString() ?? '';

    final savedPrice = data['price'];

    if (savedPrice is num && savedPrice > 0) {
      priceController.text = _formatAmount(savedPrice.toDouble());
    }

    accommodationTypeController.text = data['accommodationType']?.toString() ??
        data['unitDetails']?.toString() ??
        '';

    numberOfUnitsController.text = data['numberOfUnits']?.toString() ?? '';

    extraDetailsController.text = data['description']?.toString() ?? '';

    saleDescriptionController.text = data['description']?.toString() ?? '';

    // ----------------------------------------------------------
    // HOSTEL INFORMATION
    // ----------------------------------------------------------

    campusNameController.text = data['campusName']?.toString() ?? '';

    final savedGender = data['genderPreference']?.toString();

    if (_kGenderOptions.any((option) => option.$1 == savedGender)) {
      genderPreference = savedGender;
    }

    roomCapacityController.text = data['roomCapacity']?.toString() ?? '';

    _sharedFacilities.addAll(_listFrom(data['sharedFacilities']));

    // ----------------------------------------------------------
    // AMENITIES (rent only — sale listings have none)
    // ----------------------------------------------------------

    final amenities = data['amenities'];

    if (amenities is List) {
      amenitiesController.text = amenities
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .join(', ');
    } else {
      amenitiesController.text = amenities?.toString() ?? '';
    }

    // ----------------------------------------------------------
    // COUNTY
    // ----------------------------------------------------------

    final county = data['county']?.toString();

    if (county != null && KenyaLocation.counties.contains(county)) {
      selectedCounty = county;
    }

    // ----------------------------------------------------------
    // SUB-COUNTY
    // ----------------------------------------------------------

    final subCounty = data['subCounty']?.toString();

    if (subCounty != null &&
        selectedCounty != null &&
        KenyaLocation.subcountiesOf(selectedCounty!).contains(subCounty)) {
      selectedSubCounty = subCounty;
    }

    // ----------------------------------------------------------
    // PAYMENT CYCLE
    // ----------------------------------------------------------

    final cycle = data['paymentCycle']?.toString();

    if (cycle == 'per_semester') {
      paymentCycle = 'per_semester';
    } else if (cycle == 'monthly') {
      paymentCycle = 'monthly';
    } else if (cycle != null && cycle.isNotEmpty) {
      paymentCycleController.text = cycle;
    }

    // ----------------------------------------------------------
    // EXISTING MEDIA — kept in saved order, cover photo first.
    // ----------------------------------------------------------

    final imageUrls = <String>[];

    for (final url in [
      ..._listFrom(data['images']),
      ..._listFrom(data['unitImages']),
    ]) {
      if (!imageUrls.contains(url)) imageUrls.add(url);
    }

    final savedCover =
        data['mainImage']?.toString() ?? data['coverImage']?.toString();

    if (savedCover != null && imageUrls.contains(savedCover)) {
      imageUrls
        ..remove(savedCover)
        ..insert(0, savedCover);
    }

    _photos.addAll(imageUrls.map(_PhotoItem.remote));

    _videos.addAll(_listFrom(data['videos']).map(_VideoItem.remote));
  }

  List<String> _listFrom(dynamic value) {
    if (value is! List) return [];

    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    _scrollController.dispose();
    titleController.dispose();
    areaController.dispose();
    priceController.dispose();
    accommodationTypeController.dispose();
    numberOfUnitsController.dispose();
    amenitiesController.dispose();
    extraDetailsController.dispose();
    campusNameController.dispose();
    roomCapacityController.dispose();
    saleDescriptionController.dispose();
    paymentCycleController.dispose();

    super.dispose();
  }

  // ------------------------------------------------------------
  // MESSAGE
  // ------------------------------------------------------------

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _isDark ? const Color(0xFF24312A) : null,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ------------------------------------------------------------
  // CANCEL
  // ------------------------------------------------------------

  void _cancel() {
    if (isLoading) return;
    Navigator.of(context).pop();
  }

  // ============================================================
  // ACCESS CONTROL
  //
  // 1. The signed-in user's Firestore profile must be active and
  //    have a property-owner role.
  // 2. When editing, the property document is read FRESH from the
  //    server and its ownerId must equal the signed-in user. We
  //    never trust widget.initialData for this.
  //
  // The same rules are enforced by Firestore / Storage Security
  // Rules (firebase_rules.txt), so editing the app cannot
  // bypass them.
  // ============================================================

  String _normalizeRole(dynamic value) => (value?.toString() ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-]+'), '_');

  Future<({String? error, Map<String, dynamic>? property})>
  _checkOwnerAccess(User user) async {
    final db = FirebaseFirestore.instance;

    const serverOnly = GetOptions(source: Source.server);

    final userSnap = await db.collection('users').doc(user.uid).get(serverOnly);

    final userData = userSnap.data();

    if (userData == null) {
      return (
      error: _tr(
        'Your account profile was not found. Please log in again.',
        'Wasifu wa akaunti yako haukupatikana. Tafadhali ingia tena.',
      ),
      property: null,
      );
    }

    if (userData['isActive'] == false || userData['status'] == 'deactivated') {
      return (
      error: _tr(
        'Your account is deactivated and cannot manage properties.',
        'Akaunti yako imezimwa na haiwezi kusimamia mali.',
      ),
      property: null,
      );
    }

    if (!_kOwnerRoles.contains(_normalizeRole(userData['role']))) {
      return (
      error: _tr(
        'Only property owner accounts can list or edit properties.',
        'Akaunti za wamiliki wa mali pekee ndizo zinaweza kuweka au kuhariri mali.',
      ),
      property: null,
      );
    }

    if (!widget.isEditing) return (error: null, property: null);

    final propertySnap = await db
        .collection('properties')
        .doc(widget.propertyId)
        .get(serverOnly);

    final property = propertySnap.data();

    if (!propertySnap.exists || property == null) {
      return (
      error: _tr(
        'This property no longer exists.',
        'Mali hii haipo tena.',
      ),
      property: null,
      );
    }

    final ownerId = property['ownerId']?.toString();

    if (ownerId == null || ownerId.isEmpty || ownerId != user.uid) {
      return (
      error: _tr(
        'You are not allowed to edit this property.',
        'Huruhusiwi kuhariri mali hii.',
      ),
      property: null,
      );
    }

    return (error: null, property: property);
  }

  Future<void> _runAccessCheck() async {
    if (!mounted) return;

    setState(() {
      _accessChecking = true;
      _accessError = null;
    });

    String? error;

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        error = _tr('Please login again.', 'Tafadhali ingia tena.');
      } else {
        error = (await _checkOwnerAccess(user)).error;
      }
    } catch (e) {
      debugPrint('ACCESS CHECK ERROR: $e');

      error = _tr(
        'Could not verify your account. Check your internet connection and try again.',
        'Imeshindikana kuthibitisha akaunti yako. Angalia mtandao wako kisha ujaribu tena.',
      );
    }

    if (!mounted) return;

    setState(() {
      _accessChecking = false;
      _accessError = error;
    });
  }

  // ============================================================
  // VALIDATORS (shared by the form fields and the final check)
  // ============================================================

  String? _validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _tr('Enter a property name', 'Weka jina la mali');
    }

    return null;
  }

  String? _validatePrice(String? value) {
    final raw = (value ?? '').replaceAll(',', '').trim();

    if (raw.isEmpty) {
      return _isForSale
          ? _tr('Enter the asking price', 'Weka bei ya kuuza')
          : _tr('Enter the rent amount', 'Weka kiasi cha kodi');
    }

    final price = double.tryParse(raw);

    if (price == null || !price.isFinite || price <= 0) {
      return _tr(
        'Enter a valid price greater than zero',
        'Weka bei sahihi iliyo zaidi ya sifuri',
      );
    }

    final max = _isForSale ? _kMaxSalePrice : _kMaxRentPrice;

    if (price > max) {
      return _tr(
        'That price looks too high. The maximum is KES ${_formatAmount(max)}.',
        'Bei hii inaonekana kubwa mno. Kiwango cha juu ni KES ${_formatAmount(max)}.',
      );
    }

    return null;
  }

  double? get _priceValue =>
      double.tryParse(priceController.text.replaceAll(',', '').trim());

  String? _validateUnits(String? value) {
    final number = int.tryParse(value?.trim() ?? '');

    if (number == null || number < 1) {
      return _tr(
        'Enter a valid number of units (1 or more)',
        'Weka idadi sahihi ya vitengo (1 au zaidi)',
      );
    }

    return null;
  }

  String? _validateCapacity(String? value) {
    final number = int.tryParse(value?.trim() ?? '');

    if (number == null || number < 1 || number > 20) {
      return _tr(
        'Enter how many people share a room (1 to 20)',
        'Weka idadi ya watu wanaoshiriki chumba (1 hadi 20)',
      );
    }

    return null;
  }

  /// Walks every required field in order and returns the first
  /// problem and the step it belongs to, or null if all is well.
  /// Used right before submitting, so a step that was skipped or
  /// invalidated by going back is never submitted incomplete.
  ({_StepId step, String message})? _findProblem() {
    if (_validateTitle(titleController.text) != null) {
      return (
      step: _StepId.basics,
      message: _tr('Enter a property name', 'Weka jina la mali')
      );
    }

    if (_isHostel && campusNameController.text.trim().isEmpty) {
      return (
      step: _StepId.basics,
      message: _tr('Please enter the campus name for this hostel.',
          'Tafadhali weka jina la chuo kwa hosteli hii.')
      );
    }

    if (selectedCounty == null) {
      return (
      step: _StepId.location,
      message: _tr('Please select a county.', 'Tafadhali chagua kaunti.')
      );
    }

    if (selectedSubCounty == null) {
      return (
      step: _StepId.location,
      message: _tr('Please select a sub-county.',
          'Tafadhali chagua kaunti ndogo.')
      );
    }

    if (areaController.text.trim().isEmpty) {
      return (
      step: _StepId.location,
      message: _tr('Enter the estate or area', 'Weka mtaa au eneo')
      );
    }

    final priceError = _validatePrice(priceController.text);

    if (priceError != null) {
      return (step: _StepId.pricing, message: priceError);
    }

    if (!_usesPaymentCycleDropdown &&
        paymentCycleController.text.trim().isEmpty) {
      return (
      step: _StepId.pricing,
      message: _tr('Please enter the payment cycle.',
          'Tafadhali weka mzunguko wa malipo.')
      );
    }

    if (_isForSale) {
      if (saleDescriptionController.text.trim().isEmpty) {
        return (
        step: _StepId.pricing,
        message: _tr('Please enter the property description.',
            'Tafadhali weka maelezo ya mali.')
        );
      }
    } else {
      if (accommodationTypeController.text.trim().isEmpty) {
        return (
        step: _StepId.pricing,
        message: _tr('Enter the accommodation type', 'Weka aina ya makazi')
        );
      }

      final unitsError = _validateUnits(numberOfUnitsController.text);

      if (unitsError != null) {
        return (step: _StepId.pricing, message: unitsError);
      }

      if (_isHostel) {
        if (genderPreference == null) {
          return (
          step: _StepId.features,
          message: _tr('Select the gender preference for this hostel',
              'Chagua jinsia inayokubaliwa kwenye hosteli hii')
          );
        }

        final capacityError = _validateCapacity(roomCapacityController.text);

        if (capacityError != null) {
          return (step: _StepId.features, message: capacityError);
        }
      }

      if (amenitiesController.text.trim().isEmpty) {
        return (
        step: _StepId.features,
        message: _tr('Enter at least one amenity',
            'Weka huduma angalau moja')
        );
      }
    }

    return null;
  }

  // ============================================================
  // WIZARD NAVIGATION
  // ============================================================

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;

    _scrollController.jumpTo(0);
  }

  bool _validateCurrentStep() {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_isReadOnly) return true;

    final ok = _formKey.currentState?.validate() ?? true;

    if (!ok) {
      _showSnack(_tr(
        'Some required details are missing. Check the highlighted fields.',
        'Baadhi ya maelezo muhimu yakosekana. Angalia sehemu zilizoangaziwa.',
      ));

      _scrollToFirstError();

      return false;
    }

    return true;
  }

  void _next() {
    if (!_validateCurrentStep()) return;

    if (_step >= _steps.length - 1) return;

    setState(() {
      _step++;
      if (_step > _maxStep) _maxStep = _step;
    });

    _scrollToTop();
  }

  void _back() {
    if (_step == 0) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _step--);

    _scrollToTop();
  }

  void _goToStep(_StepId id) {
    final index = _steps.indexOf(id);

    if (index == -1) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _step = index);

    _scrollToTop();
  }

  void _goToStepIndex(int index) {
    if (index == _step || index > _maxStep || index >= _steps.length) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _step = index);

    _scrollToTop();
  }

  // ------------------------------------------------------------
  // SCROLL TO FIRST INVALID FIELD
  // ------------------------------------------------------------

  Future<void> _scrollToFirstError() async {
    final formState = _formKey.currentState;

    if (formState == null) return;

    BuildContext? errorContext;

    for (final field in formState.fields) {
      if (field.hasError) {
        errorContext = field.context;
        break;
      }
    }

    if (errorContext == null || !errorContext.mounted) return;

    await Scrollable.ensureVisible(
      errorContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.4,
    );
  }

  // ------------------------------------------------------------
  // SEARCHABLE PICKER (county + sub-county)
  // ------------------------------------------------------------

  Future<String?> _showSearchablePicker({
    required String title,
    required List<String> options,
    String? currentValue,
    String? emptyHint,
  }) {
    final searchController = TextEditingController();
    final searchFocus = FocusNode();

    var filtered = options;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
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
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  children: [
                    // ---------------- HANDLE + TITLE ----------------
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _mutedText,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _brand,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: _mutedText),
                            onPressed: () =>
                                Navigator.pop(sheetContext, null),
                          ),
                        ],
                      ),
                    ),

                    // ---------------- SEARCH BAR ----------------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                      child: TextField(
                        controller: searchController,
                        focusNode: searchFocus,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        style: TextStyle(color: _bodyText),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: _tr('Search...', 'Tafuta...'),
                          hintStyle: TextStyle(color: _hintText),
                          prefixIcon: Icon(Icons.search, color: _brand),
                          filled: true,
                          fillColor: _fieldFill,
                          contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                            BorderSide(color: _brand, width: 1.6),
                          ),
                        ),
                        onChanged: (query) {
                          setSheetState(() {
                            final q = query.trim().toLowerCase();
                            filtered = q.isEmpty
                                ? options
                                : options
                                .where((item) =>
                                item.toLowerCase().contains(q))
                                .toList();
                          });
                        },
                      ),
                    ),

                    // ---------------- OPTION LIST ----------------
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                        child: Text(
                          emptyHint ??
                              _tr('No matches found',
                                  'Hakuna matokeo yanayolingana'),
                          style:
                          TextStyle(color: _mutedText, fontSize: 13),
                        ),
                      )
                          : Scrollbar(
                        child: ListView.builder(
                          padding:
                          const EdgeInsets.fromLTRB(8, 0, 8, 16),
                          itemCount: filtered.length,
                          itemBuilder: (listContext, index) {
                            final option = filtered[index];

                            final isSelected =
                                option == currentValue;

                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(10),
                              ),
                              leading: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.location_on_outlined,
                                color: isSelected
                                    ? _brand
                                    : _mutedText,
                                size: 20,
                              ),
                              title: Text(
                                option,
                                style: TextStyle(
                                  color: isSelected
                                      ? _brand
                                      : _bodyText,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              onTap: () => Navigator.pop(
                                sheetContext,
                                option,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      searchController.dispose();
      searchFocus.dispose();
    });
  }

  Future<void> _pickCounty() async {
    if (_isReadOnly) return;

    final result = await _showSearchablePicker(
      title: _tr('Select county', 'Chagua kaunti'),
      options: KenyaLocation.counties,
      currentValue: selectedCounty,
    );

    if (result == null) return;

    setState(() {
      selectedCounty = result;
      selectedSubCounty = null;
    });

    _countyFieldKey.currentState?.didChange(result);
    _subCountyFieldKey.currentState?.didChange(null);
  }

  Future<void> _pickSubCounty() async {
    if (_isReadOnly || selectedCounty == null) return;

    final result = await _showSearchablePicker(
      title: _tr('Select sub-county', 'Chagua kaunti ndogo'),
      options: KenyaLocation.subcountiesOf(selectedCounty!),
      currentValue: selectedSubCounty,
    );

    if (result == null) return;

    setState(() {
      selectedSubCounty = result;
    });

    _subCountyFieldKey.currentState?.didChange(result);
  }

  // ============================================================
  // MEDIA VALIDATION
  // ============================================================

  String _fileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');

    if (dot == -1 || dot == fileName.length - 1) return '';

    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Detects the REAL image format from the file's first bytes
  /// (not just its name). Returns 'jpg', 'png', 'webp' or null.
  String? _detectImageFormat(Uint8List b) {
    if (b.length < 12) return null;

    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpg';

    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'png';
    }

    // RIFF....WEBP
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'webp';
    }

    return null;
  }

  String _imageMime(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  String _videoMime(String extension) {
    switch (extension) {
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      default:
        return 'video/mp4';
    }
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  /// Checks size, real format and dimensions of one picked photo.
  Future<({String? error, Uint8List? bytes, String? extension})>
  _validateImage(XFile file) async {
    final size = await file.length();

    if (size > _kMaxImageMb * 1024 * 1024) {
      return (
      error: _tr(
        'is too large (${_mb(size)} MB). The limit is $_kMaxImageMb MB.',
        'ni kubwa mno (MB ${_mb(size)}). Kikomo ni MB $_kMaxImageMb.',
      ),
      bytes: null,
      extension: null,
      );
    }

    final bytes = await file.readAsBytes();

    final format = _detectImageFormat(bytes);

    if (format == null) {
      return (
      error: _tr(
        'is not a supported format. Use JPG, PNG or WebP.',
        'si umbizo linalokubalika. Tumia JPG, PNG au WebP.',
      ),
      bytes: null,
      extension: null,
      );
    }

    int width;
    int height;

    try {
      final decoded = await decodeImageFromList(bytes);

      width = decoded.width;
      height = decoded.height;

      decoded.dispose();
    } catch (_) {
      return (
      error: _tr(
        'could not be read. The file may be damaged.',
        'haikuweza kusomwa. Faili inaweza kuwa imeharibika.',
      ),
      bytes: null,
      extension: null,
      );
    }

    final shortSide = width < height ? width : height;
    final longSide = width < height ? height : width;

    if (shortSide < _kMinImageShortSide || longSide < _kMinImageLongSide) {
      return (
      error: _tr(
        'is too small (${width}x$height). Minimum is '
            '$_kMinImageLongSide x $_kMinImageShortSide pixels.',
        'ni ndogo mno (${width}x$height). Kiwango cha chini ni '
            'pikseli $_kMinImageLongSide x $_kMinImageShortSide.',
      ),
      bytes: null,
      extension: null,
      );
    }

    if (longSide > _kMaxImageLongSide) {
      return (
      error: _tr(
        'is too large in dimensions (${width}x$height). The maximum is '
            '$_kMaxImageLongSide pixels on the longest side.',
        'ina vipimo vikubwa mno (${width}x$height). Kiwango cha juu ni '
            'pikseli $_kMaxImageLongSide upande mrefu.',
      ),
      bytes: null,
      extension: null,
      );
    }

    return (error: null, bytes: bytes, extension: format);
  }

  // ------------------------------------------------------------
  // PICK PHOTOS
  // ------------------------------------------------------------

  Future<void> _pickImages() async {
    if (_isReadOnly) return;

    if (_photos.length >= _kMaxImages) {
      _showSnack(_tr(
        'You can only add up to $_kMaxImages photos.',
        'Unaweza kuongeza picha $_kMaxImages pekee.',
      ));
      return;
    }

    final picked = await _picker.pickMultiImage();

    if (picked.isEmpty) return;

    final problems = <String>[];
    var skippedForLimit = 0;

    for (final file in picked) {
      if (_photos.length >= _kMaxImages) {
        skippedForLimit++;
        continue;
      }

      final result = await _validateImage(file);

      if (result.error != null) {
        problems.add('${file.name} ${result.error}');
        continue;
      }

      if (!mounted) return;

      setState(() {
        _photos.add(_PhotoItem.local(
          file: file,
          bytes: result.bytes!,
          extension: result.extension!,
        ));
      });
    }

    if (problems.isNotEmpty) {
      final extra = problems.length > 1
          ? _tr(' (+${problems.length - 1} more not added)',
          ' (+${problems.length - 1} nyingine hazikuongezwa)')
          : '';

      _showSnack('${problems.first}$extra');
    } else if (skippedForLimit > 0) {
      _showSnack(_tr(
        'Only $_kMaxImages photos are allowed. Extra photos were not added.',
        'Picha $_kMaxImages pekee zinaruhusiwa. Picha za ziada hazikuongezwa.',
      ));
    }
  }

  // ------------------------------------------------------------
  // PICK VIDEO — validated, then previewed so the owner can
  // confirm it is the right one BEFORE it is added.
  // ------------------------------------------------------------

  Future<void> _pickVideo() async {
    if (_isReadOnly) return;

    if (_videos.length >= _kMaxVideos) {
      _showSnack(_tr(
        'You can only add up to $_kMaxVideos videos.',
        'Unaweza kuongeza video $_kMaxVideos pekee.',
      ));
      return;
    }

    final picked = await _picker.pickVideo(source: ImageSource.gallery);

    if (picked == null) return;

    final extension = _fileExtension(picked.name);

    if (!_kVideoExtensions.contains(extension)) {
      _showSnack(_tr(
        'Unsupported video format. Use MP4, MOV, WebM or 3GP.',
        'Umbizo wa video haukubaliki. Tumia MP4, MOV, WebM au 3GP.',
      ));
      return;
    }

    final sizeBytes = await picked.length();

    if (sizeBytes > _kMaxVideoMb * 1024 * 1024) {
      _showSnack(_tr(
        'That video is too large (${_mb(sizeBytes)} MB). The limit is $_kMaxVideoMb MB.',
        'Video hiyo ni kubwa mno (MB ${_mb(sizeBytes)}). Kikomo ni MB $_kMaxVideoMb.',
      ));
      return;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VideoPreviewDialog(
        file: picked,
        confirmMode: true,
        brand: _brand,
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _videos.add(_VideoItem.local(
        file: picked,
        extension: extension,
        sizeBytes: sizeBytes,
      ));
    });
  }

  void _previewVideo(_VideoItem item) {
    showDialog<bool>(
      context: context,
      builder: (_) => _VideoPreviewDialog(
        url: item.url,
        file: item.file,
        brand: _brand,
      ),
    );
  }

  // ------------------------------------------------------------
  // PHOTO ORDER / COVER / REMOVE
  // ------------------------------------------------------------

  void _makeCover(int index) {
    if (_isReadOnly || index == 0) return;

    setState(() {
      final item = _photos.removeAt(index);
      _photos.insert(0, item);
    });

    _showSnack(_tr('Cover photo updated.', 'Picha kuu imesasishwa.'));
  }

  void _reorderPhotos(int oldIndex, int newIndex) {
    if (_isReadOnly) return;

    if (newIndex > oldIndex) newIndex -= 1;

    setState(() {
      final item = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, item);
    });
  }

  void _removePhoto(int index) {
    if (_isReadOnly) return;
    setState(() => _photos.removeAt(index));
  }

  void _removeVideo(int index) {
    if (_isReadOnly) return;
    setState(() => _videos.removeAt(index));
  }

  // ============================================================
  // UPLOAD + CLEANUP
  // ============================================================

  Future<String> _uploadPhoto({
    required _PhotoItem item,
    required String ownerId,
    required String propertyId,
    required int stamp,
    required int index,
    required List<Reference> uploaded,
  }) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('properties')
        .child(ownerId)
        .child(propertyId)
        .child('units')
        .child('${stamp}_$index.${item.extension}');

    await ref.putData(
      item.bytes!,
      SettableMetadata(contentType: _imageMime(item.extension)),
    );

    uploaded.add(ref);

    return ref.getDownloadURL();
  }

  Future<String> _uploadVideo({
    required _VideoItem item,
    required String ownerId,
    required String propertyId,
    required int stamp,
    required int index,
    required List<Reference> uploaded,
  }) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('properties')
        .child(ownerId)
        .child(propertyId)
        .child('videos')
        .child('${stamp}_$index.${item.extension}');

    final metadata = SettableMetadata(contentType: _videoMime(item.extension));

    if (kIsWeb) {
      await ref.putData(await item.file!.readAsBytes(), metadata);
    } else {
      // putFile streams from disk instead of loading the whole
      // video into memory.
      await ref.putFile(File(item.file!.path), metadata);
    }

    uploaded.add(ref);

    return ref.getDownloadURL();
  }

  /// Deletes files uploaded during a save that then failed, so
  /// nothing is left orphaned in Storage. Best effort.
  Future<void> _deleteUploaded(List<Reference> uploaded) async {
    for (final ref in uploaded) {
      try {
        await ref.delete();
      } catch (e) {
        debugPrint('UPLOAD CLEANUP ERROR (${ref.fullPath}): $e');
      }
    }
  }

  /// After the property document was saved successfully, deletes
  /// the files the owner removed.
  ///
  /// Safety rules:
  ///  * only files that were in the property's PREVIOUS server
  ///    document and are no longer used anywhere in the new
  ///    document are deleted (a file shared by photos and videos
  ///    lists is never removed while still referenced);
  ///  * only files inside THIS listing's own storage folder
  ///    (properties/<ownerId>/<propertyId>/) are deleted, so a
  ///    URL copied from another listing is never touched.
  Future<void> _deleteRemovedFiles({
    required Set<String> previousUrls,
    required Set<String> keptUrls,
    required String ownerId,
    required String propertyId,
  }) async {
    final removed = previousUrls.difference(keptUrls);

    if (removed.isEmpty) return;

    final ownFolder = 'properties/$ownerId/$propertyId/';

    for (final url in removed) {
      try {
        final ref = FirebaseStorage.instance.refFromURL(url);

        if (!ref.fullPath.startsWith(ownFolder)) continue;

        await ref.delete();
      } catch (e) {
        // Not a Storage URL, or already gone. Never fail the
        // save because of leftover cleanup.
        debugPrint('REMOVED FILE CLEANUP ERROR: $e');
      }
    }
  }

  // ============================================================
  // SAVE PROPERTY
  // ============================================================

  Future<void> save() async {
    if (_isReadOnly || isLoading) return;

    FocusManager.instance.primaryFocus?.unfocus();

    // ----------------------------------------------------------
    // Final check of EVERY required field, whatever order the
    // owner filled the steps in.
    // ----------------------------------------------------------

    final problem = _findProblem();

    if (problem != null) {
      _goToStep(problem.step);
      _showSnack(problem.message);
      return;
    }

    setState(() {
      isLoading = true;
      _uploadStatus = _tr('Checking your account...',
          'Inathibitisha akaunti yako...');
    });

    final uploaded = <Reference>[];

    var saved = false;

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _showSnack(_tr('Please login again.', 'Tafadhali ingia tena.'));
        return;
      }

      // --------------------------------------------------------
      // ROLE + OWNERSHIP — re-checked against the SERVER right
      // before anything is uploaded or written.
      // --------------------------------------------------------

      final access = await _checkOwnerAccess(user);

      if (access.error != null) {
        _showSnack(access.error!);
        return;
      }

      // Files the property document currently references on the
      // server (used later to delete only what was removed).
      final previousUrls = <String>{
        ..._listFrom(access.property?['images']),
        ..._listFrom(access.property?['unitImages']),
        ..._listFrom(access.property?['videos']),
      };

      // --------------------------------------------------------
      // PROPERTY DOCUMENT
      // --------------------------------------------------------

      final collection = FirebaseFirestore.instance.collection('properties');

      final docRef = widget.propertyId == null
          ? collection.doc()
          : collection.doc(widget.propertyId);

      final stamp = DateTime.now().millisecondsSinceEpoch;

      // --------------------------------------------------------
      // UPLOAD MEDIA — in the owner's chosen order.
      // --------------------------------------------------------

      final imageUrls = <String>[];

      for (var i = 0; i < _photos.length; i++) {
        final item = _photos[i];

        if (item.isRemote) {
          imageUrls.add(item.url!);
          continue;
        }

        if (mounted) {
          setState(() {
            _uploadStatus = _tr(
              'Uploading photo ${i + 1} of ${_photos.length}...',
              'Inapakia picha ${i + 1} kati ya ${_photos.length}...',
            );
          });
        }

        imageUrls.add(await _uploadPhoto(
          item: item,
          ownerId: user.uid,
          propertyId: docRef.id,
          stamp: stamp,
          index: i,
          uploaded: uploaded,
        ));
      }

      final videoUrls = <String>[];

      for (var i = 0; i < _videos.length; i++) {
        final item = _videos[i];

        if (item.isRemote) {
          videoUrls.add(item.url!);
          continue;
        }

        if (mounted) {
          setState(() {
            _uploadStatus = _tr(
              'Uploading video ${i + 1} of ${_videos.length}...',
              'Inapakia video ${i + 1} kati ya ${_videos.length}...',
            );
          });
        }

        videoUrls.add(await _uploadVideo(
          item: item,
          ownerId: user.uid,
          propertyId: docRef.id,
          stamp: stamp,
          index: i,
          uploaded: uploaded,
        ));
      }

      if (mounted) {
        setState(() {
          _uploadStatus = _tr('Saving property...', 'Inahifadhi mali...');
        });
      }

      // --------------------------------------------------------
      // PAYMENT CYCLE
      // --------------------------------------------------------

      final effectivePaymentCycle = _usesPaymentCycleDropdown
          ? paymentCycle
          : paymentCycleController.text.trim();

      // --------------------------------------------------------
      // PROPERTY PAYLOAD
      // --------------------------------------------------------

      final payload = <String, dynamic>{
        'title': titleController.text.trim(),
        'purpose': purpose,
        'category': selectedCategory,
        'type': propertyType,
        'county': selectedCounty,
        'subCounty': selectedSubCounty,
        'area': areaController.text.trim(),
        'location': [
          areaController.text.trim(),
          selectedSubCounty,
          selectedCounty,
        ]
            .where((item) => item != null && item.toString().isNotEmpty)
            .join(', '),
        'price': _priceValue ?? 0,
        'currency': 'KES',
        'paymentCycle': effectivePaymentCycle,

        // Ordered gallery: the FIRST photo is the cover photo.
        'images': imageUrls,
        'unitImages': imageUrls,
        'videos': videoUrls,

        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (imageUrls.isNotEmpty) {
        payload['mainImage'] = imageUrls.first;
        payload['coverImage'] = imageUrls.first;
      } else if (widget.isEditing) {
        payload['mainImage'] = FieldValue.delete();
        payload['coverImage'] = FieldValue.delete();
      }

      if (_isForSale) {
        payload['description'] = saleDescriptionController.text.trim();

        if (widget.isEditing) {
          payload['accommodationType'] = FieldValue.delete();
          payload['unitDetails'] = FieldValue.delete();
          payload['numberOfUnits'] = FieldValue.delete();
          payload['amenities'] = FieldValue.delete();
        }
      } else {
        final amenities = amenitiesController.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();

        final accommodationType = accommodationTypeController.text.trim();

        payload['accommodationType'] = accommodationType;
        payload['numberOfUnits'] =
            int.tryParse(numberOfUnitsController.text.trim()) ?? 0;
        payload['unitDetails'] = accommodationType;
        payload['amenities'] = amenities;
        payload['description'] = extraDetailsController.text.trim();
      }

      // --------------------------------------------------------
      // HOSTEL INFORMATION
      // --------------------------------------------------------

      if (_isHostel) {
        payload['campusName'] = campusNameController.text.trim();
        payload['genderPreference'] = genderPreference;
        payload['roomCapacity'] =
            int.tryParse(roomCapacityController.text.trim()) ?? 1;
        payload['sharedFacilities'] = _sharedFacilities.toList();
      } else if (widget.isEditing) {
        payload['campusName'] = FieldValue.delete();
        payload['genderPreference'] = FieldValue.delete();
        payload['roomCapacity'] = FieldValue.delete();
        payload['sharedFacilities'] = FieldValue.delete();
      }

      // --------------------------------------------------------
      // NEW PROPERTY
      // --------------------------------------------------------

      if (!widget.isEditing) {
        payload.addAll({
          'ownerId': user.uid,
          'available': true,
          'isActive': true,
          'status': 'pending',
          'property_status': 'unverified',
          'adsverification': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // --------------------------------------------------------
      // SAVE
      // --------------------------------------------------------

      await docRef.set(
        payload,
        widget.isEditing ? SetOptions(merge: true) : null,
      );

      saved = true;

      // --------------------------------------------------------
      // Only now that the document is safely saved: delete files
      // the owner removed.
      // --------------------------------------------------------

      await _deleteRemovedFiles(
        previousUrls: previousUrls,
        keptUrls: {...imageUrls, ...videoUrls},
        ownerId: user.uid,
        propertyId: docRef.id,
      );

      if (!mounted) return;

      _showSnack(
        widget.isEditing
            ? _tr('Property updated successfully.',
            'Mali imesasishwa kwa mafanikio.')
            : _tr('Property submitted for approval.',
            'Mali imetumwa kwa idhini.'),
      );

      Navigator.pop(context);
    } catch (e) {
      // The save did not complete: remove everything this attempt
      // uploaded so no orphan files stay in Storage.
      if (!saved) {
        await _deleteUploaded(uploaded);
      }

      _showSnack('${_tr('Unable to save property: ',
          'Imeshindikana kuhifadhi mali: ')}$e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          _uploadStatus = null;
        });
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final title = _isReadOnly
        ? _tr('View Property', 'Angalia Mali')
        : widget.isEditing
        ? _tr('Edit Property', 'Hariri Mali')
        : _tr('Add Property', 'Ongeza Mali');

    // ---------------- checking access ----------------

    if (_accessChecking) {
      return Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
        ),
        body: Center(child: CircularProgressIndicator(color: _brand)),
      );
    }

    // ---------------- access denied ----------------

    if (_accessError != null) {
      return Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 54, color: _errColor),
                const SizedBox(height: 14),
                Text(
                  _accessError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _bodyText, fontSize: 15),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _brand,
                        side: BorderSide(color: _brand),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(_tr('Go back', 'Rudi nyuma')),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _runAccessCheck,
                      child: Text(_tr('Try again', 'Jaribu tena')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ---------------- the form ----------------

    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      // The phone's back button / gesture steps back through the
      // form first, and only leaves the page from step 1.
      canPop: _step == 0 && !isLoading,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || isLoading) return;
        if (_step > 0) _back();
      },
      child: Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBar: keyboardOpen ? null : _bottomBar(),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stepHeader(),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      autovalidateMode: _isReadOnly
                          ? AutovalidateMode.disabled
                          : AutovalidateMode.onUserInteraction,
                      child: _stepContent(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // STEP HEADER — numbered circles + progress bar
  // ------------------------------------------------------------

  Widget _stepHeader() {
    final steps = _steps;
    final total = steps.length;

    final circles = <Widget>[];

    for (var i = 0; i < total; i++) {
      final done = i < _step;
      final current = i == _step;
      final reachable = i <= _maxStep;

      circles.add(
        GestureDetector(
          onTap: reachable ? () => _goToStepIndex(i) : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? _brand
                  : current
                  ? _brand.withValues(alpha: 0.14)
                  : Colors.transparent,
              border: Border.all(
                color: (done || current) ? _brand : _cardBorder,
                width: current ? 2 : 1.4,
              ),
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: current ? _brand : _mutedText,
                ),
              ),
            ),
          ),
        ),
      );

      if (i != total - 1) {
        circles.add(
          Expanded(
            child: Container(
              height: 2,
              color: i < _step ? _brand : _cardBorder,
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: circles),
        const SizedBox(height: 12),
        Text(
          _tr('Step ${_step + 1} of $total', 'Hatua ${_step + 1} kati ya $total'),
          style: TextStyle(fontSize: 12, color: _mutedText),
        ),
        const SizedBox(height: 2),
        Text(
          _stepTitle(_currentStep),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: _brand,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (_step + 1) / total,
            minHeight: 6,
            color: _brand,
            backgroundColor: _brand.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // BOTTOM BAR — Back / Cancel + Next / List Property
  // ------------------------------------------------------------

  Widget _bottomBar() {
    final isLast = _step >= _steps.length - 1;

    final String primaryLabel = !isLast
        ? _tr('Next', 'Endelea')
        : _isReadOnly
        ? _tr('Close', 'Funga')
        : widget.isEditing
        ? _tr('Save Changes', 'Hifadhi Mabadiliko')
        : _tr('List Property', 'Weka Mali');

    final IconData primaryIcon = !isLast
        ? Icons.arrow_forward
        : _isReadOnly
        ? Icons.close
        : widget.isEditing
        ? Icons.save
        : Icons.add_home_work;

    return Material(
      elevation: 10,
      color: _cardColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: isLoading
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _brand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _uploadStatus ??
                          _tr('Saving...', 'Inahifadhi...'),
                      style: TextStyle(color: _bodyText),
                    ),
                  ),
                ],
              )
                  : Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _brand,
                        side: BorderSide(color: _brand),
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                          horizontal: 8,
                        ),
                      ),
                      onPressed: _step == 0 ? _cancel : _back,
                      child: Text(
                        _step == 0
                            ? _tr('Cancel', 'Ghairi')
                            : _tr('Back', 'Rudi'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                          horizontal: 8,
                        ),
                      ),
                      onPressed: !isLast
                          ? _next
                          : (_isReadOnly ? _cancel : save),
                      icon: Icon(primaryIcon),
                      label: Text(
                        primaryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  // ------------------------------------------------------------
  // STEP CONTENT
  // ------------------------------------------------------------

  Widget _stepContent() {
    switch (_currentStep) {
      case _StepId.basics:
        return _basicsStep();
      case _StepId.location:
        return _locationStep();
      case _StepId.pricing:
        return _pricingStep();
      case _StepId.features:
        return _featuresStep();
      case _StepId.media:
        return _mediaStep();
      case _StepId.preview:
        return _previewStep();
    }
  }

  // ---------------- STEP 1: TYPE + NAME (+ CAMPUS) ----------------

  Widget _basicsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          icon: Icons.home_work,
          title: _tr('Property type & name', 'Aina ya mali na jina'),
          children: [
            DropdownButtonFormField<String>(
              initialValue: purpose,
              decoration: _fieldDecoration(_tr('Purpose', 'Madhumuni')),
              items: [
                DropdownMenuItem(
                  value: 'rent',
                  child: Text(_tr('For Rent', 'Ya Kupangisha')),
                ),
                DropdownMenuItem(
                  value: 'sale',
                  child: Text(_tr('For Sale', 'Ya Kuuza')),
                ),
              ],
              onChanged: _isReadOnly
                  ? null
                  : (value) {
                setState(() {
                  purpose = value ?? purpose;

                  selectedCategory = _availableCategories.first;
                  propertyType = _availableTypes.first;
                });
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('category_${purpose}_$selectedCategory'),
              initialValue: selectedCategory,
              decoration: _fieldDecoration(
                _isForSale
                    ? _tr('Sale category', 'Kategoria ya kuuza')
                    : _tr('Rent category', 'Kategoria ya kupangisha'),
              ),
              items: _availableCategories
                  .map(
                    (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item),
                ),
              )
                  .toList(),
              onChanged: _isReadOnly
                  ? null
                  : (value) {
                setState(() {
                  selectedCategory = value ?? selectedCategory;
                  propertyType = _availableTypes.first;
                });
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('type_${purpose}_$selectedCategory'),
              initialValue: propertyType,
              decoration:
              _fieldDecoration(_tr('Property type', 'Aina ya mali')),
              items: _availableTypes
                  .map(
                    (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item),
                ),
              )
                  .toList(),
              onChanged: _isReadOnly
                  ? null
                  : (value) {
                setState(() {
                  propertyType = value ?? propertyType;
                });
              },
            ),
            const SizedBox(height: 14),
            _textField(
              controller: titleController,
              label: _tr('Property name', 'Jina la mali'),
              validator: _validateTitle,
            ),
          ],
        ),
        if (_isHostel) ...[
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.school,
            title: _tr('Campus', 'Chuo'),
            subtitle: _tr(
              'Required for hostel listings. Enter the campus this hostel serves.',
              'Inahitajika kwa hosteli. Weka chuo ambacho hosteli hii inahudumia.',
            ),
            children: [
              _textField(
                controller: campusNameController,
                label: _tr('Campus name', 'Jina la chuo'),
                hintText: _tr('e.g. Maseno University',
                    'mfano Chuo Kikuu cha Maseno'),
                validator: (value) {
                  if (!_isHostel) return null;

                  if (value == null || value.trim().isEmpty) {
                    return _tr(
                        'Enter the campus name', 'Weka jina la chuo');
                  }

                  return null;
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------- STEP 2: LOCATION ----------------

  Widget _locationStep() {
    return _sectionCard(
      icon: Icons.location_on,
      title: _tr('Location details', 'Maelezo ya eneo'),
      children: [
        _pickerField(
          fieldKey: _countyFieldKey,
          label: _tr('County', 'Kaunti'),
          value: selectedCounty,
          placeholder:
          _tr('Tap to select county', 'Bonyeza kuchagua kaunti'),
          errorText: _tr('Select a county', 'Chagua kaunti'),
          onPick: _pickCounty,
        ),
        const SizedBox(height: 14),
        _pickerField(
          fieldKey: _subCountyFieldKey,
          label: _tr('Sub-county', 'Kaunti ndogo'),
          value: selectedSubCounty,
          placeholder: selectedCounty == null
              ? _tr('Select a county first', 'Chagua kaunti kwanza')
              : _tr('Tap to select sub-county',
              'Bonyeza kuchagua kaunti ndogo'),
          errorText: _tr('Select a sub-county', 'Chagua kaunti ndogo'),
          onPick: selectedCounty == null ? null : _pickSubCounty,
        ),
        const SizedBox(height: 14),
        _textField(
          controller: areaController,
          label: _tr('Estate / Area', 'Mtaa / Eneo'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _tr('Enter the estate or area', 'Weka mtaa au eneo');
            }

            return null;
          },
        ),
      ],
    );
  }

  // ---------------- STEP 3: PRICE + UNITS / DESCRIPTION ----------------

  Widget _pricingStep() {
    final maxPrice = _isForSale ? _kMaxSalePrice : _kMaxRentPrice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          icon: Icons.payments,
          title: _isForSale
              ? _tr('Price & payment', 'Bei na malipo')
              : _tr('Rent & payment', 'Kodi na malipo'),
          children: [
            _textField(
              controller: priceController,
              label: _isForSale
                  ? _tr('Asking price', 'Bei ya kuuza')
                  : _tr('Amount of rent', 'Kiasi cha kodi'),
              prefixText: 'KES ',
              helperText: _tr(
                'Maximum KES ${_formatAmount(maxPrice)}',
                'Kiwango cha juu KES ${_formatAmount(maxPrice)}',
              ),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_CurrencyInputFormatter()],
              validator: _validatePrice,
            ),
            const SizedBox(height: 14),

            // HOSTEL keeps the fixed dropdown (monthly / per
            // semester). Every other type gets a free-text input.
            if (_usesPaymentCycleDropdown)
              DropdownButtonFormField<String>(
                initialValue: paymentCycle,
                decoration: _fieldDecoration(
                    _tr('Payment cycle', 'Mzunguko wa malipo')),
                items: [
                  DropdownMenuItem(
                    value: 'monthly',
                    child: Text(_tr('Per Month', 'Kwa Mwezi')),
                  ),
                  DropdownMenuItem(
                    value: 'per_semester',
                    child: Text(_tr('Per Semester', 'Kwa Muhula')),
                  ),
                ],
                onChanged: _isReadOnly
                    ? null
                    : (value) {
                  setState(() {
                    paymentCycle = value ?? paymentCycle;
                  });
                },
              )
            else
              _textField(
                controller: paymentCycleController,
                label: _tr('Payment cycle', 'Mzunguko wa malipo'),
                hintText: _kPaymentCycleHint,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _tr('Enter the payment cycle',
                        'Weka mzunguko wa malipo');
                  }

                  return null;
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          icon: _isForSale ? Icons.description : Icons.meeting_room,
          title: _isForSale
              ? _tr('Property details', 'Maelezo ya mali')
              : _tr('Unit details', 'Maelezo ya kitengo'),
          subtitle: _isForSale
              ? _tr('Describe the property.', 'Eleza mali.')
              : _tr(
            'Enter the accommodation type and how many units of that type are available.',
            'Weka aina ya makazi na idadi ya vitengo vinavyopatikana.',
          ),
          children: [
            if (_isForSale)
              _textField(
                controller: saleDescriptionController,
                label: _tr('Property description', 'Maelezo ya mali'),
                maxLines: 6,
                hintText: _kSaleDescriptionHint,
                hintMaxLines: 6,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _tr('Enter the property description',
                        'Weka maelezo ya mali');
                  }

                  return null;
                },
              )
            else ...[
              _textField(
                controller: accommodationTypeController,
                label: _tr('Accommodation type', 'Aina ya makazi'),
                hintText: _tr(
                  'e.g. Bedsitter, 1 Bedroom, Single Room',
                  'mfano Bedsitter, Chumba 1, Chumba kimoja',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _tr('Enter the accommodation type',
                        'Weka aina ya makazi');
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              _textField(
                controller: numberOfUnitsController,
                label: _tr('Number of units', 'Idadi ya vitengo'),
                hintText: _tr('e.g. 5', 'mfano 5'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _validateUnits,
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ---------------- STEP 4 (rent only): HOSTEL INFO + AMENITIES ----------------

  Widget _featuresStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isHostel) ...[
          _sectionCard(
            icon: Icons.bed,
            title: _tr('Hostel information', 'Taarifa za hosteli'),
            subtitle: _tr(
              'Helps students find the right hostel quickly.',
              'Huwasaidia wanafunzi kupata hosteli sahihi haraka.',
            ),
            children: [
              DropdownButtonFormField<String>(
                initialValue: genderPreference,
                decoration: _fieldDecoration(
                    _tr('Gender preference', 'Jinsia inayokubaliwa')),
                items: [
                  for (final option in _kGenderOptions)
                    DropdownMenuItem(
                      value: option.$1,
                      child: Text(_tr(option.$2, option.$3)),
                    ),
                ],
                validator: (value) {
                  if (!_isHostel) return null;

                  if (value == null) {
                    return _tr('Select the gender preference',
                        'Chagua jinsia inayokubaliwa');
                  }

                  return null;
                },
                onChanged: _isReadOnly
                    ? null
                    : (value) => setState(() => genderPreference = value),
              ),
              const SizedBox(height: 14),
              _textField(
                controller: roomCapacityController,
                label: _tr('Room capacity (people per room)',
                    'Uwezo wa chumba (watu kwa chumba)'),
                hintText: _tr('e.g. 2', 'mfano 2'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) =>
                _isHostel ? _validateCapacity(value) : null,
              ),
              const SizedBox(height: 16),
              Text(
                _tr('Shared facilities', 'Huduma za pamoja'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _bodyText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _tr('Select everything students will share.',
                    'Chagua kila kitu ambacho wanafunzi watashiriki.'),
                style: TextStyle(fontSize: 12.5, color: _mutedText),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final facility in _kSharedFacilities)
                    FilterChip(
                      label: Text(_tr(facility.$1, facility.$2)),
                      selected: _sharedFacilities.contains(facility.$1),
                      selectedColor: _brand.withValues(alpha: 0.25),
                      checkmarkColor: _brand,
                      backgroundColor: _cardColor,
                      side: BorderSide(
                        color: _sharedFacilities.contains(facility.$1)
                            ? _brand
                            : _cardBorder,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        color: _bodyText,
                      ),
                      onSelected: _isReadOnly
                          ? null
                          : (selected) {
                        setState(() {
                          if (selected) {
                            _sharedFacilities.add(facility.$1);
                          } else {
                            _sharedFacilities.remove(facility.$1);
                          }
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _sectionCard(
          icon: Icons.checklist,
          title: _tr('Amenities', 'Huduma'),
          subtitle: _tr('Separate each amenity with a comma.',
              'Tenganisha kila huduma kwa koma.'),
          children: [
            _textField(
              controller: amenitiesController,
              label: _tr('Amenities', 'Huduma'),
              maxLines: 5,
              hintText: _kAmenitiesHint,
              hintMaxLines: 6,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return _tr('Enter at least one amenity',
                      'Weka huduma angalau moja');
                }

                return null;
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          icon: Icons.notes,
          title: _tr('Extra details', 'Maelezo ya ziada'),
          subtitle: _tr(
            'Anything else prospective tenants should know.',
            'Mambo mengine wanapangaji wanapaswa kujua.',
          ),
          children: [
            _textField(
              controller: extraDetailsController,
              label: _tr('Extra details (optional)',
                  'Maelezo ya ziada (si lazima)'),
              maxLines: 6,
              hintText: _kExtraDetailsHint,
              hintMaxLines: 6,
            ),
          ],
        ),
      ],
    );
  }

  // ---------------- STEP 5: PHOTOS + VIDEOS ----------------

  Widget _mediaStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          icon: Icons.photo_library,
          title: _isForSale
              ? _tr('Property photos', 'Picha za mali')
              : _tr('Unit photos', 'Picha za kitengo'),
          subtitle: _tr(
            'Optional. Up to $_kMaxImages photos (JPG, PNG or WebP, max '
                '$_kMaxImageMb MB each, at least $_kMinImageLongSide x '
                '$_kMinImageShortSide pixels). The first photo is the '
                'cover photo shown on your listing.',
            'Si lazima. Hadi picha $_kMaxImages (JPG, PNG au WebP, '
                'kila moja isizidi MB $_kMaxImageMb, angalau pikseli '
                '$_kMinImageLongSide x $_kMinImageShortSide). Picha ya '
                'kwanza ndiyo picha kuu ya tangazo lako.',
          ),
          children: [_photoManager()],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          icon: Icons.videocam,
          title: _isForSale
              ? _tr('Property videos', 'Video za mali')
              : _tr('Unit videos', 'Video za kitengo'),
          subtitle: _tr(
            'Optional. Up to $_kMaxVideos videos (MP4, MOV, WebM or 3GP, '
                'max $_kMaxVideoMb MB each). You can preview a video '
                'before adding it.',
            'Si lazima. Hadi video $_kMaxVideos (MP4, MOV, WebM au 3GP, '
                'kila moja isizidi MB $_kMaxVideoMb). Unaweza kuikagua '
                'video kabla ya kuiongeza.',
          ),
          children: [_videoManager()],
        ),
      ],
    );
  }

  // ---------------- STEP 6: PREVIEW ----------------

  String _paymentCycleLabel() {
    if (_usesPaymentCycleDropdown) {
      return paymentCycle == 'per_semester'
          ? _tr('Per Semester', 'Kwa Muhula')
          : _tr('Per Month', 'Kwa Mwezi');
    }

    return paymentCycleController.text.trim();
  }

  Widget _previewRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: _mutedText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: _bodyText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewSection({
    required String title,
    required _StepId editStep,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 1.5,
        color: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _brand,
                      ),
                    ),
                  ),
                  if (!_isReadOnly)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: _brand),
                      onPressed: () => _goToStep(editStep),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(_tr('Edit', 'Hariri')),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewImage(_PhotoItem item, {double? height, double? width}) {
    final Widget image = item.isRemote
        ? Image.network(
      item.url!,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => _brokenImage(width, height),
    )
        : Image.memory(
      item.bytes!,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: image,
    );
  }

  Widget _brokenImage(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: _isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      child: Icon(Icons.broken_image, color: _hintText),
    );
  }

  Widget _previewStep() {
    final price = _priceValue;

    final amenities = amenitiesController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    final purposeLabel = _isForSale
        ? _tr('For Sale', 'Ya Kuuza')
        : _tr('For Rent', 'Ya Kupangisha');

    final locationLine = [
      areaController.text.trim(),
      selectedSubCounty,
      selectedCounty,
    ].where((item) => item != null && item.isNotEmpty).join(', ');

    final genderLabel = _kGenderOptions
        .where((option) => option.$1 == genderPreference)
        .map((option) => _tr(option.$2, option.$3))
        .join();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------------- headline card ----------------
        Card(
          elevation: 1.5,
          color: _cardColor,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_photos.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 190,
                  child: _previewImage(_photos.first, height: 190),
                )
              else
                Container(
                  width: double.infinity,
                  height: 120,
                  color: _brand.withValues(alpha: 0.08),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported_outlined,
                          color: _mutedText, size: 30),
                      const SizedBox(height: 6),
                      Text(
                        _tr('No photos added — listings with photos get '
                            'more attention.',
                            'Hakuna picha — mali zenye picha huvutia '
                                'zaidi.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _mutedText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleController.text.trim(),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: _bodyText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$purposeLabel · $selectedCategory · $propertyType',
                      style: TextStyle(fontSize: 12.5, color: _mutedText),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      price == null
                          ? '—'
                          : 'KES ${_formatAmount(price)}'
                          '${_paymentCycleLabel().isEmpty ? '' : ' · ${_paymentCycleLabel()}'}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _brand,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 16, color: _mutedText),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locationLine,
                            style: TextStyle(
                                fontSize: 13, color: _bodyText),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---------------- basics ----------------
        _previewSection(
          title: _tr('Property type', 'Aina ya mali'),
          editStep: _StepId.basics,
          children: [
            _previewRow(_tr('Purpose', 'Madhumuni'), purposeLabel),
            _previewRow(_tr('Category', 'Kategoria'), selectedCategory),
            _previewRow(_tr('Type', 'Aina'), propertyType),
            if (_isHostel)
              _previewRow(_tr('Campus', 'Chuo'),
                  campusNameController.text.trim()),
          ],
        ),

        // ---------------- location ----------------
        _previewSection(
          title: _tr('Location', 'Eneo'),
          editStep: _StepId.location,
          children: [
            _previewRow(_tr('County', 'Kaunti'), selectedCounty ?? ''),
            _previewRow(
                _tr('Sub-county', 'Kaunti ndogo'), selectedSubCounty ?? ''),
            _previewRow(
                _tr('Estate / Area', 'Mtaa / Eneo'), areaController.text.trim()),
          ],
        ),

        // ---------------- price + details ----------------
        _previewSection(
          title: _isForSale
              ? _tr('Price & details', 'Bei na maelezo')
              : _tr('Price & units', 'Bei na vitengo'),
          editStep: _StepId.pricing,
          children: [
            _previewRow(
              _isForSale
                  ? _tr('Asking price', 'Bei ya kuuza')
                  : _tr('Rent', 'Kodi'),
              price == null ? '' : 'KES ${_formatAmount(price)}',
            ),
            _previewRow(
                _tr('Payment cycle', 'Mzunguko wa malipo'),
                _paymentCycleLabel()),
            if (_isForSale)
              _previewRow(_tr('Description', 'Maelezo'),
                  saleDescriptionController.text.trim())
            else ...[
              _previewRow(_tr('Accommodation', 'Makazi'),
                  accommodationTypeController.text.trim()),
              _previewRow(_tr('Units', 'Vitengo'),
                  numberOfUnitsController.text.trim()),
            ],
          ],
        ),

        // ---------------- hostel + amenities (rent) ----------------
        if (!_isForSale)
          _previewSection(
            title: _isHostel
                ? _tr('Hostel & amenities', 'Hosteli na huduma')
                : _tr('Amenities', 'Huduma'),
            editStep: _StepId.features,
            children: [
              if (_isHostel) ...[
                _previewRow(_tr('Gender', 'Jinsia'), genderLabel),
                _previewRow(_tr('Room capacity', 'Uwezo wa chumba'),
                    roomCapacityController.text.trim()),
                if (_sharedFacilities.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _tr('Shared facilities', 'Huduma za pamoja'),
                    style: TextStyle(fontSize: 12.5, color: _mutedText),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final item in _sharedFacilities)
                        _previewChip(item),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
              ],
              if (amenities.isNotEmpty) ...[
                Text(
                  _tr('Amenities', 'Huduma'),
                  style: TextStyle(fontSize: 12.5, color: _mutedText),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final item in amenities) _previewChip(item)],
                ),
              ],
              _previewRow(_tr('Extra details', 'Maelezo ya ziada'),
                  extraDetailsController.text.trim()),
            ],
          ),

        // ---------------- media ----------------
        _previewSection(
          title: _tr('Photos & videos', 'Picha na video'),
          editStep: _StepId.media,
          children: [
            _previewRow(
              _tr('Photos', 'Picha'),
              '${_photos.length} / $_kMaxImages',
            ),
            _previewRow(
              _tr('Videos', 'Video'),
              '${_videos.length} / $_kMaxVideos',
            ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) =>
                      _previewImage(_photos[index], width: 64, height: 64),
                ),
              ),
            ],
          ],
        ),

        // ---------------- review notice ----------------
        if (!_isReadOnly)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _brand.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: _brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isEditing
                        ? _tr(
                      'Check everything above, then tap "Save Changes".',
                      'Kagua kila kitu hapo juu, kisha gusa "Hifadhi Mabadiliko".',
                    )
                        : _tr(
                      'Check everything above, then tap "List Property". '
                          'Your listing will be reviewed before it is shown to the public.',
                      'Kagua kila kitu hapo juu, kisha gusa "Weka Mali". '
                          'Tangazo lako litakaguliwa kabla ya kuonyeshwa kwa umma.',
                    ),
                    style: TextStyle(fontSize: 12.5, color: _bodyText),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _previewChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: _brand),
      ),
    );
  }

  // ------------------------------------------------------------
  // PHOTO MANAGER — add, set cover, drag to reorder, remove
  // ------------------------------------------------------------

  Widget _photoManager() {
    final canAddMore = !_isReadOnly && _photos.length < _kMaxImages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canAddMore)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _brand,
              side: BorderSide(color: _brand),
            ),
            onPressed: _pickImages,
            icon: const Icon(Icons.add_a_photo),
            label: Text(_tr('Add photos', 'Ongeza picha')),
          ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 112,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: !_isReadOnly,
              itemCount: _photos.length,
              onReorder: _reorderPhotos,
              proxyDecorator: (child, index, animation) =>
                  Material(color: Colors.transparent, child: child),
              itemBuilder: (context, index) {
                final item = _photos[index];

                return Padding(
                  key: item.key,
                  padding: const EdgeInsets.only(right: 10),
                  child: _photoTile(item, index),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _tr('${_photos.length}/$_kMaxImages photos added',
              'Picha ${_photos.length}/$_kMaxImages zimeongezwa'),
          style: TextStyle(fontSize: 12, color: _mutedText),
        ),
        if (_photos.length > 1 && !_isReadOnly)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _tr(
                'Press and hold a photo, then drag it to change the order. '
                    'Tap the star to make a photo the cover.',
                'Bonyeza na ushikilie picha, kisha iburute kubadilisha mpangilio. '
                    'Gusa nyota kuifanya picha kuu.',
              ),
              style: TextStyle(fontSize: 12, color: _mutedText),
            ),
          ),
      ],
    );
  }

  Widget _photoTile(_PhotoItem item, int index) {
    const double size = 96;

    final isCover = index == 0;

    final Widget image = item.isRemote
        ? Image.network(
      item.url!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) =>
          _brokenImage(size, size),
    )
        : Image.memory(
      item.bytes!,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCover ? _brand : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: image,
              ),
            ),
          ),

          // COVER badge on the first photo.
          if (isCover)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _brand,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _tr('Cover', 'Kuu'),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // SET AS COVER star on every other photo.
          if (!isCover && !_isReadOnly)
            Positioned(
              left: 4,
              bottom: 4,
              child: InkWell(
                onTap: () => _makeCover(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star_border,
                      size: 16, color: Colors.white),
                ),
              ),
            ),

          // Position number.
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),

          if (!_isReadOnly) _removeBadge(() => _removePhoto(index)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // VIDEO MANAGER — add (with confirm preview), play, remove
  // ------------------------------------------------------------

  Widget _videoManager() {
    final canAddMore = !_isReadOnly && _videos.length < _kMaxVideos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canAddMore)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _brand,
              side: BorderSide(color: _brand),
            ),
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_call),
            label: Text(_tr('Add video', 'Ongeza video')),
          ),
        if (_videos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _videos.length; i++) _videoTile(_videos[i], i),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _tr('${_videos.length}/$_kMaxVideos videos added',
              'Video ${_videos.length}/$_kMaxVideos zimeongezwa'),
          style: TextStyle(fontSize: 12, color: _mutedText),
        ),
        if (_videos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _tr('Tap a video to play it.', 'Gusa video kuicheza.'),
              style: TextStyle(fontSize: 12, color: _mutedText),
            ),
          ),
      ],
    );
  }

  Widget _videoTile(_VideoItem item, int index) {
    final label = item.isRemote
        ? _tr('Video ${index + 1}', 'Video ${index + 1}')
        : item.file!.name;

    return Stack(
      children: [
        InkWell(
          onTap: () => _previewVideo(item),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 104,
            height: 96,
            decoration: BoxDecoration(
              color: _isDark ? const Color(0xFF24312A) : Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_circle_fill,
                    color: Colors.white, size: 34),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white70,
                    ),
                  ),
                ),
                if (!item.isRemote)
                  Text(
                    '${_mb(item.sizeBytes)} MB',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!_isReadOnly) _removeBadge(() => _removeVideo(index)),
      ],
    );
  }

  // ------------------------------------------------------------
  // REMOVE BADGE
  // ------------------------------------------------------------

  Widget _removeBadge(VoidCallback onTap) {
    return Positioned(
      top: 4,
      right: 4,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // SEARCHABLE PICKER FIELD (county / sub-county)
  // ------------------------------------------------------------

  Widget _pickerField({
    required GlobalKey<FormFieldState<String>> fieldKey,
    required String label,
    required String? value,
    required String placeholder,
    required String errorText,
    required Future<void> Function()? onPick,
  }) {
    final enabled = onPick != null && !_isReadOnly;

    final hasValue = value != null && value.isNotEmpty;

    return FormField<String>(
      key: fieldKey,
      initialValue: value,
      enabled: enabled,
      validator: (current) =>
      (current == null || current.isEmpty) ? errorText : null,
      builder: (fieldState) {
        return InkWell(
          onTap: enabled ? onPick : null,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: _fieldDecoration(label).copyWith(
              filled: true,
              fillColor: _fieldFill,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              suffixIcon: Icon(
                Icons.arrow_drop_down,
                color: _brand,
              ),
              errorText: fieldState.errorText,
              errorStyle: TextStyle(color: _errColor),
            ),
            child: Text(
              hasValue ? value : placeholder,
              style: TextStyle(
                color: hasValue ? _bodyText : _hintText,
                fontSize: 15,
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // TEXT FIELD
  // ------------------------------------------------------------

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    int? hintMaxLines,
    String? helperText,
    String? prefixText,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: _isReadOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: TextStyle(color: _bodyText),
      decoration: _fieldDecoration(label).copyWith(
        hintText: hintText,
        hintMaxLines: hintMaxLines,
        helperText: helperText,
        helperMaxLines: 2,
        prefixText: prefixText,
        prefixStyle: TextStyle(
          color: _bodyText,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: _hintText,
          fontSize: 13,
        ),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  // ------------------------------------------------------------
  // FIELD DECORATION
  // ------------------------------------------------------------

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _brand),
      filled: true,
      fillColor: _fieldFill,
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: _isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _brand, width: 1.6),
      ),
      errorStyle: TextStyle(color: _errColor),
    );
  }

  // ------------------------------------------------------------
  // SECTION CARD
  // ------------------------------------------------------------

  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1.5,
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: _brand, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _brand,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 46),
                child: Text(
                  subtitle,
                  style: TextStyle(color: _mutedText, fontSize: 12.5),
                ),
              ),
            ],
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ============================================================
// VIDEO PREVIEW DIALOG
//
// Plays a video from a Storage URL (existing videos) or from a
// picked local file (new videos).
//
// confirmMode: true  -> shows "Discard" / "Use this video", so
//                       the owner can confirm it is the right
//                       video before it is added.
// confirmMode: false -> plain player with a Close button.
// ============================================================

class _VideoPreviewDialog extends StatefulWidget {
  const _VideoPreviewDialog({
    this.url,
    this.file,
    this.confirmMode = false,
    required this.brand,
  });

  final String? url;
  final XFile? file;
  final bool confirmMode;
  final Color brand;

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  VideoPlayerController? _controller;

  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final VideoPlayerController controller;

      if (widget.url != null) {
        controller = VideoPlayerController.networkUrl(Uri.parse(widget.url!));
      } else if (kIsWeb) {
        // On web a picked file's path is a blob: URL.
        controller =
            VideoPlayerController.networkUrl(Uri.parse(widget.file!.path));
      } else {
        controller = VideoPlayerController.file(File(widget.file!.path));
      }

      _controller = controller;

      await controller.initialize();

      controller.addListener(_onTick);

      if (!mounted) return;

      setState(() {});

      await controller.play();
    } catch (e) {
      debugPrint('VIDEO PREVIEW ERROR: $e');

      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = AppSettings.of(context).languageCode == 'sw';

    String tr(String en, String s) => sw ? s : en;

    final controller = _controller;

    final ready = controller != null && controller.value.isInitialized;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      title: Text(
        widget.confirmMode
            ? tr('Is this the right video?', 'Je, hii ndiyo video sahihi?')
            : tr('Video preview', 'Hakiki ya video'),
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  tr(
                    'This video could not be played. It may be damaged or in a format your device cannot play.',
                    'Video hii haiwezi kuchezwa. Inaweza kuwa imeharibika au katika umbizo ambalo kifaa chako hakiwezi kucheza.',
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else if (!ready)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(),
              )
            else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
                const SizedBox(height: 8),
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: widget.brand,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 34,
                      color: widget.brand,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                      onPressed: () {
                        if (controller.value.isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                        }
                      },
                    ),
                  ],
                ),
              ],
          ],
        ),
      ),
      actions: widget.confirmMode
          ? [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('Discard', 'Ondoa')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: widget.brand),
          onPressed: _failed ? null : () => Navigator.pop(context, true),
          child: Text(tr('Use this video', 'Tumia video hii')),
        ),
      ]
          : [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Close', 'Funga')),
        ),
      ],
    );
  }
}