import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_settings.dart';

/// Terms and Conditions page.
///
/// [isAdmin] is accepted for backwards compatibility with existing call
/// sites, but it is NOT trusted for permission decisions — a caller could
/// pass the wrong value (intentionally or otherwise). The page always
/// re-verifies the signed-in user's role directly against Firestore, and
/// only shows the Edit / Add / Delete controls when that check confirms
/// `role == 'admin'`. Non-admins (and signed-out users) only ever see the
/// terms content fetched from Firestore.
class TermsPage extends StatefulWidget {
  final bool isAdmin;

  const TermsPage({super.key, this.isAdmin = false});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
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

  Color get _cardColor =>
      _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _pageBackground =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  bool _loadingRole = true;
  bool _isAdmin = false;

  // Bumping this forces the StreamBuilder below to re-subscribe with a
  // fresh .snapshots() call, since a new stream instance is created on
  // every build — used to retry after a permission or network error.
  int _retryTick = 0;

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
  }

  Future<void> _checkAdminRole() async {
    bool confirmedAdmin = false;

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        confirmedAdmin =
            (userDoc.data()?['role'] ?? '').toString().trim().toLowerCase() ==
                'admin';
      }
    } catch (e) {
      // If the role check fails for any reason, fail closed — treat the
      // user as a non-admin rather than trusting the constructor value.
      confirmedAdmin = false;
    }

    if (mounted) {
      setState(() {
        _isAdmin = confirmedAdmin;
        _loadingRole = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: Text(_tr('Terms and Conditions',
            'Sheria na Masharti')),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: _loadingRole
          ? Center(
        child: CircularProgressIndicator(color: _green),
      )
          : StreamBuilder<QuerySnapshot>(
        key: ValueKey(_retryTick),
        stream: FirebaseFirestore.instance
            .collection('terms')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: _green),
            );
          }

          if (snapshot.hasError) {
            return _errorState(snapshot.error.toString());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return _emptyState();
          }

          // For simplicity show the latest terms document
          final latest = docs.first;
          final data = latest.data() as Map<String, dynamic>;
          final content = data['content'] as String? ?? '';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.description,
                      size: 48,
                      color: _green,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 2,
                  color: _cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: _cardBorder),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['title'] as String? ??
                              _tr('Terms and Conditions',
                                  'Sheria na Masharti'),
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: _green,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Divider(
                          color: _green,
                          thickness: 0.6,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          content,
                          style: TextStyle(
                            height: 1.6,
                            fontSize: 15,
                            color: _bodyText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Edit / Add / Delete are only ever rendered once the
                // Firestore-backed role check has confirmed the
                // signed-in user is an admin.
                if (_isAdmin)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                        ),
                        onPressed: () =>
                            _editTerms(context, latest.id, data),
                        icon: const Icon(Icons.edit),
                        label: Text(_tr('Edit', 'Hariri')),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                        ),
                        onPressed: () => _addNewTerms(context),
                        icon: const Icon(Icons.add),
                        label: Text(_tr('Add New', 'Ongeza Mpya')),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _isDark
                              ? Colors.red.shade300
                              : Colors.red.shade700,
                        ),
                        onPressed: () =>
                            _confirmDeleteTerms(context, latest.id),
                        icon: const Icon(Icons.delete),
                        label: Text(_tr('Delete', 'Futa')),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.description_outlined,
                size: 56,
                color: _green,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _tr('No terms and conditions have been added yet.',
                  'Hakuna sheria na masharti zilizoongezwa bado.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _bodyText,
              ),
            ),
            if (_isAdmin) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _green),
                onPressed: () => _addNewTerms(context),
                icon: const Icon(Icons.add),
                label: Text(_tr('Add Terms', 'Ongeza Masharti')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: (_isDark ? Colors.red.shade300 : Colors.red)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 56,
                color: _isDark
                    ? Colors.red.shade300
                    : Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _tr('Unable to load terms and conditions.',
                  'Imeshindikana kupakia sheria na masharti.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _bodyText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedText, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green),
              ),
              onPressed: () => setState(() => _retryTick++),
              icon: const Icon(Icons.refresh),
              label: Text(_tr('Try again', 'Jaribu tena')),
            ),
          ],
        ),
      ),
    );
  }

  void _addNewTerms(BuildContext context) {
    if (!_isAdmin) return;

    showDialog(
      context: context,
      builder: (_) {
        final titleController = TextEditingController();
        final contentController = TextEditingController();
        return AlertDialog(
          backgroundColor: _cardColor,
          title: Text(
            _tr('Add Terms', 'Ongeza Masharti'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _green,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: TextStyle(color: _bodyText),
                decoration: InputDecoration(
                  labelText: _tr('Title', 'Kichwa'),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _green, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                style: TextStyle(color: _bodyText),
                decoration: InputDecoration(
                  labelText: _tr('Content', 'Maudhui'),
                  alignLabelWithHint: true,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _green, width: 2),
                  ),
                ),
                maxLines: 6,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_tr('Cancel', 'Ghairi')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: () async {
                final title = titleController.text.trim();
                final content = contentController.text.trim();
                if (title.isNotEmpty && content.isNotEmpty) {
                  await FirebaseFirestore.instance.collection('terms').add({
                    'title': title,
                    'content': content,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(_tr('Save', 'Hifadhi')),
            ),
          ],
        );
      },
    );
  }

  void _editTerms(
      BuildContext context,
      String id,
      Map<String, dynamic> data,
      ) {
    if (!_isAdmin) return;

    showDialog(
      context: context,
      builder: (_) {
        final titleController =
        TextEditingController(text: data['title'] as String?);
        final contentController =
        TextEditingController(text: data['content'] as String?);
        return AlertDialog(
          backgroundColor: _cardColor,
          title: Text(
            _tr('Edit Terms', 'Hariri Masharti'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _green,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: TextStyle(color: _bodyText),
                decoration: InputDecoration(
                  labelText: _tr('Title', 'Kichwa'),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _green, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                style: TextStyle(color: _bodyText),
                decoration: InputDecoration(
                  labelText: _tr('Content', 'Maudhui'),
                  alignLabelWithHint: true,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _green, width: 2),
                  ),
                ),
                maxLines: 6,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_tr('Cancel', 'Ghairi')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: () async {
                final title = titleController.text.trim();
                final content = contentController.text.trim();
                if (title.isNotEmpty && content.isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('terms')
                      .doc(id)
                      .update({
                    'title': title,
                    'content': content,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(_tr('Update', 'Sasisha')),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  // DELETE — now asks for confirmation first.
  // ------------------------------------------------------------

  Future<void> _confirmDeleteTerms(BuildContext context, String id) async {
    if (!_isAdmin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(_tr('Delete Terms & Conditions?',
            'Kufuta Sheria na Masharti?')),
        content: Text(
          _tr(
            'Are you sure you want to delete this Terms & '
                'Conditions entry? This action cannot be undone.',
            'Una uhakika unataka kufuta sheria na masharti '
                'haya? Hatua hii haiwezi kurudishwa.',
          ),
          style: TextStyle(color: _bodyText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _isDark
                  ? Colors.red.shade300
                  : Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Delete', 'Futa')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection('terms').doc(id).delete();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('Terms & Conditions deleted.',
              'Sheria na masharti yamefutwa.')),
        ),
      );
    }
  }
}