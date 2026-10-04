import 'dart:convert';

import 'package:uuid/uuid.dart';

/// 保密项类型：决定展示掩码与输入键盘。
enum SecretFieldType { text, password, tel, date, number }

/// 条目上的自定义保密项（安全码、客户号、PIN 等）。
///
/// 存储为 `password_items.customFields` 列的 JSON 数组元素，
/// 随条目整行参与同步与 last-write-wins 合并。
class SecretField {
  SecretField({
    String? id,
    required this.label,
    required this.value,
    this.type = SecretFieldType.text,
    this.protected = false,
  }) : id = id ?? const Uuid().v4();

  final String id;
  String label;
  String value;
  SecretFieldType type;
  bool protected;

  SecretField copyWith({
    String? label,
    String? value,
    SecretFieldType? type,
    bool? protected,
  }) {
    return SecretField(
      id: id,
      label: label ?? this.label,
      value: value ?? this.value,
      type: type ?? this.type,
      protected: protected ?? this.protected,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'value': value,
      'type': type.name,
      'protected': protected,
    };
  }

  static SecretField fromMap(Map map) {
    SecretFieldType parseType(dynamic v) {
      if (v is SecretFieldType) return v;
      final String? name = v?.toString();
      for (final SecretFieldType t in SecretFieldType.values) {
        if (t.name == name) return t;
      }
      return SecretFieldType.text;
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is int || v is num) return v != 0;
      if (v is String) {
        final String s = v.toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
      }
      return false;
    }

    return SecretField(
      id: map['id']?.toString(),
      label: map['label']?.toString() ?? '',
      value: map['value']?.toString() ?? '',
      type: parseType(map['type']),
      protected: parseBool(map['protected']),
    );
  }

  /// 解析 customFields 列（JSON 文本）为保密项列表；坏数据静默为空。
  static List<SecretField> fromJsonColumn(String? raw) {
    if (raw == null || raw.isEmpty) return <SecretField>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <SecretField>[];
      return decoded
          .whereType<Map>()
          .map(SecretField.fromMap)
          .where((SecretField f) => f.label.isNotEmpty)
          .toList();
    } catch (_) {
      return <SecretField>[];
    }
  }

  static String toJsonColumn(List<SecretField> fields) {
    if (fields.isEmpty) return '[]';
    return jsonEncode(fields.map((SecretField f) => f.toMap()).toList());
  }
}

/// 编辑页快捷模板：一键填入常用保密项名称。
const List<String> kSecretFieldTemplates = <String>[
  '安全码',
  '客户号',
  '会员号',
  'PIN',
  '备用邮箱',
  '恢复代码',
  '客服电话',
];

/// Select an unused default name without renaming existing fields.
String nextPasswordLabel(Iterable<String> labels) {
  final used = labels.map((s) => s.trim()).toSet();
  int number = 2;
  while (used.contains('密码$number')) {
    number++;
  }
  return '密码$number';
}
