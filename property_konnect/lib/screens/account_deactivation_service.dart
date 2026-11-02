import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccountDeactivationService {
  AccountDeactivationService._();

  static final AccountDeactivationService instance =
  AccountDeactivationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ------------------------------------------------------------
  // DEACTIVATE ACCOUNT
  //
  // IMPORTANT:
  // Nothing is deleted from Firestore.
  //
  // The user's profile remains.
  // The user's properties remain.
  // The records are simply marked inactive/deactivated.
  //
  // Each property's PREVIOUS status (verified / unverified)
  // is saved as previousStatus / previousPropertyStatus so the
  // admin can fully restore the listing on reactivation.
  // ------------------------------------------------------------

  Future<void> deactivateAccount() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No authenticated user was found.');
    }

    final uid = user.uid;

    // ----------------------------------------------------------
    // 1. DEACTIVATE USER PROFILE
    // ----------------------------------------------------------

    await _firestore.collection('users').doc(uid).set(
      {
        'isActive': false,
        'isDeactivated': true,
        'status': 'deactivated',
        'accountStatus': 'deactivated',
        'deactivatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // ----------------------------------------------------------
    // 2. FIND ALL PROPERTIES OWNED BY THE USER
    // ----------------------------------------------------------

    final propertiesSnapshot = await _firestore
        .collection('properties')
        .where('ownerId', isEqualTo: uid)
        .get();

    // ----------------------------------------------------------
    // 3. MARK ALL OWNED PROPERTIES INACTIVE
    //
    // NOTHING IS DELETED. The previous status is preserved so
    // reactivation restores verified/unverified exactly.
    // ----------------------------------------------------------

    if (propertiesSnapshot.docs.isNotEmpty) {
      final now = FieldValue.serverTimestamp();

      final batch = _firestore.batch();

      for (final property in propertiesSnapshot.docs) {
        final data = property.data();

        batch.update(
          property.reference,
          {
            'isDeactivated': true,
            'isActive': false,
            'available': false,
            'status': 'inactive',
            'property_status': 'inactive',
            // Remember the original values so the account can be
            // fully restored later (by admin reactivation).
            'previousStatus': data['status'] ?? 'active',
            'previousPropertyStatus': data['property_status'] ?? 'unverified',
            'deactivatedAt': now,
            'updatedAt': now,
          },
        );
      }

      await batch.commit();
    }

    // ----------------------------------------------------------
    // 4. SIGN OUT
    //
    // We deliberately DO NOT call:
    //
    // FirebaseAuth.instance.currentUser!.delete()
    //
    // because the account record should remain available for
    // historical ownership/audit purposes.
    // ----------------------------------------------------------

    await _auth.signOut();
  }
}