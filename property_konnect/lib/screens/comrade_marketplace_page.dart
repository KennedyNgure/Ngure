// ============================================================
// comrade_marketplace_page.dart  (FULL UPDATED FILE)
//
// CHANGES IN THIS VERSION
//  REPORTING NOW WORKS AND IS SAVED LIKE ROOMMATE REPORTS
//   - The Report button in the item details dialog now saves to
//     the shared `reports` collection in the SAME format as the
//     roommate reports:
//       kind: 'marketplace_item'
//       targetCollection: 'comrade_marketplace'
//       targetId / targetName (item title) / targetOwnerId
//       reason, details, reporterId, deviceId, status: 'open',
//       createdAt
//     Document id: marketplace_item_{itemId}_{deviceId}
//     (one device = one report per item).
//   - The `reportCount` bump is best-effort in its own try
//     block, so a rules denial no longer makes the whole report
//     look like it failed.
//   - The unused page-level report code was removed; everything
//     lives in the shared file report_helper.dart.
//  EDIT BUTTON FIX
//   - "Edit" in the details dialog used
//     findAncestorStateOfType from the dialog, which can never
//     find the page (a dialog is a separate route), so the edit
//     sheet never opened. The page now passes an `onEdit`
//     callback down to the card and the dialog instead.
//
// KEPT FROM BEFORE: edit listing (owner only), full-screen image
// gallery, up to 20 images, upload progress + cleanup on failure,
// owner-only Edit / Delete (matched by device id).
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'post_helpers.dart';
import 'report_helper.dart';

// ------------------------------------------------------------
// Shared helpers
// ------------------------------------------------------------
String _t(BuildContext c, String en, String sw) =>
    AppSettings.of(c).languageCode == 'sw' ? sw : en;

/// English key -> Kiswahili label
const Map<String, String> _kCategories = {
  'Electronics': 'Vifaa vya Kielektroniki',
  'Books & Stationery': 'Vitabu na Vifaa vya Kuandikia',
  'Furniture': 'Samani',
  'Clothes & Shoes': 'Nguo na Viatu',
  'Kitchen & Appliances': 'Jikoni na Vifaa vya Nyumbani',
  'Bedding': 'Matandiko',
  'Phones & Accessories': 'Simu na Vifaa vyake',
  'Other': 'Vingine',
};

const Map<String, String> _kConditions = {
  'New': 'Mpya',
  'Like New': 'Kama Mpya',
  'Used - Good': 'Imetumika - Nzuri',
  'Used - Fair': 'Imetumika - Wastani',
};

String _catLabel(BuildContext c, String key) =>
    _t(c, key, _kCategories[key] ?? key);

String _condLabel(BuildContext c, String key) =>
    _t(c, key, _kConditions[key] ?? key);

String _formatPrice(num p) {
  final s = p.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final left = s.length - i;
    buf.write(s[i]);
    if (left > 1 && left % 3 == 1) buf.write(',');
  }
  return 'KES $buf';
}

String _normCampus(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _cleanPhone(String p) {
  var d = p.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.startsWith('+')) d = d.substring(1);
  if (d.startsWith('0')) d = '254${d.substring(1)}';
  return d;
}

// ============================================================
// PAGE
// ============================================================
class ComradeMarketplacePage extends StatefulWidget {
  const ComradeMarketplacePage({super.key});

  @override
  State<ComradeMarketplacePage> createState() =>
      _ComradeMarketplacePageState();
}

