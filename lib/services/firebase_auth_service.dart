import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._();
  FirebaseAuthService._();
  static FirebaseAuthService get instance => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get userId => _auth.currentUser?.uid;
  String? get username => _auth.currentUser?.displayName;

  Future<void> signInAnonymously(String username) async {
    try {
      if (_auth.currentUser != null) {
        if (_auth.currentUser!.displayName != username) {
          await _auth.currentUser!.updateDisplayName(username);
        }
        debugPrint('[FirebaseAuth] Already signed in as ${_auth.currentUser!.uid}');
        return;
      }
      final cred = await _auth.signInAnonymously();
      await cred.user?.updateDisplayName(username);
      debugPrint('[FirebaseAuth] Signed in anonymously as ${cred.user?.uid}');
    } catch (e) {
      debugPrint('[FirebaseAuth] ERROR: $e');
      rethrow;
    }
  }
}
