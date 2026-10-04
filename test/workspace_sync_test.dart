// 工作区 / 选择性同步 / 保密项 核心行为测试（设计文档 §4-§5）。
//
// 覆盖：v1→v2 迁移回填、混版本字段保留合并、墓碑防复活与作用域、
// 接收侧防御（桌面端拒收 mobile_only）、策略收窄传播、发送侧墓碑过滤。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/models/password_item.dart';
import 'package:key_ring/models/secret_field.dart';
import 'package:key_ring/models/tombstone.dart';
import 'package:key_ring/models/workspace.dart';
import 'package:key_ring/services/password_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('keyring_ws_test_');
  });

  tearDown(() async {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String dbPath(String name) =>
      '${tempDir.path}${Platform.pathSeparator}$name.db';

  Future<PasswordRepository> openRepo(String name) async {
    final PasswordRepository repo = PasswordRepository(dbPathOverride: dbPath(name));
    await repo.init();
    return repo;
  }

  PasswordItem item(String id, {String? workspaceId, DateTime? updatedAt}) {
    return PasswordItem(
      id: id,
      title: 'T-$id',
      username: 'u',
      password: 'p',
      workspaceId: workspaceId ?? '',
      updatedAt: updatedAt,
    );
  }

  group('v1 → v2 迁移', () {
    test('存量条目回填默认工作区，新表就绪', () async {
      final String path = dbPath('migrate');

      // 手工构造 v1 库：旧 schema + 两条存量数据。
      final Database v1 = await openDatabase(
        path,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE password_items (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              username TEXT NOT NULL,
              password TEXT NOT NULL,
              url TEXT,
              notes TEXT,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL,
              isFavorite INTEGER NOT NULL DEFAULT 0
            );
          ''');
        },
      );
      final String t = DateTime.now().toIso8601String();
      await v1.insert('password_items', <String, Object?>{
        'id': 'old-1',
        'title': 'Old',
        'username': 'u',
        'password': 'p',
        'url': null,
        'notes': null,
        'createdAt': t,
        'updatedAt': t,
        'isFavorite': 0,
      });
      await v1.close();

      final PasswordRepository repo = PasswordRepository(dbPathOverride: path);
      await repo.init();

      expect(repo.workspacesNotifier.value, isNotEmpty);
      expect(
        repo.workspacesNotifier.value.any(
          (Workspace w) => w.id == Workspace.defaultId,
        ),
        isTrue,
        reason: '默认工作区应被创建',
      );
      final PasswordItem? migrated = await repo.getByIdAsync('old-1');
      expect(migrated, isNotNull);
      expect(migrated!.workspaceId, Workspace.defaultId);
      expect(migrated.customFields, isEmpty);
      await repo.dispose();
    });

    test('全新安装直接建 v2 schema', () async {
      final PasswordRepository repo = await openRepo('fresh');
      expect(
        repo.workspacesNotifier.value.any(
          (Workspace w) => w.id == Workspace.defaultId,
        ),
        isTrue,
      );
      expect(repo.itemsNotifier.value, isEmpty);
      await repo.dispose();
    });
  });

  group('混版本字段保留合并（§5.4 防数据丢失）', () {
    test('v1 对端条目缺新键时不抹掉本地保密项与归属', () async {
      final PasswordRepository repo = await openRepo('merge');
      addTearDown(() => repo.dispose());

      final DateTime t0 = DateTime.utc(2026, 1, 1);
      await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[
          PasswordItem(
            id: 'x1',
            title: 'X',
            username: 'u',
            password: 'p',
            workspaceId: Workspace.defaultId,
            updatedAt: t0,
            customFields: <SecretField>[
              SecretField(label: '安全码', value: '9', protected: true),
            ],
          ).toMap(),
        ],
        localDeviceClass: 'mobile',
      );

      // v1 旧端发来的同 id 条目：改了标题（时间更新），但缺全部 v2 新键。
      final SyncApplyResult result = await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'x1',
            'title': 'X-edited-on-v1',
            'username': 'u',
            'password': 'p',
            'createdAt': t0.toIso8601String(),
            'updatedAt':
                DateTime.utc(2026, 6, 1).toIso8601String(),
            'isFavorite': 0,
          },
        ],
        localDeviceClass: 'mobile',
      );

      expect(result.updated, 1);
      final PasswordItem? storedNullable = await repo.getByIdAsync('x1');
      expect(storedNullable, isNotNull);
      final PasswordItem stored = storedNullable!;
      expect(stored.title, 'X-edited-on-v1');
      expect(stored.workspaceId, Workspace.defaultId, reason: '归属应保留');
      expect(
        stored.customFields.single.label,
        '安全码',
        reason: '保密项不应被整行替换抹掉',
      );
    });

    test('v2 对端显式携带空保密项时按新值覆盖（用户清空语义）', () async {
      final PasswordRepository repo = await openRepo('merge-v2');
      addTearDown(() => repo.dispose());

      final DateTime t0 = DateTime.utc(2026, 1, 1);
      final Map<String, dynamic> withField = PasswordItem(
        id: 'y1',
        title: 'Y',
        username: 'u',
        password: 'p',
        workspaceId: Workspace.defaultId,
        updatedAt: t0,
        customFields: <SecretField>[SecretField(label: '安全码', value: '1')],
      ).toMap();
      await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[withField],
        localDeviceClass: 'mobile',
      );

      // v2 端显式携带空 customFields（键存在、值为空数组）且时间更新。
      final Map<String, dynamic> cleared = PasswordItem(
        id: 'y1',
        title: 'Y',
        username: 'u',
        password: 'p',
        workspaceId: Workspace.defaultId,
        updatedAt: DateTime.utc(2026, 6, 1),
      ).toMap();
      await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[cleared],
        localDeviceClass: 'mobile',
      );

      expect((await repo.getByIdAsync('y1'))!.customFields, isEmpty);
    });
  });

  group('墓碑（§5.5 删除传播）', () {
    test('removeItem 写墓碑：旧副本同步进来被拒绝，新副本放行', () async {
      final PasswordRepository repo = await openRepo('tomb');
      addTearDown(() => repo.dispose());

      await repo.addItem(item('a', workspaceId: Workspace.defaultId));
      await repo.removeItem('a');

      // 对端残留旧副本（updatedAt 早于删除）：拒绝复活。
      final SyncApplyResult stale = await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[
          item(
            'a',
            workspaceId: Workspace.defaultId,
            updatedAt: DateTime.now().subtract(const Duration(days: 1)),
          ).toMap(),
        ],
        localDeviceClass: 'mobile',
      );
      expect(stale.deleted, 1);
      expect(await repo.getByIdAsync('a'), isNull);

      // 更新的重新添加（updatedAt 晚于删除）：允许复活。
      final SyncApplyResult fresh = await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[
          item(
            'a',
            workspaceId: Workspace.defaultId,
            updatedAt: DateTime.now().add(const Duration(hours: 1)),
          ).toMap(),
        ],
        localDeviceClass: 'mobile',
      );
      expect(fresh.added, 1);
      expect(await repo.getByIdAsync('a'), isNotNull);
    });

    test('策略收窄 full→mobileOnly 产生 desktopOnly 工作区墓碑', () async {
      final PasswordRepository repo = await openRepo('narrow');
      addTearDown(() => repo.dispose());

      final Workspace ws = Workspace(name: '工作');
      await repo.addWorkspace(ws);

      final List<Tombstone> forDesktop = await repo.tombstonesFor('desktop');
      expect(
        forDesktop.where((Tombstone t) => t.id == ws.id),
        isEmpty,
        reason: '未收窄前不应有墓碑',
      );

      await repo.updateWorkspace(ws.copyWith(syncPolicy: SyncPolicy.mobileOnly));

      final List<Tombstone> desktopAfter = await repo.tombstonesFor('desktop');
      final Tombstone? wsTombstone = desktopAfter
          .where((Tombstone t) => t.id == ws.id)
          .firstOrNull;
      expect(wsTombstone, isNotNull);
      expect(wsTombstone!.isWorkspace, isTrue);
      expect(wsTombstone.scope, TombstoneScope.desktopOnly);

      // 移动端对端不应收到该墓碑（它们仍可见该工作区）。
      final List<Tombstone> mobileAfter = await repo.tombstonesFor('mobile');
      expect(mobileAfter.where((Tombstone t) => t.id == ws.id), isEmpty);
    });

    test('条目移入 mobileOnly 工作区：对桌面端表现为删除', () async {
      final PasswordRepository repo = await openRepo('move');
      addTearDown(() => repo.dispose());

      final Workspace hidden = Workspace(name: '高隐私', syncPolicy: SyncPolicy.mobileOnly);
      await repo.addWorkspace(hidden);

      final PasswordItem it = item('m1', workspaceId: Workspace.defaultId);
      await repo.addItem(it);

      await repo.moveItem('m1', hidden.id);

      expect((await repo.getByIdAsync('m1'))!.workspaceId, hidden.id);
      final List<Tombstone> forDesktop = await repo.tombstonesFor('desktop');
      expect(
        forDesktop.any((Tombstone t) => t.id == 'm1' && !t.isWorkspace),
        isTrue,
        reason: '桌面端应收到条目删除指令',
      );
      final List<Tombstone> forMobile = await repo.tombstonesFor('mobile');
      expect(forMobile.any((Tombstone t) => t.id == 'm1'), isFalse);
    });

    test('工作区墓碑到达时连带删除分组与条目', () async {
      final PasswordRepository receiver = await openRepo('ws-tomb-recv');
      addTearDown(() => receiver.dispose());

      final Workspace ws = Workspace(id: 'ws-x', name: '工作');
      await receiver.addWorkspace(ws);
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      await receiver.applyIncoming(
        rawWorkspaces: <Map<String, dynamic>>[ws.toMap()],
        rawGroups: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'g1',
            'workspaceId': 'ws-x',
            'name': '开发',
            'sortWeight': 0,
            'createdAt': t0.toIso8601String(),
            'updatedAt': t0.toIso8601String(),
          },
        ],
        rawItems: <Map<String, dynamic>>[
          item('i1', workspaceId: 'ws-x', updatedAt: t0).toMap(),
        ],
        localDeviceClass: 'mobile',
      );
      expect(receiver.groupsNotifier.value, isNotEmpty);

      // 对端删除了整个工作区。
      await receiver.applyIncoming(
        rawItems: const <Map<String, dynamic>>[],
        rawTombstones: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'ws-x',
            'kind': 'workspace',
            'scope': 'all',
            'deletedAt': DateTime.now().toIso8601String(),
          },
        ],
        localDeviceClass: 'mobile',
      );

      expect(
        receiver.workspacesNotifier.value.any((Workspace w) => w.id == 'ws-x'),
        isFalse,
      );
      expect(receiver.groupsNotifier.value, isEmpty);
      expect(await receiver.getByIdAsync('i1'), isNull);
    });
  });

  group('接收侧防御（§5.3 双侧执行）', () {
    test('桌面端拒收 mobile_only 工作区定义与其条目', () async {
      final PasswordRepository desktop = await openRepo('desktop-defense');
      addTearDown(() => desktop.dispose());

      final DateTime t0 = DateTime.utc(2026, 1, 1);
      final SyncApplyResult result = await desktop.applyIncoming(
        rawWorkspaces: <Map<String, dynamic>>[
          Workspace(
            id: 'ws-secret',
            name: '高隐私',
            syncPolicy: SyncPolicy.mobileOnly,
          ).copyWith(updatedAt: t0).toMap(),
        ],
        rawItems: <Map<String, dynamic>>[
          item('s1', workspaceId: 'ws-secret', updatedAt: t0).toMap(),
        ],
        localDeviceClass: 'desktop',
      );

      expect(
        desktop.workspacesNotifier.value.any((Workspace w) => w.id == 'ws-secret'),
        isFalse,
        reason: '桌面端不得接收 mobileOnly 工作区定义（连名称都不能出现）',
      );
      expect(await desktop.getByIdAsync('s1'), isNull);
      expect(result.dropped, 1);
    });

    test('未知工作区的条目被拒收并计数', () async {
      final PasswordRepository repo = await openRepo('unknown-ws');
      addTearDown(() => repo.dispose());

      final SyncApplyResult result = await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[
          item('u1', workspaceId: 'ws-nope', updatedAt: DateTime.now()).toMap(),
        ],
        localDeviceClass: 'mobile',
      );
      expect(result.dropped, 1);
      expect(await repo.getByIdAsync('u1'), isNull);
    });
  });

  group('SyncPolicy 可见性（发送侧过滤的判定核心）', () {
    test('visibleTo 矩阵', () {
      expect(SyncPolicy.full.visibleTo('mobile'), isTrue);
      expect(SyncPolicy.full.visibleTo('desktop'), isTrue);
      expect(SyncPolicy.mobileOnly.visibleTo('mobile'), isTrue);
      expect(SyncPolicy.mobileOnly.visibleTo('desktop'), isFalse);
      expect(SyncPolicy.localOnly.visibleTo('mobile'), isFalse);
      expect(SyncPolicy.localOnly.visibleTo('desktop'), isFalse);
    });

    test('wire 序列化往返', () {
      for (final SyncPolicy p in SyncPolicy.values) {
        expect(SyncPolicy.fromWire(p.wireName), p);
      }
      expect(SyncPolicy.fromWire(null), SyncPolicy.full);
      expect(SyncPolicy.fromWire('garbage'), SyncPolicy.full);
    });
  });

  group('保密项模型', () {
    test('JSON 列往返与坏数据容错', () {
      final List<SecretField> fields = <SecretField>[
        SecretField(label: '安全码', value: '123', type: SecretFieldType.password, protected: true),
        SecretField(label: '客户号', value: 'C88'),
      ];
      final String encoded = SecretField.toJsonColumn(fields);
      final List<SecretField> decoded = SecretField.fromJsonColumn(encoded);
      expect(decoded.length, 2);
      expect(decoded.first.label, '安全码');
      expect(decoded.first.type, SecretFieldType.password);
      expect(decoded.first.protected, isTrue);

      expect(SecretField.fromJsonColumn(null), isEmpty);
      expect(SecretField.fromJsonColumn('not-json'), isEmpty);
      expect(SecretField.fromJsonColumn('{"a":1}'), isEmpty);
    });

    test('PasswordItem.toMap/fromMap 往返（数组形态与字符串形态）', () {
      final PasswordItem it = PasswordItem(
        id: 'f1',
        title: 'T',
        username: 'u',
        password: 'p',
        workspaceId: 'ws-1',
        groupId: 'g-1',
        customFields: <SecretField>[SecretField(label: '安全码', value: '9')],
      );
      final Map<String, dynamic> wire = it.toMap();
      expect(wire['customFields'], isA<List<dynamic>>());
      expect(PasswordItem.fromMap(wire).customFields.single.label, '安全码');

      // SQLite 行形态：customFields 是 JSON 字符串。
      final Map<String, dynamic> row = Map<String, dynamic>.from(wire)
        ..['customFields'] = SecretField.toJsonColumn(it.customFields);
      expect(PasswordItem.fromMap(row).customFields.single.value, '9');

      // v1 旧数据形态：缺全部新键。
      final Map<String, dynamic> legacy = Map<String, dynamic>.from(wire)
        ..remove('customFields')
        ..remove('workspaceId')
        ..remove('groupId');
      final PasswordItem legacyItem = PasswordItem.fromMap(legacy);
      expect(legacyItem.customFields, isEmpty);
      expect(legacyItem.workspaceId, isEmpty);
    });
  });

  group('工作区删除约束', () {
    test('非空工作区不可删除，清空后可删除', () async {
      final PasswordRepository repo = await openRepo('ws-del');
      addTearDown(() => repo.dispose());

      final Workspace ws = Workspace(name: '临时');
      await repo.addWorkspace(ws);
      await repo.addItem(item('d1', workspaceId: ws.id));

      expect(() => repo.deleteWorkspace(ws.id), throwsStateError);

      await repo.removeItem('d1');
      await repo.deleteWorkspace(ws.id);
      expect(
        repo.workspacesNotifier.value.any((Workspace w) => w.id == ws.id),
        isFalse,
      );
    });
  });

  group('LWW 与工作区内唯一性', () {
    test('applyIncoming 遵循条目级 newer-wins', () async {
      final PasswordRepository repo = await openRepo('lww');
      addTearDown(() => repo.dispose());

      final DateTime t0 = DateTime.utc(2026, 1, 1);
      await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[
          item('n1', workspaceId: Workspace.defaultId, updatedAt: t0).toMap(),
        ],
        localDeviceClass: 'mobile',
      );

      // 更旧：跳过。
      final SyncApplyResult older = await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[
          item(
            'n1',
            workspaceId: Workspace.defaultId,
            updatedAt: t0.subtract(const Duration(days: 1)),
          ).toMap(),
        ],
        localDeviceClass: 'mobile',
      );
      expect(older.skipped, 1);

      // 更新：覆盖。
      final SyncApplyResult newer = await repo.applyIncoming(
        rawItems: <Map<String, dynamic>>[
          item(
            'n1',
            workspaceId: Workspace.defaultId,
            updatedAt: t0.add(const Duration(days: 1)),
          ).toMap(),
        ],
        localDeviceClass: 'mobile',
      );
      expect(newer.updated, 1);
    });

    test('titleExists 默认工作区内唯一、跨工作区允许同名', () async {
      final PasswordRepository repo = await openRepo('title');
      addTearDown(() => repo.dispose());

      final Workspace other = Workspace(name: '另一个');
      await repo.addWorkspace(other);

      final PasswordItem a = item('t1', workspaceId: Workspace.defaultId)
        ..title = 'GitHub';
      await repo.addItem(a);

      expect(
        await repo.titleExists('github', workspaceId: Workspace.defaultId),
        isTrue,
        reason: '大小写不敏感',
      );
      expect(
        await repo.titleExists(
          'GitHub',
          workspaceId: other.id,
        ),
        isFalse,
        reason: '跨工作区允许同名',
      );
      expect(
        await repo.titleExists(
          'GitHub',
          workspaceId: Workspace.defaultId,
          exceptId: 't1',
        ),
        isFalse,
        reason: '排除自身',
      );
    });
  });
}
