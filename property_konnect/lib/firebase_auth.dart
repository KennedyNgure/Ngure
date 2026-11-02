
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;

class FirebaseAuthService {
  FirebaseAuthService._();

  static final FirebaseAuthService instance =
  FirebaseAuthService._();

  final firebase.FirebaseAuth _auth =
      firebase.FirebaseAuth.instance;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  firebase.User? get currentUser => _auth.currentUser;

  Stream<firebase.User?> get authStateChanges =>
      _auth.authStateChanges();

  bool get isLoggedIn => _auth.currentUser != null;

  Future<firebase.UserCredential> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String role = 'owner',
    String accountType = 'property_owner',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw Exception('Firebase could not create the user account.');
    }

    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': phone.trim(),
      'role': role,
      'accountType': accountType,
      'verificationStatus': 'pending',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await user.sendEmailVerification();
    } catch (_) {
      // The account already exists if sending verification fails.
    }

    return credential;
  }

  Future<firebase.UserCredential> login({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<void> logout() => _auth.signOut();

  /// Sends a Firebase password-reset email.
  ///
  /// The Firebase Hosting email-action link can open the Android app
  /// when the app links and Firebase configuration are correct.
  Future<void> sendPasswordReset(String email) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Please enter your email address.');
    }

    final settings = firebase.ActionCodeSettings(
      url: 'https://property-konnect-cb4bc.firebaseapp.com/reset-password',
      handleCodeInApp: true,
      androidPackageName: 'com.MEG.property_konnect',
      androidInstallApp: true,
      androidMinimumVersion: '1',
    );

    await _auth.sendPasswordResetEmail(
      email: normalizedEmail,
      actionCodeSettings: settings,
    );
  }

  /// Checks whether Firebase accepts the password-reset code.
  Future<String> verifyPasswordResetCode(String code) {
    return _auth.verifyPasswordResetCode(code);
  }

  /// Changes the password only after Firebase accepts the reset code.
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) {
    return _auth.confirmPasswordReset(
      code: code,
      newPassword: newPassword,
    );
  }

  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No user is currently signed in.');
    }

    await user.sendEmailVerification();
  }

  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>>
  getCurrentUserProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No user is currently signed in.');
    }

    return _firestore.collection('users').doc(user.uid).get();
  }

  Future<Map<String, dynamic>?> getCurrentUserData() async {
    final snapshot = await getCurrentUserProfile();

    if (!snapshot.exists) {
      return null;
    }

    return snapshot.data();
  }

  Future<String?> getCurrentUserRole() async {
    final data = await getCurrentUserData();

    if (data == null || data['role'] == null) {
      return null;
    }

    return data['role'].toString();
  }

  Future<bool> isAdmin() async {
    final role = await getCurrentUserRole();
    return role == 'admin' || role == 'super_admin';
  }

  Future<bool> isPropertyOwner() async {
    final role = await getCurrentUserRole();
    return role == 'owner' || role == 'property_owner';
  }

  Future<void> updateCurrentUserProfile(
      Map<String, dynamic> data,
      ) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No user is currently signed in.');
    }

    await _firestore.collection('users').doc(user.uid).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
