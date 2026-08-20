import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/password_item.dart';
import 'vault_metadata_service.dart';

class DataExportResult {
  const DataExportResult({required this.path, required this.itemCount});

  final String path;
  final int itemCount;
}

class DataExportService {
  DataExportService({VaultMetadataService? metadataService})
    : _metadataService = metadataService ?? VaultMetadataService();

  final VaultMetadataService _metadataService;

  Future<DataExportResult> exportJson(List<PasswordItem> items) async {
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
      'exportVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'vaultVersion': metadata.vaultVersion,
      'protocolVersion': metadata.protocolVersion,
      'itemCount': items.length,
      'items': items.map((PasswordItem item) => item.toMap()).toList(),
    };

    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    await File(filePath).writeAsString(encoder.convert(payload));
    return DataExportResult(path: filePath, itemCount: items.length);
  }

  /// 从 JSON 文件导入密码条目。
  ///
  /// 兼容两种格式：
  /// - 标准导出格式 `{app, items: [...]}`（见 exportJson）
  /// - 纯数组格式 `[...]`（直接是条目列表）
  /// 返回解析出的 [PasswordItem] 列表，合并/去重由调用方决定。
  Future<List<PasswordItem>> importJson(String filePath) async {
    final String raw = await File(filePath).readAsString();
    return parseJsonItems(raw);
  }

  /// 解析 JSON 文本为 [PasswordItem] 列表（与 [importJson] 同规则）。
  ///
  /// 抽取为静态方法，便于二维码（内容即 JSON 文本）等非文件来源复用，
  /// 无需先落盘成文件。
  static List<PasswordItem> parseJsonItems(String raw) {
    final dynamic decoded = jsonDecode(raw);

    List<dynamic> rawItems;
    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      rawItems = decoded['items'] as List;
    } else if (decoded is List) {
      rawItems = decoded;
    } else {
      throw const FormatException('无法识别的导入文件格式');
    }

    return rawItems
        .whereType<Map>()
        .map((Map m) => PasswordItem.fromMap(m))
        .toList();
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
