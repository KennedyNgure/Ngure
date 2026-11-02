import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';

/// Main class — matches the import in homepage.dart:
///
///   import 'contact_page.dart';
///   ...
///   MaterialPageRoute(builder: (_) => const ContactPage()),
class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

/// Backward-compatible alias if any page still
/// references the old name.
class ContactUsPage extends ContactPage {
  const ContactUsPage({super.key});
}

class _SupportContacts {
  final String companyName;
  final String supportEmail;
  final String whatsappContact;
  final String phoneContact;

  const _SupportContacts({
    required this.companyName,
    required this.supportEmail,
    required this.whatsappContact,
    required this.phoneContact,
  });

  factory _SupportContacts.fromMap(Map<String, dynamic> data) {
    final whatsapp = (data['whatsappContact'] ?? '').toString().trim();
    final phone = (data['phoneContact'] ?? whatsapp).toString().trim();

    return _SupportContacts(
      companyName:
      (data['companyName'] ?? 'Kenya Hostels & Homes Ltd').toString().trim(),
      supportEmail: (data['supportEmail'] ?? '').toString().trim(),
      whatsappContact: whatsapp,
      phoneContact: phone,
    );
  }
}

class _ContactPageState extends State<ContactPage> {
  int _contactRetry = 0;

  // ==========================================================
  // THEME + TRANSLATION — dark mode follows the app-wide
  // AppSettings theme; every visible string is an inline
  // English/Kiswahili pair.
  // ==========================================================

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _greenDeep =>
      _isDark ? kBrandGreenOnDark : const Color(0xFF146C43);

  Color get _greenSurface =>
      _isDark ? const Color(0xFF152219) : const Color(0xFFEAF7EF);

  Color get _cardColor =>
      _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _disabledSurface =>
      _isDark ? Colors.grey.shade800 : Colors.grey.shade100;

  Color get _disabledBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade300;

