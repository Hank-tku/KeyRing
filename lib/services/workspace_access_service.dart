import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_lock_state.dart';
import '../screens/auth_service.dart';

enum WorkspaceUnlockMode { none, system, password }

abstract class WorkspaceCredentialStore {
  Future<String?> read(String id);
  Future<void> write(String id, String value);
  Future<void> delete(String id);
}

class SecureWorkspaceCredentialStore implements WorkspaceCredentialStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String _key(String id) => 'workspace_password_v1_$id';
  @override
  Future<String?> read(String id) => _storage.read(key: _key(id));
  @override
  Future<void> write(String id, String value) =>
      _storage.write(key: _key(id), value: value);
  @override
  Future<void> delete(String id) => _storage.delete(key: _key(id));
}

Future<List<int>> _derive(Map<String, dynamic> args) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: args['iterations'] as int,
        bits: 256,
      ).deriveKeyFromPassword(
        password: args['password'] as String,
        nonce: List<int>.from(args['salt'] as List),
      );
  return key.extractBytes();
}

/// Device-local access control. The database flag is also read by native
/// autofill; credentials never enter workspace serialization or LAN payloads.
class WorkspaceAccessService extends ChangeNotifier {
  WorkspaceAccessService({
    required this.persistProtection,
    WorkspaceCredentialStore? store,
    this.iterations = 600000,
    DateTime Function()? now,
    Future<bool> Function()? systemAuthenticate,
  }) : _store = store ?? SecureWorkspaceCredentialStore(),
       _now = now ?? DateTime.now,
       _systemAuthenticate =
           systemAuthenticate ??
           (() => AuthService().authenticateWithSystemPassword(
             reason: '请验证身份以访问此工作区',
           )) {
    AppLockState.listenable.addListener(_onAppLock);
  }

  final Future<void> Function(String, bool) persistProtection;
  final WorkspaceCredentialStore _store;
  final int iterations;
  final DateTime Function() _now;
  final Future<bool> Function() _systemAuthenticate;
  final Set<String> _systemProtected = {};
  final Set<String> _protected = {};
  final Set<String> _authorized = {};
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _blockedUntil = {};
  final Set<String> _busy = {};
  int _generation = 0;
  bool _ready = false;

  void initialize(Iterable<String> protectedIds) {
    _protected
      ..clear()
      ..addAll(protectedIds);
    _systemProtected.clear();
    _ready = true;
    lockAll();
  }

  WorkspaceUnlockMode modeFor(String id) => !isProtected(id)
      ? WorkspaceUnlockMode.none
      : _systemProtected.contains(id)
      ? WorkspaceUnlockMode.system
      : WorkspaceUnlockMode.password;

