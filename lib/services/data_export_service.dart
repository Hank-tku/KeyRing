import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/item_group.dart';
import '../models/password_item.dart';
import '../models/workspace.dart';
import 'vault_metadata_service.dart';

class DataExportResult {
  const DataExportResult({required this.path, required this.itemCount});

  final String path;
  final int itemCount;
}

/// 导入文件解析结果（v2 结构文件包含工作区/分组定义；v1 只有条目）。
class ParsedImport {
  const ParsedImport({
    required this.rawItems,
    this.rawWorkspaces = const <Map<String, dynamic>>[],
    this.rawGroups = const <Map<String, dynamic>>[],
    this.exportVersion = 1,
  });

  /// 条目原始 map（保留键存在性，供字段保留合并判断缺键）。
  final List<Map<String, dynamic>> rawItems;
  final List<Map<String, dynamic>> rawWorkspaces;
  final List<Map<String, dynamic>> rawGroups;
  final int exportVersion;

  List<PasswordItem> get items =>
      rawItems.map(PasswordItem.fromMap).toList();
}

class DataExportService {
  DataExportService({VaultMetadataService? metadataService})
    : _metadataService = metadataService ?? VaultMetadataService();

  final VaultMetadataService _metadataService;

  /// 导出为 v2 JSON：条目携带工作区归属与保密项，顶层带结构定义。
  /// 旧版应用导入该文件时只读 items 并忽略新键（graceful degradation）。
  Future<DataExportResult> exportJson(
    List<PasswordItem> items, {
    List<Workspace>? workspaces,
    List<ItemGroup>? groups,
    bool Function()? isAuthorized,
  }) async {
    final Directory directory = await _resolveExportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final VaultMetadata metadata = await _metadataService.load();
    final String timestamp = _timestamp(DateTime.now());
    final String filePath = p.join(
      directory.path,
      'KeyRing-export-v${metadata.vaultVersion}-$timestamp.json',
    );
    final Map<String, dynamic> payload = <String, dynamic>{
      'app': 'KeyRing',
      'exportVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'vaultVersion': metadata.vaultVersion,
      'protocolVersion': metadata.protocolVersion,
      'itemCount': items.length,
      'workspaces': (workspaces ?? const <Workspace>[])
          .map((Workspace w) => w.toMap())
          .toList(),
      'groups': (groups ?? const <ItemGroup>[])
          .map((ItemGroup g) => g.toMap())
          .toList(),
      'items': items.map((PasswordItem item) => item.toMap()).toList(),
    };

    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    if (isAuthorized != null && !isAuthorized()) throw StateError('访问授权已失效');
    await File(filePath).writeAsString(encoder.convert(payload));
    return DataExportResult(path: filePath, itemCount: items.length);
  }

  /// 从 JSON 文件导入密码条目（含结构定义）。
  Future<ParsedImport> importJson(String filePath) async {
    final String raw = await File(filePath).readAsString();
    return parseJsonBundle(raw);
  }

  /// 解析 JSON 文本为 [PasswordItem] 列表（v1 行为，二维码等单条来源复用）。
  static List<PasswordItem> parseJsonItems(String raw) =>
      parseJsonBundle(raw).items;

  /// 解析 v1/v2 导出格式。兼容：
  /// - 标准导出格式 `{app, items: [...], workspaces?, groups?}`
  /// - 纯数组格式 `[...]`
  static ParsedImport parseJsonBundle(String raw) {
    final dynamic decoded = jsonDecode(raw);

    List<Map<String, dynamic>> asMaps(dynamic list) => (list as List? ?? <dynamic>[])
        .whereType<Map>()
        .map((Map m) => Map<String, dynamic>.from(m))
        .toList();

    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      return ParsedImport(
        rawItems: asMaps(decoded['items']),
        rawWorkspaces: asMaps(decoded['workspaces']),
        rawGroups: asMaps(decoded['groups']),
        exportVersion:
            decoded['exportVersion'] as int? ?? 1,
      );
    }
    if (decoded is List) {
      return ParsedImport(rawItems: asMaps(decoded));
    }
    throw const FormatException('无法识别的导入文件格式');
  }

  Future<Directory> _resolveExportDirectory() async {
    final Directory? downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory(p.join(downloads.path, 'KeyRing'));
    }

    final Directory documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'exports'));
  }

  String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}
