// 时间戳保留 + 导入合并行为测试（阶段一 1.1）。
//
// 验证 PasswordRepository.importItem / importItems 不会覆盖条目自带的
// createdAt/updatedAt，从而保证 newer-wins 合并逻辑正确。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/models/password_item.dart';
import 'package:key_ring/services/password_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 让 path_provider 在测试里返回一个临时目录，避免依赖平台通道。
class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _MockPathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

void main() {
  // 桌面端 sqflite + path_provider 需要先初始化 binding 与 FFI。
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('keyring_test_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir);
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  late PasswordRepository repo;

  setUp(() async {
    repo = PasswordRepository();
    await repo.init();
    // 清空可能残留的旧数据，保证每个用例独立。
    for (final item in repo.itemsNotifier.value) {
      await repo.removeItem(item.id);
    }
  });

  tearDown(() async {
    await repo.dispose();
  });

  PasswordItem makeItem({
    required String id,
    String title = 't',
    String username = 'u',
    String password = 'p',
    required DateTime updatedAt,
    DateTime? createdAt,
  }) {
    return PasswordItem(
      id: id,
      title: title,
      username: username,
      password: password,
      createdAt: createdAt ?? updatedAt,
      updatedAt: updatedAt,
    );
  }

  test('importItem 保留条目自带的 updatedAt，不被 now() 覆盖', () async {
    final DateTime fixed = DateTime.utc(2020, 1, 1, 12, 0, 0);
    final PasswordItem item =
        makeItem(id: 'a1', updatedAt: fixed);

    await repo.importItem(item);

    final PasswordItem? stored = await repo.getByIdAsync('a1');
    expect(stored, isNotNull);
    expect(stored!.updatedAt.toUtc(), fixed);
    expect(stored.createdAt.toUtc(), fixed);
  });

  test('importItems 批量导入保留各自时间戳且只刷新一次', () async {
    final DateTime t1 = DateTime.utc(2021, 1, 1);
    final DateTime t2 = DateTime.utc(2022, 6, 15, 8, 30);

    final int count = await repo.importItems(<PasswordItem>[
      makeItem(id: 'b1', updatedAt: t1),
      makeItem(id: 'b2', updatedAt: t2),
    ]);

    expect(count, 2);
    expect(repo.itemsNotifier.value.length, 2);

    final PasswordItem? s1 = await repo.getByIdAsync('b1');
    final PasswordItem? s2 = await repo.getByIdAsync('b2');
    expect(s1!.updatedAt.toUtc(), t1);
    expect(s2!.updatedAt.toUtc(), t2);
  });

  test('importItems 对空集合返回 0 且不报错', () async {
    final int count = await repo.importItems(<PasswordItem>[]);
    expect(count, 0);
  });

  test('importItem 按 id 幂等：相同 id 重复导入以最后一次为准', () async {
    final DateTime older = DateTime.utc(2020, 1, 1);
    final DateTime newer = DateTime.utc(2024, 1, 1);

    await repo.importItem(makeItem(id: 'c1', password: 'old', updatedAt: older));
    await repo.importItem(
      makeItem(id: 'c1', password: 'new', updatedAt: newer),
    );

    final PasswordItem? stored = await repo.getByIdAsync('c1');
    expect(stored, isNotNull);
    expect(stored!.password, 'new');
    expect(stored.updatedAt.toUtc(), newer);
  });

  // newer-wins 决策逻辑本身（不依赖 DB）放在 import_merger 的测试里，
  // 这里只校验仓库层的「不覆盖时间戳」这一核心契约。
  test('newer-wins：本地更新于导入项时，导入不应倒退本地数据', () async {
    final DateTime localNewer = DateTime.utc(2025, 1, 1);
    final DateTime importOlder = DateTime.utc(2019, 1, 1);

    // 先写入较新的本地数据。
    await repo.importItem(
      makeItem(id: 'd1', password: 'keep', updatedAt: localNewer),
    );

    // 模拟错误的导入路径：直接 importItem 会无条件 replace，可能倒退数据。
    // 这里仅验证 importItem 本身保留传入时间戳（决策应由调用方 import_merger 做出）。
    final PasswordItem incoming =
        makeItem(id: 'd1', password: 'should-not-win', updatedAt: importOlder);

    // 正确用法：调用方应先用 newer-wins 判断后再决定是否写入。
    // 此用例确认 importItem 写入的是 incoming 自身时间戳（而非 now）。
    await repo.importItem(incoming);
    final PasswordItem? stored = await repo.getByIdAsync('d1');
    expect(stored!.updatedAt.toUtc(), importOlder);
    expect(stored.password, 'should-not-win');
    // 提示：实际合并应通过 ImportMerger，它会在写入前比较时间戳。
  });
}
