// ============================================================
// campus_communities_page.dart  (FULL UPDATED FILE)
//
// CHANGES IN THIS VERSION
//  REPORTING NOW WORKS AND IS SAVED LIKE ROOMMATE REPORTS
//   - The Report button (card menu + details sheet) now saves to
//     the shared `reports` collection, in the same format as the
//     roommate reports:
//       kind: 'campus_community'
//       targetCollection: 'campus_communities'
//       targetId / targetName / targetOwnerId
//       reason, details, reporterId, deviceId, status: 'open',
//       createdAt
//     Document id: campus_community_{communityId}_{deviceId}
//     (one device = one report per community).
//   - The `reportCount` bump is best-effort, in its own try
//     block, so a rules denial no longer makes the whole report
//     look like it failed (that was why the button seemed to do
//     nothing).
//   - The old `reports` SUBCOLLECTION write was removed.
//   - All of this lives in the new shared file report_helper.dart.
//
// KEPT: JOIN COMMUNITY, SHARE COMMUNITY, EDIT POSTS (owners only,
// delete code required), optional "Meeting place", ads-verified
// posts first, delete flow unchanged.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'post_helpers.dart';
import 'report_helper.dart';

const List<String> _categoryKeys = [
  'academic',
  'sports',
  'faith',
  'arts',
  'career',
  'social',
  'other',
];

// ============================================================
// MODEL
// ============================================================

class CampusCommunity {
  final String id;
  final String name;
  final String category;
  final String customCategory;
  final String campus;
  final String meetingPlace;
  final String description;
  final String contact;
  final String email;
  final String communityLink;
  final String userId;
  final String postedBy;
  final String deleteCode;
  final bool adsVerified;
  final DateTime? createdAt;

  const CampusCommunity({
    required this.id,
    required this.name,
    required this.category,
    required this.customCategory,
    required this.campus,
    required this.meetingPlace,
    required this.description,
    required this.contact,
    required this.email,
    required this.communityLink,
    required this.userId,
    required this.postedBy,
    required this.deleteCode,
    required this.adsVerified,
    required this.createdAt,
  });

