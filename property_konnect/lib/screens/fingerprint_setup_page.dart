import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'admin_dashboard.dart';
import 'app_localizations.dart';
import 'app_settings.dart';
import 'login_page.dart';
import 'property_owner_dashboard.dart';

class FingerprintSetupPage extends StatefulWidget {
  /// True when this page is opened from LoginPage.
  ///
  /// False means the user is completing new registration.
  final bool isLoginFlow;

  /// The account's email + password, passed from LoginPage in the
  /// login flow so the FULL device-bound biometric credential can
  /// be stored here — exactly like LoginPage's own enable flow.
  /// In the registration flow they are null (the user signs out
  /// afterwards anyway; the credential is stored on their next
  /// password login).
  final String? email;
  final String? password;

  const FingerprintSetupPage({
    super.key,
    this.isLoginFlow = false,
    this.email,
    this.password,
  });

  @override
  State<FingerprintSetupPage> createState() => _FingerprintSetupPageState();
}

class _FingerprintSetupPageState extends State<FingerprintSetupPage> {
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // Device binding + biometric credential keys (shared with
  // LoginPage).
  static const String _kDeviceId =
      'property_konnect_device_id';
  static const String _kBiometricDeviceId =
      'property_konnect_biometric_device_id';
  static const String _kBiometricEnabled =
      'property_konnect_biometric_enabled';
  static const String _kBiometricUid =
      'property_konnect_biometric_uid';
  static const String _kBiometricEmail =
      'property_konnect_biometric_email';
  static const String _kBiometricPassword =
      'property_konnect_biometric_password';

  bool _checking = true;
  bool _loading = false;

  /// Error shown inline on the page after a failed biometric
  /// attempt, so the user can retry without leaving.
  String? _setupError;

  /// The user's role, used to pick the correct dashboard
  /// after a successful login-flow setup.
  String _role = '';

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _background =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _text => _isDark ? Colors.grey.shade200 : Colors.grey.shade800;

