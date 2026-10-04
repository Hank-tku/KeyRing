import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/services/app_lock_state.dart';
import 'package:key_ring/services/workspace_access_service.dart';

class MemoryCredentials implements WorkspaceCredentialStore {
  final Map<String, String> records = {};
  Completer<void>? readGate;
  @override
  Future<String?> read(String id) async {
    await readGate?.future;
    return records[id];
  }

  @override
  Future<void> write(String id, String value) async {
    records[id] = value;
  }

  @override
  Future<void> delete(String id) async {
    records.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryCredentials store;
  late WorkspaceAccessService access;
  late Set<String> flags;
  late DateTime now;
  bool systemResult = true;
  int systemCalls = 0;
  Completer<bool>? systemGate;
  setUp(() {
    AppLockState.markUnlocked();
    store = MemoryCredentials();
    flags = {};
    systemResult = true;
    systemCalls = 0;
    systemGate = null;
    now = DateTime.utc(2026);
    access = WorkspaceAccessService(
      store: store,
      iterations: 1,
      systemAuthenticate: () async {
        systemCalls++;
        return systemGate == null ? systemResult : systemGate!.future;
      },
      now: () => now,
      persistProtection: (id, enabled) async {
        if (enabled) {
          flags.add(id);
        } else {
          flags.remove(id);
        }
      },
    );
    access.initialize(flags);
  });
  tearDown(() => access.dispose());

  test(
    'setup stores salted verifier, enters locked, survives restart',
    () async {
      await access.setPassword('work', ' secret ');
      expect(access.canAccess('work'), false);
      expect(access.canAccess('personal'), true);
      expect(flags, {'work'});
      expect(store.records['work'], isNot(contains('secret')));
      final record = jsonDecode(store.records['work']!) as Map;
      expect(base64Decode(record['salt'] as String), hasLength(32));
      expect(await access.verify('work', 'secret'), false);
      expect(await access.verify('work', ' secret '), true);
      access.initialize(flags);
      expect(access.canAccess('work'), false);
      expect(await access.verify('work', ' secret '), true);
    },
  );
  test(
    'five failures cool down, application locking does not reset attempts',
    () async {
      await access.setPassword('work', 'secret');
      for (int i = 0; i < 5; i++) {
        expect(await access.verify('work', 'wrong'), false);
      }
      expect(access.cooldownSeconds('work'), 30);
      AppLockState.markLocked();
      AppLockState.markUnlocked();
      expect(await access.verify('work', 'secret'), false);
      now = now.add(const Duration(seconds: 31));
      expect(await access.verify('work', 'secret'), true);
    },
  );
  test('switch-away and application locking revoke authorization', () async {
    await access.setPassword('work', 'secret');
    await access.verify('work', 'secret');
    access.lock('work');
    expect(access.canAccess('work'), false);
    await access.verify('work', 'secret');
    AppLockState.markLocked();
    expect(access.canAccess('work'), false);
    expect(await access.verify('work', 'secret'), false);
  });
  test('late verification cannot unlock after application lock', () async {
    await access.setPassword('work', 'secret');
    store.readGate = Completer<void>();
    final verification = access.verify('work', 'secret');
    AppLockState.markLocked();
    AppLockState.markUnlocked();
    store.readGate!.complete();
    expect(await verification, false);
    expect(access.canAccess('work'), false);
  });
  test(
    'changing/disabling password requires old password even in unlocked session',
    () async {
      await access.setPassword('work', 'secret');
      await access.verify('work', 'secret');
      await expectLater(
        access.setPassword('work', 'newpass', oldPassword: 'wrong'),
        throwsStateError,
      );
      await expectLater(
        access.removePassword('work', 'wrong'),
        throwsStateError,
      );
      await access.setPassword('work', 'newpass', oldPassword: 'secret');
      expect(await access.verify('work', 'secret'), false);
      expect(await access.verify('work', 'newpass'), true);
      await access.removePassword('work', 'newpass');
      expect(access.canAccess('work'), true);
      expect(flags, isEmpty);
      expect(store.records, isEmpty);
    },
  );
  test('missing or malformed secure storage fails closed', () async {
    access.initialize({'work'});
    expect(await access.verify('work', 'secret'), false);
    store.records['work'] = 'invalid';
    expect(await access.verify('work', 'secret'), false);
    expect(access.canAccess('work'), false);
  });
  test(
    'system mode validates on setup and entry, survives reload without a password',
    () async {
      await access.setSystemUnlock('work');
      expect(systemCalls, 1);
      expect(access.canAccess('work'), false);
      expect(access.modeFor('work'), WorkspaceUnlockMode.system);
      expect(await access.verify('work', 'anything'), false);
      expect(await access.verifySystem('work'), true);
      expect(systemCalls, 2);
      access.initialize(flags);
      await access.loadModes();
      expect(access.modeFor('work'), WorkspaceUnlockMode.system);
      expect(access.canAccess('work'), false);
      expect(await access.verifySystem('work'), true);
    },
  );
  test(
    'cancelled or unavailable system authentication cannot enable or unlock',
    () async {
      systemResult = false;
      await expectLater(access.setSystemUnlock('work'), throwsStateError);
      expect(flags, isEmpty);
      systemResult = true;
      await access.setSystemUnlock('work');
      systemResult = false;
      expect(await access.verifySystem('work'), false);
      expect(access.canAccess('work'), false);
      await expectLater(access.removePassword('work', ''), throwsStateError);
      expect(access.isProtected('work'), true);
    },
  );
  test(
    'switching modes requires original credential and clears old password use',
    () async {
      await access.setPassword('work', 'custom');
      await expectLater(
        access.setSystemUnlock('work', oldPassword: 'wrong'),
        throwsStateError,
      );
      expect(systemCalls, 0);
      await access.setSystemUnlock('work', oldPassword: 'custom');
      expect(await access.verify('work', 'custom'), false);
      systemResult = false;
      await expectLater(
        access.setPassword('work', 'another'),
        throwsStateError,
      );
      systemResult = true;
      await access.setPassword('work', 'another');
      expect(access.modeFor('work'), WorkspaceUnlockMode.password);
      expect(await access.verifySystem('work'), false);
      expect(await access.verify('work', 'another'), true);
    },
  );
  test(
    'late system success cannot restore access after global lock or cancellation',
    () async {
      await access.setSystemUnlock('work');
      systemGate = Completer<bool>();
      final verification = access.verifySystem('work');
      AppLockState.markLocked();
      AppLockState.markUnlocked();
      systemGate!.complete(true);
      expect(await verification, false);
      expect(access.canAccess('work'), false);
      systemGate = null;
      expect(await access.verifySystem('work', isCurrent: () => false), false);
      expect(access.canAccess('work'), false);
    },
  );
  test('cancelled password dialog cannot grant authorization', () async {
    await access.setPassword('work', 'secret');
    store.readGate = Completer<void>();
    bool active = true;
    final pending = access.verify('work', 'secret', isCurrent: () => active);
    active = false;
    store.readGate!.complete();
    expect(await pending, false);
    expect(access.canAccess('work'), false);
  });
}