  Color get _disabledText =>
      _isDark ? Colors.grey.shade500 : Colors.grey.shade600;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDark ? kPageBackgroundDark : kPageBackgroundLight,
      appBar: AppBar(
        title: Text(_tr('Contact Us', 'Wasiliana Nasi')),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==================================================
            // HEADER
            // ==================================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.contact_mail,
                    color: Colors.white,
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tr('Get in touch with us', 'Wasiliana nasi'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      'Have a question about a property, listing, or your '
                          'account? Reach us on any of the channels below and our '
                          'team will get back to you.',
                      'Una swali kuhusu mali, machapisho, au akaunti yako? '
                          'Wasiliana nasi kwa njia yoyote hapa chini na timu yetu '
                          'itakujibu.',
                    ),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _contactDetailsCard(context),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // CONTACT DETAILS
  // ================================================================

  Widget _contactDetailsCard(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey(_contactRetry),
      future: FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get(),
      builder: (context, snapshot) {
        // ========================================================
        // LOADING
        // ========================================================
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            color: _cardColor,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _green,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _tr('Loading contact options...',
                        'Inapakia njia za mawasiliano...'),
                    style: TextStyle(color: _bodyText),
                  ),
                ],
              ),
            ),
          );
        }

        // ========================================================
        // ERROR
        // ========================================================
        if (snapshot.hasError || !snapshot.hasData) {
          return Card(
            color: _cardColor,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('Contact us', 'Wasiliana nasi'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _greenDeep,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      'We could not load the contact options right now.',
                      'Hatukuweza kupakia njia za mawasiliano kwa wakati huu.',
                    ),
                    style: TextStyle(color: _bodyText),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      side: BorderSide(color: _green),
                    ),
                    onPressed: () {
                      setState(() {
                        _contactRetry++;
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(_tr('Try again', 'Jaribu tena')),
                  ),
                ],
              ),
            ),
          );
        }

        // ========================================================
        // NO DATA
        // ========================================================
        final data = snapshot.data!.data();

        if (data == null) {
          return Card(
            color: _cardColor,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                _tr('Contact options are not configured yet.',
                    'Njia za mawasiliano hazijasanidiwa bado.'),
                style: TextStyle(color: _bodyText),
              ),
            ),
          );
        }

        final contacts = _SupportContacts.fromMap(data);

        // ========================================================
        // CONTACT BUTTONS
        // ========================================================
        return Card(
          color: _cardColor,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Contact us', 'Wasiliana nasi'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _greenDeep,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  contacts.companyName,
                  style: TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 20),

                // ==============================================
                // WHATSAPP
                // ==============================================
                _contactButton(
                  icon: Icons.chat_rounded,
                  title: _tr('WhatsApp', 'WhatsApp'),
                  subtitle: _tr('Chat with our support team',
                      'Zungumza na timu yetu ya msaada'),
                  enabled: contacts.whatsappContact.isNotEmpty,
                  onPressed: contacts.whatsappContact.isEmpty
                      ? null
                      : () => _openWhatsApp(contacts.whatsappContact),
                ),

                const SizedBox(height: 12),

                // ==============================================
                // CALL
                // ==============================================
                _contactButton(
                  icon: Icons.phone_rounded,
                  title: _tr('Call Us', 'Piga Simu'),
                  subtitle: _tr('Speak with our support team',
                      'Piga simu kwa timu yetu ya msaada'),
                  enabled: contacts.phoneContact.isNotEmpty,
                  onPressed: contacts.phoneContact.isEmpty
                      ? null
                      : () => _openPhone(contacts.phoneContact),
                ),

                const SizedBox(height: 12),

                // ==============================================
                // EMAIL — opens Gmail (or the default email
                // app) with the RECEIVER already filled in.
                // Subject and message are left EMPTY for the
                // user to write their own, then tap send.
                // ==============================================
                _contactButton(
                  icon: Icons.email_rounded,
                  title: _tr('Email Us', 'Tuma Barua Pepe'),
                  subtitle: _tr('Send us an email via Gmail',
                      'Tutumie barua pepe kupitia Gmail'),
                  enabled: contacts.supportEmail.isNotEmpty,
                  onPressed: contacts.supportEmail.isEmpty
                      ? null
                      : () => _openEmail(contacts.supportEmail),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================================================================
  // CONTACT BUTTON
  // ================================================================

  Widget _contactButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          decoration: BoxDecoration(
            color: enabled ? _greenSurface : _disabledSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled ? _green : _disabledBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled
                      ? _green
                      : (_isDark
                      ? Colors.grey.shade600
                      : Colors.grey.shade400),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? _greenDeep : _disabledText,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      enabled
                          ? subtitle
                          : _tr('Currently unavailable',
                          'Haipatikani kwa sasa'),
                      style: TextStyle(
                        color: _mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 17,
                color: enabled
                    ? _green
                    : (_isDark
                    ? Colors.grey.shade600
                    : Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // WHATSAPP
  // ================================================================

  Future<void> _openWhatsApp(String contact) async {
    final internationalNumber = _toInternationalNumber(contact);
    final uri = Uri.parse('https://wa.me/$internationalNumber');

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
        _showError(_tr(
          'Could not open WhatsApp.',
          'Imeshindwa kufungua WhatsApp.',
        ));
      }
    } catch (_) {
      if (mounted) {
        _showError(_tr(
          'Could not open WhatsApp.',
          'Imeshindwa kufungua WhatsApp.',
        ));
      }
    }
  }

  // ================================================================
  // PHONE
  // ================================================================

  Future<void> _openPhone(String contact) async {
    final uri = Uri(scheme: 'tel', path: contact);

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
        _showError(_tr(
          'Could not open the phone dialer.',
          'Imeshindwa kufungua kipaza simu.',
        ));
      }
    } catch (_) {
      if (mounted) {
        _showError(_tr(
          'Could not open the phone dialer.',
          'Imeshindwa kufungua kipaza simu.',
        ));
      }
    }
  }

  // ================================================================
  // EMAIL — opens an EMPTY compose screen in Gmail with ONLY
  // the receiver (To:) pre-filled. Subject and message are left
  // blank for the user to write themselves, then tap send.
  //
  // Fallbacks, in order:
  //   1. googlegmail:// — the Gmail app compose screen
  //   2. Gmail web compose (mail.google.com) — opens the Gmail
  //      app if installed, otherwise the browser
  //   3. mailto: — the device's default email app
  // ================================================================

  Future<void> _openEmail(String email) async {
    // ---------------------------------------------------------
    // 1. Try to open the GMAIL APP directly, with only the
    //    receiver email filled in.
    // ---------------------------------------------------------
    final gmailAppUri = Uri.parse(
      'googlegmail://co?to=${Uri.encodeComponent(email)}',
    );

    try {
      final openedGmailApp = await launchUrl(
        gmailAppUri,
        mode: LaunchMode.externalApplication,
      );

      if (openedGmailApp) {
        return;
      }
    } catch (_) {
      // Gmail app not installed (or the scheme is not
      // allowed) — fall through to the next option.
    }

    // ---------------------------------------------------------
    // 2. Try the Gmail web compose screen (opens the Gmail
    //    app if it is installed, otherwise the browser).
    // ---------------------------------------------------------
    final gmailWebUri = Uri.https(
      'mail.google.com',
      '/mail/',
      {
        'view': 'cm',
        'fs': '1',
        'to': email,
      },
    );

    try {
      final openedGmailWeb = await launchUrl(
        gmailWebUri,
        mode: LaunchMode.externalApplication,
      );

      if (openedGmailWeb) {
        return;
      }
    } catch (_) {
      // Gmail web / app both unavailable — fall through to
      // the device's default email app.
    }

    // ---------------------------------------------------------
    // 3. Fall back to the device's default email app.
    // ---------------------------------------------------------
    final mailtoUri = Uri(scheme: 'mailto', path: email);

    try {
      final openedMailto = await launchUrl(
        mailtoUri,
        mode: LaunchMode.externalApplication,
      );

      if (!openedMailto && mounted) {
        _showError(_tr(
          'Could not open an email app.',
          'Imeshindwa kufungua programu ya barua pepe.',
        ));
      }
    } catch (_) {
      if (mounted) {
        _showError(_tr(
          'Could not open an email app.',
          'Imeshindwa kufungua programu ya barua pepe.',
        ));
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ================================================================
  // KENYAN PHONE NUMBER FORMAT
  // ================================================================

  String _toInternationalNumber(String contact) {
    final digits = contact.replaceAll(RegExp(r'[^0-9+]'), '');

    // Already international, e.g. +254712345678
    if (digits.startsWith('+254')) {
      return digits.substring(1);
    }

    if (digits.startsWith('+')) {
      return digits.substring(1);
    }

    // Local Kenyan format, e.g. 0712345678 -> 254712345678
    if (digits.startsWith('0')) {
      return '254${digits.substring(1)}';
    }

    // Already without +, e.g. 254712345678
    if (digits.startsWith('254')) {
      return digits;
    }

    return digits;
  }
}