  Color get _muted => _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) {
    final code = AppSettings.of(context).languageCode;
    if (code == 'sw') return sw;
    return AppLocalizations.trText(en, code);
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRole();
      _checkDeviceBiometrics();
    });
  }

  // ============================================================
  // DEVICE ID
  // ============================================================

  /// A stable random id for THIS installation. Generated once,
  /// then kept in secure storage. Used to bind the biometric
  /// setting to this physical device, so the user's biometric
  /// gate will NOT be active on any other device.
  Future<String> _getDeviceId() async {
    try {
      final existing = await _storage.read(key: _kDeviceId);

      if (existing != null && existing.isNotEmpty) return existing;

      final rng = Random.secure();
      final id = DateTime.now().microsecondsSinceEpoch.toString() +
          List.generate(8, (_) => rng.nextInt(16).toRadixString(16))
              .join();

      await _storage.write(key: _kDeviceId, value: id);

      return id;
    } catch (e) {
      debugPrint('DEVICE ID ERROR: $e');
      return DateTime.now().microsecondsSinceEpoch.toString();
    }
  }

  // ============================================================
  // LOAD USER ROLE (used for dashboard redirection)
  // ============================================================

  Future<void> _loadRole() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      setState(() {
        _role = (doc.data()?['role'] ?? '').toString().trim().toLowerCase();
      });
    } catch (e) {
      debugPrint('FINGERPRINT ROLE LOAD ERROR: $e');
      // Role stays empty — _dashboardPage() falls back to the
      // owner dashboard.
    }
  }

  // ============================================================
  // CHECK DEVICE BIOMETRICS
  // ============================================================

  /// Returns true if the device supports biometrics and has at
  /// least one biometric method enrolled.
  Future<bool> _deviceHasBiometricSetUp() async {
    if (kIsWeb) return false;

    final supported = await _localAuth
        .isDeviceSupported()
        .timeout(const Duration(seconds: 15));

    if (!supported) return false;

    final canCheck = await _localAuth
        .canCheckBiometrics
        .timeout(const Duration(seconds: 15));

    if (!canCheck) return false;

    final available = await _localAuth
        .getAvailableBiometrics()
        .timeout(const Duration(seconds: 15));

    return available.isNotEmpty;
  }

  Future<void> _checkDeviceBiometrics() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _checking = false;
      });

      _message(
        _tr(
          'Your session has expired. Please sign in again.',
          'Kipindi chako kimeisha. Tafadhali ingia tena.',
        ),
      );

      return;
    }

    try {
      final hasBiometric = await _deviceHasBiometricSetUp();

      if (!mounted) return;

      if (hasBiometric) {
        setState(() {
          _checking = false;
        });

        return;
      }

      // Do not mark biometric setup as completed just because the
      // device has no enrolled biometric. Keep this optional setup
      // page visible so the user can add biometrics in Android
      // settings or explicitly choose "Skip and continue".
      setState(() {
        _checking = false;
        _setupError = _tr(
          'No fingerprint or face is currently enrolled on this device. Add one in your device settings, or choose Skip and continue.',
          'Hakuna alama ya kidole au uso iliyosajiliwa kwenye kifaa hiki. Ongeza kwenye mipangilio ya kifaa, au uchague Ruka na uendelee.',
        );
      });
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('BIOMETRIC CHECK TIMEOUT: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _checking = false;
      });

      _message(
        _tr(
          'Checking your device took too long. Please try again.',
          'Ukaguzi wa kifaa umechukua muda mrefu. Tafadhali jaribu tena.',
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('BIOMETRIC DEVICE CHECK ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _checking = false;
      });

      _message(
        _tr(
          'We could not check biometric availability. Please try setting it up again or skip.',
          'Imeshindikana kuangalia upatikanaji wa alama za kibayometriki. Tafadhali jaribu tena au ruka hatua hii.',
        ),
      );
    }
  }

  // ============================================================
  // COMPLETE REGISTRATION OR LOGIN VERIFICATION
  // ============================================================

  /// The dashboard matching the user's role, used after a
  /// successful login-flow biometric setup.
  Widget _dashboardPage() {
    switch (_role) {
      case 'admin':
        return const AdminDashboardPage();
      case 'owner':
      default:
        return const PropertyOwnerDashboard();
    }
  }

  Future<void> _completeRegistration({
    required User user,
    required bool fingerprintEnabled,
  }) async {
    // The device id this biometric setting is bound to. It is
    // saved locally AND in Firestore, so the biometric gate in
    // LoginPage only opens on this exact device.
    final deviceId = await _getDeviceId();

    // Update the user's existing Firestore profile.
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'fingerprintEnabled': fingerprintEnabled,
        'fingerprintSetupCompleted': true,
        'registrationStage': 'completed',
        'fingerprintSetAt': fingerprintEnabled
            ? FieldValue.serverTimestamp()
            : null,
        'biometricDeviceId': fingerprintEnabled ? deviceId : null,
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 20));
    } on FirebaseException catch (e) {
      // Surface the REAL reason (rules denials used to look like
      // a connection problem).
      debugPrint('FINGERPRINT PROFILE UPDATE FIREBASE ERROR: ${e.code}');
      debugPrint('FINGERPRINT PROFILE UPDATE MESSAGE: ${e.message}');
      rethrow;
    }

    // Store the biometric preference locally on this device.
    //
    // UPDATED: in the LOGIN flow we now store the FULL credential
    // (enabled + uid + email + password + device binding), exactly
    // like LoginPage's enable flow — otherwise the biometric step
    // at login would never trigger, because LoginPage requires the
    // stored email + password to exist.
    if (fingerprintEnabled) {
      await _storage.write(key: _kBiometricEnabled, value: 'true');
      await _storage.write(key: _kBiometricUid, value: user.uid);

      final email = widget.email?.trim();
      final password = widget.password;

      if (widget.isLoginFlow &&
          email != null &&
          email.isNotEmpty &&
          password != null &&
          password.isNotEmpty) {
        await _storage.write(key: _kBiometricEmail, value: email);
        await _storage.write(key: _kBiometricPassword, value: password);
      } else {
        // No credentials available (registration flow): clear any
        // stale ones. The credential is completed on the user's
        // next password login via LoginPage's enable flow.
        await _storage.delete(key: _kBiometricEmail);
        await _storage.delete(key: _kBiometricPassword);
      }

      // Bind the biometric setting to THIS device.
      await _storage.write(key: _kBiometricDeviceId, value: deviceId);
    } else {
      await _storage.delete(key: _kBiometricEnabled);
      await _storage.delete(key: _kBiometricUid);
      await _storage.delete(key: _kBiometricEmail);
      await _storage.delete(key: _kBiometricPassword);
      await _storage.delete(key: _kBiometricDeviceId);
    }

    if (!mounted) return;

    // LOGIN FLOW: keep the session and go to the dashboard that
    // matches the user's role. Uses a direct route (not a named
    // '/home' route) so it works even without a routes table
    // entry.
    if (widget.isLoginFlow) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => _dashboardPage(),
        ),
            (route) => false,
      );

      return;
    }

    // REGISTRATION FLOW: registration finishes and the user
    // returns to login.
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
          (route) => false,
    );
  }

  // ============================================================
  // SKIP BIOMETRIC SETUP
  // ============================================================

  Future<void> _skipFingerprint() async {
    if (_loading) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _message(
        _tr(
          'Your session has expired. Please sign in again.',
          'Kipindi chako kimeisha. Tafadhali ingia tena.',
        ),
      );

      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _completeRegistration(
        user: user,
        fingerprintEnabled: false,
      );
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('FINGERPRINT SKIP FIREBASE ERROR: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _setupError = _tr(
          'Could not save your settings. Please try again.',
          'Imeshindikana kuhifadhi mipangilio yako. Tafadhali jaribu tena.',
        );
      });
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('FINGERPRINT SKIP TIMEOUT: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _setupError = _tr(
          'The request took too long. Check your internet connection and try again.',
          'Ombi limechukua muda mrefu. Hakikisha intaneti yako kisha ujaribu tena.',
        );
      });
    } catch (e, stackTrace) {
      debugPrint('FINGERPRINT SKIP ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _setupError = _tr(
          'Could not complete this step. Please try again.',
          'Imeshindikana kukamilisha hatua hii. Tafadhali jaribu tena.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // SET UP FINGERPRINT / FACE AUTHENTICATION
  // ============================================================

  /// Translates a local_auth failure into a clear, actionable
  /// message. Normalises LocalAuthException and PlatformException
  /// to a lowercase string code, so it compiles on every plugin
  /// version.
  String _messageForLocalAuthError(Object error) {
    String code = '';
    String details = error.toString().toLowerCase();

    if (error is PlatformException) {
      code = error.code.toLowerCase();
      details = '${error.code} ${error.message ?? ''} ${error.details ?? ''}'
          .toLowerCase();
    } else {
      final match = RegExp(r'code[:= ]+([a-z_]+)', caseSensitive: false)
          .firstMatch(details);
      code = match?.group(1)?.toLowerCase() ?? '';
    }

    debugPrint('LOCAL AUTH ERROR CODE: $code');
    debugPrint('LOCAL AUTH ERROR DETAILS: $details');

    if (code.contains('not_enrolled') ||
        code.contains('notenrolled') ||
        details.contains('not enrolled')) {
      return _tr(
        'No fingerprint or face is enrolled on this device. Add one in your device settings, then try again.',
        'Hakuna alama ya kidole au uso iliyosajiliwa kwenye kifaa hiki. Ongeza kwenye mipangilio ya kifaa, kisha ujaribu tena.',
      );
    }

    if (code.contains('locked') || details.contains('locked out')) {
      return _tr(
        'Too many failed attempts. Unlock your device with its PIN or pattern, then try again.',
        'Majaribio mengi yameshindwa. Fungua kifaa kwa PIN au pattern, kisha ujaribu tena.',
      );
    }

    if (code.contains('passcode') ||
        code.contains('passcode_not_set') ||
        details.contains('no passcode')) {
      return _tr(
        'Your device has no screen lock set. Set a PIN, pattern or password in device settings first.',
        'Kifaa chako hakina kilinda skrini. Weka PIN, pattern au nenosiri kwenye mipangilio ya kifaa kwanza.',
      );
    }

    if (code.contains('not_available') ||
        code.contains('notavailable') ||
        details.contains('not available')) {
      return _tr(
        'Biometric authentication is not available right now. Check your device settings, or skip this optional step.',
        'Uthibitishaji wa kibayometriki haupatikani kwa sasa. Angalia mipangilio ya kifaa, au ruka hatua hii ya hiari.',
      );
    }

    return _tr(
      'Fingerprint authentication could not be completed. Make sure a fingerprint or face is enrolled and your device has a screen lock, then try again or skip.',
      'Uthibitishaji wa alama ya kidole haukukamilika. Hakikisha alama ya kidole au uso imesajiliwa na kifaa kina kilinda skrini, kisha ujaribu tena au ruka hatua hii.',
    );
  }

  Future<void> _setupFingerprint() async {
    if (_loading) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _message(
        _tr(
          'Your session has expired. Please sign in again.',
          'Kipindi chako kimeisha. Tafadhali ingia tena.',
        ),
      );

      return;
    }

    setState(() {
      _loading = true;
      _setupError = null;
    });

    try {
      // Check again before requesting biometric authentication.
      final hasBiometric = await _deviceHasBiometricSetUp();

      if (!mounted) return;

      if (!hasBiometric) {
        setState(() {
          _setupError = _tr(
            'No fingerprint or face is enrolled on this device. Add one in your device settings, or skip this step.',
            'Hakuna alama ya kidole au uso iliyoongezwa kwenye kifaa hiki. Ongeza kwenye mipangilio ya kifaa, au ruka hatua hii.',
          );
        });

        return;
      }

      // Ask the device to authenticate the user.
      final authenticated = await _localAuth.authenticate(
        localizedReason: _tr(
          'Confirm your fingerprint or face to continue with Property Konnect.',
          'Thibitisha alama yako ya kidole au uso ili kuendelea na Property Konnect.',
        ),
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;

      if (!authenticated) {
        // The user cancelled or the scan did not match. Stay on
        // this page and let them retry — do NOT auto-complete
        // the setup as "not enabled" and navigate away.
        setState(() {
          _setupError = _tr(
            'Authentication was cancelled or not recognised. Please try again.',
            'Uthibitishaji ulikatishwa au haukutambuliwa. Tafadhali jaribu tena.',
          );
        });

        return;
      }

      // Success — save (including this device's id) and continue
      // to the correct dashboard.
      await _completeRegistration(
        user: user,
        fingerprintEnabled: true,
      );
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('FINGERPRINT SETUP TIMEOUT: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _setupError = _tr(
          'The device check took too long. Please try again or skip.',
          'Ukaguzi wa kifaa umechukua muda mrefu. Tafadhali jaribu tena au ruka hatua hii.',
        );
      });
    } on PlatformException catch (e, stackTrace) {
      // Older plugin versions / platform-channel errors.
      debugPrint('LOCAL AUTH ERROR: ${e.code} — ${e.message}');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _setupError = _messageForLocalAuthError(e);
      });
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('FINGERPRINT FIREBASE ERROR: ${e.code}');
      debugPrint('FINGERPRINT FIREBASE MESSAGE: ${e.message}');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _setupError = e.code == 'permission-denied'
            ? _tr(
          'Fingerprint confirmed, but saving was blocked by security rules. Please contact support.',
          'Alama ya kidole imethibitishwa, lakini kuhifadhi kumezuiwa na sheria za usalama. Tafadhali wasiliana na usaidizi.',
        )
            : _tr(
          'Fingerprint confirmed, but we could not save your settings. Check your connection and try again.',
          'Alama ya kidole imethibitishwa, lakini mipangilio haijahifadhiwa. Angalia muunganisho wako kisha ujaribu tena.',
        );
      });
    } catch (e, stackTrace) {
      debugPrint('FINGERPRINT SETUP ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _setupError = _messageForLocalAuthError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _green),
                const SizedBox(height: 16),
                Text(
                  _tr(
                    'Checking your device...',
                    'Inakagua kifaa chako...',
                  ),
                  style: TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: Text(
          _tr(
            'Fingerprint Setup',
            'Usanidi wa Alama ya Kidole',
          ),
        ),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: !widget.isLoginFlow,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ICON
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fingerprint,
                          size: 80,
                          color: _green,
                        ),
                      ),

                      const SizedBox(height: 22),

                      // TITLE
                      Text(
                        _tr(
                          'Set up biometric login',
                          'Weka uthibitishaji wa kibayometriki',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: _text,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // DESCRIPTION
                      Text(
                        _tr(
                          'Your device has a fingerprint or face scan available. Enable biometric authentication to make future sign-ins easier. It will only work on this device — on any other device you will use your email and password.',
                          'Kifaa chako kina uwezo wa kutumia alama ya kidole au uso. Wezesha uthibitishaji huu ili kurahisisha kuingia baadaye. Utatumika kwenye kifaa hiki pekee — kwenye kifaa kingine utatumia barua pepe na nenosiri.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _muted,
                          height: 1.5,
                        ),
                      ),

                      // INLINE ERROR
                      if (_setupError != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.40),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: _isDark
                                    ? Colors.red.shade300
                                    : Colors.red.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _setupError!,
                                  style: TextStyle(
                                    color: _isDark
                                        ? Colors.red.shade300
                                        : Colors.red.shade700,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // SETUP BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _setupFingerprint,
                          icon: _loading
                              ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(Icons.fingerprint),
                          label: Text(
                            _loading
                                ? _tr(
                              'Processing...',
                              'Inachakata...',
                            )
                                : _tr(
                              'Set up fingerprint / face',
                              'Weka alama ya kidole / uso',
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 15,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // SKIP BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _skipFingerprint,
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(
                            _tr(
                              'Skip and continue',
                              'Ruka na uendelee',
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _green,
                            side: BorderSide(color: _green),
                            padding: const EdgeInsets.symmetric(
                              vertical: 15,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // SECURITY NOTE
                      Text(
                        _tr(
                          'Biometric login is optional and works only on this device. You can always sign in with your email and password.',
                          'Kuingia kwa kutumia alama za kibayometriki ni hiari na inafanya kazi kwenye kifaa hiki pekee. Unaweza kuingia kwa barua pepe na nenosiri wakati wowote.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}