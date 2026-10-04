import 'workspace.dart';

/// 分组：工作区内的纯组织单元，不承载同步语义。
class ItemGroup {
  ItemGroup({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.sortWeight = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String workspaceId;
  String name;
  int sortWeight;
  DateTime createdAt;
  DateTime updatedAt;

  ItemGroup copyWith({
    String? name,
    int? sortWeight,
    DateTime? updatedAt,
  }) {
    return ItemGroup(
      id: id,
      workspaceId: workspaceId,
      name: name ?? this.name,
      sortWeight: sortWeight ?? this.sortWeight,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'workspaceId': workspaceId,
      'name': name,
      'sortWeight': sortWeight,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static ItemGroup fromMap(Map map) {
    String? asString(dynamic v) => v?.toString();
    return ItemGroup(
      id: asString(map['id']) ?? '',
      workspaceId: asString(map['workspaceId']) ?? '',
      name: asString(map['name']) ?? '',
      sortWeight: int.tryParse(asString(map['sortWeight']) ?? '') ?? 0,
      createdAt:
          DateTime.tryParse(asString(map['createdAt']) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(asString(map['updatedAt']) ?? '') ??
          DateTime.now(),
    );
  }

  /// 来自同步/导入的对端分组是否落在已知工作区。
  static bool belongsToAny(ItemGroup group, Iterable<Workspace> workspaces) {
    return workspaces.any((Workspace w) => w.id == group.workspaceId);
  }
}
