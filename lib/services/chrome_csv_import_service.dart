import 'dart:convert';
import 'package:csv/csv.dart';

import '../models/password_item.dart';
import 'password_repository.dart';

/// Chrome 导出 CSV 中的一条密码记录。
///
/// [password] 逐字保留（不 trim、不做数字转换）；其余文本列去除首尾空白。
/// [note] 内部换行统一为 `\n`，空白备注视为「来源缺失」（null），更新时保留本地值。
class ChromeCsvEntry {
  const ChromeCsvEntry({
    required this.sourceRow,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    this.note,
  });

  /// 数据行序号（表头之后从 1 开始，含畸形行计数）。
  final int sourceRow;
  final String name;
  final String url;
  final String username;
  final String password;
  final String? note;

  bool get hasNote => note?.trim().isNotEmpty ?? false;

  /// 期望标题：名称 → 网址主机 → 用户名 → 兜底。
  String get desiredTitle {
    if (name.trim().isNotEmpty) return name.trim();
    final String host = ChromeCsvImportService.urlHostOf(url);
    if (host.isNotEmpty) return host;
    if (username.trim().isNotEmpty) return username.trim();
    return '未命名条目';
  }
}

/// 无法导入的行（原因描述不包含字段内容）。
class ChromeCsvRowError {
  const ChromeCsvRowError({required this.sourceRow, required this.reason});

  final int sourceRow;
  final String reason;
}

class ChromeCsvParseResult {
  const ChromeCsvParseResult({
    required this.entries,
    required this.errors,
    this.headerError,
  });

  final List<ChromeCsvEntry> entries;
  final List<ChromeCsvRowError> errors;

  /// 整文件级错误（缺列/空文件/格式不完整），此时 [entries] 为空。
  final String? headerError;

  bool get isOk => headerError == null;
}

enum ChromeImportKind {
  /// 无本地匹配，将新增。
  create,

  /// 与本地条目内容完全相同，固定跳过。
  identical,

  /// 恰好一条匹配且内容不同，可保留本地 / 更新 / 另存。
  conflict,

  /// 多条本地匹配，必须明确选择目标。
  multiMatch,
}

enum ChromeImportChoice {
  /// 多条匹配尚未选择（仅 multiMatch 的初始态，提交被阻止）。
  undecided,

  addNew,
  skipImport,
  keepLocal,
  update,
  saveAsNew,
}

/// 预览中的一行：CSV 条目 + 本地匹配 + 用户决策。
class ChromeImportRow {
  ChromeImportRow({
    required this.entry,
    required this.matches,
    required this.choice,
    this.duplicateInFile = false,
  });

  final ChromeCsvEntry entry;
  final bool duplicateInFile;

  /// 与该行同键（工作区 + 规范化网址 + 用户名）的本地条目。
  final List<PasswordItem> matches;

  /// 可被界面直接修改的决策。
  ChromeImportChoice choice;

  /// [ChromeImportChoice.update] 且多条匹配时，用户明确指定的目标条目 id。
  String? updateTargetId;

  /// buildPreview 为默认会写入的行生成的最终（唯一）名称。
  String? resolvedTitle;

  ChromeImportKind get kind {
    if (duplicateInFile) return ChromeImportKind.identical;
    if (matches.isEmpty) return ChromeImportKind.create;
    if (matches.length > 1) return ChromeImportKind.multiMatch;
    return isIdenticalTo(matches.single)
        ? ChromeImportKind.identical
        : ChromeImportKind.conflict;
  }

  /// 内容完全相同（密码/用户名/备注；网址经规范化已由匹配保证）。
  /// 标题不参与比较：标题是本地展示层概念（可能被改名或加消歧后缀）。
  bool isIdenticalTo(PasswordItem local) {
    return local.password == entry.password &&
        local.username.trim() == entry.username &&
        (!entry.hasNote || (local.notes ?? '').trim() == entry.note!.trim());
  }
}

