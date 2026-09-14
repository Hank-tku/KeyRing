import 'package:uuid/uuid.dart';

import 'secret_field.dart';

class PasswordItem {
  PasswordItem({
    String? id,
    required this.title,
    required this.username,
    required this.password,
    this.url,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isFavorite = false,
    this.workspaceId = '',
    this.groupId,
    List<SecretField>? customFields,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       customFields = customFields ?? <SecretField>[];

  final String id;
  String title;
  String username;
  String password;
  String? url;
  String? notes;
  DateTime createdAt;
  DateTime updatedAt;
  bool isFavorite;

  /// 所属工作区。空串表示「未指定」：写入时由仓库回落到默认工作区，
  /// 合并时若本地已有该条目则保留本地归属（旧版本数据兼容）。
  String workspaceId;

  /// 所属分组（工作区内），null 表示未分组。
  String? groupId;

  /// 自定义保密项（安全码、客户号等）。
  List<SecretField> customFields;

  PasswordItem copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    Object? notes = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    String? workspaceId,
    Object? groupId = _unset,
    List<SecretField>? customFields,
  }) {
    return PasswordItem(
      id: id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes == _unset ? this.notes : notes as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      workspaceId: workspaceId ?? this.workspaceId,
      groupId: groupId == _unset ? this.groupId : groupId as String?,
      customFields: customFields ?? this.customFields,
    );
  }

  static const Object _unset = Object();

  /// 线格式（同步协议 / 导出 JSON）：customFields 为对象数组。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'username': username,
      'password': password,
      'url': url,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isFavorite': isFavorite ? 1 : 0, // Convert bool to int for SQLite
      'workspaceId': workspaceId,
      'groupId': groupId,
      'customFields': customFields.map((SecretField f) => f.toMap()).toList(),
    };
  }

  static PasswordItem fromMap(Map map) {
    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is int) return v != 0;
      if (v is num) return v != 0;
      if (v is String) {
        final String s = v.toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
      }
      return false;
    }

    String? asString(dynamic v) => v?.toString();

    final String? createdAtStr = asString(map['createdAt']);
    final String? updatedAtStr = asString(map['updatedAt']);

    // customFields 兼容三种形态：对象数组（协议/导出）、
    // JSON 字符串（SQLite 行）、缺失（v1 旧数据 → 空列表）。
    List<SecretField> parseFields(dynamic raw) {
      if (raw is List) {
        return raw.whereType<Map>().map(SecretField.fromMap).toList();
      }
      if (raw is String && raw.isNotEmpty) {
        return SecretField.fromJsonColumn(raw);
      }
      return <SecretField>[];
    }

    return PasswordItem(
      id: asString(map['id']),
      title: asString(map['title']) ?? '',
      username: asString(map['username']) ?? '',
      password: asString(map['password']) ?? '',
      url: asString(map['url']),
      notes: asString(map['notes']),
      createdAt: DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAtStr ?? '') ?? DateTime.now(),
      isFavorite: parseBool(map['isFavorite'] ?? false),
      workspaceId: asString(map['workspaceId']) ?? '',
      groupId: asString(map['groupId']),
      customFields: parseFields(map['customFields']),
    );
  }

  /// 移除线格式中的 v2 新键，得到 v1 旧端可读的条目（legacy 同步降级用）。
  Map<String, dynamic> toLegacyMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'username': username,
      'password': password,
      'url': url,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isFavorite': isFavorite ? 1 : 0,
    };
  }
}
