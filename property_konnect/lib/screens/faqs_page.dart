import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_localizations.dart';
import 'app_settings.dart';
import 'contact_page.dart';

// ============================================================
// THEME + TRANSLATION HELPERS — dark mode follows the app-wide
// AppSettings theme; every visible string is an inline
// English/Kiswahili pair (any other language falls back to
// the central catalog, then English).
// ============================================================

bool _isDark(BuildContext context) =>
    AppSettings.of(context).isDark;

Color _green(BuildContext context) =>
    _isDark(context) ? kBrandGreenOnDark : kBrandGreen;

Color _cardColor(BuildContext context) =>
    _isDark(context) ? const Color(0xFF1A241D) : Colors.white;

Color _cardBorder(BuildContext context) =>
    _isDark(context) ? Colors.grey.shade700 : Colors.grey.shade200;

Color _pageBackground(BuildContext context) =>
    _isDark(context) ? kPageBackgroundDark : kPageBackgroundLight;

Color _mutedText(BuildContext context) =>
    _isDark(context) ? Colors.grey.shade400 : Colors.grey.shade600;

Color _bodyText(BuildContext context) =>
    _isDark(context) ? Colors.grey.shade300 : Colors.grey.shade700;

String _tr(BuildContext context, String en, String sw) {
  final code = AppSettings.of(context).languageCode;
  if (code == 'sw') return sw;
  return AppLocalizations.trText(en, code);
}

// ============================================================
// FAQ CATEGORIES
//
// Every FAQ document gets a `category` field using the KEYS
// below (never the translated label, so switching language
// does not break stored data). Unknown/missing categories
// fall back to 'general'.
//
// Admins also get an `order` field (an int) for reordering by
// importance; FAQs without it sort last, by createdAt.
// ============================================================

class FAQCategories {
  FAQCategories._();

  static const String general = 'general';
  static const String account = 'account';
  static const String findingHomes = 'finding_homes';
  static const String roommates = 'roommates';
  static const String propertyOwners = 'property_owners';
  static const String payments = 'payments';
  static const String safety = 'safety';

  static const List<String> all = [
    general,
    account,
    findingHomes,
    roommates,
    propertyOwners,
    payments,
    safety,
  ];

  static String normalize(dynamic value) {
    final key = (value ?? '').toString().trim();
    return all.contains(key) ? key : general;
  }

  static String label(BuildContext context, String key) {
    switch (normalize(key)) {
      case account:
        return _tr(context, 'Account & Profile', 'Akaunti na Wasifu');
      case findingHomes:
        return _tr(context, 'Finding Homes', 'Kutafuta Nyumba');
      case roommates:
        return _tr(context, 'Roommates', 'Wenza wa Chumba');
      case propertyOwners:
        return _tr(context, 'Property Owners', 'Wenye Mali');
      case payments:
        return _tr(context, 'Payments', 'Malipo');
      case safety:
        return _tr(context, 'Safety', 'Usalama');
      default:
        return _tr(context, 'General', 'Kwa Ujumla');
    }
  }

  static IconData icon(String key) {
    switch (normalize(key)) {
      case account:
        return Icons.person_outline_rounded;
      case findingHomes:
        return Icons.home_outlined;
      case roommates:
        return Icons.group_outlined;
      case propertyOwners:
        return Icons.real_estate_agent_outlined;
      case payments:
        return Icons.payments_outlined;
      case safety:
        return Icons.shield_outlined;
      default:
        return Icons.help_outline;
    }
  }
}

// ============================================================
// ERROR HELPERS — raw Firebase exception text is NEVER shown
// to users. Technical details go to the debug log only; the
// user sees a clear translated message.
// ============================================================

void _logError(String where, Object error) {
  debugPrint('FAQs $where error: $error');
}

bool _isPermissionError(Object error) =>
    error.toString().toLowerCase().contains('permission');

