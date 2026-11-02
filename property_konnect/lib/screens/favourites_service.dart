import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Provides DeviceIdService (no-account favourites are per device).
import 'property_details_page.dart' show DeviceIdService;

class FavouritesService {
  static const String _localKey = 'favourite_properties';

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static FirebaseAuth get _auth => FirebaseAuth.instance;

  // ============================================================
  // PROPERTY FAVOURITES (unchanged)
  // ============================================================

  static Future<bool> isFavourite(String propertyId) async {
    if (propertyId.trim().isEmpty) {
      return false;
    }

    final user = _auth.currentUser;

    if (user != null) {
      final document = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favourites')
          .doc(propertyId)
          .get();

      return document.exists;
    }

    final preferences = await SharedPreferences.getInstance();
    final favourites = preferences.getStringList(_localKey) ?? <String>[];

    return favourites.contains(propertyId);
  }

  static Future<bool> toggleFavourite(String propertyId) async {
    if (propertyId.trim().isEmpty) {
      return false;
    }

    final user = _auth.currentUser;

    if (user != null) {
      final reference = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favourites')
          .doc(propertyId);

      final document = await reference.get();

      if (document.exists) {
        await reference.delete();
        return false;
      }

      await reference.set({
        'propertyId': propertyId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    }

    final preferences = await SharedPreferences.getInstance();
    final favourites = List<String>.from(
      preferences.getStringList(_localKey) ?? <String>[],
    );

    if (favourites.contains(propertyId)) {
      favourites.remove(propertyId);
      await preferences.setStringList(_localKey, favourites);
      return false;
    }

    favourites.add(propertyId);
    await preferences.setStringList(_localKey, favourites);
    return true;
  }

  static Future<void> addFavourite(String propertyId) async {
    if (propertyId.trim().isEmpty) {
      return;
    }

    final user = _auth.currentUser;

    if (user != null) {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favourites')
          .doc(propertyId)
          .set({
        'propertyId': propertyId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    final favourites = List<String>.from(
      preferences.getStringList(_localKey) ?? <String>[],
    );

    if (!favourites.contains(propertyId)) {
      favourites.add(propertyId);
      await preferences.setStringList(_localKey, favourites);
    }
  }

  static Future<void> removeFavourite(String propertyId) async {
    if (propertyId.trim().isEmpty) {
      return;
    }

    final user = _auth.currentUser;

    if (user != null) {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favourites')
          .doc(propertyId)
          .delete();
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    final favourites = List<String>.from(
      preferences.getStringList(_localKey) ?? <String>[],
    );

    favourites.remove(propertyId);
    await preferences.setStringList(_localKey, favourites);
  }

  // ============================================================
  // ROOMMATE REQUEST FAVOURITES (NEW)
  //
  // No account needed. Saved per DEVICE:
  //   - locally (SharedPreferences) so the heart responds
  //     instantly and works offline, and
  //   - in the Firestore `favorites` collection as
  //     "roommate_{postId}_{deviceId}" with kind: 'roommate'
  //     so the saves survive reinstalls of the same device id.
  // Firestore errors never block the local save.
  // ============================================================

  static const String _localRoommateKey = 'favourite_roommates';
  static const String _favoritesCollection = 'favorites';

  /// Fires whenever roommate favourites change, so open pages
  /// (e.g. the Favourites page) can refresh themselves.
  static final ValueNotifier<int> roommateChanges = ValueNotifier<int>(0);

  static void notifyRoommates() => roommateChanges.value++;

  static Future<String> _deviceId() async {
    try {
      return await DeviceIdService.get();
    } catch (_) {
      return '';
    }
  }

  static Future<Set<String>> _localRoommateIds() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_localRoommateKey) ?? <String>[])
        .toSet();
  }

  static Future<void> _saveLocalRoommateIds(Set<String> ids) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_localRoommateKey, ids.toList());
  }

  static String _roommateDocId(String roommateId, String deviceId) =>
      'roommate_${roommateId}_$deviceId';

  static Future<bool> isRoommateFavourite(String roommateId) async {
    if (roommateId.trim().isEmpty) return false;
    return (await _localRoommateIds()).contains(roommateId);
  }

  /// Saves or un-saves a roommate request. Returns true when it
  /// is saved AFTER the call.
  static Future<bool> toggleRoommateFavourite(String roommateId) async {
    if (roommateId.trim().isEmpty) return false;

    final ids = await _localRoommateIds();
    final deviceId = await _deviceId();

    if (ids.contains(roommateId)) {
      ids.remove(roommateId);
      await _saveLocalRoommateIds(ids);

      if (deviceId.isNotEmpty) {
        try {
          await _firestore
              .collection(_favoritesCollection)
              .doc(_roommateDocId(roommateId, deviceId))
              .delete();
        } catch (e) {
          debugPrint('Roommate favourite delete error: $e');
        }
      }

      notifyRoommates();
      return false;
    }

    ids.add(roommateId);
    await _saveLocalRoommateIds(ids);

    if (deviceId.isNotEmpty) {
      try {
        await _firestore
            .collection(_favoritesCollection)
            .doc(_roommateDocId(roommateId, deviceId))
            .set({
          'kind': 'roommate',
          'roommateId': roommateId,
          'deviceId': deviceId,
          'userId': _auth.currentUser?.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Roommate favourite save error: $e');
      }
    }

    notifyRoommates();
    return true;
  }

  /// Every saved roommate request id for this device (local list
  /// merged with the Firestore copies; the local list is updated
  /// with anything found remotely).
  static Future<Set<String>> roommateFavouriteIds() async {
    final ids = await _localRoommateIds();
    final before = ids.length;

    final deviceId = await _deviceId();

    if (deviceId.isNotEmpty) {
      try {
        final snapshot = await _firestore
            .collection(_favoritesCollection)
            .where('deviceId', isEqualTo: deviceId)
            .where('kind', isEqualTo: 'roommate')
            .get();

        for (final doc in snapshot.docs) {
          final id = doc.data()['roommateId']?.toString() ?? '';
          if (id.isNotEmpty) ids.add(id);
        }
      } catch (e) {
        debugPrint('Roommate favourites load error: $e');
      }
    }

    if (ids.length != before) {
      await _saveLocalRoommateIds(ids);
    }

    return ids;
  }

  static Future<void> removeRoommateFavourite(String roommateId) async {
    if (roommateId.trim().isEmpty) return;

    final ids = await _localRoommateIds();
    ids.remove(roommateId);
    await _saveLocalRoommateIds(ids);

    final deviceId = await _deviceId();

    if (deviceId.isNotEmpty) {
      try {
        await _firestore
            .collection(_favoritesCollection)
            .doc(_roommateDocId(roommateId, deviceId))
            .delete();
      } catch (e) {
        debugPrint('Roommate favourite remove error: $e');
      }
    }

    notifyRoommates();
  }
}