class _ComradeMarketplacePageState extends State<ComradeMarketplacePage> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _category = 'All';
  String _campus = 'All';

  // Device id of this device — used to identify the owner of a
  // listing (posts store it as `userId` when created).
  String _myId = '';

  @override
  void initState() {
    super.initState();
    loadOwnerId().then((id) {
      if (mounted) setState(() => _myId = id);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream =>
      FirebaseFirestore.instance
          .collection('comrade_marketplace')
          .orderBy('createdAt', descending: true)
          .snapshots();

  Future<void> _openPostSheet() async {
    // Resolve the owner id BEFORE opening the sheet.
    final String ownerId =
    _myId.isNotEmpty ? _myId : await loadOwnerId();
    if (_myId.isEmpty && mounted) setState(() => _myId = ownerId);

    if (!mounted) return;

    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PostItemSheet(ownerId: ownerId),
    );
    if (posted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(context, 'Your item has been posted.',
              'Bidhaa yako imetangazwa.')),
        ),
      );
    }
  }

  Future<void> _openEditSheet(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final edited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _PostItemSheet.existing(doc),
    );
    if (edited == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(context, 'Listing updated.',
              'Chapisho limeharibiwa.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.of(context).isDark;
    final brand = isDark ? kBrandGreenOnDark : kBrandGreen;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t(context, 'Comrade Marketplace', 'Soko la Wanafunzi'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        onPressed: _openPostSheet,
        icon: const Icon(Icons.add_rounded),
        label: Text(_t(context, 'Sell an Item', 'Uza Bidhaa')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _t(context, 'Could not load items. Please try again.',
                            'Imeshindwa kupakia bidhaa. Tafadhali jaribu tena.'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snap.data!.docs;

                // Campus dropdown built from data, de-duplicated
                final campusMap = <String, String>{};
                for (final d in all) {
                  final c = (d.data()['campus'] ?? '').toString().trim();
                  if (c.isEmpty) continue;
                  campusMap.putIfAbsent(_normCampus(c), () => c);
                }
                final campuses = campusMap.values.toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                if (_campus != 'All' && !campuses.contains(_campus)) {
                  _campus = 'All';
                }

                final q = _query.trim().toLowerCase();
                final items = all.where((d) {
                  final m = d.data();
                  if (_category != 'All' && m['category'] != _category) {
                    return false;
                  }
                  if (_campus != 'All' &&
                      _normCampus((m['campus'] ?? '').toString()) !=
                          _normCampus(_campus)) {
                    return false;
                  }
                  if (q.isNotEmpty) {
                    final hay =
                    '${m['title'] ?? ''} ${m['description'] ?? ''} '
                        '${m['area'] ?? ''}'
                        .toLowerCase();
                    if (!hay.contains(q)) return false;
                  }
                  return true;
                }).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: _t(context, 'Search items...',
                              'Tafuta bidhaa...'),
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          contentPadding:
                          const EdgeInsets.symmetric(vertical: 0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Category chips
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final key in ['All', ..._kCategories.keys])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(key == 'All'
                                    ? _t(context, 'All', 'Zote')
                                    : _catLabel(context, key)),
                                selected: _category == key,
                                selectedColor: brand.withValues(alpha: .22),
                                onSelected: (_) =>
                                    setState(() => _category = key),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: DropdownButtonFormField<String>(
                        initialValue: _campus,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _t(context, 'Campus', 'Chuo'),
                          prefixIcon: const Icon(Icons.school_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'All',
                            child: Text(
                                _t(context, 'All campuses', 'Vyuo vyote')),
                          ),
                          for (final c in campuses)
                            DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _campus = v ?? 'All'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_bag_outlined,
                                  size: 56, color: brand),
                              const SizedBox(height: 10),
                              Text(
                                _t(
                                  context,
                                  'No items found. Be the first to sell something!',
                                  'Hakuna bidhaa zilizopatikana. Kuwa wa kwanza kuuza!',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                          : ListView.builder(
                        padding:
                        const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _ItemCard(
                          doc: items[i],
                          isDark: isDark,
                          brand: brand,
                          myId: _myId,
                          onEdit: _openEditSheet,
                          onTapImage: (index) => _openGallery(
                            List<String>.from(
                                items[i].data()['imageUrls'] ?? const []),
                            index,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // FULL-SCREEN GALLERY
  // ------------------------------------------------------------
  void _openGallery(List<String> images, int initialIndex) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) =>
            _GalleryViewer(images: images, initialIndex: initialIndex),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

// ============================================================
// FULL-SCREEN IMAGE VIEWER (swipe + pinch-zoom + counter)
// ============================================================
class _GalleryViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _GalleryViewer({required this.images, required this.initialIndex});

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final PageController _controller =
  PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex.clamp(0, widget.images.length - 1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipe between images
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              // Pinch zoom + pan
              maxScale: 4,
              minScale: 1,
              child: Center(
                child: Image.network(
                  widget.images[i],
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 56,
                  ),
                ),
              ),
            ),
          ),

          // Counter
          if (widget.images.length > 1)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.images.length}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),

          // Close
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Back
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 26),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ITEM CARD
// ============================================================
class _ItemCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isDark;
  final Color brand;
  final String myId;
  final void Function(int index) onTapImage;

  /// Opens the page's edit sheet (passed down because a dialog
  /// cannot reach the page state through the widget tree).
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) onEdit;

  const _ItemCard({
    required this.doc,
    required this.isDark,
    required this.brand,
    required this.myId,
    required this.onTapImage,
    required this.onEdit,
  });

  void _openDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ItemDetailsDialog(
        doc: doc,
        brand: brand,
        myId: myId,
        onEdit: onEdit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final images = List<String>.from(m['imageUrls'] ?? const []);
    final sold = m['status'] == 'sold';
    final cardColor = isDark ? const Color(0xFF1A241D) : Colors.white;
    final border = isDark ? const Color(0xFF2A3A2F) : Colors.grey.shade200;
    final subtle =
    Theme.of(context).colorScheme.onSurface.withValues(alpha: .68);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openDetails(context),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                // Tapping the thumbnail opens the full-screen gallery
                GestureDetector(
                  onTap: () => onTapImage(0),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 92,
                          height: 92,
                          child: images.isEmpty
                              ? Container(
                            color: brand.withValues(alpha: .12),
                            child: Icon(Icons.image_outlined,
                                color: brand, size: 34),
                          )
                              : Image.network(
                            images.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: brand.withValues(alpha: .12),
                              child: Icon(Icons.broken_image_outlined,
                                  color: brand),
                            ),
                          ),
                        ),
                      ),
                      if (images.length > 1)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${images.length} 📷',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (m['title'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatPrice((m['price'] ?? 0) as num),
                        style: TextStyle(
                          color: brand,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_catLabel(context, (m['category'] ?? 'Other').toString())}'
                            ' • ${(m['campus'] ?? '').toString()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtle, fontSize: 12.5),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (sold)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _t(context, 'SOLD', 'IMEUZWA'),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _openDetails(context),
                            child: Text(_t(context, 'View', 'Tazama')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DETAILS DIALOG (view, gallery, report, contact, owner: edit /
// delete — owner-only!)
// ============================================================
class _ItemDetailsDialog extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Color brand;
  final String myId;
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) onEdit;

  const _ItemDetailsDialog({
    required this.doc,
    required this.brand,
    required this.myId,
    required this.onEdit,
  });

  @override
  State<_ItemDetailsDialog> createState() => _ItemDetailsDialogState();
}

class _ItemDetailsDialogState extends State<_ItemDetailsDialog> {
  bool _reported = false;

  bool get _isOwner =>
      widget.myId.isNotEmpty &&
          widget.myId == (widget.doc.data()['userId'] ?? '').toString();

  Future<String?> _askCode(BuildContext context, String title) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          decoration: InputDecoration(
            labelText:
            _t(ctx, 'Your 4-digit code', 'Msimbo wako wa tarakimu 4'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t(ctx, 'Cancel', 'Ghairi')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(_t(ctx, 'Confirm', 'Thibitisha')),
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext c, String msg) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openGallery(int index) {
    final images =
    List<String>.from(widget.doc.data()['imageUrls'] ?? const []);
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) =>
            _GalleryViewer(images: images, initialIndex: index),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // ============================================================
  // REPORT — saved to the shared `reports` collection in the same
  // format as roommate reports (see report_helper.dart).
  // ============================================================
  Future<void> _report(BuildContext context) async {
    if (_reported) {
      _snack(context, _t(context, 'You have already reported this listing.',
          'Umesha ripoti chapisho hili.'));
      return;
    }

    final m = widget.doc.data();

    final outcome = await ReportHelper.report(
      context,
      kind: 'marketplace_item',
      targetCollection: 'comrade_marketplace',
      targetId: widget.doc.id,
      targetName: (m['title'] ?? '').toString(),
      targetOwnerId: (m['userId'] ?? '').toString(),
      reasons: ReportHelper.marketplaceReasons,
    );

    if (!mounted) return;

    if (outcome == ReportOutcome.sent ||
        outcome == ReportOutcome.alreadyReported) {
      setState(() => _reported = true);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final m = widget.doc.data();
    final code = await _askCode(
        context, _t(context, 'Delete item', 'Futa bidhaa'));
    if (code == null) return;
    if (code != (m['deleteCode'] ?? '').toString()) {
      if (context.mounted) {
        _snack(context, _t(context, 'Wrong code.', 'Msimbo si sahihi.'));
      }
      return;
    }
    // Remove images from Storage (best effort)
    for (final url in List<String>.from(m['imageUrls'] ?? const [])) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }
    await widget.doc.reference.delete();
    if (context.mounted) {
      Navigator.pop(context);
      _snack(context, _t(context, 'Item deleted.', 'Bidhaa imefutwa.'));
    }
  }

  Future<void> _call(String phone) async {
    await launchUrl(Uri.parse('tel:$phone'));
  }

  Future<void> _whatsapp(String phone, String title) async {
    final text = Uri.encodeComponent(
        'Hi, I saw your "$title" on the PropertyKonnect Comrade Marketplace. Is it still available?');
    await launchUrl(
      Uri.parse('https://wa.me/${_cleanPhone(phone)}?text=$text'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.doc.data();
    final images = List<String>.from(m['imageUrls'] ?? const []);
    final phone = (m['phone'] ?? '').toString();
    final title = (m['title'] ?? '').toString();
    final sold = m['status'] == 'sold';
    final subtle =
    Theme.of(context).colorScheme.onSurface.withValues(alpha: .75);

    Widget row(IconData i, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, size: 18, color: widget.brand),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ],
      ),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (images.isNotEmpty)
                        SizedBox(
                          height: 200,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: images.length,
                            separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                            // Tapping any photo opens the
                            // full-screen gallery from that photo.
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => _openGallery(i),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  images[i],
                                  fit: BoxFit.cover,
                                  width: images.length == 1 ? 460 : 240,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 240,
                                    color:
                                    widget.brand.withValues(alpha: .12),
                                    child: Icon(Icons.broken_image_outlined,
                                        color: widget.brand),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _formatPrice((m['price'] ?? 0) as num),
                            style: TextStyle(
                                color: widget.brand,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                          if (sold) ...[
                            const SizedBox(width: 10),
                            Text(
                              _t(context, 'SOLD', 'IMEUZWA'),
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      row(
                          Icons.category_outlined,
                          _catLabel(
                              context, (m['category'] ?? 'Other').toString())),
                      row(Icons.verified_outlined,
                          _condLabel(context, (m['condition'] ?? '').toString())),
                      row(Icons.school_outlined,
                          (m['campus'] ?? '').toString()),
                      if ((m['area'] ?? '').toString().isNotEmpty)
                        row(Icons.place_outlined, (m['area']).toString()),
                      row(Icons.person_outline_rounded,
                          (m['sellerName'] ?? '').toString()),
                      const SizedBox(height: 8),
                      Text(
                        (m['description'] ?? '').toString(),
                        style: TextStyle(color: subtle, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!sold && phone.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _call(phone),
                        icon: const Icon(Icons.call_rounded),
                        label: Text(_t(context, 'Call', 'Piga')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366)),
                        onPressed: () => _whatsapp(phone, title),
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  // ---- OWNER-ONLY CONTROLS ----
                  // Edit / Delete are shown ONLY on the device that
                  // created the listing (myId == userId). The 4-digit
                  // code is the second check, and the Firestore rules
                  // enforce ownership as well.
                  if (_isOwner) ...[
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEdit(widget.doc);
                      },
                      icon: Icon(Icons.edit_outlined,
                          color: widget.brand),
                      label: Text(_t(context, 'Edit', 'Haribu'),
                          style:
                          TextStyle(color: widget.brand)),
                    ),
                    TextButton.icon(
                      onPressed: () => _delete(context),
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      label: Text(_t(context, 'Delete', 'Futa'),
                          style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                  // ---- REPORT (non-owners) ----
                  if (!_isOwner)
                    TextButton.icon(
                      onPressed:
                      _reported ? null : () => _report(context),
                      icon: Icon(
                        _reported
                            ? Icons.check_circle_outline
                            : Icons.flag_outlined,
                        color: Colors.orange.shade700,
                      ),
                      label: Text(
                        _reported
                            ? _t(context, 'Reported', 'Umeripoti')
                            : _t(context, 'Report', 'Ripoti'),
                        style: TextStyle(
                            color: Colors.orange.shade700),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_t(context, 'Close', 'Funga')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// POST / EDIT ITEM SHEET
//
// Pass nothing -> CREATE mode.
// Pass `existing` -> EDIT mode: pre-filled, reuses kept images,
// uploads new ones, deletes removed ones. The 4-digit code must
// be re-entered to confirm an edit.
// ============================================================
class _PostItemSheet extends StatefulWidget {
  final String? ownerId;
  final QueryDocumentSnapshot<Map<String, dynamic>>? existing;

  const _PostItemSheet({this.ownerId})
      : existing = null;

  const _PostItemSheet.existing(this.existing) : ownerId = null;

  @override
  State<_PostItemSheet> createState() => _PostItemSheetState();
}

class _PostItemSheetState extends State<_PostItemSheet> {
  static const int _maxImages = 20; // was 3

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _campus = TextEditingController();
  final _area = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  late String _category = 'Electronics';
  late String _condition = 'Used - Good';

  // Existing (kept) image URLs in edit mode; new XFiles to upload.
  final List<String> _keptUrls = [];
  final List<XFile> _images = [];

  bool get _isEdit => widget.existing != null;

  // ---- upload progress ----
  bool _saving = false;
  int _uploadIndex = 0;
  int _uploadTotal = 0;
  double _uploadPercent = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final m = e.data();
      _title.text = (m['title'] ?? '').toString();
      _desc.text = (m['description'] ?? '').toString();
      _price.text = (m['price'] ?? 0).toString();
      _campus.text = (m['campus'] ?? '').toString();
      _area.text = (m['area'] ?? '').toString();
      _name.text = (m['sellerName'] ?? '').toString();
      _phone.text = (m['phone'] ?? '').toString();
      _category = (m['category'] ?? 'Electronics').toString();
      _condition = (m['condition'] ?? 'Used - Good').toString();
      _keptUrls.addAll(List<String>.from(m['imageUrls'] ?? const []));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title, _desc, _price, _campus, _area, _name, _phone, _code
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = _maxImages - _keptUrls.length - _images.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(context, 'You can upload up to 20 photos.',
              'Unaweza kupakia picha hadi 20.')),
        ),
      );
      return;
    }
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 65, // compression: keeps uploads small & fast
        maxWidth: 1280,
      );
      if (picked.isEmpty) return;
      setState(() {
        _images.addAll(picked.take(remaining));
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(context, 'Could not pick images.',
              'Imeshindwa kuchagua picha.')),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // UPLOAD with progress + CLEANUP on failure
  // ------------------------------------------------------------
  Future<String> _uploadWithProgress(UploadTask task) {
    task.snapshotEvents.listen((event) {
      final total = event.totalBytes;
      if (total > 0 && mounted) {
        setState(() {
          _uploadPercent = event.bytesTransferred / total;
        });
      }
    });
    return task.then((snap) => snap.ref.getDownloadURL());
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // The 4-digit code confirms an EDIT (must match the stored one).
    final e = widget.existing;
    if (e != null) {
      final stored = (e.data()['deleteCode'] ?? '').toString();
      if (stored.isNotEmpty && _code.text.trim() != stored) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t(context,
                  'Wrong code. Changes were not saved.',
                  'Msimbo si sahihi. Mabadiliko hayakuhifadhiwa.')),
            ),
          );
        }
        return;
      }
    }

    // Uploads performed during THIS submit — deleted again if the
    // Firestore write fails, so no orphan files are left.
    final uploadedRefs = <Reference>[];
    final urls = <String>[..._keptUrls];

    try {
      final storage = FirebaseStorage.instance;
      final String docId = e?.id ??
          FirebaseFirestore.instance
              .collection('comrade_marketplace')
              .doc()
              .id;

      _uploadTotal = _images.length;
      _uploadIndex = 0;

      for (int i = 0; i < _images.length; i++) {
        setState(() {
          _uploadIndex = i + 1;
          _uploadPercent = 0;
        });

        final bytes = await _images[i].readAsBytes();
        final sRef =
        storage.ref('comrade_marketplace/$docId/img_$i.jpg');
        final task = sRef.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        uploadedRefs.add(sRef);
        urls.add(await _uploadWithProgress(task));
      }

      if (e != null) {
        // ---------------- EDIT ----------------
        // Delete photos the seller removed.
        final oldUrls =
        List<String>.from(e.data()['imageUrls'] ?? const []);
        for (final url in oldUrls) {
          if (!_keptUrls.contains(url)) {
            try {
              await storage.refFromURL(url).delete();
            } catch (_) {}
          }
        }

        await e.reference.update({
          'title': _title.text.trim(),
          'description': _desc.text.trim(),
          'price': num.parse(_price.text.trim()),
          'category': _category,
          'condition': _condition,
          'campus': _campus.text.trim(),
          'area': _area.text.trim(),
          'sellerName': _name.text.trim(),
          'phone': _phone.text.trim(),
          'imageUrls': urls,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // ---------------- CREATE ----------------
        await FirebaseFirestore.instance
            .collection('comrade_marketplace')
            .doc(docId)
            .set({
          'title': _title.text.trim(),
          'description': _desc.text.trim(),
          'price': num.parse(_price.text.trim()),
          'category': _category,
          'condition': _condition,
          'campus': _campus.text.trim(),
          'area': _area.text.trim(),
          'sellerName': _name.text.trim(),
          'phone': _phone.text.trim(),
          'imageUrls': urls,
          'deleteCode': _code.text.trim(),
          // Ownership: the device id that created this listing.
          // Only this device sees edit / delete.
          'userId': widget.ownerId ?? await loadOwnerId(),
          'reportCount': 0,
          'status': 'available',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      // CLEANUP: the listing failed to save — remove any images
      // that were already uploaded in this submit.
      for (final ref in uploadedRefs) {
        try {
          await ref.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _uploadPercent = 0;
        _uploadIndex = 0;
        _uploadTotal = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(context,
              'Failed to save the item. Please try again.',
              'Imeshindwa kutangaza bidhaa. Tafadhali jaribu tena.')),
        ),
      );
    }
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? _t(context, 'Required', 'Inahitajika')
      : null;

  // ------------------------------------------------------------
  // UPLOAD PROGRESS INDICATOR
  // ------------------------------------------------------------
  Widget _buildProgress() {
    if (!_saving || _uploadTotal == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Uploading photo $_uploadIndex of $_uploadTotal',
                'Inapakia picha $_uploadIndex kati ya $_uploadTotal'),
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _uploadPercent,
              minHeight: 8,
              backgroundColor: Colors.black12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${(_uploadPercent * 100).round()}%',
            style: const TextStyle(fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppSettings.of(context).isDark;
    final brand = isDark ? kBrandGreenOnDark : kBrandGreen;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit
                          ? _t(context, 'Edit Listing', 'Haribu Chapisho')
                          : _t(context, 'Sell an Item', 'Uza Bidhaa'),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed:
                    _saving ? null : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Photos (up to 20): kept URLs first, then new picks
              Text(
                _t(context, 'Photos (up to 20)', 'Picha (hadi 20)'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // Existing (kept) images — tap the X to remove
                    for (int i = 0; i < _keptUrls.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _keptUrls[i],
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 88,
                                  height: 88,
                                  color: brand.withValues(alpha: .12),
                                  child: Icon(Icons.broken_image_outlined,
                                      color: brand),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: InkWell(
                                onTap: _saving
                                    ? null
                                    : () =>
                                    setState(() => _keptUrls.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 11,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Newly picked images — tap the X to remove
                    for (int i = 0; i < _images.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: FutureBuilder(
                                future: _images[i].readAsBytes(),
                                builder: (_, s) => s.hasData
                                    ? Image.memory(s.data!,
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.cover)
                                    : Container(
                                    width: 88,
                                    height: 88,
                                    color: Colors.black12),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: InkWell(
                                onTap: _saving
                                    ? null
                                    : () => setState(() => _images.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 11,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_keptUrls.length + _images.length < _maxImages)
                      InkWell(
                        onTap: _saving ? null : _pickImages,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: brand.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(12),
                            border:
                            Border.all(color: brand.withValues(alpha: .5)),
                          ),
                          child: Icon(Icons.add_a_photo_outlined,
                              color: brand),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _title,
                decoration: _dec(_t(context, 'Item name', 'Jina la bidhaa'),
                    icon: Icons.sell_outlined),
                validator: _required,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: _dec(_t(context, 'Category', 'Aina'),
                    icon: Icons.category_outlined),
                items: [
                  for (final k in _kCategories.keys)
                    DropdownMenuItem(
                        value: k, child: Text(_catLabel(context, k))),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _condition,
                isExpanded: true,
                decoration: _dec(_t(context, 'Condition', 'Hali'),
                    icon: Icons.verified_outlined),
                items: [
                  for (final k in _kConditions.keys)
                    DropdownMenuItem(
                        value: k, child: Text(_condLabel(context, k))),
                ],
                onChanged: (v) => setState(() => _condition = v ?? _condition),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: _dec(_t(context, 'Price (KES)', 'Bei (KES)'),
                    icon: Icons.payments_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return _t(context, 'Required', 'Inahitajika');
                  }
                  final n = num.tryParse(v.trim());
                  if (n == null || n < 0) {
                    return _t(
                        context, 'Enter a valid amount', 'Weka kiasi sahihi');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                maxLines: 4,
                decoration: _dec(
                  _t(context, 'Description', 'Maelezo'),
                  hint: _t(context, 'Size, brand, age, reason for selling...',
                      'Ukubwa, chapa, umri, sababu ya kuuza...'),
                  icon: Icons.notes_rounded,
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _campus,
                decoration:
                _dec(_t(context, 'Campus name', 'Jina la chuo'),
                    icon: Icons.school_outlined),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _area,
                decoration: _dec(
                  _t(context, 'Area / Hostel (optional)',
                      'Eneo / Hosteli (si lazima)'),
                  icon: Icons.place_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: _dec(_t(context, 'Your name', 'Jina lako'),
                    icon: Icons.person_outline_rounded),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: _dec(
                  _t(context, 'Phone / WhatsApp number',
                      'Nambari ya simu / WhatsApp'),
                  hint: '07XXXXXXXX',
                  icon: Icons.phone_outlined,
                ),
                validator: (v) {
                  final d = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                  if (d.length < 9) {
                    return _t(context, 'Enter a valid phone number',
                        'Weka nambari sahihi ya simu');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: _dec(
                  _isEdit
                      ? _t(context, 'Confirm your 4-digit code',
                      'Thibitisha msimbo wako wa tarakimu 4')
                      : _t(context, 'Create a 4-digit code',
                      'Unda msimbo wa tarakimu 4'),
                  hint: _t(
                      context,
                      _isEdit
                          ? 'Needed to confirm your changes'
                          : 'Needed to edit or delete your item',
                      _isEdit
                          ? 'Unahitajika kuthibitisha mabadiliko'
                          : 'Unahitajika kuhariri au kufuta bidhaa yako'),
                  icon: Icons.lock_outline_rounded,
                ),
                validator: (v) => (v == null ||
                    !RegExp(r'^\d{4}$').hasMatch(v.trim()))
                    ? _t(context, 'Enter exactly 4 digits',
                    'Weka tarakimu 4 kamili')
                    : null,
              ),

              // ---- UPLOAD PROGRESS ----
              _buildProgress(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                      child: Text(_t(context, 'Cancel', 'Ghairi')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: brand),
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _uploadTotal > 0
                                  ? '${(_uploadPercent * 100).round()}%'
                                  : _t(context, 'Saving...', 'Inahifadhi...'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                          : Text(
                          _isEdit
                              ? _t(context, 'Save changes',
                              'Hifadhi mabadiliko')
                              : _t(context, 'Post Item',
                              'Tangaza Bidhaa')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}