import 'app_lock_state.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import '../models/item_group.dart';
import '../models/password_item.dart';
import '../models/tombstone.dart';
import '../models/workspace.dart';
import '../services/password_repository.dart';
import '../services/vault_metadata_service.dart';
import 'device_service.dart';

// Import the manager classes
import 'lan/connection_state_manager.dart';
import 'lan/web_socket_manager.dart';
import 'lan/verification_manager.dart';
import 'lan/service_discovery_manager.dart';
import 'lan/sync_protocol_codec.dart';

class LanSyncService {
  final PasswordRepository repository;

  static const bool _preferServerForLegacyRecovery = bool.fromEnvironment(
    'KEYRING_RECOVERY_SERVER',
  );

  // Managers
  final ConnectionStateManager _stateManager;
  late final WebSocketConnectionManager _connectionManager;
  final VerificationManager _verificationManager;
  final ServiceDiscoveryManager _discoveryManager;
  final VaultMetadataService _metadataService;
  final SyncProtocolCodec _protocolCodec;

  final Map<String, String> _activeVerificationCodes = {};
  final Map<String, bool> _verifiedPeers = {};
  // hello 协商出的对端能力（v2 对端）；v1 旧端不入表（发送时走降级路径）。
  final Map<String, PeerCapabilities> _peerCaps = <String, PeerCapabilities>{};
  Function()? _onSyncSuccess;
  Function(String message)? _onCompatibilityWarning;
  Completer<void>? _serverSyncCompleter;
  bool _legacyPeerDetected = false;
  bool _stopRequested = false;

  HttpServer? _server;
  String? _deviceId;
  String? _deviceName;
  String _deviceClass = 'mobile';
  int _port = 0;

  // Callbacks
  Function(String peerId, String code, Function(bool) onResponse)?
  _onServerCodeDisplay;

  LanSyncService({required this.repository})
    : _stateManager = ConnectionStateManager(),
      _verificationManager = VerificationManager(ConnectionStateManager()),
      _discoveryManager = ServiceDiscoveryManager(),
      _metadataService = VaultMetadataService(),
      _protocolCodec = SyncProtocolCodec() {
    // Initialize connection manager with the state manager
    _connectionManager = WebSocketConnectionManager();
  }

  Stream<Map<String, ConnectionState>> get connectionStateStream =>
      _stateManager.stateStream;

