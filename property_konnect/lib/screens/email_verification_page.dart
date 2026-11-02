import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';

import 'admin_dashboard.dart';
import 'app_settings.dart';
import 'id_upload_page.dart';
import 'login_page.dart';

/// Email verification uses Firebase Authentication's default action handler.
/// This avoids redirecting to a custom Hosting route that may show the app
/// homepage without giving a clear verification result.

/// EMAIL VERIFICATION FLOW (hardened version)
///
///  1. On entry: if the email is already verified in Firebase Auth, the
///     Firestore profile is healed automatically and the user is routed
///     to the correct next page automatically.
///  2. Otherwise the page WAITS — no email is sent automatically. The
///     user taps "Verify Email" to send the link.
///  3. AUTO-CHECK (the main mechanism):
///       - polls Firebase Auth every 3 seconds and reloads the user;
///       - re-checks when the app resumes from the browser/email app;
///       - also listens to FirebaseAuth idTokenChanges().
///     Keep this app signed in while opening the verification link, then
///     return to the app. If the link is opened on another device, sign in
///     again on this device after verifying.
///  4. DEEP LINKS:
///       - handles the COLD-START link (app opened by the email link)
///         via AppLinks().getInitialLink(), which many flows miss;
///       - handles live links via the uriLinkStream GETTER (app_links
///         exposes it as a Stream getter, not a method);
///       - accepts ANY incoming link that carries an oobCode.
///  5. ROUTING AFTER VERIFICATION (role-based):
///       - role == 'admin'  -> AdminDashboardPage (registrationStage
///         set to 'completed' — admins skip the ID upload step);
///       - everyone else   -> IdUploadPage as before.
class EmailVerificationPage extends StatefulWidget {
  final String name;
  final String email;

  const EmailVerificationPage({
    super.key,
    required this.name,
    required this.email,
  });

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage>
    with WidgetsBindingObserver {
  static const int _resendCooldownSeconds = 60;
  static const Duration _pollInterval = Duration(seconds: 3);

  bool _sending = false;
  bool _checking = false; // spinner while a deep link is being applied
  bool _navigated = false;
  bool _busy = false; // a poll is currently running
  bool _finalizing = false; // profile sync is currently running
  bool _verified = false; // verification detected — busy navigating
  bool _initialized = false; // initial check has completed

  int _cooldown = 0;

  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<User?>? _authSub;
  Timer? _pollTimer;
  Timer? _cooldownTimer;

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _background =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _text => _isDark ? Colors.grey.shade200 : Colors.grey.shade800;

  Color get _muted => _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) {
    return AppSettings.of(context).languageCode == 'sw' ? sw : en;
  }

