import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'workspace_access_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'
    if (dart.library.io) 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../models/item_group.dart';
import '../models/password_item.dart';
import '../models/secret_field.dart';
import '../models/tombstone.dart';
import '../models/workspace.dart';

/// 同步/导入批次的应用结果统计。
class SyncApplyResult {
  const SyncApplyResult({
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.dropped = 0,
    this.deleted = 0,
  });

  final int added;
  final int updated;
  final int skipped;

  /// 因未知工作区/防御规则被拒收的条目数。
  final int dropped;

  /// 因墓碑（对端已删除）被跳过的条目数。
  final int deleted;

  int get touched => added + updated + deleted;
}

class ImportSnapshotChanged implements Exception {}

class PasswordRepository {
  /// [dbPathOverride] 仅供测试注入内存/临时数据库路径。
  PasswordRepository({
    String? dbPathOverride,
    WorkspaceCredentialStore? credentialStore,
  }) : _dbPathOverride = dbPathOverride,
       _credentialStore = credentialStore;
  final WorkspaceCredentialStore? _credentialStore;

  static const String _dbName = 'KeyRing.db';
  static const String _table = 'password_items';
  static const String _workspaceTable = 'workspaces';
  static const String _groupTable = 'item_groups';
  static const String _tombstoneTable = 'tombstones';
  static const int _dbVersion = 3;

  late final WorkspaceAccessService access = WorkspaceAccessService(
    persistProtection: _persistProtection,
    store: _credentialStore,
  );

  final String? _dbPathOverride;

  Database? _db;
  final ValueNotifier<List<PasswordItem>> itemsNotifier =
      ValueNotifier<List<PasswordItem>>(<PasswordItem>[]);
  final ValueNotifier<List<Workspace>> workspacesNotifier =
      ValueNotifier<List<Workspace>>(<Workspace>[]);
  final ValueNotifier<List<ItemGroup>> groupsNotifier =
      ValueNotifier<List<ItemGroup>>(<ItemGroup>[]);