  // 启动服务端准备
  Future<void> _ensureServerReady() async {
    try {
      // Get device ID and name
      final deviceService = DeviceService();
      final String storedDeviceId = await deviceService.getOrCreateDeviceId();
      _deviceId ??= _preferServerForLegacyRecovery
          ? 'zzzz-$storedDeviceId'
          : storedDeviceId;
      _deviceName ??= await deviceService.getOrCreateDeviceName();
      _deviceClass = deviceService.getDeviceClass();
      // Start HTTP server for WebSocket signaling if not already started
      if (_server == null) {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          0,
          shared: true,
        );
        _port = _server!.port;
        _setupWebSocketServer();
      }
    } catch (e) {
      debugPrint('启动服务准备失败: $e');
      rethrow;
    }
  }

  // 启动服务端配置
  void _setupWebSocketServer() {
    _server!.listen((HttpRequest req) async {
      bool isUpgrade = WebSocketTransformer.isUpgradeRequest(req);
      if (req.uri.path == '/sync' && isUpgrade) {
        try {
          final WebSocket socket = await WebSocketTransformer.upgrade(req);
          final WebSocketChannel channel = IOWebSocketChannel(socket);

          // 生成客户端ID（可以从查询参数获取或自动生成）
          final peerId =
              req.uri.queryParameters['peerId'] ??
              'client_${DateTime.now().millisecondsSinceEpoch}';

          // 使用 ConnectionManager 注册连接
          _connectionManager.registerConnection(peerId, channel);

          // 设置消息处理器
          _setupClientMessageHandlers(peerId);
        } catch (e) {
          debugPrint('http服务升级WebSocket失败: $e');
          req.response.statusCode = 500;
          req.response.write('Internal Server Error');
          req.response.close();
        }
      } else {
        req.response.statusCode = 404;
        req.response.write('Not found');
        req.response.close();
      }
    });
  }

  // 服务端：消息监听
  void _setupClientMessageHandlers(String peerId) {
    // 监听来自特定客户端的所有消息
    _connectionManager.getMessageStream(peerId).listen((message) {
      _handleWebSocketMessage(message, peerId);
    });
  }

  // 服务端：消息处理
  Future<void> _handleWebSocketMessage(dynamic message, String peerId) async {
    try {
      final Map<String, dynamic> data = _protocolCodec.decodeMessage(message);
      final String type = _protocolCodec.messageType(data);

      switch (type) {
        case SyncMessageType.hello:
          await _handleHelloMessage(data, peerId);
          debugPrint('hello');
          break;
        case SyncMessageType.verifyResponse:
          await _handleVerifyResponse(data, peerId);
          debugPrint('verify_response');
          break;
        case SyncMessageType.syncRequest:
          await _handleSyncRequest(peerId);
          debugPrint('sync_request');
          break;
        case SyncMessageType.syncData:
          debugPrint('sync_data before');
          await _handleSyncData(data, peerId);
          break;
        case SyncMessageType.syncComplete:
          debugPrint('sync_complete');
          _completeServerSync();
          break;
        default:
          // 未知消息类型
          _connectionManager.sendMessage(
            peerId,
            _protocolCodec.error('未知消息类型: $type'),
          );
      }
    } catch (e) {
      debugPrint('处理消息时出错$e');
      _connectionManager.sendMessage(
        peerId,
        _protocolCodec.error('处理消息时出错: $e'),
      );
    }
  }

  // 服务端：消息处理-Hello握手
  Future<void> _handleHelloMessage(
    Map<String, dynamic> data,
    String peerId,
  ) async {
    final String? clientDeviceId = data['deviceId'] as String?;
    final String clientDeviceName =
        data['deviceName'] as String? ?? 'Unknown Device';

    if (_preferServerForLegacyRecovery &&
        !clientDeviceName.toLowerCase().contains('android')) {
      _connectionManager.sendMessage(
        peerId,
        _protocolCodec.error('Recovery sync only accepts Android devices.'),
      );
      await _connectionManager.closeConnection(peerId);
      return;
    }

    if (clientDeviceId == null || clientDeviceId == _deviceId) {
      _connectionManager.sendMessage(
        peerId,
        _protocolCodec.error('Invalid device ID'),
      );
      await _connectionManager.closeConnection(peerId);
      return;
    }

    // 记录对端能力，随后回敬本端 hello（v1 旧端会忽略该消息）。
    final PeerCapabilities? caps = _protocolCodec.readHelloCapabilities(data);
    if (caps != null) {
      _peerCaps[peerId] = caps;
    }
    _connectionManager.sendMessage(
      peerId,
      _protocolCodec.hello(
        deviceId: _deviceId,
        deviceName: _deviceName,
        deviceClass: _deviceClass,
      ),
    );

    // 服务端：消息处理-生成验证码
    final String code = _generateVerificationCode();
    _activeVerificationCodes[peerId] = code;

    // 发送验证请求
    _connectionManager.sendMessage(peerId, _protocolCodec.verifyRequest(code));

    // 显示验证码给用户（服务端）
    if (_onServerCodeDisplay != null) {
      _onServerCodeDisplay!(clientDeviceName, code, (bool approved) async {
        if (approved) {
          _connectionManager.markAsVerified(peerId);
          _connectionManager.sendMessage(
            peerId,
            _protocolCodec.verifySuccess(),
          );
          debugPrint('客户端 $clientDeviceName 验证通过');
        } else {
          _connectionManager.sendMessage(
            peerId,
            _protocolCodec.verifyFailed('Server rejected the connection'),
          );
          await _connectionManager.closeConnection(peerId);
        }
      });
    }
  }

  // 服务端：消息处理-验证码验证
  Future<void> _handleVerifyResponse(
    Map<String, dynamic> data,
    String peerId,
  ) async {
    final String? receivedCode = data['code'] as String?;
    final String? expectedCode = _activeVerificationCodes[peerId];

    if (receivedCode == expectedCode) {
      _connectionManager.markAsVerified(peerId);
      _activeVerificationCodes.remove(peerId);
      _connectionManager.sendMessage(peerId, _protocolCodec.verifySuccess());
    } else {
      _connectionManager.sendMessage(
        peerId,
        _protocolCodec.verifyFailed('验证码错误'),
      );
      await _connectionManager.closeConnection(peerId);
    }
  }

  // 服务端：消息处理-数据同步
  Future<void> _handleSyncRequest(String peerId) async {
    if (!_connectionManager.isVerified(peerId)) {
      _connectionManager.sendMessage(peerId, _protocolCodec.error('验证码错误'));
      return;
    }

    // 按对端能力过滤后发送（选择性同步的核心路径）。
    _connectionManager.sendMessage(
      peerId,
      await _buildOutgoingSyncData(peerId),
    );
  }

  Future<void> _handleSyncData(Map<String, dynamic> data, String peerId) async {
    if (!_connectionManager.isVerified(peerId)) {
      return;
    }

    final SyncDataPayload payload = _protocolCodec.readSyncData(data);
    await _applyIncomingSyncData(payload);

    _completeServerSync();
  }

  /// 组装发给指定对端的 sync_data（发送侧过滤，设计文档 §5.2）。
  ///
  /// - v1 旧端：剥离 v2 新键，退回纯条目同步；
  /// - v2 对端：只发送对端可见工作区的条目与结构定义（桌面端收不到
  ///   mobileOnly 工作区的任何痕迹，连名称都没有）；墓碑按 scope 过滤。
  Future<Map<String, dynamic>> _buildOutgoingSyncData(String peerId) async {
    final int vaultVersion = (await _metadataService.load()).vaultVersion;
    final generation = repository.access.generation;
    final PeerCapabilities? caps = _peerCaps[peerId];
    final List<PasswordItem> allItems = repository.itemsNotifier.value
        .where((item) => !AppLockState.isLocked && repository.access.canAccess(item.workspaceId))
        .toList();

    if (caps == null) {
      return _protocolCodec.syncData(
        itemMaps: allItems
            .where((item) => repository.workspacesNotifier.value.any((w) => w.id == item.workspaceId && w.syncPolicy == SyncPolicy.full))
            .map((PasswordItem item) => item.toLegacyMap())
            .toList(),
        deviceClass: _deviceClass,
        vaultVersion: vaultVersion,
      );
    }

    final String peerClass = caps.deviceClass;
    final List<Workspace> visibleWorkspaces = repository
        .workspacesNotifier
        .value
        .where(
          (Workspace w) =>
              !AppLockState.isLocked && w.syncPolicy.visibleTo(peerClass) &&
              repository.access.canAccess(w.id),
        )
        .toList();
    final Set<String> visibleWorkspaceIds = visibleWorkspaces
        .map((Workspace w) => w.id)
        .toSet();
    final List<Map<String, dynamic>> itemMaps = allItems
        .where(
          (PasswordItem item) => visibleWorkspaceIds.contains(item.workspaceId),
        )
        .map((PasswordItem item) => item.toMap())
        .toList();
    final List<Tombstone> tombstones = await repository.tombstonesFor(
      peerClass,
    );

    if (generation != repository.access.generation || AppLockState.isLocked) {
      return _protocolCodec.syncData(itemMaps: [], deviceClass: _deviceClass, vaultVersion: vaultVersion);
    }

    return _protocolCodec.syncData(
      itemMaps: itemMaps,
      workspaceMaps: visibleWorkspaces.map((Workspace w) => w.toMap()).toList(),
      groupMaps: repository.groupsNotifier.value
          .where((ItemGroup g) => visibleWorkspaceIds.contains(g.workspaceId))
          .map((ItemGroup g) => g.toMap())
          .toList(),
      tombstoneMaps: tombstones.map((Tombstone t) => t.toMap()).toList(),
      deviceClass: _deviceClass,
      vaultVersion: vaultVersion,
    );
  }

  /// 应用对端发来的 sync_data（接收侧防御 + 字段保留合并 + 墓碑，
  /// 全部逻辑收敛在 repository.applyIncoming，设计文档 §5.3-§5.5）。
  Future<void> _applyIncomingSyncData(SyncDataPayload payload) async {
    if (payload.isLegacyPeer) {
      _legacyPeerDetected = true;
      _onCompatibilityWarning?.call(
        '对方为旧版本：条目仍可同步，但工作区、分组、保密项与删除不会同步，'
        '也没有「仅移动端」保护。建议对方升级到最新版。',
      );
    }
    await repository.applyIncoming(
      rawItems: payload.itemMaps,
      rawWorkspaces: payload.workspaces
          .map((Workspace w) => w.toMap())
          .toList(),
      rawGroups: payload.groups.map((ItemGroup g) => g.toMap()).toList(),
      rawTombstones: payload.tombstones
          .map((Tombstone t) => t.toMap())
          .toList(),
      localDeviceClass: _deviceClass,
    );
  }

  void _completeServerSync() {
    final Completer<void>? completer = _serverSyncCompleter;
    if (completer == null) {
      return;
    }

    if (!completer.isCompleted) {
      completer.complete();

      // 数据同步传输成功后关闭弹窗，并提示成功的消息
      if (_onSyncSuccess != null) {
        _onSyncSuccess!();
      }
    }
  }

  String _generateVerificationCode() {
    final Random random = Random.secure();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<void> cleanup() async {
    await _connectionManager.closeAllConnections();
    _activeVerificationCodes.clear();
    _verifiedPeers.clear();
    _peerCaps.clear();
  }

  Future<void> resetServer() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }

  Future<void> stopSync() async {
    _stopRequested = true;
    final Completer<void>? serverSyncCompleter = _serverSyncCompleter;
    if (serverSyncCompleter != null && !serverSyncCompleter.isCompleted) {
      serverSyncCompleter.complete();
    }
    await _cleanupResources();
  }

  void dispose() async {
    await cleanup();

    _connectionManager.dispose();
    _stateManager.dispose();
  }

  // 同步逻辑
  Future<Map<String, dynamic>> discoverAndSyncOnce({
    required Function(String deviceName, String code, Function(bool) onResponse)
    onServerCodeDisplay,
    required Function(String deviceName, Function(String) onCodeEntered)
    onClientCodeInput,
    Function()? onSyncSuccess,
    Function(String message)? onCompatibilityWarning,
  }) async {
    _onServerCodeDisplay = onServerCodeDisplay;
    _onSyncSuccess = onSyncSuccess;
    _onCompatibilityWarning = onCompatibilityWarning;
    _serverSyncCompleter = null;
    _legacyPeerDetected = false;
    _stopRequested = false;

    try {
      await _ensureServerReady();
      if (_stopRequested) {
        return {'status': 'stopped', 'message': '同步已停止'};
      }

      // 启动广播
      await _discoveryManager.startBroadcast(_deviceId!, _deviceName!, _port);
      if (_stopRequested) {
        return {'status': 'stopped', 'message': '同步已停止'};
      }

      // 发现设备
      final peers = await _discoveryManager.discoverPeers(
        const Duration(seconds: 12),
        _deviceId!,
      );
      if (_stopRequested) {
        return {'status': 'stopped', 'message': '同步已停止'};
      }

      if (peers.isEmpty) {
        return {'status': 'error', 'message': '未找到设备'};
      }

      final Set<DiscoveredPeer> candidatePeers = _preferServerForLegacyRecovery
          ? peers
                .where(
                  (DiscoveredPeer peer) =>
                      peer.name.toLowerCase().contains('android'),
                )
                .toSet()
          : peers;

      if (candidatePeers.isEmpty) {
        return {'status': 'error', 'message': '未找到旧手机'};
      }

      // Process only the first peer for now to avoid complexity
      if (candidatePeers.isNotEmpty) {
        final peer = _selectPeer(candidatePeers);
        try {
          // 角色判断：设备ID较大的作为客户端
          final bool weAreClient =
              !_preferServerForLegacyRecovery &&
              _deviceId!.compareTo(peer.id) < 0;

          if (weAreClient) {
            await _syncAsClient(peer, onClientCodeInput);
            if (_stopRequested) {
              return {'status': 'stopped', 'message': '同步已停止'};
            }
            return {
              'status': 'success',
              'message': _legacyPeerDetected
                  ? '同步成功，对方版本较旧，建议升级后继续同步。'
                  : '同步成功',
            };
          } else {
            _serverSyncCompleter = Completer<void>();
            await _waitForServerSync(peer);
            if (_stopRequested) {
              return {'status': 'stopped', 'message': '同步已停止'};
            }
            return {
              'status': 'success',
              'message': _legacyPeerDetected
                  ? '同步成功，对方版本较旧，建议升级后继续同步。'
                  : '同步成功',
            };
          }
        } catch (e) {
          debugPrint('局域网连接异常 ${peer.name}: $e');
          return {'status': 'error', 'message': '局域网连接异常'};
        }
      }

      return {'status': 'pending', 'message': '同步中...'};
    } catch (e) {
      return {
        'status': 'error',
        'error': e.toString(),
        'message': '同步失败: ${e.toString()}',
      };
    } finally {
      // 确保资源正确关闭
      await _cleanupResources();
      _serverSyncCompleter = null;
      _stopRequested = false;
    }
  }

  DiscoveredPeer _selectPeer(Set<DiscoveredPeer> peers) {
    final List<DiscoveredPeer> orderedPeers = peers.toList()
      ..sort((DiscoveredPeer a, DiscoveredPeer b) {
        if (!_preferServerForLegacyRecovery) {
          return 0;
        }

        final bool aIsAndroid = a.name.toLowerCase().contains('android');
        final bool bIsAndroid = b.name.toLowerCase().contains('android');
        if (aIsAndroid != bIsAndroid) {
          return aIsAndroid ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });

    return orderedPeers.first;
  }

  Future<void> _waitForServerSync(DiscoveredPeer peer) async {
    final Completer<void>? completer = _serverSyncCompleter;
    if (completer == null) {
      throw StateError('Server sync waiter was not initialized.');
    }

    final Timer timeoutTimer = Timer(const Duration(seconds: 150), () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('等待 ${peer.name} 同步超时'));
      }
    });

    try {
      await completer.future;
    } on TimeoutException catch (e) {
      debugPrint('服务端等待同步超时 ${peer.name}: $e');
      throw Exception('等待对方完成同步超时');
    } finally {
      timeoutTimer.cancel();
    }
  }

  // 资源清理
  Future<void> _cleanupResources() async {
    try {
      await _connectionManager.closeAllConnections();
      await _discoveryManager.stopDiscovery();
      await _discoveryManager.stopBroadcast();
      _verificationManager.clearAllCodes();
      await _server?.close(force: true);
      _server = null;
      _port = 0;
    } catch (e) {
      debugPrint('Error during cleanup: $e');
    }
  }

  // 客户端同步逻辑
  Future<void> _syncAsClient(
    DiscoveredPeer peer,
    Function(String deviceName, Function(String) onCodeEntered)
    onClientCodeInput,
  ) async {
    String peerId = peer.id; // Store peerId for cleanup
    Timer? verificationTimer; // 添加定时器变量
    Timer? syncTimer; // 添加同步定时器变量
    try {
      // 连接对端设备
      await _connectionManager.connectToPeer(peer.id, peer.host, peer.port);

      // 使用单一的消息监听器
      final Completer<bool> verificationCompleter = Completer<bool>();
      final Completer<void> syncCompleter = Completer<void>();

      // 设置消息监听器（只设置一次）
      final subscription = _connectionManager
          .getMessageStream(peer.id)
          .listen(
            (message) async {
              try {
                final data = _protocolCodec.decodeMessage(message);
                await _handleClientMessage(
                  peer,
                  data,
                  onClientCodeInput,
                  verificationCompleter,
                  syncCompleter,
                );
              } catch (e) {
                debugPrint('Error handling client message: $e');
              }
            },
            onDone: () {
              if (!verificationCompleter.isCompleted) {
                verificationCompleter.complete(false);
              }
              if (!syncCompleter.isCompleted) {
                syncCompleter.complete();
              }
            },
            cancelOnError: true,
          );

      // 发送hello消息开始握手
      _connectionManager.sendMessage(
        peer.id,
        _protocolCodec.hello(
          deviceId: _deviceId,
          deviceName: _deviceName,
          deviceClass: _deviceClass,
        ),
      );

      // 创建手动控制的定时器来处理验证超时
      verificationTimer = Timer(const Duration(seconds: 120), () {
        if (!verificationCompleter.isCompleted) {
          debugPrint('验证超时: ${peer.name}');
          verificationCompleter.complete(false);
        }
      });

      final bool verified = await verificationCompleter.future;
      if (_stopRequested) {
        await subscription.cancel();
        await _connectionManager.closeConnection(peer.id);
        return;
      }

      // 取消定时器，防止内存泄漏
      verificationTimer.cancel();
      verificationTimer = null;

      debugPrint('验证：$verified');
      if (verified) {
        // 执行数据同步
        await _performClientSync(peer.id);

        // 创建同步超时定时器
        syncTimer = Timer(const Duration(seconds: 30), () {
          if (!syncCompleter.isCompleted) {
            syncCompleter.complete();
          }
        });

        await syncCompleter.future;
        if (_stopRequested) {
          await subscription.cancel();
          await _connectionManager.closeConnection(peer.id);
          return;
        }

        // 取消同步定时器
        syncTimer.cancel();
        syncTimer = null;
        _connectionManager.sendMessage(peer.id, {'type': 'sync_complete'});
      } else {}

      // 清理资源
      await subscription.cancel();
      await _connectionManager.closeConnection(peer.id);
    } catch (e) {
      debugPrint('客户端同步错误 ${peer.name}: $e');
      await _connectionManager.closeConnection(
        peerId,
      ); // Use stored peerId for cleanup
      rethrow;
    } finally {
      // 手动清理定时器资源
      verificationTimer?.cancel();
      syncTimer?.cancel();
    }
  }

  // 客户端：数据同步
  Future<void> _performClientSync(String peerId) async {
    // 请求对端数据
    _connectionManager.sendMessage(peerId, _protocolCodec.syncRequest());
    await Future.delayed(const Duration(seconds: 1));
    // 发送本地数据（按对端能力过滤后的）
    debugPrint('向服务端发送 sync_data');
    _connectionManager.sendMessage(
      peerId,
      await _buildOutgoingSyncData(peerId),
    );
  }

  // 客户端：消息处理
  Future<void> _handleClientMessage(
    DiscoveredPeer peer,
    Map<String, dynamic> data,
    Function(String, Function(String)) onCodeEntered,
    Completer<bool> verificationCompleter,
    Completer<void> syncCompleter,
  ) async {
    try {
      final String type = _protocolCodec.messageType(data);
      switch (type) {
        case SyncMessageType.hello:
          // 服务端回敬的 hello：记录对端能力（v2），供后续发送过滤使用。
          final PeerCapabilities? caps = _protocolCodec.readHelloCapabilities(
            data,
          );
          if (caps != null) {
            _peerCaps[peer.id] = caps;
          }
          break;

        case SyncMessageType.verifyRequest:
          final String? code = data['code'] as String?;
          if (code != null) {
            onCodeEntered(peer.name, (String inputCode) {
              _connectionManager.sendMessage(
                peer.id,
                _protocolCodec.verifyResponse(inputCode),
              );
            });
          }
          debugPrint('verify_request');
          break;

        case SyncMessageType.verifySuccess:
          _connectionManager.markAsVerified(peer.id);
          if (!verificationCompleter.isCompleted) {
            verificationCompleter.complete(true);
          }
          debugPrint('verify_success');
          break;

        case SyncMessageType.verifyFailed:
          if (!verificationCompleter.isCompleted) {
            verificationCompleter.complete(false);
          }
          debugPrint('verify_failed');
          break;

        case SyncMessageType.error:
          if (!verificationCompleter.isCompleted) {
            verificationCompleter.complete(false);
          }
          debugPrint('同步错误 from ${peer.name}: ${data['message']}');
          break;

        case SyncMessageType.syncData:
          debugPrint('sync_data before');
          await _handleSyncData(data, peer.id);
          if (!syncCompleter.isCompleted) {
            syncCompleter.complete();
          }
          break;
        case SyncMessageType.syncComplete:
          debugPrint('sync_complete');
          // 数据同步传输成功后关闭连接，并提示成功的消息
          break;

        default:
          debugPrint('消息类型错误 from ${peer.name}: $type');
      }
    } catch (e) {
      debugPrint('处理消息时出错$e');
      _connectionManager.sendMessage(
        peer.id,
        _protocolCodec.error('处理消息时出错: $e'),
      );
    }
  }
}
