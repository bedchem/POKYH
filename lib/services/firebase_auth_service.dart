import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._();
  FirebaseAuthService._();
  static FirebaseAuthService get instance => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Firebase Auth UID – gerätespezifisch, nur für Firestore-Session & Admin-Checks.
  String? get userId => _auth.currentUser?.uid;

  /// Benutzername wie eingegeben (z. B. "plat-feli").
  String? _username;
  String? get username => _username;

  /// Stabile, geräteübergreifende UID aus Firestore users/{username}.
  /// Gleicher Username → gleiche stableUid auf jedem Gerät.
  String? _stableUid;
  String? get stableUid => _stableUid;

  /// Ob der User erfolgreich in Firebase angemeldet ist.
  bool get isSignedIn => _auth.currentUser != null && _stableUid != null;

  /// Anmelden: Firebase Anonymous Session + stableUid aus Firestore holen.
  /// User-Daten werden NUR in Firestore gespeichert – nicht in Firebase Auth.
  Future<void> signInAnonymously(String username) async {
    _log('Anmeldung gestartet für "$username"...');

    // Firebase Auth Session sicherstellen (für Firestore-Sicherheitsregeln nötig).
    // Kein displayName setzen – Firebase Auth enthält keine Nutzerdaten.
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
      _log('Neue anonyme Firebase-Session erstellt (firebaseUid=${_auth.currentUser?.uid})');
    } else {
      _log('Bestehende Firebase-Session genutzt (firebaseUid=${_auth.currentUser!.uid})');
    }

    final firebaseUid = _auth.currentUser!.uid;
    _stableUid = await _resolveStableUid(username, firebaseUid);
    _username = username;

    _logBox(
      '✅ ANGEMELDET',
      'Username   : $username',
      'StableUID  : $_stableUid',
      'FirebaseUID: $firebaseUid',
      '(StableUID ist auf jedem Gerät gleich)',
    );
  }

  /// Sucht oder erstellt users/{username} in Firestore und gibt die stableUid zurück.
  /// - Erstes Gerät: erstellt das Dokument mit neuer stableUid
  /// - Weiteres Gerät: liest die bestehende stableUid
  /// Schreibt außerdem users/{firebaseUid} für Admin-Checks.
  Future<String> _resolveStableUid(String username, String firebaseUid) async {
    try {
      // 1. Username-Dokument lesen (geräteübergreifend stabil)
      final usernameDoc = _db.collection('users').doc(username);
      final snap = await usernameDoc.get();

      String stableUid;
      if (snap.exists) {
        final existing = snap.data()?['stableUid'] as String?;
        if (existing != null && existing.isNotEmpty) {
          stableUid = existing;
          _log('Bestehender User "$username" gefunden → stableUid=$stableUid');
        } else {
          // Dokument vorhanden aber stableUid fehlt – nachfüllen
          stableUid = _db.collection('_').doc().id;
          await usernameDoc.update({'stableUid': stableUid});
          _log('StableUID für "$username" ergänzt → $stableUid');
        }
      } else {
        // Erster Login mit diesem Username → neues User-Dokument anlegen
        stableUid = _db.collection('_').doc().id;
        await usernameDoc.set({
          'username': username,
          'stableUid': stableUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _log('Neuer User "$username" in Firestore angelegt → stableUid=$stableUid');
      }

      // 2. Gerätespezifisches Dokument (für Admin-Checks via Firebase UID)
      await _db.collection('users').doc(firebaseUid).set(
        {
          'username': username,
          'stableUid': stableUid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return stableUid;
    } catch (e) {
      _log('⚠️  Firestore-Fehler bei _resolveStableUid: $e');
      _log('   Fallback: stableUid = username ("$username")');
      return username;
    }
  }

  // ── Logging-Helpers ─────────────────────────────────────────────────────────

  static void _log(String msg) {
    debugPrint('[FirebaseAuth] $msg');
  }

  static void _logBox(String title, String line1, String line2,
      String line3, String line4) {
    const w = 52;
    final border = '─' * w;
    debugPrint('┌$border┐');
    debugPrint('│  $title${' ' * (w - title.length - 2)}│');
    debugPrint('├$border┤');
    for (final line in [line1, line2, line3, line4]) {
      final padded = '  $line';
      final padding = ' ' * (w - padded.length).clamp(0, w);
      debugPrint('│$padded$padding│');
    }
    debugPrint('└$border┘');
  }
}
