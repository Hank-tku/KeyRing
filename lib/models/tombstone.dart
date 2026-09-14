/// 墓碑传播范围：决定该删除指令发给哪些设备类。
enum TombstoneScope {
  /// 所有对端（条目/工作区被彻底删除，或移入 localOnly 工作区）。
  all,

  /// 仅桌面端（工作区从 full 收窄为 mobileOnly、条目移入 mobileOnly 工作区：
  /// 移动端对端仍能看到目标工作区，应通过正常 upsert 更新而非删除）。
  desktopOnly;

  String get wireName {
    return this == TombstoneScope.all ? 'all' : 'desktop_only';
  }

  static TombstoneScope fromWire(String? raw) {
    return raw == 'desktop_only' ? TombstoneScope.desktopOnly : TombstoneScope.all;
  }

  /// 本墓碑是否应发送给指定设备类（mobile / desktop）。
  bool visibleTo(String deviceClass) {
    return this == TombstoneScope.all || deviceClass == 'desktop';
  }
}

/// 删除墓碑：让「删除 / 移入隐藏工作区 / 工作区收窄」传播到对端，
/// 防止被对端的旧副本复活。只含 id，不泄露名称或内容。
class Tombstone {
  const Tombstone({
    required this.id,
    required this.isWorkspace,
    required this.scope,
    required this.deletedAt,
  });

  /// 条目墓碑或工作区墓碑（工作区墓碑会连带删除其全部分组与条目）。
  final String id;
  final bool isWorkspace;
  final TombstoneScope scope;
  final DateTime deletedAt;

  /// 本地保留期；过期清理（覆盖全部设备离线的窗口）。
  static const Duration ttl = Duration(days: 90);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'kind': isWorkspace ? 'workspace' : 'item',
      'scope': scope.wireName,
      'deletedAt': deletedAt.toIso8601String(),
    };
  }

  static Tombstone fromMap(Map map) {
    String? asString(dynamic v) => v?.toString();
    return Tombstone(
      id: asString(map['id']) ?? '',
      isWorkspace: asString(map['kind']) == 'workspace',
      scope: TombstoneScope.fromWire(asString(map['scope'])),
      deletedAt:
          DateTime.tryParse(asString(map['deletedAt']) ?? '') ??
          DateTime.now(),
    );
  }
}