/// 预览时刻的仓库指纹（目标工作区范围），提交前用于检测仓库是否变化。
class ChromeImportSnapshot {
  ChromeImportSnapshot._(this.fingerprint);
  final String fingerprint;
  static ChromeImportSnapshot capture(PasswordRepository repository, String workspaceId) =>
      ChromeImportSnapshot._(repository.importSnapshot(workspaceId));
  bool isStaleAgainst(PasswordRepository repository, String workspaceId) =>
      fingerprint != repository.importSnapshot(workspaceId);
}

class ChromeImportPreview {
  ChromeImportPreview({
    required this.parse,
    required this.workspaceId,
    required this.rows,
    required this.snapshot,
  });

  final ChromeCsvParseResult parse;
  final String workspaceId;
  final List<ChromeImportRow> rows;
  final ChromeImportSnapshot snapshot;

  int get createCount => rows
      .where((ChromeImportRow r) => r.kind == ChromeImportKind.create)
      .length;
  int get identicalCount => rows
      .where((ChromeImportRow r) => r.kind == ChromeImportKind.identical)
      .length;
  int get conflictCount => rows
      .where((ChromeImportRow r) => r.kind == ChromeImportKind.conflict)
      .length;
  int get multiMatchCount => rows
      .where((ChromeImportRow r) => r.kind == ChromeImportKind.multiMatch)
      .length;
  int get undecidedCount => rows
      .where((ChromeImportRow r) => r.choice == ChromeImportChoice.undecided)
      .length;
}

/// 决策确定后的一笔写入（新增或更新）。
class ChromePlannedWrite {
  const ChromePlannedWrite({
    required this.row,
    required this.item,
    required this.isUpdate,
  });

  final ChromeImportRow row;
  final PasswordItem item;
  final bool isUpdate;
}

class ChromeImportPlan {
  const ChromeImportPlan({
    required this.writes,
    required this.skippedCount,
    required this.errors,
  });

  final List<ChromePlannedWrite> writes;
  final int skippedCount;

  /// 决策问题（多条匹配未选择等）。非空时禁止提交。
  final List<String> errors;
}

class ChromeImportCommitResult {
  const ChromeImportCommitResult({
    this.stale = false,
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.invalid = 0,
    this.errors = const <String>[],
  });

  /// 预览后仓库已变化：未做任何写入，应刷新预览后重试。
  final bool stale;
  final int added;
  final int updated;
  final int skipped;
  final int invalid;
  final List<String> errors;

  String get summaryMessage {
    if (stale) return '数据已变化，本次导入已取消';
    final List<String> parts = <String>[
      '新增 $added',
      '更新 $updated',
      '跳过 $skipped',
    ];
    if (invalid > 0) parts.add('无效 $invalid');
    return 'Chrome 导入完成：${parts.join('，')}';
  }
}

/// Chrome CSV 导入：解析 → 预览（不写入）→ 按决策经仓库事务方法提交。
///
/// 安全约束：密码逐字保留；任何错误信息只含行号与原因，不含字段内容。
class ChromeCsvImportService {
  ChromeCsvImportService({required this.repository});

  final PasswordRepository repository;

  static final RegExp _schemePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://');

  // ---------------------------------------------------------------------------
  // 解析
  // ---------------------------------------------------------------------------

