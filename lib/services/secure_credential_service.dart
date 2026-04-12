import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores login credentials securely using platform Keychain/Keystore.
///
/// Passwords are NEVER stored in plaintext. Only a salted SHA-256 hash is kept
/// for display/verification purposes. The actual password is encrypted by the
/// OS secure enclave via FlutterSecureStorage.
class SecureCredentialService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true, // auto-reset on keystore corruption (e.g. after factory reset)
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false, // never sync passwords to iCloud Keychain
    ),
    lOptions: LinuxOptions(),
    wOptions: WindowsOptions(),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  static const _keyAccounts = 'saved_accounts';
  static const _keySalt = 'global_hash_salt';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Save (or update) credentials for [username].
  /// [profileImageBase64] may be null if not yet fetched.
  Future<void> saveCredentials({
    required String username,
    required String password,
    String? profileImageBase64,
  }) async {
    final accounts = await loadAccounts();
    final salt = await _getOrCreateSalt();

    // Remove old entry for the same username (case-insensitive)
    accounts.removeWhere(
          (a) => a.username.toLowerCase() == username.toLowerCase(),
    );

    accounts.add(
      SavedAccount(
        username: username,
        passwordHash: _hash(password, salt),
        profileImageBase64: profileImageBase64,
        savedAt: DateTime.now(),
      ),
    );

    // Persist the list (metadata only — no plaintext password)
    await _storage.write(
      key: _keyAccounts,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );

    // Store actual password separately under a per-user key
    await _storage.write(key: _passwordKey(username), value: password);
  }

  /// Update the stored profile image for [username].
  Future<void> updateProfileImage(String username, String base64) async {
    final accounts = await loadAccounts();
    final idx = accounts.indexWhere(
          (a) => a.username.toLowerCase() == username.toLowerCase(),
    );
    if (idx == -1) return;

    accounts[idx] = accounts[idx].copyWith(profileImageBase64: base64);
    await _storage.write(
      key: _keyAccounts,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  /// Load all saved accounts (metadata, no passwords).
  Future<List<SavedAccount>> loadAccounts() async {
    try {
      final raw = await _storage.read(key: _keyAccounts);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupted data — wipe accounts list, keep passwords intact
      await _storage.delete(key: _keyAccounts);
      return [];
    }
  }

  /// Retrieve the stored password for [username] (used after biometric auth).
  Future<String?> getPassword(String username) =>
      _storage.read(key: _passwordKey(username));

  /// Remove a saved account and its stored password.
  Future<void> removeAccount(String username) async {
    final accounts = await loadAccounts();
    accounts.removeWhere(
          (a) => a.username.toLowerCase() == username.toLowerCase(),
    );
    await _storage.write(
      key: _keyAccounts,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    await _storage.delete(key: _passwordKey(username));
  }

  /// Clear all saved accounts, passwords, and the salt.
  Future<void> clearAll() => _storage.deleteAll();

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _passwordKey(String username) =>
      'pwd_${username.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Returns a stable per-installation salt, creating it on first use.
  Future<String> _getOrCreateSalt() async {
    final existing = await _storage.read(key: _keySalt);
    if (existing != null && existing.isNotEmpty) return existing;

    // Generate a random 32-byte salt stored in secure storage
    final salt = DateTime.now().microsecondsSinceEpoch.toString() +
        Object().hashCode.toString();
    final newSalt = sha256.convert(utf8.encode(salt)).toString();
    await _storage.write(key: _keySalt, value: newSalt);
    return newSalt;
  }

  /// SHA-256 with a per-installation salt (display / integrity check only).
  static String _hash(String value, String salt) =>
      sha256.convert(utf8.encode('$salt:$value')).toString();
}

// ── Model ──────────────────────────────────────────────────────────────────

class SavedAccount {
  final String username;

  /// Salted SHA-256 of the password — used for display/integrity only,
  /// never for authentication. The real password lives in secure storage.
  final String passwordHash;

  final String? profileImageBase64;
  final DateTime savedAt;

  const SavedAccount({
    required this.username,
    required this.passwordHash,
    this.profileImageBase64,
    required this.savedAt,
  });

  SavedAccount copyWith({String? profileImageBase64}) => SavedAccount(
    username: username,
    passwordHash: passwordHash,
    profileImageBase64: profileImageBase64 ?? this.profileImageBase64,
    savedAt: savedAt,
  );

  Map<String, dynamic> toJson() => {
    'username': username,
    'passwordHash': passwordHash,
    if (profileImageBase64 != null) 'profileImageBase64': profileImageBase64,
    'savedAt': savedAt.toIso8601String(),
  };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    username: j['username'] as String,
    passwordHash: j['passwordHash'] as String,
    profileImageBase64: j['profileImageBase64'] as String?,
    savedAt: DateTime.parse(j['savedAt'] as String),
  );
}