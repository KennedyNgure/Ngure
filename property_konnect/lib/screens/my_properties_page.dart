import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'add_property_page.dart';
import 'app_localizations.dart';
import 'app_settings.dart';
import 'download_helper.dart';

class MyPropertiesPage extends StatefulWidget {
  final String propertyId;

  const MyPropertiesPage({
    super.key,
    required this.propertyId,
  });

  @override
  State<MyPropertiesPage> createState() => _MyPropertiesPageState();
}

class _MyPropertiesPageState extends State<MyPropertiesPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _propertyStream;

  bool _deleting = false;
  bool _downloading = false;
  int _imageIndex = 0;

  // ------------------------------------------------------------
  // THEME + LANGUAGE
  // ------------------------------------------------------------

  SettingsController get _settings => AppSettings.of(context);

  bool get _isDark => _settings.isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _mutedText => _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) {
    final code = _settings.languageCode;
    if (code == 'sw') return sw;
    return AppLocalizations.trText(en, code);
  }

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _propertyStream = FirebaseFirestore.instance
        .collection(AppSettings.propertiesCollection)
        .doc(widget.propertyId)
        .snapshots();
  }

  // ------------------------------------------------------------
  // LIVE ANALYTICS COUNTS
  //
  // Views and contact clicks live in `property_views`
  // (kind == 'view' deduped per user, kind == 'contact'
  // counted per click). Favourites live in `favorites`
  // (deleting the doc un-counts it). No counter fields are
  // stored on the property document.
  // ------------------------------------------------------------

  Stream<int> _viewsStream() => FirebaseFirestore.instance
      .collection(AppSettings.propertyViewsCollection)
      .where('propertyId', isEqualTo: widget.propertyId)
      .where('kind', isEqualTo: 'view')
      .snapshots()
      .map((snap) => snap.docs.length);

  Stream<int> _contactsStream() => FirebaseFirestore.instance
      .collection(AppSettings.propertyViewsCollection)
      .where('propertyId', isEqualTo: widget.propertyId)
      .where('kind', isEqualTo: 'contact')
      .snapshots()
      .map((snap) => snap.docs.length);

  Stream<int> _favouritesStream() => FirebaseFirestore.instance
      .collection(AppSettings.favoritesCollection)
      .where('propertyId', isEqualTo: widget.propertyId)
      .snapshots()
      .map((snap) => snap.docs.length);

  /// One-time counts for the downloaded report file.
  Future<(int, int, int)> _fetchCounts() async {
    final views = await FirebaseFirestore.instance
        .collection(AppSettings.propertyViewsCollection)
        .where('propertyId', isEqualTo: widget.propertyId)
        .where('kind', isEqualTo: 'view')
        .count()
        .get();

    final contacts = await FirebaseFirestore.instance
        .collection(AppSettings.propertyViewsCollection)
        .where('propertyId', isEqualTo: widget.propertyId)
        .where('kind', isEqualTo: 'contact')
        .count()
        .get();

    final favourites = await FirebaseFirestore.instance
        .collection(AppSettings.favoritesCollection)
        .where('propertyId', isEqualTo: widget.propertyId)
        .count()
        .get();

    return (
    views.count ?? 0,
    contacts.count ?? 0,
    favourites.count ?? 0,
    );
  }

  // ------------------------------------------------------------
  // DATA HELPERS
  // ------------------------------------------------------------

  String _text(dynamic value) => value?.toString().trim() ?? '';

  int _count(dynamic value) => value is num ? value.toInt() : 0;

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];

    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<String> _images(Map<String, dynamic> data) {
    final urls = <String>[];

    for (final url in [
      ..._stringList(data['images']),
      ..._stringList(data['unitImages']),
      if (_text(data['mainImage']).isNotEmpty) _text(data['mainImage']),
      if (_text(data['image']).isNotEmpty) _text(data['image']),
    ]) {
      if (!urls.contains(url)) urls.add(url);
    }

    return urls;
  }

  List<String> _amenities(Map<String, dynamic> data) {
    final value = data['amenities'];

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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final date = value.toDate().toLocal();

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _priceText(Map<String, dynamic> data) {
    final price = data['price'];

    if (price is! num) return '';

    final isSale = _text(data['purpose']) == 'sale';

    var text = 'KES ${_formatNumber(price)}';

    if (!isSale) {
      text += _text(data['paymentCycle']) == 'per_semester'
          ? ' ${_tr('per semester', 'kwa muhula')}'
          : ' ${_tr('per month', 'kwa mwezi')}';
    }

    return text;
  }

  String _locationText(Map<String, dynamic> data) {
    final saved = _text(data['location']);

    if (saved.isNotEmpty) return saved;

    return [
      _text(data['area']),
      _text(data['subCounty']),
      _text(data['county']),
    ].where((item) => item.isNotEmpty).join(', ');
  }

  // ------------------------------------------------------------
  // STATUS HELPERS
  // ------------------------------------------------------------

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

  (String, Color, IconData) _verificationInfo(Map<String, dynamic> data) {
    if (_text(data['property_status']) == 'verified') {
      return (_tr('Verified', 'Imethibitishwa'), _brand, Icons.verified);
    }

    if (_text(data['status']) == 'rejected') {
      return (_tr('Rejected', 'Imekataliwa'), Colors.red, Icons.cancel);
    }

    return (
    _tr('Pending', 'Inasubiri'),
    Colors.orange,
    Icons.hourglass_top_rounded,
    );
  }

  // ------------------------------------------------------------
  // DETAIL ROWS (used on screen and in the downloaded file)
  // ------------------------------------------------------------

  List<(String, String)> _detailEntries(Map<String, dynamic> data) {
    final isSale = _text(data['purpose']) == 'sale';

    final (statusLabel, _, _) = _statusInfo(_text(data['status']));
    final (verifyLabel, _, _) = _verificationInfo(data);

    final photoCount = _images(data).length;
    final videoCount = _stringList(data['videos']).length;

    final entries = <(String, String)>[
      (
      _tr('Purpose', 'Madhumuni'),
      isSale ? _tr('For Sale', 'Ya Kuuza') : _tr('For Rent', 'Ya Kupangisha'),
      ),
      (_tr('Property type', 'Aina ya mali'), _text(data['type'])),
      (_tr('Category', 'Kategoria'), _text(data['category'])),
      (
      isSale ? _tr('Asking price', 'Bei ya kuuza') : _tr('Rent', 'Kodi'),
      _priceText(data),
      ),
      (
      _tr('Accommodation type', 'Aina ya makazi'),
      _text(data['accommodationType'] ?? data['unitDetails']),
      ),
      (
      _tr('Number of units', 'Idadi ya vitengo'),
      _text(data['numberOfUnits']),
      ),
      (_tr('Campus', 'Chuo'), _text(data['campusName'])),
      (_tr('County', 'Kaunti'), _text(data['county'])),
      (_tr('Sub-county', 'Kaunti ndogo'), _text(data['subCounty'])),
      (_tr('Estate / Area', 'Mtaa / Eneo'), _text(data['area'])),
      (_tr('Listing status', 'Hali ya orodha'), statusLabel),
      (_tr('Verification', 'Uthibitisho'), verifyLabel),
      (
      _tr('Photos', 'Picha'),
      photoCount > 0 ? photoCount.toString() : '',
      ),
      (
      _tr('Videos', 'Video'),
      videoCount > 0 ? videoCount.toString() : '',
      ),
      (_tr('Listed on', 'Imewekwa tarehe'), _formatDate(data['createdAt'])),
      (_tr('Last updated', 'Imesasishwa'), _formatDate(data['updatedAt'])),
    ];

    return entries.where((entry) => entry.$2.isNotEmpty).toList();
  }

  // ------------------------------------------------------------
  // EDIT
  // ------------------------------------------------------------

  void _editProperty(Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddPropertyPage(
          propertyId: widget.propertyId,
          initialData: data,
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // DOWNLOAD (property details + analytics as a real .txt file)
  //
  // Uses the SAME DownloadHelper the admin pages use — on web
  // this triggers a normal browser download; on mobile/desktop
  // it saves a temp file and opens the OS share sheet. No
  // pdf/printing packages involved, so the old
  // MissingPluginException (sharePdf on channel
  // net.nfet.printing) is gone.
  //
  // Analytics in the report use REAL counts queried from
  // property_views and favorites at download time.
  // ------------------------------------------------------------

  Future<void> _downloadDetails(Map<String, dynamic> data) async {
    if (_downloading) return;

    setState(() => _downloading = true);

    try {
      final title = _text(data['title']).isEmpty
          ? _tr('Property', 'Mali')
          : _text(data['title']);

      final location = _locationText(data);
      final entries = _detailEntries(data);
      final amenities = _amenities(data);
      final description = _text(data['description']);

      final (viewCount, contactCount, favouriteCount) = await _fetchCounts();

      final overviewLines = <(String, String)>[
        (_tr('Title', 'Jina'), title),
        (_tr('Location', 'Eneo'), location),
      ];

      final analyticsLines = <(String, String)>[
        (_tr('Views', 'Mitazamo'), viewCount.toString()),
        (_tr('Contacts', 'Mawasiliano'), contactCount.toString()),
        (_tr('Favourites', 'Vipendwa'), favouriteCount.toString()),
      ];

      final amenitiesLines = <(String, String)>[
        (_tr('Amenities', 'Huduma'), amenities.join(', ')),
      ];

      final descriptionLines = <(String, String)>[
        (_tr('Extra details', 'Maelezo ya ziada'), description),
      ];

      final generatedLines = <(String, String)>[
        (
        _tr('Generated on', 'Imetolewa tarehe'),
        _formatDate(Timestamp.now()),
        ),
      ];

      await DownloadHelper.downloadCuratedText(
        context: context,
        fileNamePrefix: 'property_${widget.propertyId}',
        sections: [
          (
          heading: _tr('Property', 'Mali'),
          lines: overviewLines,
          ),
          (
          heading: _tr('Analytics', 'Uchambuzi'),
          lines: analyticsLines,
          ),
          (
          heading: _tr('Property details', 'Maelezo ya mali'),
          lines: entries,
          ),
          (
          heading: _tr('Amenities', 'Huduma'),
          lines: amenitiesLines,
          ),
          (
          heading: _tr('Extra details', 'Maelezo ya ziada'),
          lines: descriptionLines,
          ),
          (
          heading: _tr('Report', 'Ripoti'),
          lines: generatedLines,
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_tr('Unable to create the file: ', 'Imeshindikana kuunda faili: ')}$e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  // ------------------------------------------------------------
  // DELETE
  // ------------------------------------------------------------

  Future<void> _deleteStorageFolder(Reference ref) async {
    final result = await ref.listAll();

    for (final item in result.items) {
      await item.delete();
    }

    for (final prefix in result.prefixes) {
      await _deleteStorageFolder(prefix);
    }
  }

  Future<void> _deleteProperty(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    final ownerId = _text(data['ownerId']);

    if (user == null || (ownerId.isNotEmpty && ownerId != user.uid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'You are not allowed to delete this property.',
              'Huruhusiwi kufuta mali hii.',
            ),
          ),
        ),
      );
      return;
    }

    final title = _text(data['title']);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever,
          color: Colors.red,
          size: 34,
        ),
        title: Text(_tr('Delete property?', 'Kufuta mali?')),
        content: Text(
          '${_tr(
            'Are you sure you want to delete the property?',
            'Una uhakika unataka kufuta mali hii?',
          )}'
              '${title.isEmpty ? '' : '\n\n"$title"'}'
              '\n\n${_tr(
            'All its details will be permanently removed. This action cannot be undone.',
            'Maelezo yote yataondolewa kabisa. Hatua hii haiwezi kurudishwa.',
          )}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Delete', 'Futa')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _deleting = true);

    try {
      // 1. Remove the property document from Firestore.
      await FirebaseFirestore.instance
          .collection(AppSettings.propertiesCollection)
          .doc(widget.propertyId)
          .delete();

      // 2. Best-effort cleanup of the property's view / contact
      //    and favourite documents so old stats don't linger.
      try {
        final batch = FirebaseFirestore.instance.batch();

        final viewDocs = await FirebaseFirestore.instance
            .collection(AppSettings.propertyViewsCollection)
            .where('propertyId', isEqualTo: widget.propertyId)
            .get();

        final favoriteDocs = await FirebaseFirestore.instance
            .collection(AppSettings.favoritesCollection)
            .where('propertyId', isEqualTo: widget.propertyId)
            .get();

        for (final doc in viewDocs.docs) {
          batch.delete(doc.reference);
        }

        for (final doc in favoriteDocs.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      } catch (_) {
        // The property is already gone; ignore stats cleanup
        // errors (rules may also block non-admin deletes here).
      }

      // 3. Best-effort cleanup of the property's photos and videos.
      try {
        await _deleteStorageFolder(
          FirebaseStorage.instance
              .ref()
              .child('properties')
              .child(ownerId.isEmpty ? user.uid : ownerId)
              .child(widget.propertyId),
        );
      } catch (_) {
        // The property is already gone; ignore storage cleanup errors.
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(_tr('Property deleted.', 'Mali imefutwa.')),
        ),
      );

      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${_tr('Unable to delete: ', 'Imeshindikana kufuta: ')}$e',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Property Details', 'Maelezo ya Mali')),
        backgroundColor: _brand,
        foregroundColor: Colors.white,
      ),
      body: _deleting
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _brand),
            const SizedBox(height: 14),
            Text(_tr('Deleting property...', 'Inafuta mali...')),
          ],
        ),
      )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _propertyStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                _tr(
                  'Unable to load this property.',
                  'Imeshindikana kupakia mali hii.',
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: _brand),
            );
          }

          final snap = snapshot.data!;
          final data = snap.data();

          if (!snap.exists || data == null) {
            return Center(
              child: Text(
                _tr(
                  'This property no longer exists.',
                  'Mali hii haipo tena.',
                ),
              ),
            );
          }

          return _buildDetails(data);
        },
      ),
    );
  }

  Widget _buildDetails(Map<String, dynamic> data) {
    final title = _text(data['title']).isEmpty
        ? _tr('Property', 'Mali')
        : _text(data['title']);

    final location = _locationText(data);

    final (statusLabel, statusColor, statusIcon) =
    _statusInfo(_text(data['status']));
    final (verifyLabel, verifyColor, verifyIcon) = _verificationInfo(data);

    final entries = _detailEntries(data);
    final amenities = _amenities(data);
    final description = _text(data['description']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ----------------------------------------------------
        // PHOTOS
        // ----------------------------------------------------
        _imageGallery(_images(data)),
        const SizedBox(height: 16),

        // ----------------------------------------------------
        // TITLE + STATUS
        // ----------------------------------------------------
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (location.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: _mutedText),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  location,
                  style: TextStyle(color: _mutedText, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill(statusLabel, statusColor, statusIcon),
            _pill(verifyLabel, verifyColor, verifyIcon),
          ],
        ),
        const SizedBox(height: 22),

        // ----------------------------------------------------
        // ANALYTICS — live counts from property_views and
        // favorites, not stored counter fields.
        // ----------------------------------------------------
        _sectionTitle(_tr('Property analytics', 'Uchambuzi wa mali')),
        Row(
          children: [
            Expanded(
              child: _liveStatTile(
                stream: _viewsStream(),
                icon: Icons.visibility,
                label: _tr('Views', 'Mitazamo'),
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _liveStatTile(
                stream: _contactsStream(),
                icon: Icons.phone_in_talk,
                label: _tr('Contacts', 'Mawasiliano'),
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _liveStatTile(
                stream: _favouritesStream(),
                icon: Icons.favorite,
                label: _tr('Favourites', 'Vipendwa'),
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ----------------------------------------------------
        // DETAILS
        // ----------------------------------------------------
        _sectionTitle(_tr('Property details', 'Maelezo ya mali')),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _cardColor,
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

        // ----------------------------------------------------
        // AMENITIES
        // ----------------------------------------------------
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

        // ----------------------------------------------------
        // EXTRA DETAILS
        // ----------------------------------------------------
        if (description.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionTitle(_tr('Extra details', 'Maelezo ya ziada')),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: Text(description, style: const TextStyle(height: 1.4)),
          ),
        ],

        const SizedBox(height: 26),

        // ----------------------------------------------------
        // ACTIONS
        // ----------------------------------------------------
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _editProperty(data),
                icon: const Icon(Icons.edit),
                label: Text(_tr('Edit', 'Hariri')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: BorderSide(color: _brand),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _downloading ? null : () => _downloadDetails(data),
                icon: _downloading
                    ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brand,
                  ),
                )
                    : const Icon(Icons.download),
                label: Text(_tr('Download', 'Pakua')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _deleteProperty(data),
            icon: const Icon(Icons.delete_outline),
            label: Text(_tr('Delete property', 'Futa mali')),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ------------------------------------------------------------
  // IMAGE GALLERY
  // ------------------------------------------------------------

  Widget _imageGallery(List<String> images) {
    if (images.isEmpty) {
      return Container(
        height: 170,
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder),
        ),
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 48,
            color: _mutedText,
          ),
        ),
      );
    }

    final index = _imageIndex.clamp(0, images.length - 1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            PageView.builder(
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _imageIndex = i),
              itemBuilder: (_, i) => Image.network(
                images[i],
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: Colors.grey.shade300,
                  child: const Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
            if (images.length > 1)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // SMALL WIDGETS
  // ------------------------------------------------------------

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
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

  /// Stat tile that shows a LIVE count from a Firestore stream.
  Widget _liveStatTile({
    required Stream<int> stream,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 6),
          StreamBuilder<int>(
            stream: stream,
            builder: (context, snapshot) {
              final value = snapshot.data ?? 0;

              return Text(
                value.toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _mutedText),
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}