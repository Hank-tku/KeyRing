// Chrome CSV 导入模块测试。
//
// 覆盖：解析（BOM/CRLF/LF/引号转义/字段内换行/数字形态密码逐字保留/note与notes/
// 名称缺失/空用户名）、保守网址规范化、同站多账号、重复导入、冲突默认保留本地、
// 更新保留字段（ID/收藏/分组/保密项/来源缺失备注）、多条匹配必须明确选择、
// 缺列/畸形行、提交前仓库变化（stale）。全部使用合成数据。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/models/item_group.dart';
import 'package:key_ring/models/password_item.dart';
import 'package:key_ring/models/secret_field.dart';
import 'package:key_ring/models/workspace.dart';
import 'package:key_ring/services/chrome_csv_import_service.dart';
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
    tempDir = Directory.systemTemp.createTempSync('keyring_chrome_csv_test_');
  });

  tearDown(() async {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<PasswordRepository> openRepo(String name) async {
    final PasswordRepository repo = PasswordRepository(
      dbPathOverride: '${tempDir.path}${Platform.pathSeparator}$name.db',
    );
    await repo.init();
    return repo;
  }

  String buildCsv(List<String> rows, {bool bom = true, String eol = '\r\n'}) =>
      (bom ? '﻿' : '') + rows.join(eol) + eol;

  const String ws = Workspace.defaultId;

  group('解析', () {
    test('标准 Chrome 导出：BOM + CRLF + note 列，引号内逗号与转义引号', () {
      final ChromeCsvImportService service = ChromeCsvImportService(
        repository: PasswordRepository(),
      );
      final ChromeCsvParseResult r = service.parseCsv(buildCsv(<String>[
        'name,url,username,password,note',
        'GitHub,https://github.com,alice@example.com,"p,ass""word",backup code 123',
      ]));

      expect(r.isOk, isTrue, reason: r.headerError);
      expect(r.errors, isEmpty);
      expect(r.entries, hasLength(1));
      final ChromeCsvEntry e = r.entries.single;
      expect(e.name, 'GitHub');
      expect(e.url, 'https://github.com');
      expect(e.username, 'alice@example.com');
      expect(e.password, 'p,ass"word');
      expect(e.note, 'backup code 123');
      expect(e.desiredTitle, 'GitHub');
    });

    test('特殊字符与多行备注：字段内换行、密码逐字保留（含 CRLF 与引号）', () {
      final ChromeCsvImportService service = ChromeCsvImportService(
        repository: PasswordRepository(),
      );
      final ChromeCsvParseResult r = service.parseCsv(buildCsv(<String>[
        'name,url,username,password,note',
        '"Site ""A"", inc",https://x.com,u1,"p1,\r\n""q""","n1\r\nn2"',
        'Digits,https://d.com,u2,0731,',
      ]));

      expect(r.isOk, isTrue);
      expect(r.errors, isEmpty);
      expect(r.entries, hasLength(2));
      final ChromeCsvEntry a = r.entries[0];
      expect(a.name, 'Site "A", inc');
      // 密码逐字保留：内部 CRLF 与引号原样，不 trim。
      expect(a.password, 'p1,\r\n"q"');
      // 备注内部换行统一为 \n。
      expect(a.note, 'n1\nn2');
      // 未加引号的数字形态密码保持字符串原样（前导零不丢）。
      expect(r.entries[1].password, '0731');
      expect(r.entries[1].password, isA<String>());
    });

    test('LF 行尾（手工编辑文件）同样可解析', () {
      final ChromeCsvImportService service = ChromeCsvImportService(
        repository: PasswordRepository(),
      );
      final ChromeCsvParseResult r = service.parseCsv(buildCsv(<String>[
        'name,url,username,password',
        'GitHub,https://github.com,alice,pw',
      ], eol: '\n'));

      expect(r.isOk, isTrue);
      expect(r.entries.single.password, 'pw');
    });

    test('名称缺失按网址主机生成标题；空用户名合法', () {
      final ChromeCsvImportService service = ChromeCsvImportService(
        repository: PasswordRepository(),
      );
      final ChromeCsvParseResult r = service.parseCsv(buildCsv(<String>[
        'name,url,username,password,note',
        ',https://example.com/login,,pw,',
      ]));

      expect(r.entries.single.name, isEmpty);
      expect(r.entries.single.username, isEmpty);
      expect(r.entries.single.desiredTitle, 'example.com');
    });

    test('note 与 notes 列名均可识别', () {
      final ChromeCsvImportService service = ChromeCsvImportService(
        repository: PasswordRepository(),
      );
      for (final String noteCol in <String>['note', 'notes']) {
        final ChromeCsvParseResult r = service.parseCsv(buildCsv(<String>[
          'name,url,username,password,$noteCol',
          'A,https://a.com,u,p,n',
        ]));
        expect(r.isOk, isTrue, reason: noteCol);
        expect(r.entries.single.note, 'n');
      }
    });

    test('缺必需列：整文件错误并列出缺失列名', () {
      final ChromeCsvImportService service = ChromeCsvImportService(
        repository: PasswordRepository(),
      );
      final ChromeCsvParseResult r = service.parseCsv(buildCsv(<String>[
        'name,url,username',
        'A,https://a.com,u',
      ]));

      expect(r.isOk, isFalse);
      expect(r.entries, isEmpty);
      expect(r.headerError, contains('password'));
    });

    test('畸形行（字段数不符）计入错误且不影响有效行', () {
      final ChromeCsvImportService service = ChromeCsvImportService(
        repository: PasswordRepository(),
      );
      final ChromeCsvParseResult r = service.parseCsv(buildCsv(<String>[
        'name,url,username,password,note',
        'A,https://a.com,u,p,n',
        'B,https://b.com,u',
        'C,https://c.com,u2,p2,',
      ]));

      expect(r.entries, hasLength(2));
      expect(r.errors, hasLength(1));
      expect(r.errors.single.sourceRow, 2);
      expect(r.errors.single.reason, contains('字段数'));
      expect(r.entries.last.name, 'C');
    });

    test('空文件与全空行', () {
      final ChromeCsvImportService service = ChromeCsvImportService(
        repository: PasswordRepository(),
      );
      expect(service.parseCsv('').headerError, isNotNull);
      expect(service.parseCsv('﻿').headerError, isNotNull);
      final ChromeCsvParseResult r = service.parseCsv(buildCsv(<String>[
        'name,url,username,password,note',
        ',,,,',
        ',,,,"仅备注非空"',
        'A,https://a.com,u,p,',
      ]));
      // 全空行视为空行静默跳过；仅备注非空的行记「均为空」错误。
      expect(r.entries, hasLength(1));
      expect(r.errors.single.sourceRow, 2);
      expect(r.errors.single.reason, contains('均为空'));
    });
  });

  group('网址保守规范化', () {
    test('尾斜杠/片段/默认端口/大小写归一；www 与协议差异不合并；查询串保留', () {
      const String a = 'https://example.com';
      expect(
        ChromeCsvImportService.normalizeUrlForMatch('https://example.com/'),
        a,
      );
      expect(
        ChromeCsvImportService.normalizeUrlForMatch('https://EXAMPLE.com'),
        a,
      );
      expect(
        ChromeCsvImportService.normalizeUrlForMatch('https://example.com#x'),
        a,
      );
      expect(
        ChromeCsvImportService.normalizeUrlForMatch('https://example.com:443'),
        a,
      );
      // 裸域补 https 后归一。
      expect(ChromeCsvImportService.normalizeUrlForMatch('example.com'), a);

      expect(
        ChromeCsvImportService.normalizeUrlForMatch('https://www.example.com'),
        isNot(a),
      );
      expect(
        ChromeCsvImportService.normalizeUrlForMatch('http://example.com'),
        isNot(a),
      );

      expect(
        ChromeCsvImportService.normalizeUrlForMatch('https://example.com/a?b=1'),
        'https://example.com/a?b=1',
      );
      expect(
        ChromeCsvImportService.normalizeUrlForMatch('https://example.com:8443'),
        'https://example.com:8443',
      );
      expect(ChromeCsvImportService.normalizeUrlForMatch(''), isEmpty);
    });
  });

  group('预览与匹配', () {
    test('同站多账号互不冲突，标题在工作区内唯一', () async {
      final PasswordRepository repo = await openRepo('multi-account');
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);

      final String csv = buildCsv(<String>[
        'name,url,username,password,note',
        'Example,https://example.com,alice@example.com,pw1,',
        'Example,https://example.com,bob@example.com,pw2,',
      ]);
      final ChromeImportPreview preview = service.buildPreview(
        csvContent: csv,
        workspaceId: ws,
      );

      expect(preview.rows, hasLength(2));
      expect(preview.createCount, 2);
      expect(preview.rows[0].resolvedTitle, 'Example');
      expect(preview.rows[1].resolvedTitle, 'Example (bob@example.com)');

      final ChromeImportCommitResult result = await service.commit(preview);
      expect(result.added, 2);
      final List<PasswordItem> saved = repo.itemsNotifier.value;
      expect(
        saved.map((PasswordItem it) => it.title).toSet(),
        <String>{'Example', 'Example (bob@example.com)'},
      );
      await repo.dispose();
    });

    test('匹配范围与规范化：尾斜杠匹配、www/协议差异不匹配、用户名大小写区分', () async {
      final PasswordRepository repo = await openRepo('match-scope');
      await repo.addItem(PasswordItem(
        title: 'Site',
        username: 'Alice',
        password: 'pw',
        url: 'https://example.com/',
        workspaceId: ws,
      ));
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);

      // 用户名大小写不同可能表示不同账号，不能合并。
      final ChromeImportPreview p1 = service.buildPreview(
        csvContent: buildCsv(<String>[
          'name,url,username,password',
          'Site,https://example.com,alice,pw',
        ]),
        workspaceId: ws,
      );
      expect(p1.rows.single.kind, ChromeImportKind.create);

      // www 与 http 视为不同站点（保守，不合并）。
      final ChromeImportPreview p2 = service.buildPreview(
        csvContent: buildCsv(<String>[
          'name,url,username,password',
          'Site,https://www.example.com,alice,pw',
          'Site2,http://example.com,alice,pw',
        ]),
        workspaceId: ws,
      );
      expect(
        p2.rows
            .every((ChromeImportRow r) => r.kind == ChromeImportKind.create),
        isTrue,
      );
      await repo.dispose();
    });

    test('空用户名与本地空用户名条目匹配', () async {
      final PasswordRepository repo = await openRepo('empty-username');
      await repo.addItem(PasswordItem(
        title: 'NoName',
        username: '',
        password: 'pw',
        url: 'https://a.com',
        workspaceId: ws,
      ));
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);

      final ChromeImportPreview preview = service.buildPreview(
        csvContent: buildCsv(<String>[
          'name,url,username,password',
          'NoName,https://a.com,,pw',
        ]),
        workspaceId: ws,
      );
      expect(preview.rows.single.kind, ChromeImportKind.identical);
      await repo.dispose();
    });

    test('重复导入：第二次预览全部「完全相同」，提交零写入', () async {
      final PasswordRepository repo = await openRepo('re-import');
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);
      final String csv = buildCsv(<String>[
        'name,url,username,password,note',
        'GitHub,https://github.com,alice@example.com,pw,note1',
      ]);

      final ChromeImportPreview first = service.buildPreview(
        csvContent: csv,
        workspaceId: ws,
      );
      final ChromeImportCommitResult r1 = await service.commit(first);
      expect(r1.added, 1);

      final ChromeImportPreview second = service.buildPreview(
        csvContent: csv,
        workspaceId: ws,
      );
      expect(second.identicalCount, 1);
      expect(second.createCount, 0);
      final ChromeImportCommitResult r2 = await service.commit(second);
      expect(r2.added, 0);
      expect(r2.updated, 0);
      expect(r2.skipped, 1);
      expect(repo.itemsNotifier.value, hasLength(1));
      await repo.dispose();
    });
  });

  group('冲突与更新', () {
    Future<PasswordRepository> seedConflictRepo(String name) async {
      final PasswordRepository repo = await openRepo(name);
      await repo.addGroup(ws, '银行');
      final ItemGroup seededGroup = repo.groupsNotifier.value
          .singleWhere((ItemGroup g) => g.workspaceId == ws);
      await repo.addItem(PasswordItem(
        id: 'local-1',
        title: '旧银行',
        username: 'alice',
        password: 'old-pw',
        url: 'https://bank.com/login',
        notes: '本地备注',
        isFavorite: true,
        workspaceId: ws,
        groupId: seededGroup.id,
        customFields: <SecretField>[
          SecretField(label: 'PIN', value: '99'),
        ],
      ));
      return repo;
    }

    const String conflictCsvHeader = 'name,url,username,password,note';

    test('默认保留本地：提交零写入，本地条目不变', () async {
      final PasswordRepository repo = await seedConflictRepo('keep-local');
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);
      final ChromeImportPreview preview = service.buildPreview(
        csvContent: buildCsv(<String>[
          conflictCsvHeader,
          'Bank,https://bank.com/login,alice,new-pw,',
        ]),
        workspaceId: ws,
      );

      expect(preview.rows.single.kind, ChromeImportKind.conflict);
      expect(preview.rows.single.choice, ChromeImportChoice.keepLocal);

      final ChromeImportCommitResult result = await service.commit(preview);
      expect(result.added, 0);
      expect(result.updated, 0);
      expect(result.skipped, 1);
      expect((await repo.getByIdAsync('local-1'))!.password, 'old-pw');
      await repo.dispose();
    });

    test('更新保留 ID/收藏/分组/保密项，来源缺失备注保留，其余取 CSV', () async {
      final PasswordRepository repo = await seedConflictRepo('update-keep');
      final ItemGroup group = repo.groupsNotifier.value
          .singleWhere((ItemGroup g) => g.workspaceId == ws);
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);
      final ChromeImportPreview preview = service.buildPreview(
        csvContent: buildCsv(<String>[
          conflictCsvHeader,
          'Bank,https://bank.com/login,alice,new-pw,',
        ]),
        workspaceId: ws,
      );
      preview.rows.single.choice = ChromeImportChoice.update;

      final ChromeImportCommitResult result = await service.commit(preview);
      expect(result.updated, 1);

      final PasswordItem? saved = await repo.getByIdAsync('local-1');
      expect(saved, isNotNull);
      // 保留项
      expect(saved!.id, 'local-1');
      expect(saved.isFavorite, isTrue);
      expect(saved.groupId, group.id);
      expect(saved.customFields, hasLength(1));
      expect(saved.customFields.single.value, '99');
      expect(saved.notes, '本地备注');
      // 更新项
      expect(saved.password, 'new-pw');
      expect(saved.title, 'Bank');
      expect(saved.username, 'alice');
      await repo.dispose();
    });

    test('CSV 备注非空时覆盖本地备注', () async {
      final PasswordRepository repo = await seedConflictRepo('update-note');
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);
      final ChromeImportPreview preview = service.buildPreview(
        csvContent: buildCsv(<String>[
          conflictCsvHeader,
          'Bank,https://bank.com/login,alice,new-pw,CSV 备注',
        ]),
        workspaceId: ws,
      );
      preview.rows.single.choice = ChromeImportChoice.update;

      await service.commit(preview);
      expect((await repo.getByIdAsync('local-1'))!.notes, 'CSV 备注');
      await repo.dispose();
    });

    test('多条匹配：未选择时拒绝提交，明确目标后仅更新选定条目', () async {
      final PasswordRepository repo = await openRepo('multi-match');
      await repo.addItem(PasswordItem(
        id: 'm1',
        title: 'Bank One',
        username: 'alice',
        password: 'pw1',
        url: 'https://bank.com',
        workspaceId: ws,
      ));
      await repo.addItem(PasswordItem(
        id: 'm2',
        title: 'Bank Two',
        username: 'alice',
        password: 'pw2',
        url: 'https://bank.com',
        workspaceId: ws,
      ));
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);
      final ChromeImportPreview preview = service.buildPreview(
        csvContent: buildCsv(<String>[
          conflictCsvHeader,
          'Bank,https://bank.com,alice,new-pw,',
        ]),
        workspaceId: ws,
      );

      final ChromeImportRow row = preview.rows.single;
      expect(row.kind, ChromeImportKind.multiMatch);
      expect(row.choice, ChromeImportChoice.undecided);
      expect(preview.undecidedCount, 1);

      final ChromeImportCommitResult blocked = await service.commit(preview);
      expect(blocked.errors, isNotEmpty);
      expect(blocked.added + blocked.updated, 0);
      expect((await repo.getByIdAsync('m1'))!.password, 'pw1');

      row.choice = ChromeImportChoice.update;
      row.updateTargetId = 'm1';
      final ChromeImportCommitResult ok = await service.commit(preview);
      expect(ok.updated, 1);

      final PasswordItem? a1 = await repo.getByIdAsync('m1');
      final PasswordItem? a2 = await repo.getByIdAsync('m2');
      expect(a1!.password, 'new-pw');
      expect(a1.title, 'Bank');
      expect(a2!.password, 'pw2', reason: '未选中的匹配条目不得被盲覆盖');
      await repo.dispose();
    });
  });

  group('提交前仓库变化', () {
    test('目标工作区在预览后变化：拒绝写入并返回 stale', () async {
      final PasswordRepository repo = await openRepo('stale-same-ws');
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);
      final String csv = buildCsv(<String>[
        'name,url,username,password',
        'New,https://new.com,csv-user,csv-pw',
      ]);
      final ChromeImportPreview preview = service.buildPreview(
        csvContent: csv,
        workspaceId: ws,
      );

      await repo.addItem(PasswordItem(
        title: '并发修改',
        username: 'other',
        password: 'p',
        workspaceId: ws,
      ));

      final ChromeImportCommitResult result = await service.commit(preview);
      expect(result.stale, isTrue);
      expect(
        repo.itemsNotifier.value
            .any((PasswordItem it) => it.username == 'csv-user'),
        isFalse,
        reason: 'stale 时不得写入任何导入条目',
      );
      // 刷新预览后可重新提交。
      final ChromeImportPreview refreshed = service.buildPreview(
        csvContent: csv,
        workspaceId: ws,
      );
      expect(refreshed.createCount, 1);
      final ChromeImportCommitResult retry = await service.commit(refreshed);
      expect(retry.stale, isFalse);
      expect(retry.added, 1);
      await repo.dispose();
    });

    test('其它工作区变化不算 stale', () async {
      final PasswordRepository repo = await openRepo('stale-other-ws');
      await repo.addWorkspace(Workspace(id: 'ws-other', name: '其它'));
      final ChromeCsvImportService service =
          ChromeCsvImportService(repository: repo);
      final ChromeImportPreview preview = service.buildPreview(
        csvContent: buildCsv(<String>[
          'name,url,username,password',
          'New,https://new.com,u,pw',
        ]),
        workspaceId: ws,
      );

      await repo.addItem(PasswordItem(
        title: 'Other',
        username: 'o',
        password: 'p',
        workspaceId: 'ws-other',
      ));

      final ChromeImportCommitResult result = await service.commit(preview);
      expect(result.stale, isFalse);
      expect(result.added, 1);
      await repo.dispose();
    });
  });
  group('导入边界回归', () {
    test('文件内完全重复只创建一次；缺少 name 列按网址命名', () async {
      final repo = await openRepo('same-file');
      final service = ChromeCsvImportService(repository: repo);
      final preview = service.buildPreview(csvContent:
        'url,username,password\nhttps://example.test,a, secret \nhttps://example.test,a, secret \n', workspaceId: ws);
      expect(preview.createCount, 1);
      expect(preview.identicalCount, 1);
      final result = await service.commit(preview);
      expect(result.added, 1);
      expect(result.skipped, 1);
      expect(repo.itemsNotifier.value.single.password, ' secret ');
      await repo.dispose();
    });
    test('LF 表头和带 CRLF 的备注能完整解析', () async {
      final repo = await openRepo('mixed-eol');
      final parsed = ChromeCsvImportService(repository: repo).parseCsv(
        'name,url,username,password,note\nExample,https://example.test,u,p,"第一行\r\n第二行"\n');
      expect(parsed.entries.single.note, '第一行\n第二行');
      expect(parsed.errors, isEmpty);
      await repo.dispose();
    });
    test('多行更新同一本地记录必须先消除冲突', () async {
      final repo = await openRepo('two-updates');
      await repo.addItem(PasswordItem(title: 'Example', username: 'a', password: 'old', url: 'https://example.test'));
      final service = ChromeCsvImportService(repository: repo);
      final preview = service.buildPreview(csvContent:
        'name,url,username,password\nExample,https://example.test,a,new1\nExample,https://example.test,a,new2\n', workspaceId: ws);
      for (final row in preview.rows) { row.choice = ChromeImportChoice.update; }
      final result = await service.commit(preview);
      expect(result.errors, isNotEmpty);
      expect(repo.itemsNotifier.value.single.password, 'old');
      await repo.dispose();
    });
    test('SQLite 已变化而 notifier 尚未刷新时也拒绝覆盖', () async {
      final repo = await openRepo('stale-db');
      final item = PasswordItem(title: 'Example', username: 'a', password: 'old', url: 'https://example.test');
      await repo.addItem(item);
      final service = ChromeCsvImportService(repository: repo);
      final preview = service.buildPreview(csvContent:
        'name,url,username,password\nExample,https://example.test,a,new\n', workspaceId: ws);
      preview.rows.single.choice = ChromeImportChoice.update;
      final db = await openDatabase('${tempDir.path}/stale-db.db');
      await db.update('password_items', {'notes': 'Concurrent edit'}, where: 'id = ?', whereArgs: [item.id]);
      final result = await service.commit(preview);
      expect(result.stale, true);
      expect((await repo.getByIdAsync(item.id))!.password, 'old');
      expect((await repo.getByIdAsync(item.id))!.notes, 'Concurrent edit');
      await repo.dispose();
    });
  });

}