bool _isNetworkError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('network') ||
      text.contains('unavailable') ||
      text.contains('internet');
}

String _saveErrorMessage(BuildContext context, Object error) {
  if (_isPermissionError(error)) {
    return _tr(
      context,
      'Unable to save. Only admins can manage FAQs.',
      'Imeshindikana kuhifadhi. Ni wasimamizi pekee '
          'wanaoweza kusimamia maswali.',
    );
  }
  if (_isNetworkError(error)) {
    return _tr(
      context,
      'Unable to save. Check your internet connection and try again.',
      'Imeshindikana kuhifadhi. Angalia muunganisho wa '
          'intaneti kisha ujaribu tena.',
    );
  }
  return _tr(
    context,
    'Unable to save the FAQ. Please try again.',
    'Imeshindikana kuhifadhi swali. Tafadhali jaribu tena.',
  );
}

String _deleteErrorMessage(BuildContext context, Object error) {
  if (_isPermissionError(error)) {
    return _tr(
      context,
      'Unable to delete. Only admins can manage FAQs.',
      'Imeshindikana kufuta. Ni wasimamizi pekee '
          'wanaoweza kusimamia maswali.',
    );
  }
  return _tr(
    context,
    'Unable to delete the FAQ. Please try again.',
    'Imeshindikana kufuta swali. Tafadhali jaribu tena.',
  );
}

class FAQsPage extends StatefulWidget {
  const FAQsPage({super.key});

  @override
  State<FAQsPage> createState() => _FAQsPageState();
}

class _FAQsPageState extends State<FAQsPage> {
  // Role is verified server-side against the Firestore users doc.
  bool _isAdmin = false;
  bool _checkingRole = true;

  // ----------------------------------------------------------
  // SEARCH
  // ----------------------------------------------------------

  final TextEditingController _searchController =
  TextEditingController();
  String _searchQuery = '';

  // ----------------------------------------------------------
  // CATEGORY FILTER
  // ----------------------------------------------------------

  String? _categoryFilter; // null = All categories

  // ----------------------------------------------------------
  // ADMIN SORTING
  // ----------------------------------------------------------