  static String _detectEol(String text) {
    bool quoted = false;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == '"') {
        if (quoted && i + 1 < text.length && text[i + 1] == '"') { i++; }
        else { quoted = !quoted; }
      } else if (!quoted && text[i] == '\r') {
        return i + 1 < text.length && text[i + 1] == '\n' ? '\r\n' : '\r';
      } else if (!quoted && text[i] == '\n') { return '\n'; }
    }
    return '\n';
  }

  /// 解析 Chrome 导出的 CSV 文本。
  ///
  /// 兼容：UTF-8 BOM、CRLF/LF 行尾（自动探测）、RFC4180 引号转义与字段内
  /// 换行、note/notes 备注列。缺必需列返回整文件错误；畸形行逐条记入
  /// [ChromeCsvParseResult.errors]，不影响其余行。
  ChromeCsvParseResult parseCsv(String csvContent) {
    String text = csvContent;
    if (text.startsWith('﻿')) {
      text = text.substring(1);
    }
    if (text.trim().isEmpty) {
      return const ChromeCsvParseResult(
        entries: <ChromeCsvEntry>[],
        errors: <ChromeCsvRowError>[],
        headerError: '文件为空',
      );
    }

    // Chrome 导出为 CRLF；手工编辑过的文件可能是 LF。引号内换行按文本保留。
    final String eol = _detectEol(text);
    List<List<dynamic>> rows;
    try {
      rows = const CsvToListConverter(shouldParseNumbers: false, allowInvalid: false)
          .convert<dynamic>(text, eol: eol);
    } on FormatException {
      return const ChromeCsvParseResult(
        entries: <ChromeCsvEntry>[],
        errors: <ChromeCsvRowError>[],
        headerError: 'CSV 格式不完整（存在未闭合的引号）',
      );
    }
    if (rows.isEmpty) {
      return const ChromeCsvParseResult(
        entries: <ChromeCsvEntry>[],
        errors: <ChromeCsvRowError>[],
        headerError: '文件为空',
      );
    }

    final List<String> header = <String>[
      for (final dynamic cell in rows.first)
        (cell ?? '').toString().trim().toLowerCase(),
    ];
    int? colOf(List<String> names) {
      for (final String name in names) {
        final int i = header.indexOf(name);
        if (i >= 0) return i;
      }
      return null;
    }

    final int? nameIdx = colOf(<String>['name']);
    final int? urlIdx = colOf(<String>['url']);
    final int? usernameIdx = colOf(<String>['username']);
    final int? passwordIdx = colOf(<String>['password']);
    final int? noteIdx = colOf(<String>['note', 'notes']);

    final List<String> missing = <String>[
      if (urlIdx == null) 'url',
      if (usernameIdx == null) 'username',
      if (passwordIdx == null) 'password',
    ];
    if (missing.isNotEmpty) {
      return ChromeCsvParseResult(
        entries: const <ChromeCsvEntry>[],
        errors: const <ChromeCsvRowError>[],
        headerError:
            '缺少必需列：${missing.join('、')}（应为 name,url,username,password[,note/notes]）',
      );
    }

    final int columnCount = header.length;
    final List<ChromeCsvEntry> entries = <ChromeCsvEntry>[];
    final List<ChromeCsvRowError> errors = <ChromeCsvRowError>[];

    for (int i = 1; i < rows.length; i++) {
      final List<dynamic> row = rows[i];
      final int rowNum = i;

      final bool blank = row.every(
        (dynamic cell) => (cell ?? '').toString().trim().isEmpty,
      );
      if (blank) continue;

      if (row.length != columnCount) {
        errors.add(ChromeCsvRowError(
          sourceRow: rowNum,
          reason: '字段数不符（应为 $columnCount 列，实际 ${row.length} 列）',
        ));
        continue;
      }

      String field(int? idx) => idx == null ? '' : (row[idx] ?? '').toString();
      final String name = field(nameIdx).trim();
      final String url = field(urlIdx).trim();
      final String username = field(usernameIdx).trim();
      // 密码逐字保留：不 trim、不做任何转换。
      final String password = field(passwordIdx);
      final String noteRaw = field(noteIdx);
      final String? note =
          noteRaw.trim().isEmpty ? null : noteRaw.replaceAll('\r\n', '\n');

      if (name.isEmpty && url.isEmpty && username.isEmpty &&
          password.trim().isEmpty) {
        errors.add(ChromeCsvRowError(
          sourceRow: rowNum,
          reason: '名称、网址、用户名、密码均为空',
        ));
        continue;
      }
      entries.add(ChromeCsvEntry(
        sourceRow: rowNum,
        name: name,
        url: url,
        username: username,
        password: password,
        note: note,
      ));
    }

    return ChromeCsvParseResult(entries: entries, errors: errors);
  }

  // ---------------------------------------------------------------------------
  // 网址规范化（保守）
  // ---------------------------------------------------------------------------

  /// 完整网址的保守规范化，用于匹配：
  /// - scheme/host 小写；无 scheme 的裸域按 https:// 补齐再规范化
  /// - 去默认端口（http:80 / https:443）、去片段（#…）、根路径 '/' 归一为空
  /// - 不去 www、不合并 http/https、保留路径大小写与查询串
  /// 解析失败时退回小写原文。
  static String normalizeUrlForMatch(String? raw) {
    final String s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    final bool hasScheme = _schemePattern.hasMatch(s);
    final Uri? uri = Uri.tryParse(hasScheme ? s : 'https://$s');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return s;
    }
    final String scheme = uri.scheme.toLowerCase();
    String host = uri.host.toLowerCase();
    if (host.contains(':')) host = '[$host]'; // IPv6
    final int port = uri.port;
    final bool defaultPort = port == 0 ||
        (scheme == 'http' && port == 80) ||
        (scheme == 'https' && port == 443);
    final String authority = (uri.userInfo.isEmpty ? '' : '${uri.userInfo}@') +
        host +
        (defaultPort ? '' : ':$port');
    String path = uri.path;
    if (path == '/') path = '';
    final String query = uri.hasQuery ? '?${uri.query}' : '';
    return '$scheme://$authority$path$query';
  }

  /// 提取主机名（标题生成用）；无 host 返回空串。
  static String urlHostOf(String? raw) {
    final String s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    final bool hasScheme = _schemePattern.hasMatch(s);
    final Uri? uri = Uri.tryParse(hasScheme ? s : 'https://$s');
    if (uri == null || uri.host.isEmpty) return '';
    return uri.host;
  }

  /// 匹配键：规范化网址 + 用户名（去首尾空白，区分大小写）。
  /// 空用户名合法（与本地同为空的条目匹配）。
  static String matchKeyOf(String normalizedUrl, String username) {
    return '$normalizedUrl\u{0000}${username.trim()}';
  }

  // ---------------------------------------------------------------------------
  // 预览
  // ---------------------------------------------------------------------------

  /// 构建导入预览。只读取仓库状态，不写入。
  ///
  /// 匹配范围限定 [workspaceId] 工作区；默认决策：新增→导入、完全相同→跳过、
  /// 单条冲突→保留本地、多条匹配→待选择。新增行会生成工作区内唯一的最终名称。
  ChromeImportPreview buildPreview({
    required String csvContent,
    required String workspaceId,
  }) {
    final ChromeCsvParseResult parse = parseCsv(csvContent);
    final List<PasswordItem> localItems = repository.itemsNotifier.value
        .where((PasswordItem it) => it.workspaceId == workspaceId)
        .toList();

    final Map<String, List<PasswordItem>> byKey = <String, List<PasswordItem>>{};
    for (final PasswordItem it in localItems) {
      final String key = matchKeyOf(normalizeUrlForMatch(it.url), it.username);
      byKey.putIfAbsent(key, () => <PasswordItem>[]).add(it);
    }

    final Set<String> takenTitles = <String>{
      for (final PasswordItem it in localItems) it.title.trim().toLowerCase(),
    };

    final List<ChromeImportRow> rows = <ChromeImportRow>[];
    final seen = <String>{};
    for (final ChromeCsvEntry e in parse.entries) {
      final List<PasswordItem> matches =
          byKey[matchKeyOf(normalizeUrlForMatch(e.url), e.username)] ??
              const <PasswordItem>[];
      final fingerprint = jsonEncode([normalizeUrlForMatch(e.url), e.username, e.password, e.note]);
      final ChromeImportRow row = ChromeImportRow(
        duplicateInFile: !seen.add(fingerprint),
        entry: e,
        matches: List<PasswordItem>.of(matches),
        choice: ChromeImportChoice.keepLocal, // 占位，下面按 kind 覆盖
      );
      row.choice = switch (row.kind) {
        ChromeImportKind.create => ChromeImportChoice.addNew,
        ChromeImportKind.identical => ChromeImportChoice.skipImport,
        ChromeImportKind.conflict => ChromeImportChoice.keepLocal,
        ChromeImportKind.multiMatch => ChromeImportChoice.undecided,
      };
      if (row.kind == ChromeImportKind.create) {
        row.resolvedTitle = _uniqueTitle(e.desiredTitle, e.username, takenTitles);
      }
      rows.add(row);
    }

    return ChromeImportPreview(
      parse: parse,
      workspaceId: workspaceId,
      rows: rows,
      snapshot: ChromeImportSnapshot.capture(repository, workspaceId),
    );
  }

  /// 工作区内唯一标题：被占用时依次尝试 `名称 (用户名)`、`名称 2`、`名称 3`…
  static String _uniqueTitle(String base, String username, Set<String> taken) {
    String key(String s) => s.trim().toLowerCase();
    String candidate = base.trim().isEmpty ? '未命名条目' : base.trim();
    if (!taken.contains(key(candidate))) {
      taken.add(key(candidate));
      return candidate;
    }
    final String user = username.trim();
    if (user.isNotEmpty) {
      candidate = '$base ($user)';
      if (!taken.contains(key(candidate))) {
        taken.add(key(candidate));
        return candidate;
      }
    }
    int n = 2;
    while (true) {
      candidate = '$base $n';
      if (!taken.contains(key(candidate))) {
        taken.add(key(candidate));
        return candidate;
      }
      n++;
    }
  }

  // ---------------------------------------------------------------------------
  // 决策 → 计划 → 提交
  // ---------------------------------------------------------------------------

  /// 按当前决策生成写入计划（纯计算，不写库）。
  ///
  /// 更新条目保留原 id、收藏、分组、保密项与来源缺失的备注；标题取 CSV 侧并
  /// 做工作区内唯一化（允许沿用目标条目原标题）。新增条目归入 [groupId]
  /// （null 为未分组）。
  ChromeImportPlan finalizePlan(
    ChromeImportPreview preview, {
    String? groupId,
  }) {
    final List<ChromePlannedWrite> writes = <ChromePlannedWrite>[];
    final List<String> errors = <String>[];
    int skipped = 0;
    final updatedIds = <String>{};
    final DateTime now = DateTime.now();
    final String workspaceId = preview.workspaceId;

    final List<PasswordItem> localItems = repository.itemsNotifier.value
        .where((PasswordItem it) => it.workspaceId == workspaceId)
        .toList();
    final Set<String> taken = <String>{
      for (final PasswordItem it in localItems) it.title.trim().toLowerCase(),
    };

    for (final ChromeImportRow row in preview.rows) {
      final ChromeCsvEntry e = row.entry;

      if (row.choice == ChromeImportChoice.undecided) {
        errors.add('第 ${e.sourceRow} 行存在多条本地匹配，请明确选择处理方式');
        continue;
      }
      if (row.duplicateInFile || row.choice == ChromeImportChoice.skipImport ||
          row.choice == ChromeImportChoice.keepLocal) {
        skipped++;
        continue;
      }

      if (row.choice == ChromeImportChoice.addNew ||
          row.choice == ChromeImportChoice.saveAsNew) {
        if (row.choice == ChromeImportChoice.addNew &&
            row.kind != ChromeImportKind.create) {
          errors.add('第 ${e.sourceRow} 行的选择不适用');
          continue;
        }
        final String title = _uniqueTitle(e.desiredTitle, e.username, taken);
        row.resolvedTitle = title;
        writes.add(ChromePlannedWrite(
          row: row,
          isUpdate: false,
          item: PasswordItem(
            title: title,
            username: e.username,
            password: e.password,
            url: e.url.isEmpty ? null : e.url,
            notes: e.hasNote ? e.note : null,
            workspaceId: workspaceId,
            groupId: groupId,
            createdAt: now,
            updatedAt: now,
          ),
        ));
        continue;
      }

      // ChromeImportChoice.update
      final PasswordItem? target = _resolveUpdateTarget(row);
      if (target == null) {
        errors.add('第 ${e.sourceRow} 行未指定有效的更新目标');
        continue;
      }
      if (!updatedIds.add(target.id)) {
        errors.add('多行将更新同一条记录，请只保留一个更新选择，其余保留本地或另存');
        continue;
      }
      // 目标条目自己的原标题不参与撞名判断（可沿用或改名）。
      taken.remove(target.title.trim().toLowerCase());
      final String title = _uniqueTitle(e.desiredTitle, e.username, taken);
      row.resolvedTitle = title;
      writes.add(ChromePlannedWrite(
        row: row,
        isUpdate: true,
        item: PasswordItem(
          id: target.id,
          title: title,
          username: e.username,
          password: e.password,
          url: e.url.isNotEmpty ? e.url : target.url,
          notes: e.hasNote ? e.note : target.notes,
          createdAt: target.createdAt,
          updatedAt: now,
          isFavorite: target.isFavorite,
          workspaceId: target.workspaceId,
          groupId: target.groupId,
          customFields: target.customFields,
        ),
      ));
    }

    return ChromeImportPlan(
      writes: writes,
      skippedCount: skipped,
      errors: errors,
    );
  }

  static PasswordItem? _resolveUpdateTarget(ChromeImportRow row) {
    if (row.matches.isEmpty) return null;
    if (row.matches.length == 1) {
      return row.choice == ChromeImportChoice.update
          ? row.matches.single
          : null;
    }
    final String? targetId = row.updateTargetId;
    if (targetId == null) return null;
    for (final PasswordItem m in row.matches) {
      if (m.id == targetId) return m;
    }
    return null;
  }

  /// 提交导入。流程：
  /// 1. 校验快照——预览后仓库（目标工作区范围）变化则拒绝写入（stale）；
  /// 2. 生成计划——决策未完成同样拒绝；
  /// 3. 经 [PasswordRepository.importItems] 单事务写入。
  ///
  /// 工作区访问验证（authorizeWorkspace）由调用方在提交前完成。
  Future<ChromeImportCommitResult> commit(
    ChromeImportPreview preview, {
    String? groupId,
  }) async {
    if (preview.snapshot.isStaleAgainst(repository, preview.workspaceId)) {
      return const ChromeImportCommitResult(stale: true);
    }
    final ChromeImportPlan plan = finalizePlan(preview, groupId: groupId);
    if (plan.errors.isNotEmpty) {
      return ChromeImportCommitResult(errors: plan.errors);
    }
    if (plan.writes.isNotEmpty) {
      try {
        await repository.importItems(
          plan.writes.map((ChromePlannedWrite w) => w.item),
          expectedWorkspaceId: preview.workspaceId,
          expectedSnapshot: preview.snapshot.fingerprint,
        );
      } on ImportSnapshotChanged {
        return const ChromeImportCommitResult(stale: true);
      }
    }
    return ChromeImportCommitResult(
      added: plan.writes.where((ChromePlannedWrite w) => !w.isUpdate).length,
      updated: plan.writes.where((ChromePlannedWrite w) => w.isUpdate).length,
      skipped: plan.skippedCount,
      invalid: preview.parse.errors.length,
    );
  }
}
