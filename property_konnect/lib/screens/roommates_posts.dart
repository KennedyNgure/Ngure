import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_settings.dart';
import 'details_dialog.dart';
import 'download_helper.dart';

// ============================================================
// ROOMMATES POSTS PAGE (admin view of all roommate posts)
//
// Settings-aware version:
//   * Reads AppSettings.of(context) live — theme (dark/light),
//     language (English/Kiswahili) and text size changes apply
//     instantly.
//   * Bilingual strings via _tr(english, kiswahili).
//   * Dark mode: brand green on dark, dark cards, visible
//     muted/body text (no hardcoded white app bar).
//   * Mobile friendly: buttons stack on narrow phones, cards
//     wrap their chips.
// ============================================================

class RoommatesPostsPage extends StatefulWidget {
  const RoommatesPostsPage({super.key});

  @override
  State<RoommatesPostsPage> createState() => _RoommatesPostsPageState();
}

class _RoommatesPostsPageState extends State<RoommatesPostsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot> _visibleDocs = [];

  // ----------------------------------------------------------
  // SETTINGS HELPERS — AppSettings.of(context) is an
  // InheritedNotifier, so reading it in build() makes this page
  // rebuild whenever the user changes theme or language.
  // ----------------------------------------------------------

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _scaffold =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _card => _isDark ? kDarkCard : Colors.white;

  Color get _cardBorder =>
      _isDark ? const Color(0xFF28352C) : const Color(0xFFE3ECE6);

  Color get _bodyText =>
      _isDark ? const Color(0xFFE3EAE5) : const Color(0xFF1C2B24);

  Color get _mutedText =>
      _isDark ? const Color(0xFFA9B8AF) : const Color(0xFF5B6B62);

  Color get _accentText =>
      _isDark ? Colors.blue.shade300 : Colors.blue.shade700;

  Color get _dangerText =>
      _isDark ? Colors.red.shade300 : Colors.red.shade700;

  Color get _searchFill =>
      _isDark ? const Color(0xFF15211A) : const Color(0xFFEAF7EF);

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deletePost(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _tr('Delete Roommate Post?', 'Kufuta Chapisho cha Mwenzi wa Chumba?'),
          style: TextStyle(color: _bodyText),
        ),
        content: Text(
          _tr('This action cannot be undone.', 'Hatua hii haiwezi kurudishwa.'),
          style: TextStyle(color: _mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _dangerText,
              foregroundColor: _isDark ? Colors.black : Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Delete', 'Futa')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('roommates').doc(id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('Roommate post deleted.', 'Chapisho la mwenzi wa chumbo limefutwa.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_tr('Could not delete post: ', 'Imeshindikana kufuta chapisho: ')}$error',
          ),
        ),
      );
    }
  }

  void _viewPost(Map<String, dynamic> data, String id) {
    final name = (data['fullName'] ?? data['name'] ?? data['displayName'] ??
        _tr('Roommate post', 'Chapisho cha mwenzi wa chumba'))
        .toString();
    showDetailsDialog(
      context: context,
      title: name,
      data: {'id': id, ...data},
      downloadFileNamePrefix: 'roommate_post_$name',
      hiddenFields: const {'id'},
    );
  }

  Future<void> _downloadList() async {
    await DownloadHelper.downloadCsv(
      context: context,
      fileNamePrefix: 'roommate_posts',
      headers: [
        _tr('Name', 'Jina'),
        _tr('Gender Preference', 'Mapendeleo ya Jinsia'),
        _tr('Accommodation Type', 'Aina ya Malazi'),
        _tr('Location', 'Eneo'),
        _tr('Campus', 'Chuo'),
        _tr('Budget', 'Bajeti'),
        _tr('Budget Period', 'Kipindi cha Bajeti'),
        _tr('Phone', 'Simu'),
        _tr('Status', 'Hali'),
      ],
      rows: _visibleDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        return <dynamic>[
          data['fullName'] ?? data['name'],
          data['genderPreference'] ?? data['gender'],
          data['accommodationType'],
          data['location'] ?? data['preferredArea'],
          data['campusName'] ?? data['universityCampus'],
          data['budget'],
          data['budgetPeriod'],
          data['phoneNumber'] ?? data['phone'],
          data['status'],
        ];
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffold,
      appBar: AppBar(
        title: Text(_tr('Roommate Posts', 'Machapisho ya Wenzi wa Chumba')),
        actions: [
          IconButton(
            tooltip: _tr('Download filtered list', 'Pakua orodha iliyochujwa'),
            icon: const Icon(Icons.download),
            onPressed: _downloadList,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: _bodyText),
              decoration: InputDecoration(
                hintText: _tr(
                  'Search by name, location, campus...',
                  'Tafuta kwa jina, eneo, chuo...',
                ),
                hintStyle: TextStyle(color: _mutedText),
                prefixIcon: Icon(Icons.search, color: _brand),
                filled: true,
                fillColor: _searchFill,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _brand, width: 2),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('roommates')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: _brand),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '${_tr('Could not load posts: ', 'Imeshindikana kupakia machapisho: ')}${snapshot.error}',
                      style: TextStyle(color: _mutedText),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                docs.sort((a, b) {
                  final ad = (a.data() as Map<String, dynamic>)['createdAt'];
                  final bd = (b.data() as Map<String, dynamic>)['createdAt'];
                  final at = ad is Timestamp ? ad.toDate() : DateTime(2000);
                  final bt = bd is Timestamp ? bd.toDate() : DateTime(2000);
                  return bt.compareTo(at);
                });
                return _buildPostList(docs);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostList(List<QueryDocumentSnapshot> docs) {
    final searchTerm = _searchController.text.trim().toLowerCase();
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      if (searchTerm.isEmpty) return true;
      final searchableText = [
        data['fullName'], data['name'], data['displayName'], data['title'],
        data['location'], data['preferredArea'], data['campusName'],
        data['universityCampus'], data['genderPreference'], data['gender'],
        data['accommodationType'], data['description'], data['roommatePreferences'],
      ].join(' ').toLowerCase();
      return searchableText.contains(searchTerm);
    }).toList();
    _visibleDocs = filtered;

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            docs.isEmpty
                ? _tr(
                'No roommate posts available.',
                'Hakuna machapisho ya wenzi wa chumba yaliyopo.')
                : _tr(
                'No matching roommate posts.',
                'Hakuna machapisho yanayolingana.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedText),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final name = (data['fullName'] ?? data['name'] ??
            data['displayName'] ??
            _tr('Unnamed User', 'Mtumiaji Asiye na Jina')).toString();
        final location = [data['location'], data['preferredArea']]
            .where((v) => v != null && v.toString().trim().isNotEmpty)
            .join(', ');
        final campus = (data['campusName'] ??
            data['universityCampus'] ?? '').toString();
        final gender = (data['genderPreference'] ??
            data['gender'] ?? '').toString();
        final accommodation = (data['accommodationType'] ?? '').toString();
        final budget = (data['budget'] ?? data['price'] ?? '').toString();
        final budgetPeriod = (data['budgetPeriod'] ?? '').toString();
        final createdAt = data['createdAt'];
        final postedText = createdAt is Timestamp
            ? DateFormat.yMMMd().format(createdAt.toDate())
            : '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          color: _card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: _cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _brand.withValues(alpha: 0.12),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: TextStyle(color: _brand, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _bodyText,
                        ),
                      ),
                      if (location.isNotEmpty)
                        Text(location, style: TextStyle(fontSize: 12, color: _mutedText)),
                      if (campus.isNotEmpty)
                        Text(campus, style: TextStyle(fontSize: 11, color: _mutedText)),
                    ],
                  )),
                ]),
                if (gender.isNotEmpty || budget.isNotEmpty || accommodation.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      if (gender.isNotEmpty)
                        Text(
                          '${_tr('Gender', 'Jinsia')}: $gender',
                          style: TextStyle(
                              fontSize: 12,
                              color: _accentText,
                              fontWeight: FontWeight.w600),
                        ),
                      if (accommodation.isNotEmpty)
                        Text(
                          accommodation,
                          style: TextStyle(
                              fontSize: 12,
                              color: _accentText,
                              fontWeight: FontWeight.w600),
                        ),
                      if (budget.isNotEmpty)
                        Text(
                          '${_tr('Budget', 'Bajeti')}: Ksh $budget'
                              '${budgetPeriod.isNotEmpty ? ' $budgetPeriod' : ''}',
                          style: TextStyle(
                              fontSize: 12,
                              color: _brand,
                              fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ],
                if ((data['roommatePreferences'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    data['roommatePreferences'].toString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: _mutedText, height: 1.4),
                  ),
                ],
                if (postedText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_tr('Posted', 'Imewekwa')} $postedText',
                    style: TextStyle(fontSize: 10, color: _mutedText),
                  ),
                ],
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final viewButton = _wideButton(
                      icon: Icons.visibility_outlined,
                      label: _tr('View', 'Angalia'),
                      color: _accentText,
                      onTap: () => _viewPost(data, doc.id),
                    );
                    final removeButton = _wideButton(
                      icon: Icons.delete_outline,
                      label: _tr('Remove', 'Ondoa'),
                      color: _dangerText,
                      onTap: () => _deletePost(doc.id),
                    );

                    // Stack on very narrow phones / large text.
                    if (constraints.maxWidth > 320) {
                      return Row(children: [
                        Expanded(child: viewButton),
                        const SizedBox(width: 8),
                        Expanded(child: removeButton),
                      ]);
                    }

                    return Column(children: [
                      SizedBox(width: double.infinity, child: viewButton),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: removeButton),
                    ]);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _wideButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
      ),
    );
  }
}