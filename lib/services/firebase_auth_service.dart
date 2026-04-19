import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._();
  FirebaseAuthService._();
  static FirebaseAuthService get instance => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get userId => _auth.currentUser?.uid;
  String? get username => _auth.currentUser?.displayName;

  Future<void> signInAnonymously(String username) async {
    try {
      if (_auth.currentUser != null) {
        if (_auth.currentUser!.displayName != username) {
          await _auth.currentUser!.updateDisplayName(username);
        }
        final uid = _auth.currentUser!.uid;
        debugPrint('[FirebaseAuth] Already signed in as $uid');
        await _writeUserRecord(uid, username);
        return;
      }
      final cred = await _auth.signInAnonymously();
      final uid = cred.user!.uid;
      await cred.user?.updateDisplayName(username);
      await _writeUserRecord(uid, username);
      debugPrint('[FirebaseAuth] Signed in anonymously as $uid');
    } catch (e) {
      debugPrint('[FirebaseAuth] ERROR: $e');
      rethrow;
    }
  }

  /// Stores or updates the username in Firestore so other users can look it up.
  Future<void> _writeUserRecord(String uid, String username) async {
    try {
      await _db.collection('users').doc(uid).set(
        {'username': username, 'uid': uid, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[FirebaseAuth] Could not write user record: $e');
    }
  }

  /// Fetches usernames for a list of UIDs from the /users collection.
  /// Returns a map of uid → username. Missing UIDs map to the UID itself.
  Future<Map<String, String>> fetchUsernames(List<String> uids) async {
    if (uids.isEmpty) return {};
    final result = <String, String>{};
    try {
      // Firestore whereIn supports max 30 items per query
      for (var i = 0; i < uids.length; i += 30) {
        final batch = uids.sublist(i, (i + 30).clamp(0, uids.length));
        final snap = await _db
            .collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snap.docs) {
          final name = doc.data()['username'] as String?;
          if (name != null && name.isNotEmpty) {
            result[doc.id] = name;
          }
        }
      }
    } catch (e) {
      debugPrint('[FirebaseAuth] fetchUsernames error: $e');
    }
    for (final uid in uids) {
      result.putIfAbsent(uid, () => uid);
    }
    return result;
  }
}