  factory CampusCommunity.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};
    final timestamp = data['createdAt'];

    return CampusCommunity(
      id: document.id,
      name: (data['name'] ?? '').toString(),
      category: (data['category'] ?? 'other').toString(),
      customCategory: (data['customCategory'] ?? '').toString(),
      campus: (data['campus'] ?? '').toString(),
      meetingPlace: (data['meetingPlace'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      contact: (data['contact'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      communityLink: (data['communityLink'] ?? '').toString(),
      userId: (data['userId'] ?? '').toString(),
      postedBy: (data['postedBy'] ?? '').toString(),
      deleteCode: (data['deleteCode'] ?? '').toString(),
      adsVerified: data['adsVerified'] == true,
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

// ============================================================
// PAGE
// ============================================================

class CampusCommunitiesPage extends StatefulWidget {
  const CampusCommunitiesPage({super.key});

  @override
  State<CampusCommunitiesPage> createState() => _CampusCommunitiesPageState();
}

class _CampusCommunitiesPageState extends State<CampusCommunitiesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  String _selectedCampus = 'All campuses';
  String _selectedCategory = 'all';
  String _searchText = '';
  String _ownerId = '';

  // Communities this device has already reported (this session).
  final Set<String> _reportedByMe = <String>{};

  // ---- Theme + translation helpers ----
  bool get _isDark => AppSettings.of(context).isDark;
  Color get _brand => _isDark ? kBrandGreenOnDark : kBrandGreen;
  Color get _cardColor => _isDark ? const Color(0xFF1A241D) : Colors.white;
  Color get _borderColor =>
      _isDark ? const Color(0xFF2A3A2F) : Colors.grey.shade200;
  Color get _subtle =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: .68);

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  String? _required(String? v) => validateRequired(context, v);
  String? _phone(String? v) => validatePhone(context, v);
  String? _email(String? v) => validateEmail(context, v);
  String? _code(String? v) => validateDeleteCode(context, v);

  @override
  void initState() {
    super.initState();
    loadOwnerId().then((id) {
      if (mounted) setState(() => _ownerId = id);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _communitiesStream {
    return _firestore
        .collection('campus_communities')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  String _categoryLabel(String key, {String custom = ''}) {
    switch (key) {
      case 'academic':
        return _tr('Academic', 'Masomo');
      case 'sports':
        return _tr('Sports', 'Michezo');
      case 'faith':
        return _tr('Faith', 'Imani');
      case 'arts':
        return _tr('Arts', 'Sanaa');
      case 'career':
        return _tr('Career', 'Taaluma');
      case 'social':
        return _tr('Social', 'Kijamii');
      default:
        return custom.trim().isEmpty ? _tr('Other', 'Nyingine') : custom.trim();
    }
  }

  IconData _categoryIcon(String key) {
    switch (key) {
      case 'academic':
        return Icons.school_outlined;
      case 'sports':
        return Icons.sports_soccer_outlined;
      case 'faith':
        return Icons.volunteer_activism_outlined;
      case 'arts':
        return Icons.palette_outlined;
      case 'career':
        return Icons.work_outline_rounded;
      case 'social':
        return Icons.celebration_outlined;
      default:
        return Icons.groups_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr('Campus Communities', 'Jumuiya za Chuo'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        onPressed: _showPostDialog,
        icon: const Icon(Icons.add),
        label: Text(_tr('Post Community', 'Posti Jumuiya')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _communitiesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: _brand),
                  );
                }

                final communities = snapshot.data?.docs
                    .map(CampusCommunity.fromFirestore)
                    .toList() ??
                    [];

                return _buildContent(communities);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<CampusCommunity> communities) {
    final campuses = _getCampuses(communities);
    final filtered = _filter(communities);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildHero(),
        const SizedBox(height: 16),
        _buildSearch(),
        const SizedBox(height: 12),
        _buildCategoryChips(),
        const SizedBox(height: 12),
        _buildCampusFilter(campuses),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _tr('Communities', 'Jumuiya'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${filtered.length}',
              style: TextStyle(color: _brand, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          _buildEmptyState()
        else
          for (final community in filtered) _buildCard(community),
      ],
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isDark
              ? const [Color(0xFF0E3D2A), Color(0xFF126B45)]
              : const [kBrandGreen, Color(0xFF2E9E6B)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups_rounded, color: Colors.white, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Find Your Campus Community',
                      'Pata Jumuiya Yako ya Chuo'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _tr(
                    'Join clubs, groups and societies on your campus, or post one for other students. No account needed.',
                    'Jiunge na vilabu, vikundi na jumuiya kwenye chuo chako au posti moja kwa wanafunzi wengine. Huhitaji akaunti.',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _searchText = value.trim()),
      decoration: InputDecoration(
        hintText: _tr('Search communities...', 'Tafuta jumuiya...'),
        prefixIcon: Icon(Icons.search, color: _brand),
        suffixIcon: _searchText.isEmpty
            ? null
            : IconButton(
          tooltip: _tr('Clear', 'Futa'),
          onPressed: () {
            _searchController.clear();
            setState(() => _searchText = '');
          },
          icon: const Icon(Icons.clear),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _brand, width: 1.6),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final keys = ['all', ..._categoryKeys];

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: keys.map((key) {
          final selected = _selectedCategory == key;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                key == 'all' ? _tr('All', 'Zote') : _categoryLabel(key),
              ),
              selected: selected,
              selectedColor: _brand,
              labelStyle: TextStyle(
                color: selected ? Colors.white : null,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (_) => setState(() => _selectedCategory = key),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCampusFilter(List<String> campuses) {
    final options = ['All campuses', ...campuses];

    if (!options.contains(_selectedCampus)) {
      _selectedCampus = 'All campuses';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.school_outlined, color: _brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCampus,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _tr('Campus', 'Kampasi'),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              items: options
                  .map(
                    (campus) => DropdownMenuItem<String>(
                  value: campus,
                  child: Text(
                    campus == 'All campuses'
                        ? _tr('All campuses', 'Vyuo vyote')
                        : campus,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedCampus = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _subtle),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _subtle, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Green badge shown on admin-verified posts.
  Widget _verifiedBadge() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brand.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 12, color: _brand),
          const SizedBox(width: 4),
          Text(
            _tr('Ads Verified', 'Imethibitishwa'),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _brand,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget _buildCard(CampusCommunity community) {
    final isOwner = _ownerId.isNotEmpty && _ownerId == community.userId;
    final canJoin = community.communityLink.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: community.adsVerified
              ? _brand.withValues(alpha: .55)
              : _borderColor,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(_categoryIcon(community.category), color: _brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        community.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                    if (community.adsVerified)
                      Icon(Icons.verified, size: 16, color: _brand),
                    // ---- CARD MENU: edit / share / report ----
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: _subtle),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'share':
                            _shareCommunity(community);
                            break;
                          case 'report':
                            _reportCommunity(community);
                            break;
                          case 'edit':
                            _showEditDialog(community);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined,
                                  size: 18, color: _brand),
                              const SizedBox(width: 10),
                              Text(_tr('Share', 'Shiriki')),
                            ],
                          ),
                        ),
                        if (isOwner)
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined,
                                    size: 18, color: _brand),
                                const SizedBox(width: 10),
                                Text(_tr('Edit listing', 'Haribu chapisho')),
                              ],
                            ),
                          ),
                        if (!isOwner)
                          PopupMenuItem<String>(
                            value: 'report',
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined,
                                    size: 18, color: Colors.orange.shade700),
                                const SizedBox(width: 10),
                                Text(
                                  _reportedByMe.contains(community.id)
                                      ? _tr('Already reported',
                                      'Umesha ripoti')
                                      : _tr('Report listing',
                                      'Ripoti chapisho'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                _infoRow(
                  Icons.category_outlined,
                  _categoryLabel(
                    community.category,
                    custom: community.customCategory,
                  ),
                ),
                _infoRow(Icons.school_outlined, community.campus),
                // Meeting place is optional: only shown when provided.
                if (community.meetingPlace.trim().isNotEmpty)
                  _infoRow(Icons.place_outlined, community.meetingPlace),
                if (community.adsVerified) _verifiedBadge(),
                const SizedBox(height: 9),

                // ---- JOIN + VIEW BUTTONS ----
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showDetails(community),
                        icon: const Icon(Icons.visibility_outlined, size: 17),
                        label: Text(_tr('View', 'Angalia')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brand,
                          side: BorderSide(color: _brand),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: canJoin
                      // openLinkButton is the shared widget that opens
                      // the WhatsApp / Telegram / website link.
                          ? openLinkButton(context, community.communityLink, _brand)
                          : OutlinedButton.icon(
                        onPressed: () => _showDetails(community),
                        icon: const Icon(Icons.info_outline, size: 17),
                        label: Text(_tr('Details', 'Maelezo')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brand,
                          side: BorderSide(color: _brand),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DETAILS SHEET
  // ============================================================

  Future<void> _showDetails(CampusCommunity community) async {
    final isOwner = _ownerId.isNotEmpty && _ownerId == community.userId;
    final canJoin = community.communityLink.trim().isNotEmpty;
    final reported = _reportedByMe.contains(community.id);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 700),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          community.name,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _tr('Share', 'Shiriki'),
                        onPressed: () => _shareCommunity(community),
                        icon: Icon(Icons.share_outlined, color: _brand),
                      ),
                      IconButton(
                        tooltip: _tr('Close', 'Funga'),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (community.adsVerified) ...[
                    const SizedBox(height: 6),
                    _verifiedBadge(),
                  ],
                  const SizedBox(height: 14),
                  _detailRow(
                    Icons.category_outlined,
                    _tr('Category', 'Aina'),
                    _categoryLabel(
                      community.category,
                      custom: community.customCategory,
                    ),
                  ),
                  _detailRow(Icons.school_outlined,
                      _tr('Campus name', 'Jina la kampasi'), community.campus),
                  if (community.meetingPlace.trim().isNotEmpty)
                    _detailRow(Icons.place_outlined,
                        _tr('Meeting place', 'Mahali pa mkutano'),
                        community.meetingPlace),
                  if (community.communityLink.trim().isNotEmpty)
                    _detailRow(Icons.link,
                        _tr('Community link', 'Kiungo cha jumuiya'),
                        community.communityLink),

                  if (isOwner) ...[
                    _privateNote(),
                    if (community.contact.trim().isNotEmpty)
                      _detailRow(Icons.phone_outlined, _tr('Phone', 'Simu'),
                          community.contact),
                    if (community.email.trim().isNotEmpty)
                      _detailRow(Icons.email_outlined,
                          _tr('Email', 'Barua pepe'), community.email),
                    if (community.postedBy.trim().isNotEmpty)
                      _detailRow(Icons.person_outline,
                          _tr('Posted by', 'Iliwekwa na'), community.postedBy),
                  ],

                  const SizedBox(height: 12),
                  Text(
                    _tr('About this community', 'Kuhusu jumuiya hii'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _brand.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      community.description.trim().isEmpty
                          ? _tr('No additional details were provided.',
                          'Hakuna maelezo ya ziada yaliyowekwa.')
                          : community.description,
                      style: const TextStyle(height: 1.5, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ---- JOIN COMMUNITY (WhatsApp / Telegram / website) ----
                  // openLinkButton is the shared widget that opens the link.
                  if (canJoin)
                    SizedBox(
                      width: double.infinity,
                      child: openLinkButton(
                          context, community.communityLink, _brand),
                    ),
                  const SizedBox(height: 10),

                  // ---- SHARE ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _brand,
                        side: BorderSide(color: _brand),
                      ),
                      onPressed: () => _shareCommunity(community),
                      icon: const Icon(Icons.share_outlined, size: 17),
                      label: Text(_tr('Share with friends',
                          'Shiriki na marafiki')),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(_tr('Close', 'Funga')),
                        ),
                      ),
                    ],
                  ),

                  // ---- REPORT (non-owners only) ----
                  if (!isOwner) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade700,
                          side: BorderSide(color: Colors.orange.shade700),
                        ),
                        onPressed: reported
                            ? null
                            : () {
                          Navigator.of(sheetContext).pop();
                          _reportCommunity(community);
                        },
                        icon: Icon(
                          reported
                              ? Icons.check_circle_outline
                              : Icons.flag_outlined,
                          size: 18,
                        ),
                        label: Text(
                          reported
                              ? _tr('You reported this listing',
                              'Umeripoti chapisho hili')
                              : _tr('Report this listing',
                              'Ripoti chapisho hiki'),
                        ),
                      ),
                    ),
                  ],

                  // ---- OWNER: EDIT + DELETE ----
                  if (isOwner) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _brand,
                              side: BorderSide(color: _brand),
                            ),
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _showEditDialog(community);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: Text(_tr('Edit', 'Haribu')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _confirmDelete(community);
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: Text(_tr('Delete', 'Futa')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // SHARE COMMUNITY
  // ============================================================

  Future<void> _shareCommunity(CampusCommunity community) async {
    final lines = <String>[
      _tr('Check out this campus community:',
          'Angalia jumuiya hii ya chuo:'),
      '${community.name} — ${_categoryLabel(
        community.category,
        custom: community.customCategory,
      )}',
      '${_tr('Campus', 'Kampasi')}: ${community.campus}',
    ];

    if (community.meetingPlace.trim().isNotEmpty) {
      lines.add('${_tr('Meeting place', 'Mahali pa mkutano')}: '
          '${community.meetingPlace}');
    }

    if (community.description.trim().isNotEmpty) {
      lines.add('');
      lines.add(community.description.trim());
    }

    if (community.communityLink.trim().isNotEmpty) {
      lines.add('');
      lines.add(community.communityLink.trim());
    }

    await Clipboard.setData(
      ClipboardData(text: lines.join('\n')),
    );

    _showMessage(_tr(
      'Community details copied. Paste them in WhatsApp, SMS or anywhere.',
      'Maelezo ya jumuiya yamenakiliwa. Weka kwenye WhatsApp, SMS au mahali pengine.',
    ));
  }

  // ============================================================
  // REPORTING — saved to the shared `reports` collection in the
  // same format as roommate reports (see report_helper.dart).
  // ============================================================

  Future<void> _reportCommunity(CampusCommunity community) async {
    if (_reportedByMe.contains(community.id)) {
      _showMessage(_tr('You have already reported this listing.',
          'Umesha ripoti chapisho hili.'));
      return;
    }

    final outcome = await ReportHelper.report(
      context,
      kind: 'campus_community',
      targetCollection: 'campus_communities',
      targetId: community.id,
      targetName: community.name,
      targetOwnerId: community.userId,
      reasons: ReportHelper.communityReasons,
    );

    if (!mounted) return;

    if (outcome == ReportOutcome.sent ||
        outcome == ReportOutcome.alreadyReported) {
      setState(() => _reportedByMe.add(community.id));
    }
  }

  Widget _privateNote() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: _brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _tr(
                'Only you can see the phone number, email and name below. Other students cannot.',
                'Ni wewe pekee unayeweza kuona nambari ya simu, barua pepe na jina hapa chini. Wanafunzi wengine hawawezi.',
              ),
              style: TextStyle(fontSize: 12, height: 1.4, color: _subtle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: _brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: _subtle)),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // POST (unchanged flow; meeting place optional)
  // ============================================================

  Future<void> _showPostDialog() async {
    final ownerId = await loadOwnerId();

    if (!mounted) return;
    _ownerId = ownerId;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final otherCategoryController = TextEditingController();
    final campusController = TextEditingController();
    final meetingPlaceController = TextEditingController();
    final descriptionController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final postedByController = TextEditingController();
    final linkController = TextEditingController();
    final codeController = TextEditingController();

    String category = _categoryKeys.first;
    String? formError;
    bool posting = false;

    final privateHelper = _tr(
      'Private: only you can see this.',
      'Siri: ni wewe pekee unayeweza kuona hii.',
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.groups_outlined, color: _brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tr('Post Campus Community',
                          'Posti Jumuiya ya Chuo'),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        postTextField(
                          controller: nameController,
                          label: _tr('Community name', 'Jina la jumuiya'),
                          hint: _tr('e.g. Maseno Football Club',
                              'mfano Klabu ya Soka ya Maseno'),
                          icon: Icons.groups_outlined,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<String>(
                            initialValue: category,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _tr('Category', 'Aina'),
                              prefixIcon: const Icon(Icons.category_outlined),
                            ),
                            items: _categoryKeys
                                .map(
                                  (key) => DropdownMenuItem<String>(
                                value: key,
                                child: Text(_categoryLabel(key)),
                              ),
                            )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => category = value);
                              }
                            },
                          ),
                        ),
                        if (category == 'other')
                          postTextField(
                            controller: otherCategoryController,
                            label:
                            _tr('Type the category', 'Andika aina ya jumuiya'),
                            hint: _tr('e.g. Photography',
                                'mfano Upigaji picha'),
                            icon: Icons.edit_outlined,
                            capitalization: TextCapitalization.sentences,
                            validator: _required,
                          ),
                        postTextField(
                          controller: campusController,
                          label: _tr('Campus name', 'Jina la kampasi'),
                          hint: _tr('e.g. Maseno University',
                              'mfano Chuo Kikuu cha Maseno'),
                          icon: Icons.school_outlined,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        // OPTIONAL: label says "(optional)", validator always accepts.
                        postTextField(
                          controller: meetingPlaceController,
                          label: _tr('Meeting place (optional)',
                              'Mahali pa mkutano (hiari)'),
                          hint: _tr('e.g. Main Hall, every Friday 5pm',
                              'mfano Ukumbi Mkuu, kila Ijumaa saa 11 jioni'),
                          icon: Icons.place_outlined,
                          capitalization: TextCapitalization.sentences,
                          validator: (_) => null,
                        ),
                        postTextField(
                          controller: descriptionController,
                          label: _tr('About the community',
                              'Kuhusu jumuiya'),
                          hint: _tr(
                            'Explain what the community does, who can join and how.',
                            'Eleza jumuiya inafanya nini, nani anaweza kujiunga na jinsi gani.',
                          ),
                          hintMaxLines: 3,
                          icon: Icons.notes_outlined,
                          capitalization: TextCapitalization.sentences,
                          maxLines: 4,
                          validator: _required,
                        ),
                        postTextField(
                          controller: phoneController,
                          label: _tr('Phone number', 'Nambari ya simu'),
                          helper: privateHelper,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          digitsOnly: true,
                          validator: _phone,
                        ),
                        postTextField(
                          controller: emailController,
                          label: _tr('Email', 'Barua pepe'),
                          helper: privateHelper,
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _email,
                        ),
                        postTextField(
                          controller: postedByController,
                          label: _tr('Your name', 'Jina lako'),
                          helper: privateHelper,
                          icon: Icons.person_outline,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: linkController,
                          label:
                          _tr('Community link', 'Kiungo cha jumuiya'),
                          hint: _tr(
                            'WhatsApp group link / Telegram group link / website link / name of app / any other link',
                            'Kiungo cha kundi la WhatsApp / kundi la Telegram / tovuti / jina la programu / kiungo kingine',
                          ),
                          helper: _tr(
                            'Public: students use this link to reach or join you.',
                            'Wazi: wanafunzi hutumia kiungo hiki kukufikia au kujiunga.',
                          ),
                          hintMaxLines: 3,
                          icon: Icons.link,
                          keyboardType: TextInputType.url,
                          validator: _required,
                        ),
                        postTextField(
                          controller: codeController,
                          label: _tr('4-digit delete code',
                              'Msimbo wa kufuta wa tarakimu 4'),
                          hint: _tr('Enter 4 digits', 'Weka tarakimu 4'),
                          helper: _tr(
                            'Keep this code. You will need it to delete your post.',
                            'Hifadhi msimbo huu. Utauhitaji kufuta chapisho lako.',
                          ),
                          icon: Icons.lock_outline,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          digitsOnly: true,
                          validator: _code,
                        ),
                        if (formError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              formError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: posting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(_tr('Cancel', 'Ghairi')),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: posting
                      ? null
                      : () async {
                    if (!formKey.currentState!.validate()) {
                      setDialogState(() {
                        formError = _tr(
                          'Please fill in every required field correctly.',
                          'Tafadhali jaza kila sehemu inayohitajika ipasavyo.',
                        );
                      });
                      return;
                    }

                    setDialogState(() {
                      formError = null;
                      posting = true;
                    });

                    final ok = await _postCommunity(
                      name: nameController.text.trim(),
                      category: category,
                      customCategory: category == 'other'
                          ? otherCategoryController.text.trim()
                          : '',
                      campus: campusController.text.trim(),
                      meetingPlace: meetingPlaceController.text.trim(),
                      description: descriptionController.text.trim(),
                      contact: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      postedBy: postedByController.text.trim(),
                      communityLink: linkController.text.trim(),
                      deleteCode: codeController.text.trim(),
                    );

                    if (!dialogContext.mounted) return;

                    if (ok) {
                      Navigator.of(dialogContext).pop();
                    } else {
                      setDialogState(() {
                        posting = false;
                        formError = _tr(
                          'Could not post the community. Please try again.',
                          'Haikuwezekana kuweka jumuiya. Tafadhali jaribu tena.',
                        );
                      });
                    }
                  },
                  icon: posting
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.send_outlined),
                  label: Text(_tr('Post', 'Posti')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _postCommunity({
    required String name,
    required String category,
    required String customCategory,
    required String campus,
    required String meetingPlace,
    required String description,
    required String contact,
    required String email,
    required String postedBy,
    required String communityLink,
    required String deleteCode,
  }) async {
    try {
      final ownerId = await loadOwnerId();

      await _firestore.collection('campus_communities').add({
        'name': name,
        'category': category,
        'customCategory': customCategory,
        'campus': campus,
        'meetingPlace': meetingPlace, // may be '' (optional)
        'description': description,
        'contact': contact,
        'email': email,
        'communityLink': communityLink,
        'userId': ownerId,
        'postedBy': postedBy,
        'deleteCode': deleteCode,
        'reportCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => _ownerId = ownerId);
        _showMessage(_tr('Community posted successfully.',
            'Jumuiya imewekwa kikamilifu.'));
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // EDIT (owner only, delete code required)
  // ============================================================

  Future<void> _showEditDialog(CampusCommunity community) async {
    if (_ownerId.isEmpty || _ownerId != community.userId) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: community.name);
    final campusController = TextEditingController(text: community.campus);
    final meetingPlaceController =
    TextEditingController(text: community.meetingPlace);
    final descriptionController =
    TextEditingController(text: community.description);
    final phoneController = TextEditingController(text: community.contact);
    final emailController = TextEditingController(text: community.email);
    final postedByController =
    TextEditingController(text: community.postedBy);
    final linkController =
    TextEditingController(text: community.communityLink);
    final codeController = TextEditingController();

    String? formError;
    bool saving = false;

    final privateHelper = _tr(
      'Private: only you can see this.',
      'Siri: ni wewe pekee unayeweza kuona hii.',
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.edit_outlined, color: _brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_tr('Edit Listing', 'Haribu Chapisho')),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        postTextField(
                          controller: nameController,
                          label: _tr('Community name', 'Jina la jumuiya'),
                          icon: Icons.groups_outlined,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: campusController,
                          label: _tr('Campus name', 'Jina la kampasi'),
                          icon: Icons.school_outlined,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: meetingPlaceController,
                          label: _tr('Meeting place (optional)',
                              'Mahali pa mkutano (hiari)'),
                          icon: Icons.place_outlined,
                          capitalization: TextCapitalization.sentences,
                          validator: (_) => null,
                        ),
                        postTextField(
                          controller: descriptionController,
                          label: _tr('About the community', 'Kuhusu jumuiya'),
                          icon: Icons.notes_outlined,
                          capitalization: TextCapitalization.sentences,
                          maxLines: 4,
                          validator: _required,
                        ),
                        postTextField(
                          controller: phoneController,
                          label: _tr('Phone number', 'Nambari ya simu'),
                          helper: privateHelper,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          digitsOnly: true,
                          validator: _phone,
                        ),
                        postTextField(
                          controller: emailController,
                          label: _tr('Email', 'Barua pepe'),
                          helper: privateHelper,
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _email,
                        ),
                        postTextField(
                          controller: postedByController,
                          label: _tr('Your name', 'Jina lako'),
                          helper: privateHelper,
                          icon: Icons.person_outline,
                          capitalization: TextCapitalization.words,
                          validator: _required,
                        ),
                        postTextField(
                          controller: linkController,
                          label: _tr('Community link', 'Kiungo cha jumuiya'),
                          helper: _tr(
                            'Public: students use this link to reach or join you.',
                            'Wazi: wanafunzi hutumia kiungo hiki kukufikia au kujiunga.',
                          ),
                          icon: Icons.link,
                          keyboardType: TextInputType.url,
                          validator: _required,
                        ),
                        postTextField(
                          controller: codeController,
                          label: _tr('Confirm your 4-digit delete code',
                              'Thibitisha msimbo wako wa kufuta'),
                          hint: _tr('Enter 4 digits', 'Weka tarakimu 4'),
                          helper: _tr(
                            'Enter your delete code to confirm the changes.',
                            'Weka msimbo wako wa kufuta kuthibitisha mabadiliko.',
                          ),
                          icon: Icons.lock_outline,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          digitsOnly: true,
                          validator: _code,
                        ),
                        if (formError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              formError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(_tr('Cancel', 'Ghairi')),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                    if (!formKey.currentState!.validate()) {
                      setDialogState(() {
                        formError = _tr(
                          'Please fill in every field correctly.',
                          'Tafadhali jaza kila sehemu ipasavyo.',
                        );
                      });
                      return;
                    }

                    // The delete code confirms the edit.
                    if (community.deleteCode.trim().isNotEmpty &&
                        codeController.text.trim() !=
                            community.deleteCode.trim()) {
                      setDialogState(() {
                        formError = _tr(
                          'Wrong delete code. Changes were not saved.',
                          'Msimbo wa kufuta si sahihi. Mabadiliko hayakuhifadhiwa.',
                        );
                      });
                      return;
                    }

                    setDialogState(() {
                      formError = null;
                      saving = true;
                    });

                    final ok = await _updateCommunity(
                      community,
                      name: nameController.text.trim(),
                      campus: campusController.text.trim(),
                      meetingPlace: meetingPlaceController.text.trim(),
                      description: descriptionController.text.trim(),
                      contact: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      postedBy: postedByController.text.trim(),
                      communityLink: linkController.text.trim(),
                    );

                    if (!dialogContext.mounted) return;

                    if (ok) {
                      Navigator.of(dialogContext).pop();
                    } else {
                      setDialogState(() {
                        saving = false;
                        formError = _tr(
                          'Could not save the changes. Please try again.',
                          'Imeshindikana kuhifadhi mabadiliko. Tafadhali jaribu tena.',
                        );
                      });
                    }
                  },
                  icon: saving
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.save_outlined),
                  label: Text(_tr('Save changes', 'Hifadhi mabadiliko')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _updateCommunity(
      CampusCommunity community, {
        required String name,
        required String campus,
        required String meetingPlace,
        required String description,
        required String contact,
        required String email,
        required String postedBy,
        required String communityLink,
      }) async {
    try {
      await _firestore
          .collection('campus_communities')
          .doc(community.id)
          .update({
        'name': name,
        'campus': campus,
        'meetingPlace': meetingPlace, // stays optional
        'description': description,
        'contact': contact,
        'email': email,
        'postedBy': postedBy,
        'communityLink': communityLink,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showMessage(_tr('Listing updated.', 'Chapisho limeharibiwa.'));
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // DELETE (unchanged flow)
  // ============================================================

  Future<void> _confirmDelete(CampusCommunity community) async {
    if (_ownerId.isEmpty || _ownerId != community.userId) return;

    final confirmed = await confirmDeleteWithCode(
      context,
      title: _tr('Delete community?', 'Ufute jumuiya?'),
      message: community.deleteCode.trim().isEmpty
          ? _tr('This community will be permanently removed.',
          'Jumuiya hii itaondolewa kabisa.')
          : _tr('Enter your 4-digit delete code to remove this community.',
          'Weka msimbo wako wa kufuta wa tarakimu 4 ili kuondoa jumuiya hii.'),
      storedCode: community.deleteCode,
    );

    if (!confirmed) return;

    try {
      await _firestore
          .collection('campus_communities')
          .doc(community.id)
          .delete();
      _showMessage(_tr('Community deleted.', 'Jumuiya imefutwa.'));
    } catch (_) {
      _showMessage(_tr('Unable to delete this community.',
          'Imeshindikana kufuta jumuiya hii.'));
    }
  }

  // ============================================================
  // FILTERING + SORTING
  //
  // Ads-VERIFIED POSTS ALWAYS COME FIRST, in "All" and in every
  // category / campus filter. The poster's name is NOT searchable.
  // ============================================================

  List<CampusCommunity> _filter(List<CampusCommunity> communities) {
    final query = _searchText.trim().toLowerCase();

    final filtered = communities.where((community) {
      if (_selectedCampus != 'All campuses' &&
          community.campus.toLowerCase() != _selectedCampus.toLowerCase()) {
        return false;
      }

      if (_selectedCategory != 'all' &&
          community.category != _selectedCategory) {
        return false;
      }

      if (query.isEmpty) return true;

      final searchable = [
        community.name,
        _categoryLabel(community.category, custom: community.customCategory),
        community.campus,
        community.meetingPlace,
        community.description,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();

    // Verified first, preserving the existing order within each group.
    final verified = filtered.where((c) => c.adsVerified).toList();
    final unverified = filtered.where((c) => !c.adsVerified).toList();

    return [...verified, ...unverified];
  }

  List<String> _getCampuses(List<CampusCommunity> communities) {
    final seen = <String, String>{};

    for (final community in communities) {
      final campus = community.campus.trim();
      if (campus.isNotEmpty) {
        seen.putIfAbsent(campus.toLowerCase(), () => campus);
      }
    }

    return seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 55),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 54, color: _brand.withValues(alpha: .65)),
          const SizedBox(height: 14),
          Text(
            _tr('No communities found', 'Hakuna jumuiya zilizopatikana'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 7),
          Text(
            _tr(
              'Try another campus or category, or post a community yourself.',
              'Jaribu kampasi au aina nyingine, au weka jumuiya mwenyewe.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _subtle, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 12),
            Text(
              _tr('Unable to load campus communities.',
                  'Imeshindikana kupakia jumuiya za chuo.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}