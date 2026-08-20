import '../models/password_item.dart';

/// 截图 OCR 字段提取结果。
class OcrExtraction {
  const OcrExtraction({
    this.title = '',
    this.username = '',
    this.password = '',
    this.url,
    this.notes,
    this.confidence = 0,
  });

  final String title;
  final String username;
  final String password;
  final String? url;
  final String? notes;

  /// 估计的置信度（0~1），基于命中的标签行数。供 UI 提示用户复核。
  final double confidence;
}

/// 对 OCR 识别出的多行文本做启发式字段抽取。
///
/// 策略：按行扫描，命中「标签关键词」时把紧随其后的非空行作为对应字段值。
/// 无法归类的行汇总进 notes。由于 OCR 准确率有限，调用方应把结果展示在
/// 可编辑表单里供用户确认后再导入。
class OcrFieldExtractor {
  const OcrFieldExtractor();

  OcrExtraction extract(String rawText) {
    final List<String> lines = rawText
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const OcrExtraction();
    }

    String username = '';
    String password = '';
    String url = '';
    final List<String> leftover = <String>[];
    int hits = 0;

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final String lower = line.toLowerCase();

      String? nextValue() {
        // 优先取下一非空行；若当前行本身是「标签: 值」形式，取冒号后内容。
        final int colon = line.indexOf(RegExp(r'[:：]'));
        if (colon >= 0 && colon < line.length - 1) {
          final String after = line.substring(colon + 1).trim();
          if (after.isNotEmpty) return after;
        }
        if (i + 1 < lines.length) {
          final String nxt = lines[i + 1];
          // 下一行不应是另一个标签行。
          if (!_looksLikeLabel(nxt)) return nxt;
        }
        return null;
      }

      if (_matches(lower, const <String>['用户名', 'username', '账号', 'account', 'email', '邮箱', '电邮'])) {
        final String? v = nextValue();
        if (v != null && v.isNotEmpty) {
          username = v;
          hits++;
          continue;
        }
      } else if (_matches(lower, const <String>['密码', 'password', 'pwd', '口令'])) {
        final String? v = nextValue();
        if (v != null && v.isNotEmpty) {
          password = v;
          hits++;
          continue;
        }
      } else if (_matches(lower, const <String>['网址', 'url', 'website', '链接', '地址'])) {
        final String? v = nextValue();
        if (v != null && v.isNotEmpty) {
          url = v;
          hits++;
          continue;
        }
      } else {
        leftover.add(line);
      }
    }

    // title：未命中专门标签时，取首行；否则尝试从剩余行第一行。
    final String title = leftover.isNotEmpty ? leftover.first : username;

    // notes：剩余行去掉 title 那一行后拼接。
    String? notes;
    if (leftover.length > 1) {
      notes = leftover.sublist(1).join('\n');
    }

    final double confidence =
        lines.isEmpty ? 0.0 : (hits / 3).clamp(0.0, 1.0).toDouble();

    return OcrExtraction(
      title: title,
      username: username,
      password: password,
      url: url.isEmpty ? null : url,
      notes: notes,
      confidence: confidence,
    );
  }

  bool _matches(String lowerLine, List<String> keywords) {
    for (final String k in keywords) {
      if (lowerLine.contains(k.toLowerCase())) return true;
    }
    return false;
  }

  bool _looksLikeLabel(String line) {
    final String lower = line.toLowerCase();
    return _matches(lower, const <String>[
      '用户名', 'username', '账号', 'account', 'email', '邮箱',
      '密码', 'password', 'pwd',
      '网址', 'url', 'website',
    ]);
  }

  /// 把提取结果转成待确认的 [PasswordItem]（不写入仓库）。
  PasswordItem toItem(OcrExtraction e) {
    return PasswordItem(
      title: e.title,
      username: e.username,
      password: e.password,
      url: e.url,
      notes: e.notes,
    );
  }
}
