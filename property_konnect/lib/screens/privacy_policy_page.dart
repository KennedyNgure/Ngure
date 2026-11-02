import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_settings.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() =>
      _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState
    extends State<PrivacyPolicyPage> {
  bool _loading = true;
  bool _isAdmin = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  _policies = [];

  // ==========================================================
  // THEME + TRANSLATION — dark mode follows the app-wide
  // AppSettings theme; every visible string is an inline
  // English/Kiswahili pair.
  // ==========================================================

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green =>
      _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _greenDeep =>
      _isDark ? kBrandGreenOnDark : const Color(0xFF146C43);

  Color get _greenSurface =>
      _isDark ? const Color(0xFF152219) : const Color(0xFFEAF7EF);

  Color get _pageBackground =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _cardColor =>
      _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _draftSurface =>
      _isDark ? const Color(0xFF2A2417) : const Color(0xFFFDF6E3);

  Color get _draftIconColor =>
      _isDark ? Colors.orange.shade300 : Colors.orange.shade800;

  Color get _deleteColor =>
      _isDark ? Colors.red.shade300 : Colors.red.shade700;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
    });

    try {
      final user =
          FirebaseAuth.instance.currentUser;

      if (user != null) {
        // Always read the role from the SERVER (never a cached
        // copy) so an outdated cache can never grant admin
        // powers, and fail CLOSED: any problem with the check
        // leaves the user as a non-admin.
        try {
          final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(
            const GetOptions(source: Source.server),
          );

          _isAdmin = (userDoc.data()?['role'] ?? '')
              .toString()
              .trim()
              .toLowerCase() ==
              'admin';
        } catch (e) {
          // Fail closed — if the role check fails for any
          // reason, treat the user as a non-admin.
          _isAdmin = false;
        }
      }

      // --------------------------------------------------------
      // LOAD POLICIES — matched to the Firestore security rules.
      //
      // The rule is:
      //   allow read: if isAdmin()
      //     || resource.data.isPublished == true;
      //
      // For a LIST query, `resource.data.isPublished == true`
      // is only satisfied when the query itself filters with
      // where('isPublished', '==', true). Querying every
      // document (admin-style) therefore fails with
      // cloud_firestore/permission-denied for non-admins.
      //
      // So:
      //  - Admins read everything (drafts included), newest
      //    first, straight from Firestore.
      //  - Non-admins read ONLY published policies, and sort
      //    client-side. (Combining the where filter with
      //    orderBy('updatedAt') would require a composite
      //    index; sorting in memory avoids that.)
      // --------------------------------------------------------
      if (_isAdmin) {
        final snapshot =
        await FirebaseFirestore.instance
            .collection('privacyPolicies')
            .orderBy(
          'updatedAt',
          descending: true,
        )
            .get();

        _policies = snapshot.docs;
      } else {
        final snapshot =
        await FirebaseFirestore.instance
            .collection('privacyPolicies')
            .where(
          'isPublished',
          isEqualTo: true,
        )
            .get();

        _policies = snapshot.docs;

        // Newest first (nulls last) — client-side, so no
        // composite index is needed.
        _policies.sort((a, b) {
          final aTime = a.data()['updatedAt'];
          final bTime = b.data()['updatedAt'];

          if (aTime is! Timestamp) return 1;
          if (bTime is! Timestamp) return -1;

          return bTime.compareTo(aTime);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            backgroundColor: _greenDeep,
            content: Text(
              '${_tr(
                  'Unable to load privacy policy: ',
                  'Imeshindikana kupakia sera ya faragha: ')}$e',
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _addPolicy() async {
    final result =
    await _showPolicyEditor();

    if (result == null) return;

    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('privacyPolicies')
        .add({
      'title': result['title'],
      'content': result['content'],
      'version': result['version'],
      'isPublished': result['isPublished'],
      'createdAt':
      FieldValue.serverTimestamp(),
      'updatedAt':
      FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });

    await _loadPage();
  }

  Future<void> _editPolicy(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) async {
    final data = doc.data();

    if (data == null) return;

    final result =
    await _showPolicyEditor(
      initialTitle:
      data['title'] ?? '',
      initialContent:
      data['content'] ?? '',
      initialVersion:
      data['version'] ?? '1.0',
      initialPublished:
      data['isPublished'] == true,
    );

    if (result == null) return;

    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('privacyPolicies')
        .doc(doc.id)
        .update({
      'title': result['title'],
      'content': result['content'],
      'version': result['version'],
      'isPublished':
      result['isPublished'],
      'updatedAt':
      FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });

    await _loadPage();
  }

  Future<void> _deletePolicy(
      String id,
      ) async {
    final confirm =
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(
          _tr('Delete Privacy Policy?',
              'Kufuta Sera ya Faragha?'),
          style: TextStyle(
            color: _bodyText,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          _tr('This action cannot be undone.',
              'Hatua hii haiwezi kutenduliwa.'),
          style: TextStyle(color: _bodyText),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
                  context,
                  false,
                ),
            child: Text(
              _tr('Cancel', 'Ghairi'),
              style: TextStyle(color: _greenDeep),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _deleteColor,
              foregroundColor: _isDark
                  ? const Color(0xFF3A1A1A)
                  : Colors.white,
            ),
            onPressed: () =>
                Navigator.pop(
                  context,
                  true,
                ),
            child: Text(
              _tr('Delete', 'Futa'),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('privacyPolicies')
        .doc(id)
        .delete();

    await _loadPage();
  }

  Future<Map<String, dynamic>?> _showPolicyEditor({
    String initialTitle = '',
    String initialContent = '',
    String initialVersion = '1.0',
    bool initialPublished = false,
  }) async {
    final titleController =
    TextEditingController(
      text: initialTitle,
    );

    final contentController =
    TextEditingController(
      text: initialContent,
    );

    final versionController =
    TextEditingController(
      text: initialVersion,
    );

    bool published =
        initialPublished;

    final result =
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder:
              (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _cardColor,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(14),
              ),
              title: Text(
                initialTitle.isEmpty
                    ? _tr('Add Privacy Policy',
                    'Ongeza Sera ya Faragha')
                    : _tr('Edit Privacy Policy',
                    'Hariri Sera ya Faragha'),
                style: TextStyle(
                  color: _greenDeep,
                  fontWeight: FontWeight.bold,
                ),
              ),

              content: SizedBox(
                width: 650,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(
                        controller:
                        titleController,
                        style: TextStyle(color: _bodyText),
                        decoration: InputDecoration(
                          labelText:
                          _tr('Title', 'Kichwa'),
                          labelStyle: TextStyle(
                            color: _mutedText,
                          ),
                          filled: true,
                          fillColor: _greenSurface,
                          contentPadding:
                          const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: _green,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: _greenDeep,
                              width: 2,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller:
                        versionController,
                        style: TextStyle(color: _bodyText),
                        decoration: InputDecoration(
                          labelText:
                          _tr('Version', 'Toleo'),
                          labelStyle: TextStyle(
                            color: _mutedText,
                          ),
                          filled: true,
                          fillColor: _greenSurface,
                          contentPadding:
                          const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: _green,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: _greenDeep,
                              width: 2,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: contentController,
                        maxLines: 15,
                        style: TextStyle(color: _bodyText),
                        decoration: InputDecoration(
                          labelText: _tr(
                              'Privacy Policy Content',
                              'Maudhui ya Sera ya Faragha'),
                          alignLabelWithHint: true,
                          labelStyle: TextStyle(
                            color: _mutedText,
                          ),
                          filled: true,
                          fillColor: _greenSurface,
                          contentPadding:
                          const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: _green,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: _greenDeep,
                              width: 2,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      SwitchListTile(
                        activeThumbColor: _green,
                        title: Text(
                          _tr('Published', 'Imechapishwa'),
                          style: TextStyle(color: _bodyText),
                        ),
                        value: published,
                        onChanged: (value) {
                          setDialogState(() {
                            published = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: Text(
                    _tr('Cancel', 'Ghairi'),
                    style: TextStyle(
                      color: _greenDeep,
                    ),
                  ),
                ),

                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (titleController
                        .text
                        .trim()
                        .isEmpty ||
                        contentController
                            .text
                            .trim()
                            .isEmpty) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      {
                        'title':
                        titleController
                            .text
                            .trim(),
                        'content':
                        contentController
                            .text
                            .trim(),
                        'version':
                        versionController
                            .text
                            .trim(),
                        'isPublished':
                        published,
                      },
                    );
                  },
                  child: Text(
                    _tr('Save', 'Hifadhi'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    contentController.dispose();
    versionController.dispose();

    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _pageBackground,
        body: Center(
          child: CircularProgressIndicator(
            color: _green,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr('Privacy Policy', 'Sera ya Faragha'),
        ),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: _tr('Add Privacy Policy',
                  'Ongeza Sera ya Faragha'),
              icon: const Icon(
                Icons.add,
              ),
              onPressed: _addPolicy,
            ),
        ],
      ),

      body: Container(
        color: _greenSurface,
        width: double.infinity,
        child: _policies.isEmpty
            ? _emptyPolicy()
            : ListView.builder(
          padding:
          const EdgeInsets.all(15),

          itemCount:
          _policies.length,

          itemBuilder:
              (context, index) {
            final doc =
            _policies[index];

            final data =
            doc.data();

            final published =
                data['isPublished'] ==
                    true;

            /*
                 * Non-admins only see
                 * published policies.
                 */
            if (!_isAdmin &&
                !published) {
              return const SizedBox
                  .shrink();
            }

            return Card(
              margin:
              const EdgeInsets.only(
                bottom: 15,
              ),
              elevation: 2,
              color: _cardColor,
              shadowColor:
              const Color(0x33198754),
              clipBehavior:
              Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(
                    14),
                side: BorderSide(
                    color: _cardBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(
                  18,
                ),

                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

                  children: [
                    Container(
                      width:
                      double.infinity,
                      padding:
                      const EdgeInsets
                          .fromLTRB(
                        14,
                        12,
                        8,
                        12,
                      ),
                      decoration:
                      BoxDecoration(
                        color:
                        _green,
                        borderRadius:
                        BorderRadius
                            .only(
                          topLeft: Radius
                              .circular(
                              14),
                          topRight: Radius
                              .circular(
                              14),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons
                                .privacy_tip_outlined,
                            color: Colors
                                .white,
                            size: 22,
                          ),
                          const SizedBox(
                              width:
                              8),
                          Expanded(
                            child: Text(
                              data['title'] ??
                                  _tr(
                                      'Privacy Policy',
                                      'Sera ya Faragha'),
                              style:
                              const TextStyle(
                                fontSize:
                                21,
                                fontWeight:
                                FontWeight
                                    .bold,
                                color: Colors
                                    .white,
                              ),
                            ),
                          ),

                          if (_isAdmin)
                            PopupMenuButton<
                                String>(
                              color:
                              _cardColor,
                              icon:
                              const Icon(
                                Icons
                                    .more_vert,
                                color: Colors
                                    .white,
                              ),
                              onSelected:
                                  (value) {
                                if (value ==
                                    'edit') {
                                  _editPolicy(
                                    doc,
                                  );
                                } else if (value ==
                                    'delete') {
                                  _deletePolicy(
                                    doc.id,
                                  );
                                }
                              },
                              itemBuilder:
                                  (_) => [
                                PopupMenuItem(
                                  value:
                                  'edit',
                                  child:
                                  Text(
                                    _tr('Edit',
                                        'Hariri'),
                                    style: TextStyle(
                                        color:
                                        _bodyText),
                                  ),
                                ),
                                PopupMenuItem(
                                  value:
                                  'delete',
                                  child:
                                  Text(
                                    _tr('Delete',
                                        'Futa'),
                                    style: TextStyle(
                                        color:
                                        _bodyText),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Padding(
                      padding: const EdgeInsets
                          .symmetric(
                        horizontal: 4,
                      ),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildChip(
                                label: (data['version'] ??
                                    '')
                                    .toString()
                                    .trim()
                                    .isEmpty
                                    ? _tr(
                                    'Version not specified',
                                    'Toleo haijawekwa')
                                    : '${_tr('Version ',
                                    'Toleo ')}${data['version']}',
                                icon: Icons
                                    .tag_outlined,
                                background:
                                _greenSurface,
                                iconColor:
                                _green,
                              ),

                              if (_isAdmin)
                                _buildChip(
                                  label: published
                                      ? _tr(
                                      'Published',
                                      'Imechapishwa')
                                      : _tr(
                                      'Draft',
                                      'Rasimu'),
                                  icon: published
                                      ? Icons
                                      .check_circle_outline
                                      : Icons
                                      .edit_note_outlined,
                                  background: published
                                      ? _greenSurface
                                      : _draftSurface,
                                  iconColor: published
                                      ? _green
                                      : _draftIconColor,
                                ),
                            ],
                          ),

                          Divider(
                            height: 25,
                            color: _cardBorder,
                          ),

                          SelectableText(
                            data['content'] ?? '',
                            style:
                            TextStyle(
                              height: 1.6,
                              fontSize: 15,
                              color: _bodyText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ================================================================
  // CUSTOM CHIP (avoids Chip parameters that differ across
  // Flutter versions)
  // ================================================================

  Widget _buildChip({
    required String label,
    required IconData icon,
    required Color background,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _greenDeep,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPolicy() {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              size: 80,
              color: _green,
            ),

            const SizedBox(height: 20),

            Text(
              _tr('No privacy policy available.',
                  'Hakuna sera ya faragha inayopatikana.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _mutedText,
                fontSize: 16,
              ),
            ),

            if (_isAdmin) ...[
              const SizedBox(height: 20),

              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets
                      .symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(
                        14),
                  ),
                ),
                onPressed: _addPolicy,
                icon: const Icon(
                  Icons.add,
                ),
                label: Text(
                  _tr('Add Privacy Policy',
                      'Ongeza Sera ya Faragha'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}