  /// Missing/corrupt credentials retain the password gate and fail closed.
  Future<void> loadModes() async {
    for (final id in _protected.toList()) {
      try {
        final raw = await _store.read(id);
        if (raw != null) {
          final record = jsonDecode(raw) as Map;
          if (record['version'] == 1 && record['mode'] == 'system') {
            _systemProtected.add(id);
          }
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  bool isProtected(String id) => _protected.contains(id);
  bool canAccess(String id) =>
      _ready && (!isProtected(id) || _authorized.contains(id));
  Set<String> get protectedIds => Set.unmodifiable(_protected);
  int get generation => _generation;

  int cooldownSeconds(String id) {
    final remaining = _blockedUntil[id]?.difference(_now()).inMilliseconds ?? 0;
    return remaining > 0 ? (remaining / 1000).ceil() : 0;
  }

  void _onAppLock() {
    if (AppLockState.isLocked) lockAll();
  }

  void lockAll() {
    _generation++;
    _authorized.clear();
    notifyListeners();
  }

  void lock(String id) {
    _generation++;
    _authorized.remove(id);
    notifyListeners();
  }

  Future<bool> verify(
    String id,
    String password, {
    bool Function()? isCurrent,
  }) async {
    if (!_ready || AppLockState.isLocked) return false;
    if (!isProtected(id)) return true;
    if (modeFor(id) != WorkspaceUnlockMode.password) return false;
    if (cooldownSeconds(id) > 0 || !_busy.add(id)) return false;
    final generation = _generation;
    try {
      final raw = await _store.read(id);
      if (raw == null) return false; // Missing Keychain entry never unlocks.
      final record = jsonDecode(raw) as Map<String, dynamic>;
      final rounds = record['iterations'] as int;
      if (record['version'] != 1 || rounds < 1 || rounds > 2000000) {
        return false;
      }
      final calculated = await compute(_derive, <String, dynamic>{
        'password': password,
        'salt': base64Decode(record['salt'] as String),
        'iterations': rounds,
      });
      final expected = base64Decode(record['hash'] as String);
      int difference = expected.length ^ calculated.length;
      for (int i = 0; i < calculated.length; i++) {
        difference |= calculated[i] ^ (i < expected.length ? expected[i] : 0);
      }
      if (generation != _generation ||
          AppLockState.isLocked ||
          isCurrent?.call() == false) {
        return false;
      }
      if (difference == 0) {
        _failures.remove(id);
        _blockedUntil.remove(id);
        _authorized.add(id);
        notifyListeners();
        return true;
      }
      final failures = (_failures[id] ?? 0) + 1;
      _failures[id] = failures;
      if (failures >= 5) {
        _blockedUntil[id] = _now().add(const Duration(seconds: 30));
        _failures[id] = 0;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _busy.remove(id);
    }
  }

  Future<bool> verifySystem(String id, {bool Function()? isCurrent}) async {
    if (!_ready ||
        AppLockState.isLocked ||
        modeFor(id) != WorkspaceUnlockMode.system ||
        !_busy.add(id)) {
      return false;
    }
    final generation = _generation;
    try {
      final ok = await _systemAuthenticate();
      if (!ok ||
          generation != _generation ||
          AppLockState.isLocked ||
          isCurrent?.call() == false) {
        return false;
      }
      _authorized.add(id);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    } finally {
      _busy.remove(id);
    }
  }

  Future<bool> _verifyCurrent(String id, String? oldPassword) async {
    switch (modeFor(id)) {
      case WorkspaceUnlockMode.none:
        return true;
      case WorkspaceUnlockMode.system:
        return verifySystem(id);
      case WorkspaceUnlockMode.password:
        return oldPassword != null && await verify(id, oldPassword);
    }
  }

  Future<void> setSystemUnlock(String id, {String? oldPassword}) async {
    if (!_ready || AppLockState.isLocked) throw StateError('请先解锁应用');
    final wasSystem = modeFor(id) == WorkspaceUnlockMode.system;
    if (!await _verifyCurrent(id, oldPassword)) throw StateError('未通过当前验证');
    if (!_busy.add(id)) throw StateError('正在验证，请稍后重试');
    final generation = _generation;
    try {
      // Enabling the mode must prove that system authentication is usable.
      if (!wasSystem && !await _systemAuthenticate()) {
        throw StateError('系统验证未完成');
      }
      if (generation != _generation || AppLockState.isLocked) {
        throw StateError('验证已失效');
      }
      await _store.write(id, jsonEncode({'version': 1, 'mode': 'system'}));
      _protected.add(id);
      _systemProtected.add(id);
      lock(id);
      await persistProtection(id, true);
    } finally {
      _busy.remove(id);
    }
  }

  Future<void> setPassword(
    String id,
    String password, {
    String? oldPassword,
  }) async {
    if (password.length < 6) throw StateError('密码至少需要 6 个字符');
    if (!await _verifyCurrent(id, oldPassword)) {
      throw StateError('原密码不正确或暂时无法验证');
    }
    if (AppLockState.isLocked || !_busy.add(id)) throw StateError('请先解锁应用');
    final generation = _generation;
    try {
      final random = Random.secure();
      final salt = List<int>.generate(32, (_) => random.nextInt(256));
      final hash = await compute(_derive, <String, dynamic>{
        'password': password,
        'salt': salt,
        'iterations': iterations,
      });
      if (generation != _generation || AppLockState.isLocked) {
        throw StateError('应用已锁定，请重新操作');
      }
      await _store.write(
        id,
        jsonEncode({
          'version': 1,
          'mode': 'password',
          'iterations': iterations,
          'salt': base64Encode(salt),
          'hash': base64Encode(hash),
        }),
      );
      // Set the in-memory gate before awaiting the native persistent gate.
      _protected.add(id);
      _systemProtected.remove(id);
      lock(id);
      await persistProtection(id, true);
    } finally {
      _busy.remove(id);
    }
  }

  Future<void> removePassword(String id, String oldPassword) async {
    if (!await _verifyCurrent(id, oldPassword)) throw StateError('未通过当前验证');
    final generation = _generation;
    if (!_busy.add(id)) throw StateError('正在处理，请稍后重试');
    try {
      if (generation != _generation || AppLockState.isLocked) {
        throw StateError('应用已锁定，请重新操作');
      }
      await persistProtection(id, false);
      _protected.remove(id);
      _systemProtected.remove(id);
      lock(id);
      // The access policy is already disabled. A stale verifier is harmless
      // and will be replaced if the user sets a new password later.
      try {
        await _store.delete(id);
      } catch (_) {}
    } finally {
      _busy.remove(id);
    }
  }

  Future<void> forgetDeletedWorkspace(String id) async {
    if (!canAccess(id)) throw StateError('请先解锁工作区');
    if (isProtected(id)) {
      await persistProtection(id, false);
      try {
        await _store.delete(id);
      } catch (_) {}
    }
    _protected.remove(id);
    _systemProtected.remove(id);
    _failures.remove(id);
    _blockedUntil.remove(id);
    lock(id);
  }

  @override
  void dispose() {
    AppLockState.listenable.removeListener(_onAppLock);
    super.dispose();
  }
}
