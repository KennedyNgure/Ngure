import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'account_deactivation_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final LocalAuthentication _localAuth = LocalAuthentication();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();

  final businessNumberController = TextEditingController();
  final accountNumberController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;

  /// True while the biometric prompt (password change) is open.
  bool _isAuthenticating = false;

  /// True while the WhatsApp contact is being fetched / opened.
  bool _isOpeningWhatsapp = false;

  String accountType = '';
  String? dateRegistered;

  String verificationStatus = 'unverified';

  bool isVerified = false;

  // ------------------------------------------------------------
  // ADS VERIFICATION (TIMED)
  // ------------------------------------------------------------

  bool adsEnabled = false;
  DateTime? adsStart;
  DateTime? adsStop;

  bool get adsVerified =>
      adsEnabled && (adsStop == null || adsStop!.isAfter(DateTime.now()));

  bool get adsExpired =>
      adsEnabled && adsStop != null && adsStop!.isBefore(DateTime.now());

  /// Renewal reminder shows in orange within this many days.
  static const int _adsExpiringSoonDays = 14;

  // ------------------------------------------------------------
  // PAYMENT VALIDATION CONFIG
  //
  // Safaricom Till and Paybill numbers are NOT a fixed length.
  // They are commonly 5-7 digits, so we accept that whole range
  // instead of forcing 6 digits. Change these two numbers if the
  // provider's rules change.
  // ------------------------------------------------------------

  static const int _minShortcodeLength = 5;
  static const int _maxShortcodeLength = 7;

  /// Kenyan mobile prefixes (after the leading 0) used by Airtel.
  static const Set<String> _airtelPrefixes = {'073', '075', '078', '010'};

  /// Prefixes that belong to Airtel ONLY (Safaricom never uses
  /// them). 075x is shared between networks, so it is not here.
  static const Set<String> _airtelOnlyPrefixes = {'073', '078', '010'};

  // ============================================================
  // THEME + TRANSLATION
  // ============================================================

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green =>
      _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _cardColor =>
      _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _pageBackground =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _subtleText =>
      _isDark ? Colors.grey.shade500 : Colors.grey.shade500;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _okColor =>
      _isDark ? Colors.green.shade300 : Colors.green.shade700;

  Color get _warnColor =>
      _isDark ? Colors.orange.shade300 : Colors.orange.shade700;

  Color get _errColor =>
      _isDark ? Colors.red.shade300 : Colors.red.shade700;

  String _tr(String en, String sw) =>
      AppSettings.of(context).languageCode == 'sw' ? sw : en;

  bool _showPassword = false;

  static const List<String> _kPaymentMethods = [
    'M-Pesa Till',
    'Paybill',
    'M-Pesa',
    'Airtel Money',
  ];

  String? selectedPaymentMethod;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    businessNumberController.dispose();
    accountNumberController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ------------------------------------------------------------
  // LOAD PROFILE
  // ------------------------------------------------------------

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = snapshot.data();

      if (data != null) {
        nameController.text = data['name']?.toString() ?? '';
        phoneController.text = data['phone']?.toString() ?? '';
        emailController.text =
            data['email']?.toString() ?? user.email ?? '';

        accountType = data['role']?.toString() ?? 'owner';

        verificationStatus =
            data['landlord_status']?.toString() ?? 'unverified';

        isVerified =
            verificationStatus.toLowerCase() == 'verified' ||
                data['ownerVerification'] == 'verified' ||
                data['isVerified'] == true;

        adsEnabled = data['adsverification'] == true ||
            data['adsVerification']?.toString().toLowerCase() ==
                'verified';

        adsStart = _parseDate(data['adsStart']);
        adsStop = _parseDate(data['adsStop']);

        final method = data['paymentMethod'];

        if (method is String && _kPaymentMethods.contains(method)) {
          selectedPaymentMethod = method;
        }

        final details = data['paymentDetails'];

        if (details is Map) {
          businessNumberController.text =
              details['businessNumber']?.toString() ?? '';
          accountNumberController.text =
              details['accountNumber']?.toString() ?? '';
        } else {
          businessNumberController.text =
              data['paymentBusinessNumber']?.toString() ?? '';
          accountNumberController.text =
              data['paymentAccountNumber']?.toString() ?? '';
        }

        final createdAt = data['createdAt'];

        if (createdAt is Timestamp) {
          final dt = createdAt.toDate();
          dateRegistered = '${dt.day}/${dt.month}/${dt.year}';
        }
      }

      if (dateRegistered == null) {
        final dt = user.metadata.creationTime;

        if (dt != null) {
          dateRegistered = '${dt.day}/${dt.month}/${dt.year}';
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
            '${_tr('Unable to load profile: ',
                'Imeshindikana kupakia wasifu: ')}$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  /// Exact date + time, e.g. 5/11/2026 14:30.
  String _formatDateTime(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '${_formatDate(date)} $hh:$mm';
  }

  // ============================================================
  // REUSABLE VALIDATED EDIT DIALOG
  // ============================================================

  /// Shows a single-field edit dialog with inline validation.
  /// Returns the entered text (untrimmed validation is up to the
  /// caller), or null if cancelled.
  Future<String?> _showValidatedEditDialog({
    required String title,
    required String label,
    required String initialValue,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    TextCapitalization capitalization = TextCapitalization.none,
    String? helperText,
    IconData? icon,
  }) async {
    // NOTE: the controller is intentionally not disposed here.
    // Disposing right after the dialog closes can throw while the
    // dialog's exit animation is still drawing the text field.
    final controller = TextEditingController(text: initialValue);
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(dialogContext, controller.text.trim());
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              maxLength: maxLength,
              textCapitalization: capitalization,
              autofocus: true,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: validator,
              onFieldSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: label,
                helperText: helperText,
                helperMaxLines: 3,
                counterText: '',
                prefixIcon: icon == null ? null : Icon(icon),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('Cancel', 'Ghairi')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
              ),
              onPressed: submit,
              child: Text(_tr('Save', 'Hifadhi')),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  // EDIT FULL NAME
  // ------------------------------------------------------------

  /// Collapses repeated spaces: "  John   Doe " -> "John Doe".
  String _cleanName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  String? _validateFullName(String? value) {
    final text = _cleanName(value ?? '');

    if (text.isEmpty) {
      return _tr('Full name is required', 'Jina kamili linahitajika');
    }

    if (text.length < 3) {
      return _tr('Name is too short', 'Jina ni fupi mno');
    }

    if (text.length > 60) {
      return _tr('Name must be 60 characters or fewer',
          'Jina lisizidi herufi 60');
    }

    // Letters (any language), spaces, dots, hyphens, apostrophes.
    final allowed = RegExp(r"^[\p{L}][\p{L} .'’-]*$", unicode: true);

    if (!allowed.hasMatch(text)) {
      return _tr('Use letters only (no numbers or symbols)',
          'Tumia herufi pekee (bila nambari au alama)');
    }

    if (!text.contains(' ')) {
      return _tr('Enter at least two names (first and last)',
          'Weka majina angalau mawili (la kwanza na la mwisho)');
    }

    return null;
  }

  Future<void> _saveName() async {
    final result = await _showValidatedEditDialog(
      title: _tr('Edit full name', 'Badilisha jina kamili'),
      label: _tr('Full name', 'Jina kamili'),
      initialValue: nameController.text,
      validator: _validateFullName,
      capitalization: TextCapitalization.words,
      maxLength: 60,
      icon: Icons.person,
      helperText: _tr(
        'Use your real name as it appears on your ID.',
        'Tumia jina lako halisi kama lilivyo kwenye kitambulisho.',
      ),
    );

    if (result == null) return;

    final value = _cleanName(result);

    // Nothing changed.
    if (value == _cleanName(nameController.text)) return;

    final ok = await _updateUserFields({'name': value});

    if (ok && mounted) {
      setState(() {
        nameController.text = value;
      });

      // Keep the sign-in account's display name in step. Not
      // important enough to fail the edit if it doesn't work.
      try {
        await FirebaseAuth.instance.currentUser
            ?.updateDisplayName(value);
      } catch (e) {
        debugPrint('DISPLAY NAME UPDATE ERROR: $e');
      }
    }
  }

  // ------------------------------------------------------------
  // KENYAN MOBILE NUMBER HELPERS
  // ------------------------------------------------------------

  /// Accepts 0712345678, 712345678, 254712345678, +254712345678
  /// (also 01xx numbers) with spaces / dashes, and returns the
  /// local form "0712345678", or null if it is not a valid
  /// Kenyan mobile number.
  String? _normalizeKenyanMobile(String input) {
    var s = input.replaceAll(RegExp(r'[\s\-()]'), '');

    if (s.startsWith('+')) s = s.substring(1);

    if (s.startsWith('254')) {
      s = s.substring(3);
    } else if (s.startsWith('0')) {
      s = s.substring(1);
    }

    // 9 digits starting with 7 (07xx) or 1 (01xx).
    if (!RegExp(r'^[17]\d{8}$').hasMatch(s)) return null;

    return '0$s';
  }

  String? _validateKenyanMobile(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return _tr('Phone number is required',
          'Nambari ya simu inahitajika');
    }

    if (_normalizeKenyanMobile(text) == null) {
      return _tr(
        'Enter a valid Kenyan number, e.g. 0712345678 or +254712345678',
        'Weka nambari sahihi ya Kenya, mfano 0712345678 au +254712345678',
      );
    }

    return null;
  }

  // ------------------------------------------------------------
  // SAVE PHONE
  // ------------------------------------------------------------

  Future<void> _savePhone() async {
    final result = await _showValidatedEditDialog(
      title: _tr('Edit phone number', 'Badilisha nambari ya simu'),
      label: _tr('Phone number', 'Nambari ya simu'),
      initialValue: phoneController.text,
      validator: _validateKenyanMobile,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
      ],
      maxLength: 17,
      icon: Icons.phone,
      helperText: _tr(
        'e.g. 0712345678 or +254712345678',
        'mfano 0712345678 au +254712345678',
      ),
    );

    if (result == null) return;

    final value = _normalizeKenyanMobile(result);

    if (value == null || value == phoneController.text.trim()) return;

    final ok = await _updateUserFields({
      'phone': value,
    });

    if (ok && mounted) {
      setState(() {
        phoneController.text = value;
      });
    }
  }

  /// Updates the signed-in user's Firestore document.
  /// Returns true on success so callers only update the screen
  /// when the save really worked.
  Future<bool> _updateUserFields(
      Map<String, dynamic> fields,
      ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return false;

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        ...fields,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnack(_tr('Profile updated successfully.',
            'Wasifu umesasishwa.'));
      }

      return true;
    } catch (e) {
      if (mounted) {
        _showSnack('${_tr('Unable to update profile: ',
            'Imeshindikana kusasisha wasifu: ')}$e');
      }

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // PAYMENT NUMBER VALIDATION (provider-aware)
  //
  //  * M-Pesa Till : 5-7 digits
  //  * Paybill     : 5-7 digits (+ a required account number/name)
  //  * M-Pesa      : valid Kenyan mobile number (Safaricom range)
  //  * Airtel Money: valid Kenyan mobile number (Airtel range)
  //
  // These are format checks only. Whether a Till / Paybill number
  // actually exists can only be confirmed by Safaricom (Daraja).
  // ============================================================

  bool _isShortcodeMethod(String? method) =>
      method == 'M-Pesa Till' || method == 'Paybill';

  bool _isMobileMethod(String? method) =>
      method == 'M-Pesa' || method == 'Airtel Money';

  String? _validatePaymentNumber(String? value, String? method) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return _tr('Payment number is required',
          'Nambari ya malipo inahitajika');
    }

    // ---------- Till / Paybill ----------
    if (_isShortcodeMethod(method)) {
      if (!RegExp(r'^\d+$').hasMatch(text)) {
        return _tr('Numbers only', 'Nambari pekee');
      }

      if (text.length < _minShortcodeLength ||
          text.length > _maxShortcodeLength) {
        return _tr(
          'Enter $_minShortcodeLength to $_maxShortcodeLength digits',
          'Weka tarakimu $_minShortcodeLength hadi $_maxShortcodeLength',
        );
      }

      return null;
    }

    // ---------- M-Pesa / Airtel Money (mobile) ----------
    final normalized = _normalizeKenyanMobile(text);

    if (normalized == null) {
      return _tr(
        'Enter a valid Kenyan number, e.g. 0712345678',
        'Weka nambari sahihi ya Kenya, mfano 0712345678',
      );
    }

    final prefix = normalized.substring(0, 3);

    if (method == 'Airtel Money' && !_airtelPrefixes.contains(prefix)) {
      return _tr('This is not an Airtel Money number',
          'Hii si nambari ya Airtel Money');
    }

    if (method == 'M-Pesa' && _airtelOnlyPrefixes.contains(prefix)) {
      return _tr('This looks like an Airtel number, not M-Pesa',
          'Hii inaonekana kama nambari ya Airtel, si M-Pesa');
    }

    return null;
  }

  String? _validatePaybillAccount(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return _tr('Account number / name is required',
          'Nambari / jina la akaunti inahitajika');
    }

    if (text.length > 30) {
      return _tr('Maximum 30 characters', 'Herufi 30 zisizidi');
    }

    if (!RegExp(r'^[A-Za-z0-9 _\-./#]+$').hasMatch(text)) {
      return _tr(
        'Use letters, numbers, spaces and - _ . / # only',
        'Tumia herufi, nambari, nafasi na - _ . / # pekee',
      );
    }

    return null;
  }

  String _paymentHelperText(String? method) {
    switch (method) {
      case 'M-Pesa Till':
        return _tr(
            'Till numbers are $_minShortcodeLength-$_maxShortcodeLength digits.',
            'Nambari za Till ni tarakimu $_minShortcodeLength-$_maxShortcodeLength.');

      case 'Paybill':
        return _tr(
            'Paybill numbers are $_minShortcodeLength-$_maxShortcodeLength digits.',
            'Nambari za Paybill ni tarakimu $_minShortcodeLength-$_maxShortcodeLength.');

      case 'Airtel Money':
        return _tr('Airtel number, e.g. 0733123456 or +254733123456.',
            'Nambari ya Airtel, mfano 0733123456 au +254733123456.');

      default:
        return _tr('Safaricom number, e.g. 0712345678 or +254712345678.',
            'Nambari ya Safaricom, mfano 0712345678 au +254712345678.');
    }
  }

  // ------------------------------------------------------------
  // PAYMENT EDITOR
  // ------------------------------------------------------------

  Future<void> _editPaymentMethod() async {
    String? tempMethod = selectedPaymentMethod;

    // Errors only appear after the first Save attempt, then stay
    // live while the owner fixes them.
    bool attempted = false;

    final tempBusinessController = TextEditingController(
      text: businessNumberController.text,
    );

    final tempAccountController = TextEditingController(
      text: accountNumberController.text,
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isPaybill = tempMethod == 'Paybill';
            final isMobile = _isMobileMethod(tempMethod);

            final String? businessNumberError = attempted
                ? _validatePaymentNumber(
              tempBusinessController.text,
              tempMethod,
            )
                : null;

            final String? accountError = attempted && isPaybill
                ? _validatePaybillAccount(tempAccountController.text)
                : null;

            String firstLabel;

            switch (tempMethod) {
              case 'M-Pesa Till':
                firstLabel =
                    _tr('Till number', 'Nambari ya Till');
                break;

              case 'Paybill':
                firstLabel =
                    _tr('Paybill number', 'Nambari ya Paybill');
                break;

              case 'M-Pesa':
                firstLabel =
                    _tr('M-Pesa number', 'Nambari ya M-Pesa');
                break;

              case 'Airtel Money':
                firstLabel = _tr(
                    'Airtel Money number',
                    'Nambari ya Airtel Money');
                break;

              default:
                firstLabel = _tr('Business / payment number',
                    'Nambari ya biashara / malipo');
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),

              title: Text(
                _tr('Payment Method', 'Njia ya Malipo'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _kPaymentMethods.contains(tempMethod)
                          ? tempMethod
                          : null,
                      decoration: InputDecoration(
                        labelText:
                        _tr('Payment method', 'Njia ya malipo'),
                        prefixIcon: const Icon(Icons.payments),
                        border: const OutlineInputBorder(),
                      ),
                      items: _kPaymentMethods
                          .map(
                            (method) => DropdownMenuItem(
                          value: method,
                          child: Text(method),
                        ),
                      )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          tempMethod = value;
                          attempted = false;

                          tempBusinessController.clear();
                          tempAccountController.clear();
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    if (tempMethod != null)
                      TextField(
                        controller: tempBusinessController,
                        keyboardType: isMobile
                            ? TextInputType.phone
                            : TextInputType.number,
                        maxLength:
                        isMobile ? 17 : _maxShortcodeLength,
                        inputFormatters: [
                          isMobile
                              ? FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\s\-]'))
                              : FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) {
                          if (attempted) setDialogState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: firstLabel,
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet,
                          ),
                          border: const OutlineInputBorder(),
                          errorText: businessNumberError,
                          errorMaxLines: 2,
                          helperText:
                          _paymentHelperText(tempMethod),
                          helperMaxLines: 3,
                          counterText: '',
                        ),
                      ),

                    if (isPaybill) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: tempAccountController,
                        keyboardType: TextInputType.text,
                        maxLength: 30,
                        onChanged: (_) {
                          if (attempted) setDialogState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: _tr('Account number / name',
                              'Nambari / jina la akaunti'),
                          prefixIcon:
                          const Icon(Icons.person_outline),
                          border: const OutlineInputBorder(),
                          errorText: accountError,
                          errorMaxLines: 2,
                          counterText: '',
                          helperMaxLines: 3,
                          helperText: _tr(
                              'The account number or account name '
                                  'tenants should enter.',
                              'Nambari au jina la akaunti ambalo '
                                  'mpangaji ataweka.'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: Text(_tr('Cancel', 'Ghairi')),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                  ),
                  onPressed: () {
                    if (tempMethod == null) {
                      return;
                    }

                    final numberError = _validatePaymentNumber(
                      tempBusinessController.text,
                      tempMethod,
                    );

                    final accError = tempMethod == 'Paybill'
                        ? _validatePaybillAccount(
                        tempAccountController.text)
                        : null;

                    if (numberError != null || accError != null) {
                      setDialogState(() {
                        attempted = true;
                      });
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(_tr('Save', 'Hifadhi')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && tempMethod != null) {
      final raw = tempBusinessController.text.trim();

      // Mobile numbers are stored in one consistent local format
      // (0712345678) however the owner typed them.
      final number = _isMobileMethod(tempMethod)
          ? (_normalizeKenyanMobile(raw) ?? raw)
          : raw;

      await _savePaymentDetails(
        tempMethod!,
        number,
        tempMethod == 'Paybill'
            ? tempAccountController.text.trim()
            : '',
      );
    }

    tempBusinessController.dispose();
    tempAccountController.dispose();
  }

  Future<void> _savePaymentDetails(
      String method,
      String businessNumber,
      String accountNumber,
      ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'paymentMethod': method,
        'paymentDetails': {
          'type': method,
          'businessNumber': businessNumber,
          'accountNumber': accountNumber,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          selectedPaymentMethod = method;
          businessNumberController.text = businessNumber;
          accountNumberController.text = accountNumber;
        });

        _showSnack(_tr('Payment details updated successfully.',
            'Maelezo ya malipo yamesasishwa.'));
      }
    } catch (e) {
      if (mounted) {
        _showSnack('${_tr('Unable to update payment details: ',
            'Imeshindikana kusasisha maelezo ya malipo: ')}$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String get _paymentSummary {
    if (selectedPaymentMethod == null) {
      return '';
    }

    final method = selectedPaymentMethod!;

    if (method == 'Paybill') {
      final paybill = businessNumberController.text.trim();
      final account = accountNumberController.text.trim();

      if (paybill.isEmpty && account.isEmpty) {
        return '';
      }

      if (paybill.isNotEmpty && account.isNotEmpty) {
        return '$method - $paybill - $account';
      }

      return paybill.isNotEmpty
          ? '$method - $paybill'
          : '$method - $account';
    }

    final number = businessNumberController.text.trim();

    if (number.isEmpty) {
      return '';
    }

    return '$method - $number';
  }

  // ============================================================
  // ADVERTISEMENT VERIFICATION — WhatsApp renewal
  //
  // The admin's WhatsApp number is read from Firestore:
  //   app_config / settings  ->  whatsappContact
  // (companyName from the same document is used in the message).
  // ============================================================

  /// Turns "0717547703", "+254717547703", "254717547703" or
  /// "717547703" into "254717547703" (the form wa.me needs).
  /// Returns null if the value is empty or unusable.
  String? _toWhatsAppNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return null;

    if (digits.startsWith('254') && digits.length == 12) return digits;

    if (digits.startsWith('0') && digits.length == 10) {
      return '254${digits.substring(1)}';
    }

    if (digits.length == 9 && RegExp(r'^[17]').hasMatch(digits)) {
      return '254$digits';
    }

    // Already an international number from another country.
    if (digits.length >= 11 && digits.length <= 15) return digits;

    return null;
  }

  Future<void> _openWhatsAppForAds() async {
    if (_isOpeningWhatsapp) return;

    setState(() => _isOpeningWhatsapp = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();

      final data = doc.data();

      final number =
      _toWhatsAppNumber(data?['whatsappContact']?.toString() ?? '');

      if (number == null) {
        _showSnack(_tr(
          'The support WhatsApp number is not available right now. Please try again later.',
          'Nambari ya WhatsApp ya msaada haipatikani kwa sasa. Tafadhali jaribu tena baadaye.',
        ));
        return;
      }

      final company =
      (data?['companyName']?.toString() ?? '').trim();

      final status = adsVerified
          ? _tr('Active', 'Hai')
          : adsExpired
          ? _tr('Expired', 'Imeisha muda')
          : _tr('Not yet verified', 'Haijathibitishwa bado');

      final isRenewal = adsEnabled;

      final lines = <String>[
        isRenewal
            ? _tr(
          'Hello${company.isEmpty ? '' : ' $company'}, I would like to renew my property advertisement verification.',
          'Habari${company.isEmpty ? '' : ' $company'}, ningependa kuongeza muda wa uthibitisho wa tangazo la mali yangu.',
        )
            : _tr(
          'Hello${company.isEmpty ? '' : ' $company'}, I would like to have my property advertisement verified.',
          'Habari${company.isEmpty ? '' : ' $company'}, ningependa tangazo la mali yangu lithibitishwe.',
        ),
        '${_tr('Name', 'Jina')}: ${nameController.text.trim()}',
        '${_tr('Email', 'Barua pepe')}: ${emailController.text.trim()}',
        '${_tr('Phone', 'Simu')}: ${phoneController.text.trim()}',
        '${_tr('Advertisement status', 'Hali ya tangazo')}: $status',
        if (adsStart != null)
          '${_tr('Start date', 'Tarehe ya kuanza')}: ${_formatDateTime(adsStart!)}',
        if (adsStop != null)
          '${_tr('Expiry date', 'Tarehe ya kuisha')}: ${_formatDateTime(adsStop!)}',
      ];

      final uri = Uri.parse(
        'https://wa.me/$number?text=${Uri.encodeComponent(lines.join('\n'))}',
      );

      final launched =
      await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!launched) {
        _showSnack(_tr(
          'Could not open WhatsApp on this device.',
          'Imeshindikana kufungua WhatsApp kwenye kifaa hiki.',
        ));
      }
    } catch (e) {
      _showSnack('${_tr('Unable to open WhatsApp: ',
          'Imeshindikana kufungua WhatsApp: ')}$e');
    } finally {
      if (mounted) setState(() => _isOpeningWhatsapp = false);
    }
  }

  // ============================================================
  // PASSWORD STRENGTH VALIDATION
  // ============================================================

  bool _hasMinLength(String value) => value.length >= 8;

  bool _hasLowercase(String value) =>
      value.contains(RegExp(r'[a-z]'));

  bool _hasUppercase(String value) =>
      value.contains(RegExp(r'[A-Z]'));

  bool _hasNumber(String value) =>
      value.contains(RegExp(r'[0-9]'));

  bool _hasSpecial(String value) =>
      value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

  bool _isPasswordStrong(String password) =>
      _hasMinLength(password) &&
          _hasLowercase(password) &&
          _hasUppercase(password) &&
          _hasNumber(password) &&
          _hasSpecial(password);

  String? _validateCurrentPassword(String? value) {
    if (value == null || value.isEmpty) {
      return _tr('Enter your current password',
          'Weka nenosiri lako la sasa');
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return _tr('Enter your new password',
          'Weka nenosiri jipya');
    }

    if (!_isPasswordStrong(value)) {
      return _tr('Meet all password requirements',
          'Timize sheria zote za nenosiri');
    }

    return null;
  }

  String? _validateConfirmNewPassword(
      String? value,
      String newPassword,
      ) {
    if (value == null || value.isEmpty) {
      return _tr('Confirm your new password',
          'Thibitisha nenosiri jipya');
    }

    if (value != newPassword) {
      return _tr('Passwords do not match',
          'Manenosiri hayalingani');
    }

    return null;
  }

  Widget _passwordRule(String label, bool valid) {
    final color = valid ? _okColor : _errColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            valid ? Icons.check : Icons.close,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordChecklist(String password) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: _isDark
            ? const Color(0xFF1B2620)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr('Your password must contain:',
                'Nenosiri lako lazima liwe na:'),
            style: TextStyle(
              fontSize: 12,
              color: _bodyText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _passwordRule(
            _tr('At least 8 characters', 'Angalau herufi 8'),
            _hasMinLength(password),
          ),
          _passwordRule(
            _tr('Lowercase letter (a-z)', 'Herufi ndogo (a-z)'),
            _hasLowercase(password),
          ),
          _passwordRule(
            _tr('Uppercase letter (A-Z)', 'Herufi kubwa (A-Z)'),
            _hasUppercase(password),
          ),
          _passwordRule(
            _tr('Number (0-9)', 'Nambari (0-9)'),
            _hasNumber(password),
          ),
          _passwordRule(
            _tr(r'Special character (!@#$%^&*(),.?":{}|<>)',
                r'Alama maalum (!@#$%^&*(),.?":{}|<>)'),
            _hasSpecial(password),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkCurrentPassword(String password) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.email == null) return false;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);

      return true;
    } on FirebaseAuthException {
      return false;
    }
  }

  // ============================================================
  // BIOMETRIC GATE FOR PASSWORD CHANGE
  //
  // The password dialog only opens after the owner passes a
  // fingerprint / face check. If the device has no biometrics
  // enrolled (or this is web) the change is blocked, because a
  // biometric check cannot be performed.
  // ============================================================

  Future<bool> _authenticateWithBiometrics() async {
    if (kIsWeb) {
      _showSnack(_tr(
        'Changing your password needs fingerprint or face verification, which is not available on the web. Please use the mobile app.',
        'Kubadilisha nenosiri kunahitaji uthibitisho wa alama ya kidole au uso, ambao haupatikani kwenye wavuti. Tafadhali tumia programu ya simu.',
      ));
      return false;
    }

    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final available = await _localAuth.getAvailableBiometrics();

      if (!supported || !canCheck || available.isEmpty) {
        _showSnack(_tr(
          'To change your password, set up a fingerprint or face scan in your phone settings first.',
          'Ili kubadilisha nenosiri, weka alama ya kidole au uso kwenye mipangilio ya simu yako kwanza.',
        ));
        return false;
      }

      final ok = await _localAuth.authenticate(
        localizedReason: _tr(
          'Verify your identity to change your password',
          'Thibitisha utambulisho wako ili kubadilisha nenosiri',
        ),
        biometricOnly: true,
      );

      if (!ok) {
        _showSnack(_tr(
          'Verification was not completed. Password not changed.',
          'Uthibitisho haukukamilika. Nenosiri halijabadilishwa.',
        ));
      }

      return ok;
    } catch (e) {
      debugPrint('BIOMETRIC AUTH ERROR: $e');

      _showSnack(_tr(
        'Fingerprint / face verification failed. Please try again.',
        'Uthibitisho wa alama ya kidole / uso umeshindikana. Tafadhali jaribu tena.',
      ));

      return false;
    }
  }

  /// Entry point of the Edit-password button: biometric check
  /// first, then the password dialog.
  Future<void> _startPasswordChange() async {
    if (_isAuthenticating) return;

    setState(() => _isAuthenticating = true);

    final verified = await _authenticateWithBiometrics();

    if (mounted) setState(() => _isAuthenticating = false);

    if (!verified || !mounted) return;

    await _changePassword();
  }

  // ============================================================
  // CHANGE PASSWORD DIALOG
  // ============================================================

  Future<void> _changePassword() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmNewPasswordController = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isChanging = false;

    bool isCheckingCurrent = false;
    bool currentPasswordVerified = false;
    String? currentPasswordError;

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: !isChanging,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),

                title: Text(
                  _tr('Change Password', 'Badilisha Nenosiri'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),

                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    autovalidateMode:
                    AutovalidateMode.onUserInteraction,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: currentPasswordController,
                          obscureText: obscureCurrent,
                          enabled: !isChanging,
                          onChanged: (_) {
                            if (currentPasswordVerified ||
                                currentPasswordError != null) {
                              setDialogState(() {
                                currentPasswordVerified = false;
                                currentPasswordError = null;
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: _tr(
                                'Current password',
                                'Nenosiri la sasa'),
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            errorText: currentPasswordError,
                            helperText: currentPasswordVerified
                                ? _tr('✓ Current password confirmed',
                                '✓ Nenosiri la sasa limethibitishwa')
                                : _tr(
                                'Tap the check icon to confirm '
                                    'your current password',
                                'Bonyeza alama ya kuangalia '
                                    'kuthibitisha nenosiri lako '
                                    'la sasa'),
                            helperStyle: TextStyle(
                              fontSize: 11,
                              color: currentPasswordVerified
                                  ? _okColor
                                  : _mutedText,
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                isCheckingCurrent
                                    ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child:
                                    CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                                    : currentPasswordVerified
                                    ? Icon(
                                  Icons.check_circle,
                                  color: _okColor,
                                  size: 22,
                                )
                                    : IconButton(
                                  tooltip: _tr(
                                      'Check current password',
                                      'Angalia nenosiri la sasa'),
                                  icon: const Icon(
                                    Icons.fact_check_outlined,
                                    size: 22,
                                  ),
                                  onPressed: isChanging
                                      ? null
                                      : () async {
                                    final password =
                                        currentPasswordController
                                            .text;

                                    if (password.isEmpty) {
                                      setDialogState(() {
                                        currentPasswordError =
                                            _tr(
                                                'Enter your current '
                                                    'password first',
                                                'Weka kwanza nenosiri '
                                                    'lako la sasa');
                                      });
                                      return;
                                    }

                                    setDialogState(() {
                                      isCheckingCurrent = true;
                                      currentPasswordError = null;
                                    });

                                    final matches =
                                    await _checkCurrentPassword(
                                      password,
                                    );

                                    if (!dialogContext.mounted) {
                                      return;
                                    }

                                    setDialogState(() {
                                      isCheckingCurrent = false;
                                      currentPasswordVerified =
                                          matches;
                                      currentPasswordError = matches
                                          ? null
                                          : _tr(
                                          'Current password is '
                                              'incorrect',
                                          'Nenosiri la sasa si '
                                              'sahihi');
                                    });
                                  },
                                ),

                                IconButton(
                                  icon: Icon(
                                    obscureCurrent
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      obscureCurrent =
                                      !obscureCurrent;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          validator: _validateCurrentPassword,
                        ),

                        const SizedBox(height: 14),

                        TextFormField(
                          controller: newPasswordController,
                          obscureText: obscureNew,
                          enabled: !isChanging,
                          onChanged: (_) {
                            setDialogState(() {});
                            formKey.currentState?.validate();
                          },
                          decoration: InputDecoration(
                            labelText: _tr(
                                'New password', 'Nenosiri jipya'),
                            prefixIcon:
                            const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureNew
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  obscureNew = !obscureNew;
                                });
                              },
                            ),
                          ),
                          validator: _validateNewPassword,
                        ),

                        const SizedBox(height: 10),

                        _passwordChecklist(
                          newPasswordController.text,
                        ),

                        const SizedBox(height: 14),

                        TextFormField(
                          controller: confirmNewPasswordController,
                          obscureText: obscureConfirm,
                          enabled: !isChanging,
                          decoration: InputDecoration(
                            labelText: _tr('Confirm new password',
                                'Thibitisha nenosiri jipya'),
                            prefixIcon:
                            const Icon(Icons.lock_reset_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirm
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  obscureConfirm =
                                  !obscureConfirm;
                                });
                              },
                            ),
                          ),
                          validator: (value) =>
                              _validateConfirmNewPassword(
                                value,
                                newPasswordController.text,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),

                actions: [
                  TextButton(
                    onPressed: isChanging
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    child: Text(_tr('Cancel', 'Ghairi')),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                    ),
                    onPressed: isChanging
                        ? null
                        : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      if (!currentPasswordVerified) {
                        final matches =
                        await _checkCurrentPassword(
                          currentPasswordController.text,
                        );

                        if (!matches) {
                          setDialogState(() {
                            currentPasswordError = _tr(
                                'Current password is '
                                    'incorrect',
                                'Nenosiri la sasa si '
                                    'sahihi');
                          });
                          return;
                        }

                        if (!dialogContext.mounted) return;

                        setDialogState(() {
                          currentPasswordVerified = true;
                        });
                      }

                      setDialogState(() {
                        isChanging = true;
                      });

                      try {
                        final user = FirebaseAuth
                            .instance.currentUser;

                        await user!.updatePassword(
                          newPasswordController.text,
                        );

                        if (!dialogContext.mounted) return;

                        Navigator.pop(dialogContext, true);
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() {
                          isChanging = false;
                        });

                        if (e.code == 'requires-recent-login') {
                          try {
                            final user = FirebaseAuth
                                .instance.currentUser;

                            final credential =
                            EmailAuthProvider.credential(
                              email: user!.email!,
                              password:
                              currentPasswordController.text,
                            );

                            await user
                                .reauthenticateWithCredential(
                              credential,
                            );

                            await user.updatePassword(
                              newPasswordController.text,
                            );

                            if (!dialogContext.mounted) return;

                            Navigator.pop(dialogContext, true);
                          } on FirebaseAuthException {
                            setDialogState(() {
                              isChanging = false;
                              currentPasswordError = _tr(
                                  'Current password is '
                                      'incorrect',
                                  'Nenosiri la sasa si '
                                      'sahihi');
                            });
                          }
                        } else if (e.code == 'weak-password') {
                          setDialogState(() {
                            isChanging = false;
                          });

                          _showSnack(_tr(
                              'The new password is too weak.',
                              'Nenosiri jipya ni dhaifu sana.'));
                        } else {
                          setDialogState(() {
                            isChanging = false;
                          });

                          _showSnack('${_tr(
                              'Unable to change password: ',
                              'Imeshindikana kubadilisha '
                                  'nenosiri: ')}${e.message}');
                        }
                      }
                    },
                    child: isChanging
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Text(_tr('Save', 'Hifadhi')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      _showSnack(_tr('Password changed successfully.',
          'Nenosiri limebadilishwa.'));
    }

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmNewPasswordController.dispose();
  }

  // ============================================================
  // DELETE ACCOUNT — with owner audit trail
  // ============================================================

  /// Preset self-deletion reasons, EN + SW pairs.
  List<({String en, String sw})> get _deletionReasons => [
    (en: 'No longer need the account',
    sw: 'Sitahitaji tena akaunti'),
    (en: 'Found another platform',
    sw: 'Nimepata jukwaa lingine'),
    (en: 'Too many notifications',
    sw: 'Taarifa nyingi mno'),
    (en: 'Privacy concerns', sw: 'Wasiwasi wa faragha'),
    (en: 'Poor experience', sw: 'Uzoefu mbaya'),
    (en: 'Other (write a reason)',
    sw: 'Nyingine (andika sababu)'),
  ];

  /// A simple selectable reason tile (replaces RadioListTile,
  /// whose groupValue API is deprecated after Flutter 3.32).
  Widget _reasonTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: selected
                ? _green.withValues(alpha: 0.10)
                : _cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _green : _cardBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? _green : _mutedText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: _bodyText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The reason dialog shown after the owner confirms deletion.
  /// Returns the final reason (with optional note), or null if
  /// cancelled.
  Future<String?> _showDeletionReasonDialog() async {
    final reasonController = TextEditingController();

    // FIX: int? — matches the index of the selected reason.
    int? selected;
    String? error;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final sw =
                AppSettings.of(dialogContext).languageCode == 'sw';

            String tr(String en, String s) => sw ? s : en;

            final isOther = selected != null &&
                _deletionReasons[selected!].en.startsWith('Other');

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              icon: Icon(Icons.help_outline,
                  color: _errColor, size: 42),
              title: Text(
                tr('Why are you deleting your account?',
                    'Kwa nini unafuta akaunti yako?'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        'Please tell us why. Your reason is saved '
                            'with your account record for our records.',
                        'Tafadhali tuambie kwa nini. Sababu yako '
                            'itahifadhiwa kwenye rekodi ya akaunti '
                            'yako.',
                      ),
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_deletionReasons.length, (i) {
                      return _reasonTile(
                        label: sw
                            ? _deletionReasons[i].sw
                            : _deletionReasons[i].en,
                        selected: selected == i,
                        onTap: () {
                          setDialogState(() {
                            selected = i;
                            error = null;
                          });
                        },
                      );
                    }),
                    if (isOther) ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: reasonController,
                        maxLines: 2,
                        textCapitalization:
                        TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: tr('Write the reason',
                              'Andika sababu'),
                          border: const OutlineInputBorder(),
                          errorText: error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr('Cancel', 'Ghairi')),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  onPressed: () {
                    if (selected == null) {
                      setDialogState(() {
                        error = tr('Select a reason first',
                            'Chagua sababu kwanza');
                      });
                      return;
                    }

                    final isOtherChoice = _deletionReasons[selected!]
                        .en
                        .startsWith('Other');

                    final note = reasonController.text.trim();

                    if (isOtherChoice && note.isEmpty) {
                      setDialogState(() {
                        error = tr('Please write the reason',
                            'Tafadhali andika sababu');
                      });
                      return;
                    }

                    final base = sw
                        ? _deletionReasons[selected!].sw
                        : _deletionReasons[selected!].en;

                    Navigator.pop(
                      dialogContext,
                      isOtherChoice
                          ? note
                          : (note.isNotEmpty
                          ? '$base — $note'
                          : base),
                    );
                  },
                  child: Text(tr('Continue', 'Endelea')),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();

    return result;
  }

  Future<void> _confirmDeactivateAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          _tr('Delete account?', 'Futa akaunti?'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          _tr(
              'Your account will be deleted. '
                  'Your profile and property listings will be '
                  'deleted.',
              'Akaunti yako itafutwa. Wasifu wako na orodha za '
                  'mali zako zitafutwa.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Cancel', 'Ghairi')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _tr('Delete Account', 'Futa Akaunti'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Ask WHY before deleting — the owner cannot proceed
    // without choosing a reason.
    final reason = await _showDeletionReasonDialog();

    if (reason == null) return; // cancelled

    await _deactivateAccount(reason);
  }

  Future<void> _deactivateAccount(String reason) async {
    final user = FirebaseAuth.instance.currentUser;

    setState(() {
      _isDeleting = true;
    });

    try {
      // AUDIT TRAIL — record that the OWNER (this signed-in
      // user) initiated their own account deletion, and why,
      // BEFORE the deactivation service runs. These audit
      // fields survive on the doc and are visible to the
      // admin in VerifyPropertyOwnersPage.
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'deactivatedBy': user.uid,
            'deactivatedByName': nameController.text.trim(),
            'deactivatedByRole': 'owner',
            'deactivationReason':
            'Account deletion — $reason',
            'deactivationInitiatedBy': 'owner',
            'deactivationRequestedAt':
            FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('DEACTIVATION AUDIT WRITE ERROR: $e');
          // Not fatal — continue with the deactivation.
        }
      }

      await AccountDeactivationService.instance
          .deactivateAccount();

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/',
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      _showSnack(
        '${_tr('Unable to delete account: ',
            'Imeshindikana kufuta akaunti: ')}$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'verified':
        return _okColor;

      case 'rejected':
        return _errColor;

      default:
        return _warnColor;
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
      backgroundColor: _pageBackground,

      appBar: AppBar(
        title: Text(_tr('My Profile', 'Wasifu Wangu')),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),

          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),

              child: Form(
                key: _formKey,

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    _profileHeader(),

                    const SizedBox(height: 20),

                    _statusCard(),

                    const SizedBox(height: 16),

                    _detailsCard(),

                    const SizedBox(height: 16),

                    _securityCard(),

                    const SizedBox(height: 24),

                    _deactivateAccountCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileHeader() {
    final name = nameController.text.trim();

    final initial =
    name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Card(
      elevation: 1.5,
      color: _cardColor,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _cardBorder),
      ),

      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            CircleAvatar(
              radius: 45,
              backgroundColor: _green,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 32,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 14),

            Text(
              name.isEmpty ? _tr('User', 'Mtumiaji') : name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _green,
              ),
            ),

            const SizedBox(height: 5),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 5,
              ),

              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),

              child: Text(
                accountType.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsCard() {
    final notProvided = _tr('Not provided', 'Haijawekwa');

    return _sectionCard(
      icon: Icons.person_outline,
      title: _tr('Account Details', 'Maelezo ya Akaunti'),

      children: [
        _editableDetailRow(
          icon: Icons.person,
          label: _tr('Full name', 'Jina kamili'),
          value: nameController.text.trim().isEmpty
              ? notProvided
              : nameController.text,
          onEdit: _saveName,
        ),

        _detailRow(
          icon: Icons.email,
          label: _tr('Email', 'Barua pepe'),
          value: emailController.text.trim().isEmpty
              ? notProvided
              : emailController.text,
        ),

        _editableDetailRow(
          icon: Icons.phone,
          label: _tr('Phone', 'Simu'),
          value: phoneController.text.trim().isEmpty
              ? notProvided
              : phoneController.text,
          onEdit: _savePhone,
        ),

        _detailRow(
          icon: Icons.calendar_today,
          label: _tr('Date registered', 'Tarehe ya kujisajili'),
          value: dateRegistered ?? notProvided,
        ),

        _editableDetailRow(
          icon: Icons.payments,
          label: _tr('Payment method', 'Njia ya malipo'),
          value: _paymentSummary,
          onEdit: _editPaymentMethod,
        ),
      ],
    );
  }

  Widget _securityCard() {
    return _sectionCard(
      icon: Icons.security,
      title: _tr('Security', 'Usalama'),

      children: [
        _passwordDetailRow(),
      ],
    );
  }

  Widget _passwordDetailRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(
            Icons.lock,
            size: 20,
            color: _green,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  _tr('Password', 'Nenosiri'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _mutedText,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  _showPassword
                      ? _tr('Hidden by Firebase - use Edit to '
                      'change it',
                      'Imefichwa na Firebase - tumia Badilisha '
                          'kubadilisha')
                      : '••••••••',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 2),

                  child: Text(
                    _tr('Passwords are managed securely by '
                        'Firebase Authentication.',
                        'Manenosiri husimamiwa kwa usalama na '
                            'Firebase Authentication.'),
                    style: TextStyle(
                      fontSize: 10,
                      color: _subtleText,
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 4),

                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.fingerprint,
                        size: 14,
                        color: _green,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _tr(
                              'Changing your password requires '
                                  'fingerprint or face verification.',
                              'Kubadilisha nenosiri kunahitaji '
                                  'uthibitisho wa alama ya kidole au '
                                  'uso.'),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: _green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: _showPassword
                ? _tr('Hide info', 'Ficha maelezo')
                : _tr('Show password info',
                'Onyesha maelezo ya nenosiri'),
            onPressed: () {
              setState(() {
                _showPassword = !_showPassword;
              });
            },
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off
                  : Icons.visibility,
              size: 20,
            ),
            color: _green,
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),

          _isAuthenticating
              ? const SizedBox(
            width: 40,
            height: 40,
            child: Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
              : IconButton(
            tooltip: _tr('Edit password', 'Badilisha nenosiri'),
            onPressed: _isSaving ? null : _startPasswordChange,
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: _green,
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final statusColor = _statusColor(verificationStatus);

    return Card(
      elevation: 1.5,
      color: _cardColor,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _cardBorder),
      ),

      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [
            Row(
              children: [
                _iconBox(Icons.verified_user),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    _tr('Account Verification',
                        'Uthibitisho wa Akaunti'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _green,
                    ),
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),

                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),

                  child: Text(
                    verificationStatus.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Divider(color: _cardBorder),

            const SizedBox(height: 8),

            _adsVerificationSection(),

            const SizedBox(height: 14),

            Divider(color: _cardBorder, height: 1),

            const SizedBox(height: 12),

            _verificationRow(
              icon: isVerified
                  ? Icons.check_circle
                  : Icons.pending,
              title: _tr('Provider Verification',
                  'Uthibitisho wa Mtoa Huduma'),
              verified: isVerified,
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ADVERTISEMENT VERIFICATION SECTION
  // (status, exact start + expiry date, days left, renew button)
  // ------------------------------------------------------------

  /// Text + colour for the time left on the advertisement.
  (String, Color) _adsRemaining() {
    final stop = adsStop;

    if (stop == null) {
      return adsVerified
          ? (_tr('No expiry date', 'Hakuna tarehe ya kuisha'), _okColor)
          : ('—', _mutedText);
    }

    final diff = stop.difference(DateTime.now());

    if (diff.isNegative) {
      final days = (-diff).inDays;

      return (
      days == 0
          ? _tr('Expired today', 'Imeisha muda leo')
          : _tr('Expired $days days ago',
          'Iliisha muda siku $days zilizopita'),
      _errColor
      );
    }

    final days = diff.inDays;

    if (days == 0) {
      return (_tr('Expires today', 'Inaisha leo'), _warnColor);
    }

    return (
    _tr('$days days left', 'Siku $days zimebaki'),
    days <= _adsExpiringSoonDays ? _warnColor : _okColor
    );
  }

  Widget _adsInfoRow(
      String label,
      String value, {
        Color? valueColor,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: _mutedText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adsVerificationSection() {
    final Color color = adsVerified
        ? _okColor
        : adsExpired
        ? _errColor
        : _warnColor;

    final IconData icon = adsVerified
        ? Icons.check_circle
        : adsExpired
        ? Icons.timer_off
        : Icons.pending;

    final String status = adsVerified
        ? _tr('Verified', 'Imethibitishwa')
        : adsExpired
        ? _tr('Expired', 'Imeisha muda')
        : _tr('Pending', 'Inasubiri');

    final (remainingText, remainingColor) = _adsRemaining();

    final bool hasEverBeenVerified = adsEnabled;

    final String buttonLabel = hasEverBeenVerified
        ? _tr('Renew advertisement via WhatsApp',
        'Ongeza muda wa tangazo kupitia WhatsApp')
        : _tr('Request verification via WhatsApp',
        'Omba uthibitisho kupitia WhatsApp');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- title + status ----------
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _tr('Property Advertisement Verification',
                    'Uthibitisho wa Matangazo ya Mali'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ---------- exact dates ----------
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: hasEverBeenVerified
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _adsInfoRow(
                _tr('Start date', 'Tarehe ya kuanza'),
                adsStart != null
                    ? _formatDateTime(adsStart!)
                    : _tr('Not recorded', 'Haijarekodiwa'),
              ),
              _adsInfoRow(
                _tr('Expiry date', 'Tarehe ya kuisha'),
                adsStop != null
                    ? _formatDateTime(adsStop!)
                    : _tr('No expiry date', 'Hakuna tarehe ya kuisha'),
                valueColor: adsExpired ? _errColor : null,
              ),
              _adsInfoRow(
                _tr('Time left', 'Muda uliobaki'),
                remainingText,
                valueColor: remainingColor,
              ),
            ],
          )
              : Text(
            _tr('Not yet verified by the admin.',
                'Bado haijathibitishwa na msimamizi.'),
            style: TextStyle(fontSize: 11.5, color: _mutedText),
          ),
        ),

        const SizedBox(height: 12),

        // ---------- WhatsApp renewal button ----------
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: _isOpeningWhatsapp ? null : _openWhatsAppForAds,
            icon: _isOpeningWhatsapp
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.chat, size: 20),
            label: Text(
              buttonLabel,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _verificationRow({
    required IconData icon,
    required String title,
    required bool verified,
    String? status,
    String? detail,
  }) {
    final isExpiredRow = status == _tr('Expired', 'Imeisha muda');

    final color = isExpiredRow
        ? _errColor
        : verified
        ? _okColor
        : _warnColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 13),
              ),
            ),

            Text(
              status ??
                  (verified
                      ? _tr('Verified', 'Imethibitishwa')
                      : _tr('Pending', 'Inasubiri')),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),

        if (detail != null && detail.isNotEmpty) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              detail,
              style: TextStyle(
                fontSize: 11,
                color: isExpiredRow ? _errColor : _mutedText,
                fontWeight: isExpiredRow
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _deactivateAccountCard() {
    return Card(
      elevation: 1,
      color: _cardColor,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: _isDark
              ? Colors.red.shade700
              : Colors.red.shade100,
        ),
      ),

      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.delete_forever,
                  color: _errColor,
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    _tr('Delete Account', 'Futa Akaunti'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              _tr(
                  'Deleting your account permanently removes your '
                      'profile and property listings. You will be '
                      'asked for a reason before the account is '
                      'deactivated. This action cannot be undone.',
                  'Kufuta akaunti yako kunaondoa wasifu wako na '
                      'orodha za mali zako kwa kudumu. Utajiulizwa '
                      'sababu kabla ya akaunti kuzimwa. Hatua hii '
                      'haiwezi kutenduliwa.'),
              style: TextStyle(
                fontSize: 12,
                color: _bodyText,
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,

              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _errColor,
                  side: BorderSide(color: _errColor),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),

                onPressed:
                _isDeleting ? null : _confirmDeactivateAccount,

                icon: _isDeleting
                    ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _errColor,
                  ),
                )
                    : const Icon(Icons.delete_forever),

                label: Text(
                  _isDeleting
                      ? _tr('Deleting account...',
                      'Inafuta akaunti...')
                      : _tr('Delete Account', 'Futa Akaunti'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1.5,
      color: _cardColor,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _cardBorder),
      ),

      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Row(
              children: [
                _iconBox(icon),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _green,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Divider(color: _cardBorder, height: 1),

            const SizedBox(height: 8),

            ...children,
          ],
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),

      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),

      child: Icon(
        icon,
        color: _green,
        size: 20,
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(icon, size: 20, color: _green),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: _mutedText,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                if (helper != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      helper,
                      style: TextStyle(
                        fontSize: 10,
                        color: _subtleText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(icon, size: 20, color: _green),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: _mutedText,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          IconButton(
            tooltip: _tr('Edit ', 'Badilisha ') + label,
            onPressed: _isSaving ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: _green,
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
        ],
      ),
    );
  }
}