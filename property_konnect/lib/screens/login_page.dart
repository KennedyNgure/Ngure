// ============================================================
// login_page.dart  (FULL UPDATED FILE)
//
// CHANGE IN THIS VERSION
//  1. REMOVED the "Login with fingerprint / face" button.
//  2. NEW LOGIN FLOW:
//       user enters email + password  ->  taps Login
//       -> Firebase Auth signs in
//       -> (device supports biometrics AND biometrics are set up
//          for THIS account on THIS device)
//             -> the biometric prompt appears as part of the
//                login; only a successful scan completes the
//                login (a failed scan signs the user out).
//       -> routing as before (admin / owner stages / dashboard).
//     If the device has no biometrics, or biometrics were never
//     enabled for this account on this device, the login goes
//     straight through with email + password.
//
// Everything else is kept: Remember-Me (email only), device
// binding, enabling biometrics after a successful login, legacy
// password cleanup, stage routing, error handling.
// ============================================================
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'admin_dashboard.dart';
import 'app_localizations.dart';
import 'app_settings.dart';
import 'email_verification_page.dart';
import 'fingerprint_setup_page.dart';
import 'forgot_password_page.dart';
import 'homepage.dart';
import 'id_upload_page.dart';
import 'property_owner_dashboard.dart';
import 'registration_page.dart';