  String _sortMode = 'manual'; // manual | newest | oldest | az

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _checkingRole = false);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final role =
      (doc.data()?['role'] ?? '').toString().trim().toLowerCase();

      if (mounted) {
        setState(() {
          _isAdmin = doc.exists && role == 'admin';
          _checkingRole = false;
        });
      }
    } catch (e) {
      _logError('role check', e);
      if (mounted) setState(() => _checkingRole = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // SORTING + FILTERING
  //
  // The Firestore query does NOT use orderBy anymore: documents
  // missing `createdAt` (edited docs only carry `updatedAt`)
  // would silently disappear from an ordered query. The stream
  // is unsorted and the list is sorted CLIENT-SIDE with a safe
  // fallback chain: order -> createdAt -> updatedAt -> epoch 0.
  // ============================================================

  DateTime _timestampOf(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<QueryDocumentSnapshot> _sortDocs(List<QueryDocumentSnapshot> docs) {
    final list = [...docs];

    int orderOf(QueryDocumentSnapshot doc) {
      final data = doc.data() as Map<String, dynamic>;
      final order = data['order'];
      if (order is num) return order.toInt();
      return 1 << 30; // unordered docs sink to the bottom
    }

    switch (_sortMode) {
      case 'newest':
        list.sort((a, b) {
          final da = a.data() as Map<String, dynamic>;
          final db = b.data() as Map<String, dynamic>;
          final ta = _timestampOf(da, 'createdAt')
              .isAfter(DateTime.fromMillisecondsSinceEpoch(0))
              ? _timestampOf(da, 'createdAt')
              : _timestampOf(da, 'updatedAt');
          final tb = _timestampOf(db, 'createdAt')
              .isAfter(DateTime.fromMillisecondsSinceEpoch(0))
              ? _timestampOf(db, 'createdAt')
              : _timestampOf(db, 'updatedAt');
          return tb.compareTo(ta);
        });
        break;
      case 'oldest':
        list.sort((a, b) {
          final da = a.data() as Map<String, dynamic>;
          final db = b.data() as Map<String, dynamic>;
          final ta = _timestampOf(da, 'createdAt')
              .isAfter(DateTime.fromMillisecondsSinceEpoch(0))
              ? _timestampOf(da, 'createdAt')
              : _timestampOf(da, 'updatedAt');
          final tb = _timestampOf(db, 'createdAt')
              .isAfter(DateTime.fromMillisecondsSinceEpoch(0))
              ? _timestampOf(db, 'createdAt')
              : _timestampOf(db, 'updatedAt');
          return ta.compareTo(tb);
        });
        break;
      case 'az':
        list.sort((a, b) {
          final qa =
              (a.data() as Map<String, dynamic>)['question'] ?? '';
          final qb =
              (b.data() as Map<String, dynamic>)['question'] ?? '';
          return qa.toString().toLowerCase().compareTo(
              qb.toString().toLowerCase());
        });
        break;
      default:
      // Manual order by importance.
        list.sort((a, b) {
          final cmp = orderOf(a).compareTo(orderOf(b));
          if (cmp != 0) return cmp;
          // Same/no order value: keep createdAt (or updatedAt)
          // position so nothing vanishes.
          final da = a.data() as Map<String, dynamic>;
          final db = b.data() as Map<String, dynamic>;
          final ta = _timestampOf(da, 'createdAt')
              .isAfter(DateTime.fromMillisecondsSinceEpoch(0))
              ? _timestampOf(da, 'createdAt')
              : _timestampOf(da, 'updatedAt');
          final tb = _timestampOf(db, 'createdAt')
              .isAfter(DateTime.fromMillisecondsSinceEpoch(0))
              ? _timestampOf(db, 'createdAt')
              : _timestampOf(db, 'updatedAt');
          return ta.compareTo(tb);
        });
    }

    return list;
  }

  List<QueryDocumentSnapshot> _filterDocs(
      List<QueryDocumentSnapshot> docs) {
    var result = docs;

    // Category filter.
    if (_categoryFilter != null) {
      result = result.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return FAQCategories.normalize(data['category']) ==
            _categoryFilter;
      }).toList();
    }

    // Search filter (question, answer and category label).
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final haystack = [
          data['question']?.toString() ?? '',
          data['answer']?.toString() ?? '',
          FAQCategories.label(context, data['category'] ?? ''),
        ].join(' ').toLowerCase();
        return haystack.contains(query);
      }).toList();
    }

    return result;
  }

  // ============================================================
  // REORDER (admin) — move an FAQ up/down by importance.
  // The two adjacent documents swap `order` values; docs
  // without an order get one first so the swap always works.
  // Each write is independent and logged on failure.
  // ============================================================

  Future<void> _moveFaq(
      QueryDocumentSnapshot doc,
      List<QueryDocumentSnapshot> orderedDocs,
      bool up,
      ) async {
    final index = orderedDocs.indexOf(doc);
    final swapWith = up ? index - 1 : index + 1;
    if (index < 0 || swapWith < 0 || swapWith >= orderedDocs.length) {
      return;
    }

    final other = orderedDocs[swapWith];

    int orderOf(QueryDocumentSnapshot d) {
      final o = (d.data() as Map<String, dynamic>)['order'];
      if (o is num) return o.toInt();
      return 1 << 30;
    }

    final myOrder = orderOf(doc);
    final otherOrder = orderOf(other);

    try {
      // Make sure both documents have explicit order values.
      if (myOrder == 1 << 30 || otherOrder == 1 << 30) {
        // Give the whole visible list sequential order values,
        // then swap the pair.
        for (int i = 0; i < orderedDocs.length; i++) {
          final d = orderedDocs[i];
          final data = d.data() as Map<String, dynamic>;
          if (data['order'] is! num) {
            await d.reference.set({'order': i},
                SetOptions(merge: true));
          }
        }
      }

      await doc.reference
          .set({'order': otherOrder == 1 << 30 ? index : otherOrder},
          SetOptions(merge: true));
      await other.reference
          .set({'order': myOrder == 1 << 30 ? swapWith : myOrder},
          SetOptions(merge: true));

      if (mounted) {
        _showSnack(_tr(
            context, 'FAQ order updated.', 'Mpangilio umesasishwa.'));
      }
    } catch (e) {
      _logError('reorder', e);
      if (mounted) {
        _showSnack(_tr(context,
            'Unable to change the order. Please try again.',
            'Imeshindikana kubadilisha mpangilio. '
                'Tafadhali jaribu tena.'));
      }
    }
  }

  // ============================================================
  // ADD / EDIT DIALOG (admin) with category selection and
  // PREVIEW-BEFORE-PUBLISHING.
  //
  // The dialog has two steps: the edit form and a preview that
  // shows the FAQ EXACTLY as users will see it. Publishing
  // happens only from the preview step, so an admin always
  // checks the result first.
  //
  // Controllers are disposed only AFTER the dialog closes. If
  // the save fails the dialog stays open with a clear error
  // message, and the admin's typed text is preserved.
  // ============================================================

  Future<void> _showFAQDialog({DocumentSnapshot? doc}) async {
    final isEditing = doc != null;
    final existing = isEditing
        ? doc.data() as Map<String, dynamic>
        : <String, dynamic>{};

    final qController =
    TextEditingController(text: existing['question'] ?? '');
    final aController =
    TextEditingController(text: existing['answer'] ?? '');
    final formKey = GlobalKey<FormState>();

    String selectedCategory =
    FAQCategories.normalize(existing['category']);
    bool previewing = false;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final saveLabel = isEditing
              ? _tr(dialogContext, 'Update', 'Sasisha')
              : _tr(dialogContext, 'Publish', 'Chapisha');

          return AlertDialog(
            backgroundColor: _cardColor(dialogContext),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _green(dialogContext).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isEditing ? Icons.edit : Icons.help_outline,
                    color: _green(dialogContext),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    previewing
                        ? _tr(dialogContext,
                        'Preview FAQ', 'Onyesha Swali')
                        : isEditing
                        ? _tr(dialogContext,
                        'Edit FAQ', 'Hariri Swali')
                        : _tr(dialogContext, 'Add FAQ', 'Ongeza Swali'),
                    style: TextStyle(
                      color: _green(dialogContext),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Step toggle: form <-> preview.
                if (!previewing)
                  IconButton(
                    tooltip: _tr(dialogContext,
                        'Preview', 'Onyesha'),
                    icon: Icon(Icons.visibility_outlined,
                        color: _green(dialogContext)),
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() {
                          previewing = true;
                          dialogError = null;
                        });
                      }
                    },
                  )
                else
                  IconButton(
                    tooltip: _tr(dialogContext,
                        'Back to editing', 'Rudi kuhariri'),
                    icon: Icon(Icons.edit_outlined,
                        color: _green(dialogContext)),
                    onPressed: () => setDialogState(() {
                      previewing = false;
                    }),
                  ),
              ],
            ),
            content: SingleChildScrollView(
              child: previewing
              // ---------------- PREVIEW ----------------
                  ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr(dialogContext,
                        'This is how users will see the FAQ:',
                        'Hivi ndivyo watumiaji watakapoviona:'),
                    style: TextStyle(
                      color: _mutedText(dialogContext),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FAQCard(
                    question: qController.text.trim(),
                    answer: aController.text.trim(),
                    category: selectedCategory,
                    isAdmin: false,
                    initiallyExpanded: true,
                  ),
                ],
              )
              // ---------------- EDIT FORM ----------------
                  : Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: qController,
                      maxLines: 2,
                      style: TextStyle(
                          color: _bodyText(dialogContext)),
                      decoration: InputDecoration(
                        labelText:
                        _tr(dialogContext, 'Question', 'Swali'),
                        prefixIcon: Icon(
                          Icons.help_outline,
                          color: _green(dialogContext),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: _cardBorder(dialogContext)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _green(dialogContext),
                            width: 2,
                          ),
                        ),
                      ),
                      validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? _tr(dialogContext,
                          'Enter the question', 'Weka swali')
                          : null,
                    ),
                    const SizedBox(height: 14),

                    // ---- CATEGORY SELECTION ----
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: InputDecoration(
                        labelText: _tr(dialogContext,
                            'Category', 'Kundi'),
                        prefixIcon: Icon(
                          FAQCategories.icon(selectedCategory),
                          color: _green(dialogContext),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: _cardBorder(dialogContext)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _green(dialogContext),
                            width: 2,
                          ),
                        ),
                      ),
                      dropdownColor: _cardColor(dialogContext),
                      items: [
                        for (final category
                        in FAQCategories.all)
                          DropdownMenuItem<String>(
                            value: category,
                            child: Text(
                              FAQCategories.label(
                                  dialogContext, category),
                              style: TextStyle(
                                color: _bodyText(dialogContext),
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        selectedCategory = value;
                      },
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: aController,
                      maxLines: 4,
                      style: TextStyle(
                          color: _bodyText(dialogContext)),
                      decoration: InputDecoration(
                        labelText:
                        _tr(dialogContext, 'Answer', 'Jibu'),
                        prefixIcon: Icon(
                          Icons.notes,
                          color: _green(dialogContext),
                        ),
                        alignLabelWithHint: true,
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: _cardBorder(dialogContext)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _green(dialogContext),
                            width: 2,
                          ),
                        ),
                      ),
                      validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? _tr(dialogContext,
                          'Enter the answer', 'Weka jibu')
                          : null,
                    ),

                    // In-dialog error (save failed, dialog
                    // stays open, text preserved).
                    if (dialogError != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red
                              .withValues(alpha: 0.08),
                          borderRadius:
                          BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.red
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          dialogError!,
                          style: TextStyle(
                            color: _isDark(dialogContext)
                                ? Colors.red.shade300
                                : Colors.red.shade700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, false),
                child: Text(
                    _tr(dialogContext, 'Cancel', 'Ghairi')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _green(dialogContext),
                ),
                onPressed: () async {
                  if (!previewing) {
                    // Go to preview first (validate the form).
                    if (!formKey.currentState!.validate()) {
                      return;
                    }
                    setDialogState(() {
                      previewing = true;
                      dialogError = null;
                    });
                    return;
                  }

                  // Publishing from the preview step.
                  setDialogState(() => dialogError = null);

                  final data = {
                    'question': qController.text.trim(),
                    'answer': aController.text.trim(),
                    'category': selectedCategory,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  try {
                    if (isEditing) {
                      await FirebaseFirestore.instance
                          .collection('faqs')
                          .doc(doc.id)
                          .update(data);
                    } else {
                      await FirebaseFirestore.instance
                          .collection('faqs')
                          .add({
                        ...data,
                        'createdAt':
                        FieldValue.serverTimestamp(),
                      });
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (e) {
                    // Log the technical details, show a clean
                    // translated message INSIDE the dialog and
                    // KEEP the dialog open so nothing typed is
                    // lost.
                    _logError('save', e);
                    setDialogState(() {
                      dialogError =
                          _saveErrorMessage(dialogContext, e);
                    });
                  }
                },
                child: Text(previewing ? saveLabel : _tr(
                    dialogContext, 'Next', 'Endelea')),
              ),
            ],
          );
        },
      ),
    );

    // Cleanup AFTER the dialog is fully closed (also on a
    // failed save followed by Cancel — nothing leaks).
    qController.dispose();
    aController.dispose();

    if (saved == true && mounted) {
      _showSnack(
        isEditing
            ? _tr(context, 'FAQ updated successfully.',
            'Swali limesasishwa kwa mafanikio.')
            : _tr(context, 'FAQ added successfully.',
            'Swali limeongezwa kwa mafanikio.'),
      );
    }
  }

  // ============================================================
  // DELETE WITH CONFIRMATION
  // ============================================================

  Future<void> _confirmDelete(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
            _tr(context, 'Delete FAQ?', 'Kufuta Swali?')),
        content: Text(
          '${_tr(context,
              'Are you sure you want to delete this FAQ?',
              'Una uhakika unataka kufuta swali hili?')}\n\n"${data['question'] ?? ''}"\n\n${_tr(context,
              'This action cannot be undone.',
              'Hatua hii haiwezi kurudishwa.')}',
          style: TextStyle(color: _bodyText(context)),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: Text(_tr(context, 'Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red),
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: Text(_tr(context, 'Delete', 'Futa')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('faqs')
          .doc(doc.id)
          .delete();
      if (mounted) {
        _showSnack(
            _tr(context, 'FAQ deleted.', 'Swali limefutwa.'));
      }
    } catch (e) {
      _logError('delete', e);
      if (mounted) {
        _showSnack(_deleteErrorMessage(context, e));
      }
    }
  }

  // ============================================================
  // CONTACT SUPPORT — opens the Contact page when an FAQ does
  // not resolve the issue or the question is not listed.
  // ============================================================

  void _openContactSupport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ContactPage()),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground(context),
      appBar: AppBar(
        title: Text(_tr(context, 'FAQs', 'Maswali ya Kawaida')),
        backgroundColor: _green(context),
        foregroundColor: Colors.white,
        // Admin sorting menu.
        actions: [
          if (_isAdmin)
            PopupMenuButton<String>(
              tooltip: _tr(context, 'Sort', 'Panga'),
              icon: const Icon(Icons.sort_rounded),
              onSelected: (value) =>
                  setState(() => _sortMode = value),
              itemBuilder: (context) => [
                _sortItem('manual',
                    _tr(context, 'Manual order (importance)',
                        'Mpangilio wa mkono (umuhimu)'),
                    Icons.format_list_numbered),
                _sortItem('newest',
                    _tr(context, 'Newest first', 'Mpya kwanza'),
                    Icons.arrow_downward),
                _sortItem('oldest',
                    _tr(context, 'Oldest first', 'Ya zamani kwanza'),
                    Icons.arrow_upward),
                _sortItem('az',
                    _tr(context, 'A to Z', 'A hadi Z'),
                    Icons.sort_by_alpha),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // ---------------- SEARCH BAR ----------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: _tr(
                  context,
                  'Search FAQs (payments, safety, roommates...)',
                  'Tafuta maswali (malipo, usalama, wenza...)',
                ),
                prefixIcon: Icon(Icons.search_rounded,
                    color: _green(context)),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: _mutedText(context)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
                filled: true,
                fillColor: _cardColor(context),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: _cardBorder(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: _green(context), width: 2),
                ),
              ),
              style: TextStyle(color: _bodyText(context)),
            ),
          ),

          // ---------------- CATEGORY CHIPS ----------------
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
              const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _categoryChip(null),
                for (final category in FAQCategories.all)
                  _categoryChip(category),
              ],
            ),
          ),

          // ---------------- FAQ LIST ----------------
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // NOTE: no orderBy here — documents missing
              // createdAt would vanish from an ordered query.
              // Sorting happens client-side (see _sortDocs).
              stream: FirebaseFirestore.instance
                  .collection('faqs')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  _logError('stream', snapshot.error!);
                  return _emptyState(
                    icon: Icons.error_outline,
                    message: _tr(
                        context,
                        'Unable to load FAQs.\n'
                            'Please check your connection and try again.',
                        'Imeshindikana kupakia maswali.\n'
                            'Tafadhali angalia muunganisho '
                            'na ujaribu tena.'),
                    showContact: true,
                  );
                }

                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: _green(context),
                    ),
                  );
                }

                final allDocs = snapshot.data!.docs;
                final filtered = _filterDocs(allDocs);
                final visible = _sortDocs(filtered);

                if (allDocs.isEmpty) {
                  return _emptyState(
                    icon: Icons.question_answer_outlined,
                    message: _isAdmin
                        ? _tr(context,
                        'No FAQs yet.\n'
                            'Tap + to add the first one.',
                        'Hakuna maswali bado.\n'
                            'Gonga + ili kuongeza la kwanza.')
                        : _tr(context,
                        'No FAQs yet.\nCheck back soon.',
                        'Hakuna maswali bado.\n'
                            'Rudi tena baadaye.'),
                    showContact: !_isAdmin,
                  );
                }

                if (visible.isEmpty) {
                  return _emptyState(
                    icon: Icons.search_off_rounded,
                    message: _tr(
                        context,
                        'No FAQs match your search.\n'
                            'Try different words or contact support.',
                        'Hakuna swali linalolingana na utafutaji.\n'
                            'Jaribu maneno mengine au '
                            'wasiliana nasi.'),
                    showContact: true,
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: visible.length + 1,
                  itemBuilder: (context, index) {
                    // Last item: contact support card.
                    if (index == visible.length) {
                      return _contactSupportCard();
                    }

                    final doc = visible[index];
                    final data =
                    doc.data() as Map<String, dynamic>;

                    return FAQCard(
                      question: data['question'] ?? '',
                      answer: data['answer'] ?? '',
                      category: data['category'],
                      isAdmin: _isAdmin,
                      onEdit: () =>
                          _showFAQDialog(doc: doc),
                      onDelete: () => _confirmDelete(doc),
                      onMoveUp: (index == 0)
                          ? null
                          : () => _moveFaq(
                          doc, visible, true),
                      onMoveDown: (index ==
                          visible.length - 1)
                          ? null
                          : () => _moveFaq(
                          doc, visible, false),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _checkingRole || !_isAdmin
          ? null
          : FloatingActionButton(
        backgroundColor: _green(context),
        foregroundColor: Colors.white,
        onPressed: () => _showFAQDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  PopupMenuItem<String> _sortItem(
      String value, String label, IconData icon) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: _sortMode == value
                  ? _green(context)
                  : _mutedText(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _sortMode == value
                    ? _green(context)
                    : _bodyText(context),
                fontWeight: _sortMode == value
                    ? FontWeight.bold
                    : FontWeight.w500,
              ),
            ),
          ),
          if (_sortMode == value)
            Icon(Icons.check,
                size: 18, color: _green(context)),
        ],
      ),
    );
  }

  Widget _categoryChip(String? category) {
    final selected = _categoryFilter == category;
    final label = category == null
        ? _tr(context, 'All', 'Yote')
        : FAQCategories.label(context, category);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: _green(context),
        labelStyle: TextStyle(
          color: selected
              ? Colors.white
              : _bodyText(context),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        backgroundColor: _cardColor(context),
        side: BorderSide(
          color: selected
              ? _green(context)
              : _cardBorder(context),
        ),
        onSelected: (_) => setState(
              () => _categoryFilter =
          selected ? null : category,
        ),
      ),
    );
  }

  // ============================================================
  // CONTACT SUPPORT CARD — shown at the end of the list and in
  // empty/error states, so users always have a way to reach
  // support when the FAQs do not resolve their issue.
  // ============================================================

  Widget _contactSupportCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        elevation: 1.5,
        color: _isDark(context)
            ? const Color(0xFF152219)
            : const Color(0xFFEAF7EF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _green(context).withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.support_agent_rounded,
                  size: 32, color: _green(context)),
              const SizedBox(height: 8),
              Text(
                _tr(
                  context,
                  'Didn\'t find your answer?',
                  'Hukupata jibu lako?',
                ),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _green(context),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _tr(
                  context,
                  'Our support team is ready to help with '
                      'registration, properties, payments and more.',
                  'Timu yetu ya usaidizi iko tayari kukusaidia '
                      'kuhusu usajili, mali, malipo na mengineyo.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _mutedText(context),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _green(context),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _openContactSupport,
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: Text(
                  _tr(context, 'Contact Support',
                      'Wasiliana na Usaidizi'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String message,
    bool showContact = false,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 56,
              color: _isDark(context)
                  ? Colors.grey.shade600
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedText(context)),
            ),
            if (showContact) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _green(context),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _openContactSupport,
                icon: const Icon(Icons.support_agent_rounded,
                    size: 18),
                label: Text(
                  _tr(context, 'Contact Support',
                      'Wasiliana na Usaidizi'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700),
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
// FAQ CARD — EXPANDABLE
//
// Each question is shown as a compact row (question + category
// chip). Tapping expands the answer inline, which keeps long
// lists easy to browse. Only one card per page needs to be
// expanded manually; cards restored from the list are compact
// again.
// ============================================================

class FAQCard extends StatefulWidget {
  final String question;
  final String answer;
  final dynamic category;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool initiallyExpanded;

  const FAQCard({
    super.key,
    required this.question,
    required this.answer,
    required this.isAdmin,
    this.category,
    this.onEdit,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.initiallyExpanded = false,
  });

  @override
  State<FAQCard> createState() => _FAQCardState();
}

class _FAQCardState extends State<FAQCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant FAQCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new question (e.g. search changed) collapses the card.
    if (oldWidget.question != widget.question) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryKey = FAQCategories.normalize(widget.category);

    return Card(
      elevation: 1.5,
      color: _cardColor(context),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _expanded
              ? _green(context).withValues(alpha: 0.5)
              : _cardBorder(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------------- COMPACT ROW ----------------
          InkWell(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16)),
            onTap: () =>
                setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _green(context)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      FAQCategories.icon(categoryKey),
                      color: _green(context),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.question,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _green(context),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Small category tag.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _green(context)
                                .withValues(alpha: 0.08),
                            borderRadius:
                            BorderRadius.circular(20),
                          ),
                          child: Text(
                            FAQCategories.label(
                                context, categoryKey),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: _green(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration:
                    const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _green(context),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---------------- EXPANDABLE ANSWER ----------------
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                widget.answer,
                style: TextStyle(
                  fontSize: 14,
                  color: _bodyText(context),
                  height: 1.45,
                ),
              ),
            ),
          ),

          // ---------------- ADMIN CONTROLS ----------------
          if (widget.isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Reorder by importance.
                  IconButton(
                    tooltip: _tr(context, 'Move up',
                        'Sogeza juu'),
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      color: _green(context),
                      size: 20,
                    ),
                    onPressed: widget.onMoveUp,
                  ),
                  IconButton(
                    tooltip: _tr(context, 'Move down',
                        'Sogeza chini'),
                    icon: Icon(
                      Icons.arrow_downward_rounded,
                      color: _green(context),
                      size: 20,
                    ),
                    onPressed: widget.onMoveDown,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: _tr(context, 'Edit', 'Hariri'),
                    icon: Icon(
                      Icons.edit,
                      color: _green(context),
                      size: 20,
                    ),
                    onPressed: widget.onEdit,
                  ),
                  IconButton(
                    tooltip: _tr(context, 'Delete', 'Futa'),
                    icon: Icon(
                      Icons.delete_outline,
                      color: _isDark(context)
                          ? Colors.red.shade300
                          : Colors.red,
                      size: 20,
                    ),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}