  void _showSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVerification();
    });

    _listenForLinks();
    _listenToAuthChanges();

    // Polls Firebase Auth. This is the main mechanism everywhere:
    // the owner clicks the email link (usually in the browser),
    // Firebase verifies the email there, and this page notices on
    // the next poll.
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkVerified());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user switches back from the email app / browser,
    // re-check immediately instead of waiting for the next poll.
    if (state == AppLifecycleState.resumed) {
      _checkVerified();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    _linkSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // ============================================================
  // INIT — if already verified in Auth, heal Firestore and route
  // automatically. Otherwise just WAIT (the user taps
  // "Verify Email" to send the link).
  // ============================================================

  Future<void> _initializeVerification() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      await _backToLogin();
      return;
    }

    if (mounted) {
      setState(() => _initialized = true);
    }

    if (await _refreshVerified()) {
      // The email was already verified (e.g. the link was clicked
      // in a browser earlier) but the Firestore profile is stale.
      // Heal it and continue automatically — no manual step.
      await _verifiedDetected();
      return;
    }

    // On native apps the email link may have OPENED the app
    // (cold start). Handle that link now.
    if (!kIsWeb) {
      await _handleInitialLink();
    }

    // NOTE: no automatic send here. The user taps the
    // "Verify Email" button when ready.
  }

  // ============================================================
  // AUTH CHANGE LISTENER — extra safety net so verification is
  // noticed as soon as Firebase refreshes the user state.
  //
  // FIX: idTokenChanges is a METHOD in firebase_auth, so it must
  // be CALLED: idTokenChanges().listen(...).
  // ============================================================

  void _listenToAuthChanges() {
    _authSub = FirebaseAuth.instance.idTokenChanges().listen((user) {
      if (user != null && user.emailVerified && !_verified) {
        _verifiedDetected();
      }
    });
  }

  // ============================================================
  // VERIFIED — sync Firestore and navigate automatically to the
  // page that matches the user's role.
  // ============================================================

  Future<void> _verifiedDetected() async {
    if (!mounted || _navigated || _verified) return;

    _verified = true;

    _pollTimer?.cancel();
    _cooldownTimer?.cancel();

    // Sync the Firestore profile so the login flow never routes
    // back to this page again. Returns the user's role so we can
    // route correctly.
    final isAdmin = await _syncVerifiedProfile();

    _goToNextStage(isAdmin: isAdmin);
  }

  /// The user's role from Firestore (or an empty string).
  Future<String> _userRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return '';

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      return (doc.data()?['role'] ?? '').toString().trim().toLowerCase();
    } catch (e) {
      debugPrint('ROLE READ ERROR: $e');
      return '';
    }
  }

  /// Mirrors the Auth emailVerified state into Firestore and
  /// advances the registration stage. Safe to call repeatedly.
  ///
  /// Returns true when the user is an ADMIN (so the caller can
  /// route them to the admin dashboard instead of ID upload).
  Future<bool> _syncVerifiedProfile() async {
    if (_finalizing) return _lastKnownAdmin;
    _finalizing = true;

    bool isAdmin = _lastKnownAdmin;

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        await _backToLogin();
        return false;
      }

      // Refresh the ID token FIRST so Firestore rules that check
      // request.auth.token.email_verified see the new value.
      try {
        await user.getIdToken(true);
      } catch (e) {
        debugPrint('TOKEN REFRESH ERROR: $e');
      }

      // Read the role BEFORE writing, so we can advance the
      // registration stage to the right value:
      //   admin            -> 'completed' (admins skip ID upload)
      //   everyone else    -> 'id_upload'
      final role = await _userRole();
      isAdmin = role == 'admin';
      _lastKnownAdmin = isAdmin;

      final nextStage = isAdmin ? 'completed' : 'id_upload';

      // Sync the Firestore profile and advance the registration
      // stage. The security rules allow this exact forward-only
      // transition.
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(
          {
            'emailVerified': true,
            'registrationStage': nextStage,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        // Do not block the user, but surface the problem in the
        // console. If this fails, check your Firestore rules.
        debugPrint('FIRESTORE VERIFY SYNC FAILED: $e');
      }
    } finally {
      _finalizing = false;
    }

    return isAdmin;
  }

  /// Cache of the role read during sync, so a repeat call while
  /// _finalizing still routes correctly.
  bool _lastKnownAdmin = false;

  // ============================================================
  // SEND VERIFICATION LINK (Firebase built-in)
  // ============================================================

  void _startCooldown() {
    _cooldownTimer?.cancel();

    setState(() {
      _cooldown = _resendCooldownSeconds;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_cooldown <= 1) {
        timer.cancel();
        setState(() {
          _cooldown = 0;
        });
      } else {
        setState(() {
          _cooldown--;
        });
      }
    });
  }

  Future<void> _sendVerificationEmail({bool silent = false}) async {
    if (_sending || _verified) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      await _backToLogin();
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      // Reload first so a previously-used code is not blocking.
      try {
        await user.reload();
      } catch (_) {}

      // Use Firebase's standard verification action URL. The link itself
      // verifies the email in Firebase Authentication. When the user returns
      // to this app, _refreshVerified() reloads the signed-in user and sends
      // them to ID Upload (owners) or the Admin dashboard (admins).
      //
      // Do not add placeholder Android/iOS package IDs or a custom continue
      // URL here: those can redirect to the Flutter homepage and make it look
      // as though verification did not happen.
      await user.sendEmailVerification();

      _startCooldown();

      if (!silent && mounted) {
        _showSnackbar(
          _tr(
            'A verification link has been sent to your email.',
            'Kiungo cha uthibitishaji kimetumwa kwa barua pepe yako.',
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('SEND VERIFICATION ERROR: ${e.code} ${e.message}');

      if (!mounted) return;

      if (e.code == 'too-many-requests') {
        _showSnackbar(
          _tr(
            'Too many requests. Please wait a few minutes and try again.',
            'Maombi mengi sana. Tafadhali subiri dakika chache kisha ujaribu tena.',
          ),
        );
      } else {
        _showSnackbar(
          e.message ??
              _tr(
                'Could not send the email. Try again.',
                'Barua pepe haikutumwa. Jaribu tena.',
              ),
        );
      }
    } catch (e) {
      debugPrint('SEND VERIFICATION UNEXPECTED ERROR: $e');

      if (!mounted) return;

      _showSnackbar(
        _tr(
          'Could not send the email. Check your connection and try again.',
          'Barua pepe haikutumwa. Angalia intaneti yako na ujaribu tena.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  // ============================================================
  // AUTO-CHECK — poll Firebase Auth until the email is verified
  // ============================================================

  /// Reloads the Auth user AND forces an ID token refresh, then
  /// returns whether the email is verified.
  Future<bool> _refreshVerified() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return false;

    try {
      await user.reload();
    } catch (e) {
      debugPrint('RELOAD ERROR: $e');
    }

    // Re-read the (possibly refreshed) user from the auth instance.
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh == null) return false;

    if (fresh.emailVerified) return true;

    // Fallback: force a token refresh and check again.
    try {
      await fresh.getIdToken(true);
      debugPrint('ID TOKEN REFRESHED OK');
    } catch (e) {
      debugPrint('TOKEN REFRESH ERROR: $e');
    }

    return FirebaseAuth.instance.currentUser?.emailVerified ?? false;
  }

  /// Called by the poll timer, on resume, and on auth changes.
  /// When the email becomes verified, sync Firestore and navigate
  /// automatically — there is no manual Continue step.
  Future<void> _checkVerified() async {
    if (!mounted || _navigated || _busy || _verified) return;

    _busy = true;

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await _backToLogin();
        return;
      }

      if (await _refreshVerified()) {
        await _verifiedDetected();
      }
    } finally {
      _busy = false;
    }
  }

  // ============================================================
  // HANDLE INCOMING LINKS (mobile only)
  //
  // 1. COLD START — the app was opened BY the email link. The
  //    stream does NOT fire for this link, so we must call
  //    getInitialLink().
  // 2. WARM — the app is already running; the stream fires.
  //
  // FIX: in app_links, uriLinkStream is a GETTER that returns a
  // Stream<Uri>. Do NOT call it with (): use
  // appLinks.uriLinkStream.listen(...). Calling it caused:
  //   "The expression doesn't evaluate to a function, so it
  //    can't be invoked."
  // ============================================================

  bool _isVerificationLink(Uri uri) {
    return uri.queryParameters.containsKey('oobCode');
  }

  Future<void> _handleInitialLink() async {
    try {
      final initial = await AppLinks().getInitialLink();

      if (initial != null && _isVerificationLink(initial)) {
        await _handleDeepLink(initial);
      }
    } catch (e) {
      debugPrint('INITIAL LINK ERROR: $e');
    }
  }

  void _listenForLinks() {
    // App links are not available on web; the polling above handles it.
    if (kIsWeb) return;

    try {
      final appLinks = AppLinks();

      _linkSub = appLinks.uriLinkStream.listen(
            (uri) {
          if (_navigated || _verified) return;

          if (_isVerificationLink(uri)) {
            _handleDeepLink(uri);
          }
        },
        onError: (e) {
          // Non-fatal: polling will still detect verification.
          debugPrint('APP LINKS STREAM ERROR: $e');
        },
      );
    } catch (e) {
      debugPrint('APP LINKS ERROR: $e');
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    final code = uri.queryParameters['oobCode'];
    if (code == null || _navigated || _verified) return;

    if (_checking) return; // another link is already being applied

    setState(() {
      _checking = true;
    });

    try {
      await FirebaseAuth.instance.applyActionCode(code);

      if (await _refreshVerified()) {
        await _verifiedDetected();
        return;
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('APPLY CODE ERROR: ${e.code} ${e.message}');

      // The code may already have been used (e.g. by the browser).
      // If the account is verified anyway, continue automatically.
      if (await _refreshVerified()) {
        await _verifiedDetected();
        return;
      }

      if (mounted) {
        _showSnackbar(
          _tr(
            'This link is invalid or has expired. Tap Verify Email to get a new one.',
            'Kiungo hiki ni batili au kimeisha muda. Bofya Thibitisha Barua Pepe kupata kingine.',
          ),
        );
      }
    } catch (e) {
      debugPrint('DEEP LINK UNEXPECTED ERROR: $e');

      if (mounted) {
        _showSnackbar(
          _tr(
            'Verification failed. Please try again.',
            'Uthibitishaji umeshindikana. Tafadhali jaribu tena.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  // ============================================================
  // NAVIGATION — role-based next stage.
  //
  //   admin -> AdminDashboardPage (admins skip ID upload)
  //   other -> IdUploadPage
  // ============================================================

  Future<void> _goToNextStage({required bool isAdmin}) async {
    if (_navigated || !mounted) return;

    // If the role could not be read yet, try once more so admins
    // are never accidentally sent to the ID upload page.
    bool admin = isAdmin;

    if (!admin && !_finalizing) {
      final role = await _userRole();
      admin = role == 'admin';
    }

    if (!mounted) return;

    _navigated = true;
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();

    if (admin) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const IdUploadPage()),
    );
  }

  Future<void> _backToLogin() async {
    if (_navigated) return;

    _navigated = true;
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();

    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('SIGN OUT ERROR: $e');
    }

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
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool sendDisabled =
        _sending || _cooldown > 0 || _verified || !_initialized;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: Text(
          _tr('Verify Email', 'Thibitisha Barua Pepe'),
        ),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildWaiting(sendDisabled),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WAITING SCREEN — user taps "Verify Email", auto-continues
  // once the link is clicked (polling every 3 seconds)
  // ============================================================

  Widget _buildWaiting(bool sendDisabled) {
    final bool linkSent = _cooldown > 0 || _sending;

    return Column(
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 70,
          color: _green,
        ),
        const SizedBox(height: 18),
        Text(
          _tr(
            'Verify your email',
            'Thibitisha barua pepe yako',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: _text,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _tr(
            'We will send a verification link to ${widget.email}. Tap Verify Email, open the link (it may open in your browser), and this page will continue automatically.',
            'Tutatuma kiungo cha uthibitishaji kwa ${widget.email}. Bofya Thibitisha Barua Pepe, fungua kiungo (kinaweza kufunguka kwenye browser), na ukurasa huu utaendelea kiotomatiki.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 24),

        // ---------------- VERIFY EMAIL BUTTON ----------------
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: sendDisabled ? null : () => _sendVerificationEmail(),
            icon: _sending
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.mark_email_read_outlined),
            label: Text(
              _cooldown > 0
                  ? _tr(
                'Link sent — resend in $_cooldown s',
                'Kiungo kimetumwa — tuma tena baada ya sekunde $_cooldown',
              )
                  : _tr('Verify Email', 'Thibitisha Barua Pepe'),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Status: spinner while waiting / applying the link.
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(
          _checking
              ? _tr(
            'Verifying your email...',
            'Inathibitisha barua pepe yako...',
          )
              : linkSent
              ? _tr(
            'Waiting for you to open the link. This page will continue automatically.',
            'Inasubiri ufungue kiungo. Ukurasa huu utaendelea kiotomatiki.',
          )
              : _tr(
            'Tap Verify Email to send the verification link.',
            'Bofya Thibitisha Barua Pepe kutuma kiungo cha uthibitishaji.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 20),

        if (linkSent)
          Text(
            _tr(
              'Check your spam/junk folder if you do not see the email.',
              'Kama hujaiona barua pepe, angalia folda ya spam/junk.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        const SizedBox(height: 20),

        // Back to login.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _backToLogin,
            icon: const Icon(Icons.login),
            label: Text(
              _tr(
                'Back to Login',
                'Rudi kwenye Kuingia',
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _green,
              side: BorderSide(color: _green),
              padding: const EdgeInsets.symmetric(
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}