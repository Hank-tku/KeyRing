import 'package:uuid/uuid.dart';

/// 工作区同步策略。
enum SyncPolicy {
  /// 全设备同步。
  full,

  /// 仅移动端：绝不发送给桌面端（连工作区名称都不发送）。
  mobileOnly,

  /// 仅本机：不参与任何同步。
  localOnly;

  String get wireName {
    return switch (this) {
      SyncPolicy.full => 'full',
      SyncPolicy.mobileOnly => 'mobile_only',
      SyncPolicy.localOnly => 'local_only',
    };
  }

  static SyncPolicy fromWire(String? raw) {
    return switch (raw) {
      'mobile_only' => SyncPolicy.mobileOnly,
      'local_only' => SyncPolicy.localOnly,
      _ => SyncPolicy.full,
    };
  }

  /// 该工作区数据是否允许发送给指定设备类（mobile / desktop）。
  bool visibleTo(String deviceClass) {
    return switch (this) {
      SyncPolicy.full => true,
      SyncPolicy.mobileOnly => deviceClass != 'desktop',
      SyncPolicy.localOnly => false,
    };
  }
}

/// 工作区：一级隔离边界，独立同步策略。
class Workspace {
  Workspace({
    String? id,
    required this.name,
    this.icon,
    this.syncPolicy = SyncPolicy.full,
    this.sortWeight = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// 迁移/旧数据回落的默认工作区（全设备同步）。
  /// 使用固定 id：所有设备对 v1 存量数据归入同一个工作区，避免各自建默认区。
  static const String defaultId = 'ws-default-personal';
  static const String defaultName = '个人';
  static const String defaultIcon = '🏠';

  final String id;
  String name;
  String? icon;
  SyncPolicy syncPolicy;
  int sortWeight;
  DateTime createdAt;
  DateTime updatedAt;

  Workspace copyWith({
    String? name,
    String? icon,
    SyncPolicy? syncPolicy,
    int? sortWeight,
    DateTime? updatedAt,
  }) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      syncPolicy: syncPolicy ?? this.syncPolicy,
      sortWeight: sortWeight ?? this.sortWeight,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'icon': icon,
      'syncPolicy': syncPolicy.wireName,
      'sortWeight': sortWeight,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static Workspace fromMap(Map map) {
    String? asString(dynamic v) => v?.toString();
    return Workspace(
      id: asString(map['id']) ?? '',
      name: asString(map['name']) ?? '',
      icon: asString(map['icon']),
      syncPolicy: SyncPolicy.fromWire(asString(map['syncPolicy'])),
      sortWeight: int.tryParse(asString(map['sortWeight']) ?? '') ?? 0,
      createdAt:
          DateTime.tryParse(asString(map['createdAt']) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(asString(map['updatedAt']) ?? '') ??
          DateTime.now(),
    );
  }
}
