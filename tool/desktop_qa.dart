// Isolated desktop QA entry point. Production builds use lib/main.dart.
// Run: flutter run -d macos -t tool/desktop_qa.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:key_ring/main.dart' as app;
import 'package:key_ring/models/password_item.dart';
import 'package:key_ring/models/secret_field.dart';
import 'package:key_ring/models/workspace.dart';
import 'package:key_ring/services/app_lock_state.dart';
import 'package:key_ring/services/password_repository.dart';
import 'package:key_ring/services/workspace_access_service.dart';

class _MemoryCredentials implements WorkspaceCredentialStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String id) async => values[id];
  @override
  Future<void> write(String id, String value) async {
    values[id] = value;
  }

  @override
  Future<void> delete(String id) async {
    values.remove(id);
  }
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'multi_window') {
    await app.main(args);
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await windowManager.ensureInitialized();
  final dir = await Directory.systemTemp.createTemp('keyring-desktop-qa-');
  final repository = PasswordRepository(
    dbPathOverride: '${dir.path}/qa.db',
    credentialStore: _MemoryCredentials(),
  );
  await repository.init();
  await repository.addItem(
    PasswordItem(
      title: 'QA Example',
      username: 'qa@example.test',
      password: 'Synthetic-Password-1!',
      url:
          'https://example.test/account/login?source=keyring&test=long-url-check',
      notes: '合成测试记录\n第二行备注：用于检查详情和换行。',
      customFields: [
        SecretField(
          label: '密码2',
          value: 'Synthetic-Password-2!',
          type: SecretFieldType.password,
          protected: true,
        ),
        SecretField(
          label: '密码3',
          value: 'Synthetic-Password-3!',
          type: SecretFieldType.password,
          protected: true,
        ),
        SecretField(
          label: '交易密码',
          value: 'Synthetic-Trade!',
          type: SecretFieldType.password,
          protected: true,
        ),
      ],
    ),
  );
  final private = Workspace(id: 'qa-private', name: 'QA 受保护工作区');
  await repository.addWorkspace(private);
  await repository.addItem(
    PasswordItem(
      title: 'QA Private',
      username: 'private@example.test',
      password: 'Synthetic-Private!',
      workspaceId: private.id,
    ),
  );
  AppLockState.markUnlocked();
  await repository.access.setPassword(private.id, 'qa-secret');
  runApp(app.KeyRingApp(repository: repository));
}
