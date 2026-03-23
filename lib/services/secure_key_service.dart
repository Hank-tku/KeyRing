import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class SecureKeyService {
  SecureKeyService()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  static const String _keyHash = 'master_password_hash_v1';
  static const String _keySalt = 'master_password_salt_v1';
  final FlutterSecureStorage _storage;

  Future<bool> hasPassword() async {
    final String? h = await _storage.read(key: _keyHash);
    return (h != null && h.isNotEmpty);
  }

  Future<void> setPassword(String password) async {
    final String salt = const Uuid().v4();
    final String hash = _hash(password, salt);
    await _storage.write(key: _keySalt, value: salt);
    await _storage.write(key: _keyHash, value: hash);
  }

  Future<bool> verifyPassword(String password) async {
    final String? salt = await _storage.read(key: _keySalt);
    final String? hash = await _storage.read(key: _keyHash);
    if (salt == null || hash == null) return false;
    final String calc = _hash(password, salt);
    return const ListEquality().equals(utf8.encode(calc), utf8.encode(hash));
  }

  String _hash(String password, String salt) {
    final List<int> bytes = utf8.encode('$password::$salt');
    return sha256.convert(bytes).toString();
  }
}

/// Lightweight equality for constant-time-ish compare (not cryptographically strict)
class ListEquality {
  const ListEquality();
  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
