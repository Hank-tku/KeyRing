import 'dart:convert';

import '../../models/password_item.dart';
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

class SyncDataPayload {
  const SyncDataPayload({
    required this.items,
    required this.isLegacyPeer,
    this.protocolVersion,
    this.vaultVersion,
  });

  final List<PasswordItem> items;
  final bool isLegacyPeer;
  final int? protocolVersion;
  final int? vaultVersion;
}

class SyncProtocolCodec {
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
  }) {
    return {
      'type': SyncMessageType.hello,
      'deviceId': deviceId,
      'deviceName': deviceName,
    };
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

  Map<String, dynamic> syncData({
    required List<PasswordItem> items,
    required int vaultVersion,
    DateTime? timestamp,
  }) {
    return {
      'type': SyncMessageType.syncData,
      'protocolVersion': VaultMetadataService.currentProtocolVersion,
      'vaultVersion': vaultVersion,
      'items': items.map((PasswordItem item) => item.toMap()).toList(),
      'timestamp': (timestamp ?? DateTime.now()).millisecondsSinceEpoch,
    };
  }

  SyncDataPayload readSyncData(Map<String, dynamic> message) {
    final List<dynamic> rawItems =
        message['items'] as List<dynamic>? ?? <dynamic>[];
    return SyncDataPayload(
      protocolVersion: message['protocolVersion'] as int?,
      vaultVersion: message['vaultVersion'] as int?,
      isLegacyPeer: message['protocolVersion'] == null,
      items: rawItems
          .map(
            (dynamic raw) => PasswordItem.fromMap(raw as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
