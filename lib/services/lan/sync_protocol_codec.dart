import 'dart:convert';

import '../../models/item_group.dart';
import '../../models/password_item.dart';
import '../../models/tombstone.dart';
import '../../models/workspace.dart';
import '../vault_metadata_service.dart';

class SyncMessageType {
  static const String hello = 'hello';
  static const String verifyRequest = 'verify_request';
  static const String verifyResponse = 'verify_response';
  static const String verifySuccess = 'verify_success';
  static const String verifyFailed = 'verify_failed';
  static const String syncRequest = 'sync_request';
  static const String syncData = 'sync_data';
  static const String syncComplete = 'sync_complete';
  static const String error = 'error';
}

/// hello 握手协商出的对端能力。null 表示 v1 旧端（无结构同步能力）。
class PeerCapabilities {
  const PeerCapabilities({required this.deviceClass});

  /// 'mobile' | 'desktop'；v2 hello 必带。
  final String deviceClass;

  bool get isDesktop => deviceClass == 'desktop';
}

/// sync_data 的完整解析结果（v1 消息的 metadata 部分为空）。
class SyncDataPayload {
  const SyncDataPayload({
    required this.itemMaps,
    required this.isLegacyPeer,
    this.protocolVersion,
    this.vaultVersion,
    this.workspaces = const <Workspace>[],
    this.groups = const <ItemGroup>[],
    this.tombstones = const <Tombstone>[],
    this.peerDeviceClass,
  });

  /// 条目的原始线格式（保留键存在性，供字段保留合并判断缺键）。
  final List<Map<String, dynamic>> itemMaps;
  final bool isLegacyPeer;
  final int? protocolVersion;
  final int? vaultVersion;
  final List<Workspace> workspaces;
  final List<ItemGroup> groups;
  final List<Tombstone> tombstones;
  final String? peerDeviceClass;

  List<PasswordItem> get items =>
      itemMaps.map(PasswordItem.fromMap).toList();
}

class SyncProtocolCodec {
  static const int protocolVersionV2 = 2;

  Map<String, dynamic> decodeMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      return message;
    }
    return jsonDecode(message as String) as Map<String, dynamic>;
  }

  String messageType(Map<String, dynamic> message) =>
      message['type'] as String? ?? '';

  Map<String, dynamic> hello({
    required String? deviceId,
    required String? deviceName,
    required String deviceClass,
  }) {
    return <String, dynamic>{
      'type': SyncMessageType.hello,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceClass': deviceClass,
      'protocolVersion': VaultMetadataService.currentProtocolVersion,
      'capabilities': <String>['workspaces'],
    };
  }

  /// 从 hello 消息解析对端能力；v1 旧端（无 protocolVersion）返回 null。
  PeerCapabilities? readHelloCapabilities(Map<String, dynamic> message) {
    final int? version = message['protocolVersion'] as int?;
    if (version == null || version < protocolVersionV2) {
      return null;
    }
    final String deviceClass =
        message['deviceClass'] as String? ?? 'mobile';
    return PeerCapabilities(deviceClass: deviceClass);
  }

  Map<String, dynamic> verifyRequest(String code) {
    return {'type': SyncMessageType.verifyRequest, 'code': code};
  }

  Map<String, dynamic> verifyResponse(String code) {
    return {'type': SyncMessageType.verifyResponse, 'code': code};
  }

  Map<String, dynamic> verifySuccess() {
    return {'type': SyncMessageType.verifySuccess};
  }

  Map<String, dynamic> verifyFailed(String message) {
    return {'type': SyncMessageType.verifyFailed, 'message': message};
  }

  Map<String, dynamic> syncRequest() {
    return {'type': SyncMessageType.syncRequest};
  }

  Map<String, dynamic> syncComplete() {
    return {'type': SyncMessageType.syncComplete};
  }

  Map<String, dynamic> error(String message) {
    return {'type': SyncMessageType.error, 'message': message};
  }

  /// 组装 sync_data。调用方（同步引擎）负责按对端能力完成发送侧过滤：
  /// [itemMaps] 已按工作区策略过滤（legacy 对端为剥离新键的 v1 条目），
  /// [workspaceMaps]/[groupMaps]/[tombstoneMaps] 为可下发的结构定义与墓碑
  /// （legacy 对端传 null/空）。
  Map<String, dynamic> syncData({
    required List<Map<String, dynamic>> itemMaps,
    List<Map<String, dynamic>>? workspaceMaps,
    List<Map<String, dynamic>>? groupMaps,
    List<Map<String, dynamic>>? tombstoneMaps,
    required String deviceClass,
    required int vaultVersion,
    DateTime? timestamp,
  }) {
    return <String, dynamic>{
      'type': SyncMessageType.syncData,
      'protocolVersion': VaultMetadataService.currentProtocolVersion,
      'vaultVersion': vaultVersion,
      'deviceClass': deviceClass,
      if (workspaceMaps != null) 'workspaces': workspaceMaps,
      if (groupMaps != null) 'groups': groupMaps,
      if (tombstoneMaps != null) 'tombstones': tombstoneMaps,
      'items': itemMaps,
      'timestamp': (timestamp ?? DateTime.now()).millisecondsSinceEpoch,
    };
  }

  SyncDataPayload readSyncData(Map<String, dynamic> message) {
    List<Map<String, dynamic>> parseList(String key) {
      final List<dynamic> raw = message[key] as List<dynamic>? ?? <dynamic>[];
      return raw
          .whereType<Map>()
          .map((Map m) => Map<String, dynamic>.from(m))
          .toList();
    }

    final int? protocolVersion = message['protocolVersion'] as int?;
    return SyncDataPayload(
      protocolVersion: protocolVersion,
      vaultVersion: message['vaultVersion'] as int?,
      isLegacyPeer: protocolVersion == null,
      peerDeviceClass: message['deviceClass'] as String?,
      itemMaps: parseList('items'),
      workspaces: parseList('workspaces')
          .map(Workspace.fromMap)
          .where((Workspace w) => w.id.isNotEmpty)
          .toList(),
      groups: parseList('groups')
          .map(ItemGroup.fromMap)
          .where((ItemGroup g) => g.id.isNotEmpty)
          .toList(),
      tombstones: parseList('tombstones')
          .map(Tombstone.fromMap)
          .where((Tombstone t) => t.id.isNotEmpty)
          .toList(),
    );
  }
}