  Future<void> init() async {
    final String dbPath = await _resolveDbPath();
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (Database db, int version) => _createSchema(db, version),
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await _upgradeToV2(db);
        }
        if (oldVersion < 3) await _createAccessTable(db);
      },
    );
    await _ensureDefaultWorkspace();
    final locks = await _db!.query('local_workspace_locks');
    access.initialize(locks.map((row) => row['workspaceId'] as String));
    await access.loadModes();
    await _reloadAll();
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_table (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        url TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        isFavorite INTEGER NOT NULL DEFAULT 0,
        workspaceId TEXT NOT NULL DEFAULT '',
        groupId TEXT,
        customFields TEXT
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${_table}_updatedAt ON $_table(updatedAt DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${_table}_workspace ON $_table(workspaceId)',
    );
    await _createWorkspaceTables(db);
    await _createAccessTable(db);
  }

  /// v1 → v2：项目首个结构迁移（调用前 main 已完成整库备份）。
  Future<void> _upgradeToV2(Database db) async {
    await db.execute(
      'ALTER TABLE $_table ADD COLUMN workspaceId TEXT NOT NULL DEFAULT \'\'',
    );
    await db.execute('ALTER TABLE $_table ADD COLUMN groupId TEXT');
    await db.execute('ALTER TABLE $_table ADD COLUMN customFields TEXT');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${_table}_workspace ON $_table(workspaceId)',
    );
    await _createWorkspaceTables(db);
    // 存量条目统一归入默认工作区（固定 id，跨设备收敛到同一归属）。
    await db.execute(
      'UPDATE $_table SET workspaceId = ? WHERE workspaceId = \'\'',
      <Object?>[Workspace.defaultId],
    );
  }

  Future<void> _createWorkspaceTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_workspaceTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT,
        syncPolicy TEXT NOT NULL DEFAULT 'full',
        sortWeight INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_groupTable (
        id TEXT PRIMARY KEY,
        workspaceId TEXT NOT NULL,
        name TEXT NOT NULL,
        sortWeight INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tombstoneTable (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'all',
        deletedAt TEXT NOT NULL
      );
    ''');
  }

  Future<void> _ensureDefaultWorkspace() async {
    await _db!.insert(
      _workspaceTable,
      Workspace(
        id: Workspace.defaultId,
        name: Workspace.defaultName,
        icon: Workspace.defaultIcon,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _createAccessTable(Database db) => db.execute(
    'CREATE TABLE IF NOT EXISTS local_workspace_locks (workspaceId TEXT PRIMARY KEY)',
  );

  Future<void> _persistProtection(String id, bool enabled) async {
    if (enabled) {
      await _db!.insert('local_workspace_locks', {
        'workspaceId': id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await _db!.delete(
        'local_workspace_locks',
        where: 'workspaceId = ?',
        whereArgs: [id],
      );
    }
    await refreshAutofill();
  }

  Future<void> refreshAutofill() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await const MethodChannel(
        'keyring/autofill',
      ).invokeMethod<void>('refresh', await databasePath());
    }
  }

  Future<void> dispose() async {
    access.dispose();
    await _db?.close();
  }

  // ---------------------------------------------------------------------------
  // 读取
  // ---------------------------------------------------------------------------

  Future<void> _reloadItems() async {
    final List<Map<String, Object?>> rows = await _db!.query(
      _table,
      orderBy: 'isFavorite DESC, datetime(updatedAt) DESC',
    );
    final List<PasswordItem> items = rows
        .map((Map<String, Object?> row) => PasswordItem.fromMap(row))
        .toList();
    itemsNotifier.value = items;
    await refreshAutofill();
  }

  Future<void> _reloadWorkspaces() async {
    final List<Map<String, Object?>> rows = await _db!.query(
      _workspaceTable,
      orderBy: 'sortWeight ASC, createdAt ASC',
    );
    workspacesNotifier.value = rows.map(Workspace.fromMap).toList();
  }

  Future<void> _reloadGroups() async {
    final List<Map<String, Object?>> rows = await _db!.query(
      _groupTable,
      orderBy: 'sortWeight ASC, createdAt ASC',
    );
    groupsNotifier.value = rows.map(ItemGroup.fromMap).toList();
  }

  Future<void> _reloadAll() async {
    await _reloadWorkspaces();
    await _reloadGroups();
    await _reloadItems();
  }

  Future<PasswordItem?> getByIdAsync(String id) async {
    final List<Map<String, Object?>> rows = await _db!.query(
      _table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return PasswordItem.fromMap(rows.first);
  }

  PasswordItem? getById(String id) {
    throw UnimplementedError('Use getByIdAsync for SQLite backend');
  }

  Future<int> itemCountInWorkspace(String workspaceId) async {
    final List<Map<String, Object?>> rows = await _db!.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE workspaceId = ?',
      <Object?>[workspaceId],
    );
    if (rows.isEmpty) return 0;
    final Object? c = rows.first['c'];
    return c is int ? c : int.tryParse(c?.toString() ?? '') ?? 0;
  }

  /// 检查账号名是否已存在（大小写不敏感）。给定 [workspaceId] 时唯一性
  /// 限定在该工作区内；省略时为全局唯一（兼容旧行为）。
  Future<bool> titleExists(
    String title, {
    String? workspaceId,
    String? exceptId,
  }) async {
    final List<String> where = <String>['LOWER(title) = LOWER(?)'];
    final List<Object?> args = <Object?>[title];
    if (workspaceId != null) {
      where.add('workspaceId = ?');
      args.add(workspaceId);
    }
    if (exceptId != null) {
      where.add('id != ?');
      args.add(exceptId);
    }
    final List<Map<String, Object?>> rows = await _db!.query(
      _table,
      columns: const <String>['id'],
      where: where.join(' AND '),
      whereArgs: args,
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // 条目写入
  // ---------------------------------------------------------------------------

  /// [PasswordItem.toMap] 是线格式（customFields 为数组），SQLite 需要
  /// 字符串列：入库前做一次行格式转换。
  Map<String, Object?> _toRow(PasswordItem item) {
    final Map<String, Object?> row = Map<String, Object?>.from(item.toMap());
    row['customFields'] = SecretField.toJsonColumn(item.customFields);
    if (row['workspaceId'] == null || (row['workspaceId'] as String).isEmpty) {
      row['workspaceId'] = Workspace.defaultId;
    }
    return row;
  }

  void _requireAccess(String id) {
    final workspaceId = id.isEmpty ? Workspace.defaultId : id;
    if (!access.canAccess(workspaceId)) throw StateError('请先解锁工作区');
  }

  void _requireItemAccess(PasswordItem item) {
    _requireAccess(item.workspaceId);
    for (final existing in itemsNotifier.value.where((x) => x.id == item.id)) {
      _requireAccess(existing.workspaceId);
    }
  }

  Future<void> addItem(PasswordItem item) async {
    _requireItemAccess(item);
    item.updatedAt = DateTime.now();
    await _db!.insert(
      _table,
      _toRow(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _reloadItems();
  }

  Future<void> updateItem(PasswordItem item) async {
    _requireItemAccess(item);
    item.updatedAt = DateTime.now();
    await _db!.update(
      _table,
      _toRow(item),
      where: 'id = ?',
      whereArgs: <Object?>[item.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _reloadItems();
  }

  Future<void> removeItem(String id) async {
    final item = await getByIdAsync(id);
    if (item != null) _requireItemAccess(item);
    await _db!.transaction((Transaction txn) async {
      await txn.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
      await _recordTombstone(
        txn,
        id,
        isWorkspace: false,
        scope: TombstoneScope.all,
      );
    });
    await _reloadItems();
  }

  /// 移动条目到目标工作区/分组。
  ///
  /// 移动进入对端「看不见」的工作区时，对端会残留旧副本：写墓碑让旧副本
  /// 在对端被删除（仅 id）。移回全同步工作区无需墓碑，下次同步 upsert 复活。
  Future<void> moveItem(
    String id,
    String workspaceId, {
    String? groupId,
  }) async {
    final PasswordItem? item = await getByIdAsync(id);
    if (item == null) return;
    _requireItemAccess(item);
    _requireAccess(workspaceId);
    final Workspace? source = _findWorkspace(item.workspaceId);
    final Workspace? dest = _findWorkspace(workspaceId);
    if (dest == null) return;

    final bool sourceVisibleToDesktop =
        source == null || source.syncPolicy.visibleTo('desktop');
    final bool destVisibleToDesktop = dest.syncPolicy.visibleTo('desktop');

    await _db!.transaction((Transaction txn) async {
      await txn.update(
        _table,
        <String, Object?>{
          'workspaceId': workspaceId,
          'groupId': groupId,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (sourceVisibleToDesktop && !destVisibleToDesktop) {
        await _recordTombstone(
          txn,
          id,
          isWorkspace: false,
          scope: dest.syncPolicy == SyncPolicy.localOnly
              ? TombstoneScope.all
              : TombstoneScope.desktopOnly,
        );
      }
    });
    await _reloadItems();
  }

  Workspace? _findWorkspace(String id) {
    for (final Workspace w in workspacesNotifier.value) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// Upsert an item coming from remote sync while preserving its timestamps.
  ///
  /// v1 兼容：进入条目未携带 workspaceId/customFields 时保留本地值
  /// （customFields 为空的判断无法区分「清空」与「未携带」，精确合并走
  /// [applyIncoming] 的线格式路径）。
  Future<void> upsertPreserveTimestamps(PasswordItem item) async {
    await _db!.transaction((Transaction txn) async {
      await _upsertItemPreserving(txn, item.toMap());
    });
    await _reloadItems();
  }

  Future<void> _upsertItemPreserving(
    DatabaseExecutor txn,
    Map<String, dynamic> raw,
  ) async {
    final Map<String, Object?>? localRow = await _findRowFor(
      txn,
      raw['id'] as String,
    );
    final PasswordItem merged = _mergeMissingColumns(raw, localRow);
    // 条目级路径（QR/OCR/旧导出解析后）无法区分「清空保密项」与「未携带」：
    // 空列表一律保留本地值，防止 v1 来源数据抹掉保密项。
    if (merged.customFields.isEmpty && localRow != null) {
      final PasswordItem local = PasswordItem.fromMap(localRow);
      if (local.customFields.isNotEmpty) {
        merged.customFields = local.customFields;
      }
    }
    await txn.insert(
      _table,
      _toRow(merged),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 查找本地行；不存在时返回 null（供字段保留合并取本地值）。
  Future<Map<String, Object?>?> _findRowFor(
    DatabaseExecutor txn,
    String id,
  ) async {
    final List<Map<String, Object?>> rows = await txn.query(
      _table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 字段保留合并：远端线格式缺失的 v2 新键，回落到本地行已有值。
  /// 防止 v1 旧端（必然缺键）的整行替换抹掉保密项与工作区归属。
  PasswordItem _mergeMissingColumns(
    Map<String, dynamic> raw,
    Map<String, Object?>? localRow,
  ) {
    final PasswordItem parsed = PasswordItem.fromMap(raw);
    if (localRow == null) {
      return parsed;
    }
    final PasswordItem local = PasswordItem.fromMap(localRow);

    return parsed.copyWith(
      // 远端未指定归属（或缺失键）时保留本地工作区/分组。
      workspaceId: parsed.workspaceId.isNotEmpty
          ? parsed.workspaceId
          : local.workspaceId,
      groupId: raw.containsKey('groupId') ? parsed.groupId : local.groupId,
      customFields:
          !raw.containsKey('customFields') && local.customFields.isNotEmpty
          ? local.customFields
          : parsed.customFields,
    );
  }

  /// 导入单条条目，保留条目自带的 createdAt/updatedAt。
  Future<void> importItem(PasswordItem item, {bool batch = false}) async {
    _requireItemAccess(item);
    await _db!.transaction((Transaction txn) async {
      await _upsertItemPreserving(txn, item.toMap());
    });
    if (!batch) {
      await _reloadItems();
    }
  }

  String importSnapshot(String workspaceId) => _importSnapshot(
    workspaceId,
    itemsNotifier.value,
    workspacesNotifier.value,
    groupsNotifier.value,
  );

  String _importSnapshot(
    String workspaceId,
    Iterable<PasswordItem> items,
    Iterable<Workspace> workspaces,
    Iterable<ItemGroup> groups,
  ) {
    List<Map<String, dynamic>> sorted(Iterable<Map<String, dynamic>> rows) =>
        rows.toList()
          ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              sorted(
                items
                    .where((x) => x.workspaceId == workspaceId)
                    .map((x) => x.toMap()),
              ),
              sorted(
                workspaces
                    .where((x) => x.id == workspaceId)
                    .map((x) => x.toMap()),
              ),
              sorted(
                groups
                    .where((x) => x.workspaceId == workspaceId)
                    .map((x) => x.toMap()),
              ),
            ]),
          ),
        )
        .toString();
  }

  /// Batch writes validate the preview against SQLite inside the same transaction.
  Future<int> importItems(
    Iterable<PasswordItem> items, {
    String? expectedWorkspaceId,
    String? expectedSnapshot,
  }) async {
    final list = items.toList();
    if (list.isEmpty) return 0;
    final generation = access.generation;
    await _db!.transaction((Transaction txn) async {
      if (expectedSnapshot != null && expectedWorkspaceId != null) {
        final ws = expectedWorkspaceId;
        final actual = _importSnapshot(
          ws,
          (await txn.query(
            _table,
            where: 'workspaceId = ?',
            whereArgs: [ws],
          )).map(PasswordItem.fromMap),
          (await txn.query(
            _workspaceTable,
            where: 'id = ?',
            whereArgs: [ws],
          )).map(Workspace.fromMap),
          (await txn.query(
            _groupTable,
            where: 'workspaceId = ?',
            whereArgs: [ws],
          )).map(ItemGroup.fromMap),
        );
        if (actual != expectedSnapshot) throw ImportSnapshotChanged();
      }
      for (final item in list) {
        _requireItemAccess(item);
        final existing = await txn.query(
          _table,
          where: 'id = ?',
          whereArgs: [item.id],
        );
        if (existing.isNotEmpty) {
          _requireAccess(existing.single['workspaceId'] as String);
        }
        await _upsertItemPreserving(txn, item.toMap());
      }
      if (generation != access.generation) throw StateError('工作区授权已失效');
      for (final item in list) {
        _requireItemAccess(item);
      }
    });
    await _reloadItems();
    return list.length;
  }

  // ---------------------------------------------------------------------------
  // 工作区 / 分组
  // ---------------------------------------------------------------------------

  Future<void> addWorkspace(Workspace workspace) async {
    await _db!.insert(
      _workspaceTable,
      workspace.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _reloadWorkspaces();
  }

  /// 更新工作区。策略收窄（full→mobileOnly / 任何→localOnly）会写工作区
  /// 墓碑，让已同步过该工作区的对端删除对应数据。
  Future<void> updateWorkspace(Workspace updated) async {
    _requireAccess(updated.id);
    final Workspace? old = _findWorkspace(updated.id);
    updated.updatedAt = DateTime.now();
    await _db!.transaction((Transaction txn) async {
      await txn.update(
        _workspaceTable,
        updated.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[updated.id],
      );
      if (old != null && old.syncPolicy != updated.syncPolicy) {
        final bool narrowed =
            old.syncPolicy == SyncPolicy.full ||
            updated.syncPolicy == SyncPolicy.localOnly;
        if (narrowed) {
          final TombstoneScope scope =
              updated.syncPolicy == SyncPolicy.mobileOnly
              ? TombstoneScope.desktopOnly
              : TombstoneScope.all;
          await _recordTombstone(
            txn,
            updated.id,
            isWorkspace: true,
            scope: scope,
          );
        }
      }
    });
    await _reloadWorkspaces();
  }

  /// 删除工作区（必须已清空条目）。墓碑 scope=all：所有对端一并删除。
  Future<void> deleteWorkspace(String id) async {
    _requireAccess(id);
    final int count = await itemCountInWorkspace(id);
    if (count > 0) {
      throw StateError('工作区内仍有 $count 个条目，请先移动或删除');
    }
    await _db!.transaction((Transaction txn) async {
      await txn.delete(
        _groupTable,
        where: 'workspaceId = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        _workspaceTable,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      await _recordTombstone(
        txn,
        id,
        isWorkspace: true,
        scope: TombstoneScope.all,
      );
    });
    await access.forgetDeletedWorkspace(id);
    await _reloadWorkspaces();
    await _reloadGroups();
  }

  Future<void> reorderWorkspaces(List<String> orderedIds) async {
    await _db!.transaction((Transaction txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update(
          _workspaceTable,
          <String, Object?>{'sortWeight': i},
          where: 'id = ?',
          whereArgs: <Object?>[orderedIds[i]],
        );
      }
    });
    await _reloadWorkspaces();
  }

  Future<ItemGroup> addGroup(String workspaceId, String name) async {
    _requireAccess(workspaceId);
    final ItemGroup group = ItemGroup(
      id: const Uuid().v4(),
      workspaceId: workspaceId,
      name: name,
    );
    await _db!.insert(
      _groupTable,
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _reloadGroups();
    return group;
  }

  Future<void> updateGroup(ItemGroup updated) async {
    _requireAccess(updated.workspaceId);
    updated.updatedAt = DateTime.now();
    await _db!.update(
      _groupTable,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[updated.id],
    );
    await _reloadGroups();
  }

  /// 删除分组：条目回落未分组，不产生墓碑（条目本身未被删除）。
  Future<void> deleteGroup(String id) async {
    final group = groupsNotifier.value.where((g) => g.id == id).firstOrNull;
    if (group != null) _requireAccess(group.workspaceId);
    await _db!.transaction((Transaction txn) async {
      await txn.update(
        _table,
        <String, Object?>{'groupId': null},
        where: 'groupId = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(_groupTable, where: 'id = ?', whereArgs: <Object?>[id]);
    });
    await _reloadGroups();
    await _reloadItems();
  }

  // ---------------------------------------------------------------------------
  // 墓碑
  // ---------------------------------------------------------------------------

  Future<void> _recordTombstone(
    DatabaseExecutor txn,
    String id, {
    required bool isWorkspace,
    required TombstoneScope scope,
  }) async {
    await txn.insert(_tombstoneTable, <String, Object?>{
      'id': id,
      'kind': isWorkspace ? 'workspace' : 'item',
      'scope': scope.wireName,
      'deletedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 取应发送给指定设备类的墓碑（发送侧过滤）。
  Future<List<Tombstone>> tombstonesFor(String deviceClass) async {
    await _deleteExpiredTombstones();
    final List<Map<String, Object?>> rows = await _db!.query(_tombstoneTable);
    return rows
        .map(Tombstone.fromMap)
        .where((Tombstone t) => t.scope.visibleTo(deviceClass))
        .toList();
  }

  Future<void> _deleteExpiredTombstones([DateTime? now]) async {
    final DateTime cutoff = (now ?? DateTime.now()).subtract(Tombstone.ttl);
    await _db!.delete(
      _tombstoneTable,
      where: 'datetime(deletedAt) < ?',
      whereArgs: <Object?>[cutoff.toIso8601String()],
    );
  }

  /// 本地是否存在比 [updatedAt] 更新的条目墓碑（对端旧副本防复活守卫）。
  Future<bool> _hasNewerTombstone(
    DatabaseExecutor txn,
    String id,
    DateTime updatedAt,
  ) async {
    final List<Map<String, Object?>> rows = await txn.query(
      _tombstoneTable,
      where: 'id = ? AND kind = ?',
      whereArgs: <Object?>[id, 'item'],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final Tombstone t = Tombstone.fromMap(rows.first);
    return t.deletedAt.isAfter(updatedAt);
  }

  Future<bool> _hasNewerWorkspaceTombstone(
    DatabaseExecutor txn,
    String id,
    DateTime updatedAt,
  ) async {
    final List<Map<String, Object?>> rows = await txn.query(
      _tombstoneTable,
      where: 'id = ? AND kind = ?',
      whereArgs: <Object?>[id, 'workspace'],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final Tombstone t = Tombstone.fromMap(rows.first);
    return t.deletedAt.isAfter(updatedAt);
  }

  // ---------------------------------------------------------------------------
  // 同步接收（统一入口：tombstone → 工作区 → 分组 → 条目）
  // ---------------------------------------------------------------------------

  /// 应用一批来自对端（同步或导入文件）的线格式数据。
  ///
  /// 顺序与防御规则（设计文档 §5）：
  /// 1. 先应用墓碑（删除优先于新增）；
  /// 2. 工作区 LWW upsert；本机为桌面端时拒收 mobile_only 定义（双侧执行）；
  /// 3. 分组 LWW upsert，只接受落在已知工作区的分组；
  /// 4. 条目：墓碑守卫 → 工作区归属校验（未知则丢弃）→ LWW →
  ///    缺键保留合并 → 落库。
  Future<SyncApplyResult> applyIncoming({
    List<Map<String, dynamic>> rawWorkspaces = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> rawGroups = const <Map<String, dynamic>>[],
    required List<Map<String, dynamic>> rawItems,
    List<Map<String, dynamic>> rawTombstones = const <Map<String, dynamic>>[],
    required String localDeviceClass,
  }) async {
    int added = 0;
    int updated = 0;
    int skipped = 0;
    int dropped = 0;
    int deleted = 0;

    await _db!.transaction((Transaction txn) async {
      // 1. 墓碑：删除优先。
      for (final Map<String, dynamic> raw in rawTombstones) {
        final Tombstone t = Tombstone.fromMap(raw);
        if (t.id.isEmpty) continue;
        if (t.isWorkspace) {
          await txn.delete(
            _groupTable,
            where: 'workspaceId = ?',
            whereArgs: <Object?>[t.id],
          );
          await txn.delete(
            _table,
            where: 'workspaceId = ?',
            whereArgs: <Object?>[t.id],
          );
          await txn.delete(
            _workspaceTable,
            where: 'id = ?',
            whereArgs: <Object?>[t.id],
          );
        } else {
          await txn.delete(_table, where: 'id = ?', whereArgs: <Object?>[t.id]);
        }
        // 记录到本地墓碑表，继续向其它对端传播（scope 原样保留）。
        await txn.insert(_tombstoneTable, <String, Object?>{
          'id': t.id,
          'kind': t.isWorkspace ? 'workspace' : 'item',
          'scope': t.scope.wireName,
          'deletedAt': t.deletedAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // 2. 工作区：LWW upsert；桌面端拒收 mobile_only（接收侧防御）。
      final Set<String> knownWorkspaceIds = <String>{
        for (final Map<String, Object?> row in await txn.query(_workspaceTable))
          row['id'].toString(),
      };
      for (final Map<String, dynamic> raw in rawWorkspaces) {
        final Workspace remote = Workspace.fromMap(raw);
        if (remote.id.isEmpty) continue;
        if (remote.syncPolicy == SyncPolicy.mobileOnly &&
            localDeviceClass == 'desktop') {
          continue;
        }
        final List<Map<String, Object?>> rows = await txn.query(
          _workspaceTable,
          where: 'id = ?',
          whereArgs: <Object?>[remote.id],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final Workspace local = Workspace.fromMap(rows.first);
          if (!remote.updatedAt.isAfter(local.updatedAt)) continue;
          if (await _hasNewerWorkspaceTombstone(
            txn,
            remote.id,
            remote.updatedAt,
          )) {
            continue;
          }
        }
        await txn.insert(
          _workspaceTable,
          remote.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        knownWorkspaceIds.add(remote.id);
      }

      // 3. 分组：只接受已知工作区内的分组，LWW upsert。
      for (final Map<String, dynamic> raw in rawGroups) {
        final ItemGroup remote = ItemGroup.fromMap(raw);
        if (remote.id.isEmpty || remote.workspaceId.isEmpty) continue;
        if (!knownWorkspaceIds.contains(remote.workspaceId)) continue;
        final List<Map<String, Object?>> rows = await txn.query(
          _groupTable,
          where: 'id = ?',
          whereArgs: <Object?>[remote.id],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final ItemGroup local = ItemGroup.fromMap(rows.first);
          if (!remote.updatedAt.isAfter(local.updatedAt)) continue;
        }
        await txn.insert(
          _groupTable,
          remote.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 4. 条目。
      final Set<String> knownGroupIds = <String>{
        for (final Map<String, Object?> row in await txn.query(_groupTable))
          row['id'].toString(),
      };
      for (final Map<String, dynamic> raw in rawItems) {
        final String? id = raw['id']?.toString();
        if (id == null || id.isEmpty) continue;

        if (await _hasNewerTombstone(
          txn,
          id,
          DateTime.tryParse(raw['updatedAt']?.toString() ?? '') ??
              DateTime.now(),
        )) {
          deleted++;
          continue;
        }

        final Map<String, Object?>? localRow = await _findRowFor(txn, id);
        final PasswordItem merged = _mergeMissingColumns(raw, localRow);

        // 工作区归属校验：未知工作区的条目直接拒收。
        if (!knownWorkspaceIds.contains(merged.workspaceId)) {
          dropped++;
          continue;
        }
        // 分组归属校验：未知分组回落未分组。
        if (merged.groupId != null && !knownGroupIds.contains(merged.groupId)) {
          merged.groupId = null;
        }

        if (localRow != null) {
          final PasswordItem local = PasswordItem.fromMap(localRow);
          if (!merged.updatedAt.isAfter(local.updatedAt)) {
            skipped++;
            continue;
          }
          updated++;
        } else {
          added++;
        }
        await txn.insert(
          _table,
          _toRow(merged),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    await _reloadAll();
    return SyncApplyResult(
      added: added,
      updated: updated,
      skipped: skipped,
      dropped: dropped,
      deleted: deleted,
    );
  }

  Future<String> _resolveDbPath() async {
    final String? override = _dbPathOverride;
    if (override != null) return override;
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, _dbName);
  }

  Future<String> databasePath() => _resolveDbPath();
}
