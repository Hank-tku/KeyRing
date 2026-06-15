// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/main.dart';
import 'package:key_ring/models/password_item.dart';
import 'package:key_ring/services/password_repository.dart';
import 'package:key_ring/screens/lock_screen.dart';
import 'package:key_ring/services/lan/sync_conflict_resolver.dart';
import 'package:key_ring/services/lan/sync_protocol_codec.dart';
import 'package:key_ring/utils/password_utils.dart';

void main() {
  group('KeyRing App Tests', () {
    testWidgets('App should build without errors', (WidgetTester tester) async {
      // 创建一个模拟的 repository
      final repository = MockPasswordRepository();
      await repository.init();

      await tester.pumpWidget(KeyRingApp(repository: repository));
      // 使用 pump() 而不是 pumpAndSettle() 避免生物识别检查导致的超时
      await tester.pump();

      // 验证应用能够正常构建
      expect(find.byType(MaterialApp), findsOneWidget);
      // 验证锁屏界面显示
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    test('Password item model should work correctly', () {
      final item = PasswordItem(
        title: 'Test App',
        username: 'testuser',
        password: 'testpass123',
        url: 'https://test.com',
        notes: 'Test notes',
        isFavorite: true,
      );

      // 验证基本属性
      expect(item.title, equals('Test App'));
      expect(item.username, equals('testuser'));
      expect(item.password, equals('testpass123'));
      expect(item.url, equals('https://test.com'));
      expect(item.notes, equals('Test notes'));
      expect(item.isFavorite, isTrue);
      expect(item.id, isNotEmpty);
      expect(item.createdAt, isNotNull);
      expect(item.updatedAt, isNotNull);

      // 测试 copyWith 方法
      final updatedItem = item.copyWith(
        title: 'Updated App',
        isFavorite: false,
      );
      expect(updatedItem.title, equals('Updated App'));
      expect(updatedItem.username, equals('testuser')); // 保持不变
      expect(updatedItem.isFavorite, isFalse);
      expect(updatedItem.id, equals(item.id)); // ID 保持不变

      // 测试 toMap 和 fromMap 方法
      final map = item.toMap();
      expect(map['title'], equals('Test App'));
      expect(map['username'], equals('testuser'));
      expect(map['password'], equals('testpass123'));
      expect(map['isFavorite'], equals(1));

      final restoredItem = PasswordItem.fromMap(map);
      expect(restoredItem.title, equals(item.title));
      expect(restoredItem.username, equals(item.username));
      expect(restoredItem.password, equals(item.password));
      expect(restoredItem.isFavorite, equals(item.isFavorite));
    });

    test(
      'Password generator should produce varied secure-looking passwords',
      () {
        final Set<String> generated = <String>{};

        for (int i = 0; i < 20; i++) {
          final String password = PasswordUtils.generatePassword(length: 16);
          generated.add(password);

          expect(password.length, equals(16));
          expect(password, matches(RegExp(r'[A-Z]')));
          expect(password, matches(RegExp(r'[a-z]')));
          expect(password, matches(RegExp(r'[0-9]')));
          expect(
            password,
            matches(RegExp(r'[!@#\$%^&*()_+\-=\[\]{}|;:,.<>?]')),
          );
        }

        expect(generated.length, greaterThan(1));
      },
    );

    test('Sync conflict resolver should add update or skip by timestamp', () {
      final SyncConflictResolver resolver = SyncConflictResolver();
      final DateTime base = DateTime.utc(2026, 1, 1);
      final PasswordItem local = PasswordItem(
        id: 'same-id',
        title: 'Local',
        username: 'local',
        password: 'local-pass',
        updatedAt: base,
      );

      final PasswordItem olderRemote = local.copyWith(
        title: 'Older',
        updatedAt: base.subtract(const Duration(minutes: 1)),
      );
      final PasswordItem newerRemote = local.copyWith(
        title: 'Newer',
        updatedAt: base.add(const Duration(minutes: 1)),
      );

      expect(
        resolver.resolve(remote: newerRemote, local: null),
        SyncResolution.add,
      );
      expect(
        resolver.resolve(remote: newerRemote, local: local),
        SyncResolution.update,
      );
      expect(
        resolver.resolve(remote: olderRemote, local: local),
        SyncResolution.skip,
      );
      expect(resolver.findLocal(<PasswordItem>[local], 'same-id'), local);
    });

    test('Sync protocol codec should encode versioned sync data', () {
      final SyncProtocolCodec codec = SyncProtocolCodec();
      final PasswordItem item = PasswordItem(
        id: 'sync-id',
        title: 'Sync App',
        username: 'sync-user',
        password: 'sync-pass',
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final Map<String, dynamic> message = codec.syncData(
        items: <PasswordItem>[item],
        vaultVersion: 1,
        timestamp: DateTime.fromMillisecondsSinceEpoch(123),
      );
      final SyncDataPayload payload = codec.readSyncData(message);

      expect(codec.messageType(message), SyncMessageType.syncData);
      expect(message['protocolVersion'], equals(1));
      expect(message['vaultVersion'], equals(1));
      expect(message['timestamp'], equals(123));
      expect(payload.isLegacyPeer, isFalse);
      expect(payload.items.single.id, equals('sync-id'));

      final SyncDataPayload legacyPayload = codec.readSyncData({
        'type': SyncMessageType.syncData,
        'items': <Map<String, dynamic>>[item.toMap()],
      });
      expect(legacyPayload.isLegacyPeer, isTrue);
    });
  });
}

// 模拟的 PasswordRepository 类
class MockPasswordRepository extends PasswordRepository {
  @override
  Future<void> init() async {
    // 模拟初始化
  }

  @override
  Future<void> dispose() async {
    // 模拟销毁
  }
}
