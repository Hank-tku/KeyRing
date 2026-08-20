import 'data_export_service.dart';
import '../models/password_item.dart';

/// 二维码内容解析结果。
sealed class QrParseResult {
  const QrParseResult();
}

/// 解析出若干条目（KeyRing JSON 或多条件二维码）。
class QrItemsResult extends QrParseResult {
  const QrItemsResult(this.items);
  final List<PasswordItem> items;
}

/// 无法识别的二维码内容。
class QrUnrecognizedResult extends QrParseResult {
  const QrUnrecognizedResult(this.reason);
  final String reason;
}

/// 二维码负载解析器。
///
/// 支持三种格式（按优先级尝试）：
/// 1. **KeyRing JSON**：内容是合法 JSON，含 `items` 数组或裸数组
///    （复用 [DataExportService.parseJsonItems]）。
/// 2. **otpauth / password URI**：`otpauth:...`（提取 label 作为 title，
///    参数里的 account/issuer 作为 username/title）。
/// 3. **自定义 keyring URI**：`keyring://item?title=...&username=...
///    &password=...&url=...&notes=...`，便于从其它工具生成单条导入码。
///
/// 任一格式失败则降级尝试下一个；全部失败返回 [QrUnrecognizedResult]。
class QrPayloadParser {
  const QrPayloadParser();

  QrParseResult parse(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const QrUnrecognizedResult('二维码内容为空');
    }

    // 1) 尝试 JSON（可能抛 FormatException，吞掉继续）。
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final List<PasswordItem> items =
            DataExportService.parseJsonItems(trimmed);
        if (items.isNotEmpty) {
          return QrItemsResult(items);
        }
      } catch (_) {
        // 不是合法 JSON，继续尝试其它格式。
      }
    }

    // 2) 自定义 keyring:// URI（单条，字段最全）。
    if (trimmed.toLowerCase().startsWith('keyring://')) {
      final PasswordItem? item = _parseKeyringUri(trimmed);
      if (item != null) {
        return QrItemsResult(<PasswordItem>[item]);
      }
    }

    // 3) otpauth / 其它 password URI（尽力提取）。
    final String lower = trimmed.toLowerCase();
    if (lower.startsWith('otpauth:') || lower.startsWith('password:')) {
      final PasswordItem? item = _parsePasswordUri(trimmed);
      if (item != null) {
        return QrItemsResult(<PasswordItem>[item]);
      }
    }

    return const QrUnrecognizedResult('无法识别的二维码内容');
  }

  /// 解析 `keyring://item?<query>`。
  PasswordItem? _parseKeyringUri(String uri) {
    final int q = uri.indexOf('?');
    if (q < 0) return null;
    final Map<String, String> params = _parseQuery(uri.substring(q + 1));

    final String title = _decode(params['title'] ?? '');
    final String password = _decode(params['password'] ?? '');
    // title 与 password 至少一个要有值，否则视为无效。
    if (title.isEmpty && password.isEmpty) return null;

    return PasswordItem(
      title: title,
      username: _decode(params['username'] ?? ''),
      password: password,
      url: params.containsKey('url') ? _decode(params['url']!) : null,
      notes: params.containsKey('notes') ? _decode(params['notes']!) : null,
    );
  }

  /// 解析 `otpauth://TYPE/LABEL?PARAMS` 或 `password:...`。
  /// otpauth 主要面向 TOTP，但常被复用携带账号密码；这里尽力提取。
  PasswordItem? _parsePasswordUri(String uri) {
    Uri parsed;
    try {
      parsed = Uri.parse(uri);
    } catch (_) {
      return null;
    }

    final Map<String, String> q = parsed.queryParameters;

    // title：优先 issuer 参数或 path 段，否则 host。
    String title = (q['issuer'] ?? '').trim();
    String username = (q['account'] ?? q['username'] ?? '').trim();

    // otpauth 的 path 形如 "/totp/Issuer:account"。
    final String path = parsed.path.startsWith('/')
        ? parsed.path.substring(1)
        : parsed.path;
    if (path.isNotEmpty) {
      // 若 path 含冒号或标签分隔，拆成 issuer:account。
      final List<String> seg = path.split(':');
      if (seg.isNotEmpty && title.isEmpty) {
        title = Uri.decodeComponent(seg.first.trim());
      }
      if (seg.length > 1 && username.isEmpty) {
        username = Uri.decodeComponent(seg.sublist(1).join(':').trim());
      }
    }
    if (title.isEmpty) title = parsed.host;

    final String password = q['secret'] ?? q['password'] ?? '';

    if (title.isEmpty && password.isEmpty && username.isEmpty) return null;

    return PasswordItem(
      title: title.isEmpty ? username : title,
      username: username,
      password: password,
      url: q['url'],
    );
  }

  /// 简易 query string 解析（不依赖 Uri，避免 keyring:// 被 Uri 拒绝）。
  Map<String, String> _parseQuery(String query) {
    final Map<String, String> result = <String, String>{};
    for (final String pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final int eq = pair.indexOf('=');
      final String key = eq < 0 ? pair : pair.substring(0, eq);
      final String value = eq < 0 ? '' : pair.substring(eq + 1);
      result[key] = value;
    }
    return result;
  }

  /// 对 query value 做 percent-decode。
  String _decode(String v) {
    return Uri.decodeComponent(v);
  }
}