/// LOGIN FLOW — REMEMBER ME (EMAIL ONLY) + DEVICE-SPECIFIC
/// BIOMETRICS
///
///  1. Sign in with Firebase Auth (email + password).
///     - Wrong email/password  -> "Incorrect email or password".
///  2. Check the account exists in Firestore (`users/{uid}`).
///     - No Firestore profile  -> sign out + "Incorrect email or
///       password".
///  3. Check deactivation (`isActive == false`).
///     - Deactivated           -> sign out + "Please contact support".
///  4. BIOMETRIC STEP (part of the Login button now — there is no
///     separate fingerprint button anymore):
///     If the device supports biometrics AND a valid biometric
///     credential is set up for this account on this device, the
///     system biometric prompt appears; the login only completes
///     after a successful scan.
///  5. ROUTE BY ROLE:
///       - ADMIN  -> AdminDashboardPage (no registration-stage checks).
///       - OWNER  -> registrationStage routing:
///                     email_verification -> EmailVerificationPage
///                     id_upload          -> IdUploadPage
///                     fingerprint_setup  -> FingerprintSetupPage
///                     completed          -> PropertyOwnerDashboard
///
/// REMEMBER ME (EMAIL ONLY — the password is NEVER stored by the
/// checkbox):
///   - Saves ONLY the email. Legacy remembered-password keys from
///     older versions are deleted on startup.
///
/// DEVICE-SPECIFIC BIOMETRICS:
///   - Enabled per device, only after a full password login, with
///     an explicit user opt-in + a biometric verification.
///   - Bound to this installation's device id (secure storage +
///     Firestore biometricDeviceId cross-check).
///   - On any other device there is no stored credential, so the
///     login is always email + password.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // Remember Me — EMAIL ONLY (no password is ever stored by the
  // checkbox; automatic password login does not exist).
  static const String _kRememberEmail =
      'property_konnect_remember_email';

  // Legacy keys from the old "remember password" version. They
  // are deleted on startup so no old password lingers.
  static const String _kLegacyRememberEnabled =
      'property_konnect_remember_enabled';
  static const String _kLegacyRememberPassword =
      'property_konnect_remember_password';

  // Per-device biometric unlock credential. The password here is
  // gated behind the biometric prompt and is device-bound.
  static const String _kBiometricEnabled =
      'property_konnect_biometric_enabled';
  static const String _kBiometricUid =
      'property_konnect_biometric_uid';
  static const String _kBiometricEmail =
      'property_konnect_biometric_email';
  static const String _kBiometricPassword =
      'property_konnect_biometric_password';

  // Device binding.
  static const String _kDeviceId =
      'property_konnect_device_id';
  static const String _kBiometricDeviceId =
      'property_konnect_biometric_device_id';

  final LocalAuthentication _localAuth = LocalAuthentication();

  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  /// True when THIS device holds a valid, device-bound biometric
  /// credential for some account (used internally to keep the
  /// enable-flow state in sync — no separate login button anymore).
  bool _fingerprintReady = false;

  /// The email the stored biometric credential belongs to (for
  /// display only — never the password).
  String _fingerprintEmail = '';

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ==========================================================
  // THEME + TRANSLATION
  // ==========================================================

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _greenDeep =>
      _isDark ? kBrandGreenOnDark : const Color(0xFF146C43);

  Color get _pageBackground =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _cardColor =>
      _isDark ? const Color(0xFF1A241D) : Colors.white;

  Color get _cardBorder =>
      _isDark ? Colors.grey.shade700 : Colors.grey.shade200;

  Color get _bodyText =>
      _isDark ? Colors.grey.shade300 : Colors.grey.shade700;

  Color get _mutedText =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  Color get _errColor =>
      _isDark ? Colors.red.shade300 : Colors.red.shade700;

  String _tr(String en, String sw) {
    final code = AppSettings.of(context).languageCode;
    if (code == 'sw') return sw;
    return AppLocalizations.trText(en, code);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _restoreRememberedEmail();
    _checkDeviceBiometricCredential();
  }

  /// Restores the remembered EMAIL ONLY. Also wipes any password
  /// left over from the old Remember-Me implementation (the
  /// password is never stored for automatic login).
  Future<void> _restoreRememberedEmail() async {
    String? email;

    try {
      // Clean up legacy stored passwords from the old version.
      await _storage.delete(key: _kLegacyRememberEnabled);
      await _storage.delete(key: _kLegacyRememberPassword);

      email = await _storage.read(key: _kRememberEmail);
    } catch (e) {
      debugPrint('RESTORE EMAIL ERROR: $e');
    }

    if (!mounted) return;

    if (email != null && email.isNotEmpty) {
      // Hoist into a final local so the setState closure below
      // keeps the non-null promotion (a variable that is
      // assigned after its declaration loses promotion inside
      // closures).
      final savedEmail = email;
      setState(() {
        _rememberMe = true;
        emailController.text = savedEmail;
      });
    }
  }

  /// Checks whether THIS device holds a valid, DEVICE-BOUND
  /// biometric unlock credential (stored after the user
  /// explicitly enabled it here, after a full password login)
  /// and the device can show a biometric prompt. Used to keep
  /// the internal state in sync — the login itself checks this
  /// again as part of the Login button flow.
  Future<void> _checkDeviceBiometricCredential() async {
    try {
      final enabled = await _storage.read(key: _kBiometricEnabled);
      final email = await _storage.read(key: _kBiometricEmail);
      final password =
      await _storage.read(key: _kBiometricPassword);
      final storedDeviceId =
      await _storage.read(key: _kBiometricDeviceId);
      final deviceId = await _getDeviceId();

      if (enabled != 'true' ||
          email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        return;
      }

      // DEVICE BINDING: the stored credential must belong to THIS
      // device. If the device id does not match (e.g. storage was
      // restored/copied to another device), the credential is
      // useless — clear it.
      if (storedDeviceId == null || storedDeviceId != deviceId) {
        await _clearBiometricCredential();
        return;
      }

      final deviceOk = await _deviceSupportsBiometrics();

      if (!mounted) return;

      if (deviceOk) {
        setState(() {
          _fingerprintReady = true;
          _fingerprintEmail = email;
        });
      }
    } catch (e) {
      debugPrint('BIOMETRIC CREDENTIAL CHECK ERROR: $e');
    }
  }

  // ==========================================================
  // DEVICE ID
  // ==========================================================

  /// A stable random id for THIS installation. Generated once,
  /// then kept in secure storage. Used to bind the biometric
  /// credential to this physical device, so biometrics enabled on
  /// one device will NOT work on any other device.
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
      // A fresh fallback value still identifies this install.
      return DateTime.now().microsecondsSinceEpoch.toString();
    }
  }

  // ==========================================================
  // CREDENTIAL STORAGE HELPERS
  // ==========================================================

  /// Remember Me — EMAIL ONLY. The password is never stored for
  /// automatic login.
  Future<void> _saveRememberedEmail() async {
    try {
      if (_rememberMe) {
        await _storage.write(
          key: _kRememberEmail,
          value: emailController.text.trim().toLowerCase(),
        );
      } else {
        await _storage.delete(key: _kRememberEmail);
      }
    } catch (e) {
      debugPrint('SAVE EMAIL ERROR: $e');
    }
  }

  Future<void> _clearBiometricCredential() async {
    try {
      await _storage.delete(key: _kBiometricEnabled);
      await _storage.delete(key: _kBiometricUid);
      await _storage.delete(key: _kBiometricEmail);
      await _storage.delete(key: _kBiometricPassword);
      await _storage.delete(key: _kBiometricDeviceId);
    } catch (e) {
      debugPrint('CLEAR BIOMETRIC CREDENTIAL ERROR: $e');
    }
  }

  // ==========================================================
  // BIOMETRIC HELPERS
  // ==========================================================

  /// True when this device can show a biometric prompt (hardware
  /// present AND at least one fingerprint / face enrolled).
  /// Web is never supported.
  Future<bool> _deviceSupportsBiometrics() async {
    if (kIsWeb) return false;

    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;

      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (e) {
      debugPrint('BIOMETRIC SUPPORT CHECK ERROR: $e');
      return false;
    }
  }

  /// Shows the system biometric prompt. Returns true only when
  /// the user successfully verified.
  Future<bool> _verifyBiometrics() async {
    // `_tr` reads `context`; this method is always called after an
    // await, so guard against use across async gaps.
    if (!mounted) return false;

    try {
      final reason = _tr(
        'Verify your identity to log in to Property Konnect',
        'Thibitisha utambulisho wako ili uingie Property Konnect',
      );

      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('BIOMETRIC VERIFY ERROR: $e');
      return false;
    }
  }

  /// True when the biometric credential stored on THIS device is
  /// valid, belongs to the given account, AND is bound to this
  /// device (local device id + Firestore biometricDeviceId must
  /// all match). Any mismatch clears the credential — biometrics
  /// enabled on one device never work on another.
  Future<bool> _localCredentialValidFor({
    required String email,
    required String firestoreDeviceId,
  }) async {
    try {
      final enabled =
          await _storage.read(key: _kBiometricEnabled) == 'true';
      final storedEmail = await _storage.read(key: _kBiometricEmail);
      final storedDeviceId =
      await _storage.read(key: _kBiometricDeviceId);
      final deviceId = await _getDeviceId();

      final valid = enabled &&
          storedEmail != null &&
          storedEmail.trim().toLowerCase() ==
              email.trim().toLowerCase() &&
          storedDeviceId != null &&
          storedDeviceId == deviceId &&
          (firestoreDeviceId.isEmpty || firestoreDeviceId == deviceId);

      if (!valid && (enabled || storedEmail != null)) {
        // Not bound to this device / account — useless here.
        await _clearBiometricCredential();

        if (mounted) {
          setState(() {
            _fingerprintReady = false;
            _fingerprintEmail = '';
          });
        }
      }

      return valid;
    } catch (e) {
      debugPrint('LOCAL CREDENTIAL CHECK ERROR: $e');
      return false;
    }
  }

  // ==========================================================
  // ENABLE BIOMETRICS ON THIS DEVICE (after a real login)
  // ==========================================================

  /// After a successful EMAIL + PASSWORD sign-in (first login on
  /// any new device), offer to enable fingerprint / face unlock
  /// ON THIS DEVICE. The user must verify their biometric before
  /// anything is stored, and the credential is bound to this
  /// device's id — locally and in Firestore.
  ///
  /// Only offered for fully-registered accounts (admins and
  /// owners whose stage is 'completed'); accounts still going
  /// through registration use the FingerprintSetupPage flow.
  Future<void> _offerEnableBiometrics({
    required String uid,
    required String email,
    required String password,
    required String role,
    required String stage,
  }) async {
    // Not for accounts still in registration.
    if (role != 'admin' && stage != 'completed') return;

    final deviceOk = await _deviceSupportsBiometrics();

    if (!mounted || !deviceOk) return;

    // Already enabled on this device for this account?
    String? storedEmail;
    String? storedDeviceId;
    String deviceId;

    try {
      storedEmail = await _storage.read(key: _kBiometricEmail);
      storedDeviceId = await _storage.read(key: _kBiometricDeviceId);
      deviceId = await _getDeviceId();
    } catch (e) {
      debugPrint('BIOMETRIC CREDENTIAL READ ERROR: $e');
      deviceId = await _getDeviceId();
    }

    if (storedEmail == email && storedDeviceId == deviceId) return;

    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          icon: Icon(Icons.fingerprint, color: _green, size: 44),
          title: Text(
            _tr(
              'Enable fingerprint / face login on this device?',
              'Wezesha kuingia kwa alama ya kidole / uso kwenye kifaa hiki?',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _greenDeep,
            ),
          ),
          content: Text(
            _tr(
              'Next time you sign in on this device with your email and password, you will also verify with your fingerprint or face before the login completes. Your login details stay stored securely on this device only — you will still need your email and password on any other device.',
              'Mara ijayo ukiingia kwenye kifaa hiki kwa barua pepe na nenosiri, utathibitisha pia kwa alama yako ya kidole au uso kabla ya kuingia kukamilika. Maelezo yako ya kuingia yanahifadhiwa kwenye kifaa hiki pekee — kwenye kifaa kingine utahitaji barua pepe na nenosiri.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _bodyText, height: 1.4),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                _tr('Not now', 'Sasa si'),
                style: TextStyle(color: _mutedText),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.fingerprint, size: 20),
              label: Text(_tr('Enable', 'Wezesha')),
            ),
          ],
        );
      },
    );

    if (!mounted || answer != true) return;

    // The user must verify the biometric BEFORE we store
    // anything on this device.
    final verified = await _verifyBiometrics();

    if (!mounted) return;

    if (!verified) {
      _showSnack(
        _tr(
          'Biometric verification failed. You can enable it after your next login.',
          'Uthibitisho wa alama za mwili umeshindwa. Unaweza kuwezesha baada ya kuingia ijayo.',
        ),
      );
      return;
    }

    try {
      await _clearBiometricCredential();

      await _storage.write(key: _kBiometricEnabled, value: 'true');
      await _storage.write(key: _kBiometricUid, value: uid);
      await _storage.write(key: _kBiometricEmail, value: email);
      await _storage.write(key: _kBiometricPassword, value: password);
      // Bind the credential to THIS device.
      await _storage.write(key: _kBiometricDeviceId, value: deviceId);
    } catch (e) {
      debugPrint('SAVE BIOMETRIC CREDENTIAL ERROR: $e');
    }

    if (!mounted) return;

    setState(() {
      _fingerprintReady = true;
      _fingerprintEmail = email;
    });

    // Save the device id in the Firestore profile too. The
    // biometric step cross-checks it, so the credential can
    // never be used from a different device.
    try {
      await _db.collection('users').doc(uid).update({
        'fingerprintEnabled': true,
        'fingerprintSetupCompleted': true,
        'biometricDeviceId': deviceId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('BIOMETRIC PROFILE FLAG UPDATE FAILED: $e');
    }

    if (!mounted) return;

    _showSnack(
      _tr(
        'Fingerprint / face verification is now enabled on this device.',
        'Uthibitisho wa alama ya kidole / uso umewezeshwa kwenye kifaa hiki.',
      ),
    );
  }

  // ==========================================================
  // LOGIN
  // ==========================================================

  Future<void> _login() async {
    if (_isLoading) return;

    if (!_formKey.currentState!.validate()) return;

    await _performSignIn(
      emailController.text.trim().toLowerCase(),
      passwordController.text,
    );
  }

  /// The full login flow, triggered by the Login button.
  /// Email + password first; the biometric prompt happens DURING
  /// this flow when (a) the device supports biometrics and
  /// (b) biometrics are set up for this account on this device.
  Future<void> _performSignIn(
      String email,
      String password, {
        bool biometricVerified = false,
      }) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // ------------------------------------------------------
      // 1. FIREBASE AUTH
      // ------------------------------------------------------
      UserCredential cred;

      try {
        cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        _handleAuthError(e);
        return;
      }

      final user = cred.user;

      if (user == null) {
        if (!mounted) return;
        _showSnack(_tr('Incorrect email or password.',
            'Barua pepe au nenosiri si sahihi.'));
        return;
      }

      // ------------------------------------------------------
      // If a DIFFERENT account just signed in, the biometric
      // credential stored on this device belongs to someone
      // else — clear it. The new account can enable it after
      // this login.
      // ------------------------------------------------------
      try {
        final storedEmail = await _storage.read(
          key: _kBiometricEmail,
        );

        if (storedEmail != null &&
            storedEmail.isNotEmpty &&
            storedEmail != email) {
          await _clearBiometricCredential();

          if (mounted) {
            setState(() {
              _fingerprintReady = false;
              _fingerprintEmail = '';
            });
          }
        }
      } catch (e) {
        debugPrint('STALE BIOMETRIC CREDENTIAL CHECK ERROR: $e');
      }

      // ------------------------------------------------------
      // 2. FIRESTORE CHECK
      // ------------------------------------------------------
      final doc = await _db.collection('users').doc(user.uid).get();

      if (!mounted) return;

      if (!doc.exists || doc.data() == null) {
        await _auth.signOut();

        if (!mounted) return;

        _showSnack(
          _tr('Incorrect email or password.',
              'Barua pepe au nenosiri si sahihi.'),
        );
        return;
      }

      final data = doc.data()!;

      // ------------------------------------------------------
      // 3. DEACTIVATION CHECK
      // ------------------------------------------------------
      final isActive = data['isActive'] != false;

      if (!isActive) {
        await _auth.signOut();

        if (!mounted) return;

        _showAlertDeactivated();
        return;
      }

      final role = (data['role'] ?? 'owner').toString().toLowerCase();
      final stage =
      (data['registrationStage'] ?? 'completed').toString();
      final firestoreDeviceId =
      (data['biometricDeviceId'] ?? '').toString();

      // ------------------------------------------------------
      // 4. BIOMETRIC STEP (part of the login — no separate
      //    fingerprint button anymore)
      //
      //    The prompt appears when:
      //      - the device supports biometrics, AND
      //      - biometrics were enabled for THIS account on
      //        THIS device (valid local credential bound to
      //        this device id + Firestore biometricDeviceId).
      //    A failed scan signs the user out.
      // ------------------------------------------------------
      if (!biometricVerified && stage != 'fingerprint_setup') {
        final localValid = await _localCredentialValidFor(
          email: email,
          firestoreDeviceId: firestoreDeviceId,
        );

        if (!mounted) return;

        if (localValid) {
          final deviceCanVerify = await _deviceSupportsBiometrics();

          if (!mounted) return;

          if (deviceCanVerify) {
            final verified = await _verifyBiometrics();

            if (!mounted) return;

            if (!verified) {
              await _auth.signOut();

              if (!mounted) return;

              _showSnack(
                _tr(
                  'Biometric verification failed. Please try again.',
                  'Uthibitisho wa alama za mwili umeshindwa. Tafadhali jaribu tena.',
                ),
              );
              return;
            }
          }
        }
      }

      // ------------------------------------------------------
      // 5. REMEMBER ME — persist or clear the EMAIL now that
      //    sign-in actually succeeded (never the password).
      // ------------------------------------------------------
      await _saveRememberedEmail();

      // Mirror the email into `registered_emails` so the
      // Forgot Password page can verify it (self-healing for
      // accounts registered before this collection existed).
      try {
        await _db
            .collection('registered_emails')
            .doc(email)
            .set({'uid': user.uid}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('REGISTERED EMAILS SYNC FAILED: $e');
      }

      if (!mounted) return;

      // ------------------------------------------------------
      // 6. ENABLE BIOMETRICS ON THIS DEVICE — only after a
      //    real, successful login (first login on a new device),
      //    and only if the user accepts and verifies their
      //    biometric.
      // ------------------------------------------------------
      await _offerEnableBiometrics(
        uid: user.uid,
        email: email,
        password: password,
        role: role,
        stage: stage,
      );

      if (!mounted) return;

      // ------------------------------------------------------
      // 7. ROUTE BY ROLE
      // ------------------------------------------------------
      if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
        );
        return;
      }

      // ------------------------------------------------------
      // 8. OWNER — REGISTRATION STAGE ROUTING
      // ------------------------------------------------------
      if (!user.emailVerified || stage == 'email_verification') {
        _gotoEmailVerification();
        return;
      }

      if (!mounted) return;

      switch (stage) {
        case 'id_upload':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const IdUploadPage()),
          );
          return;

        case 'fingerprint_setup':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
              const FingerprintSetupPage(isLoginFlow: true),
            ),
          );
          return;
      }

      // ------------------------------------------------------
      // 9. OWNER FULLY VERIFIED — owner dashboard.
      // ------------------------------------------------------
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PropertyOwnerDashboard()),
      );
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      debugPrint('LOGIN ERROR: $e');
      if (!mounted) return;
      _showSnack(
        _tr('Could not sign in. Check your connection and try again.',
            'Imeshindikana kuingia. Angalia intaneti yako kisha ujaribu tena.'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleAuthError(FirebaseAuthException e) {
    debugPrint('LOGIN AUTH ERROR: ${e.code}');

    if (!mounted) return;

    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-email':
        _showSnack(
          _tr('Incorrect email or password.',
              'Barua pepe au nenosiri si sahihi.'),
        );
        break;

      case 'user-disabled':
        _showAlertDeactivated();
        break;

      case 'too-many-requests':
        _showSnack(
          _tr('Too many attempts. Please try again later.',
              'Majaribio mengi sana. Tafadhali jaribu tena baadaye.'),
        );
        break;

      case 'network-request-failed':
        _showSnack(
          _tr('Network error. Check your internet connection.',
              'Kosa la mtandao. Angalia muunganisho wako wa intaneti.'),
        );
        break;

      default:
        _showSnack(
          e.message ??
              _tr('Incorrect email or password.',
                  'Barua pepe au nenosiri si sahihi.'),
        );
    }
  }

  // ==========================================================
  // DEACTIVATED ACCOUNT ALERT
  // ==========================================================

  void _showAlertDeactivated() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          icon: Icon(Icons.block, color: _errColor, size: 40),
          title: Text(
            _tr('Account deactivated', 'Akaunti imezimwa'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _greenDeep,
            ),
          ),
          content: Text(
            _tr(
              'Your account has been deactivated. Please contact support for assistance.',
              'Akaunti yako imezimwa. Tafadhali wasiliana na usaidizi kwa msaada.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _bodyText),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('OK', 'Sawa')),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // NAVIGATION HELPERS
  // ==========================================================

  void _gotoHomePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  void _gotoEmailVerification() {
    final email = emailController.text.trim();
    final name = email.isEmpty ? '' : email.split('@').first;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EmailVerificationPage(
          name: name,
          email: email,
        ),
      ),
    );
  }

  void _openForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
  }

  void _openSignUp() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegistrationPage()),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: Text(_tr('Login', 'Ingia')),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: _tr('Back to home', 'Rudi mwanzo'),
          icon: const Icon(Icons.arrow_back),
          onPressed: _gotoHomePage,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 78,
                      color: _green,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _tr('Welcome back', 'Karibu tena'),
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: _greenDeep,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _tr(
                        'Sign in to your account to continue.',
                        'Ingia kwenye akaunti yako kuendelea.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _bodyText),
                    ),
                    const SizedBox(height: 26),

                    // ---------------- EMAIL ----------------
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      enabled: !_isLoading,
                      style: TextStyle(color: _bodyText),
                      decoration: InputDecoration(
                        labelText: _tr('Email', 'Barua pepe'),
                        prefixIcon: Icon(Icons.email, color: _green),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _green, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return _tr('Enter your email',
                              'Weka barua pepe yako');
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return _tr('Enter a valid email',
                              'Weka barua pepe halali');
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // ---------------- PASSWORD ----------------
                    TextFormField(
                      controller: passwordController,
                      obscureText: _obscurePassword,
                      enabled: !_isLoading,
                      style: TextStyle(color: _bodyText),
                      decoration: InputDecoration(
                        labelText: _tr('Password', 'Nenosiri'),
                        prefixIcon: Icon(Icons.lock, color: _green),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _green, width: 2),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: _mutedText,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return _tr('Enter your password',
                              'Weka nenosiri lako');
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 10),

                    // ---------------- REMEMBER ME ----------------
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _rememberMe,
                            activeColor: _green,
                            onChanged: _isLoading
                                ? null
                                : (value) {
                              setState(() {
                                _rememberMe = value ?? false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _tr(
                              'Remember my email on this device',
                              'Nikumbalie barua pepe kwenye kifaa hiki',
                            ),
                            style: TextStyle(
                              color: _bodyText,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // ---------------- FORGOT PASSWORD ----------------
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed:
                        _isLoading ? null : _openForgotPassword,
                        child: Text(
                          _tr('Forgot Password?', 'Umesahau Nenosiri?'),
                          style: TextStyle(color: _green),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ---------------- LOGIN BUTTON ----------------
                    // Email + password first. If this device
                    // supports biometrics AND biometrics are set
                    // up for this account on this device, the
                    // biometric prompt appears as part of THIS
                    // button's flow.
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onPressed: _isLoading ? null : _login,
                        icon: _isLoading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(Icons.login),
                        label: Text(
                          _isLoading
                              ? _tr('Signing in...', 'Inaingia...')
                              : _tr('Login', 'Ingia'),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ---------------- SIGN UP PROMPT ----------------
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _tr(
                                "Don't have an account? ",
                                'Hauna akaunti? ',
                              ),
                              style: TextStyle(
                                color: _mutedText,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Flexible(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _openSignUp,
                              child: Text(
                                _tr('Sign up', 'Jiunge'),
                                style: TextStyle(
                                  color: _green,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}