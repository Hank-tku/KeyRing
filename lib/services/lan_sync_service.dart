import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import '../models/password_item.dart';
import '../services/password_repository.dart';
import 'device_service.dart';

// Import the manager classes
import 'lan/connection_state_manager.dart';
import 'lan/web_socket_manager.dart';
import 'lan/verification_manager.dart';
import 'lan/data_sync_engine.dart';
import 'lan/service_discovery_manager.dart';

class LanSyncService {
  final PasswordRepository repository;

  // Managers
  final ConnectionStateManager _stateManager;
  late final WebSocketConnectionManager _connectionManager;
  final VerificationManager _verificationManager;
  final DataSyncEngine _syncEngine;
  final ServiceDiscoveryManager _discoveryManager;

  final Map<String, String> _activeVerificationCodes = {};
  final Map<String, bool> _verifiedPeers = {};
  Function()? _onSyncSuccess;

  HttpServer? _server;
  String? _deviceId;
  String? _deviceName;
  int _port = 0;

  // Callbacks
  Function(String peerId, String code, Function(bool) onResponse)?
  _onServerCodeDisplay;

  LanSyncService({required this.repository})
    : _stateManager = ConnectionStateManager(),
      // _connectionManager = WebSocketConnectionManager(ConnectionStateManager()),
      _verificationManager = VerificationManager(ConnectionStateManager()),
      _syncEngine = DataSyncEngine(repository),
      _discoveryManager = ServiceDiscoveryManager() {
    // Initialize connection manager with the state manager
    _connectionManager = WebSocketConnectionManager(_stateManager);
  }

  Stream<Map<String, ConnectionState>> get connectionStateStream =>
      _stateManager.stateStream;

  // 启动服务端准备
  Future<void> _ensureServerReady() async {
    try {
      // Get device ID and name
      final deviceService = DeviceService();
      _deviceId ??= await deviceService.getOrCreateDeviceId();
      _deviceName ??= await deviceService.getOrCreateDeviceName();
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
      print('启动服务准备失败: $e');
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
          print('http服务升级WebSocket失败: $e');
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
      final Map<String, dynamic> data =
          jsonDecode(message as String) as Map<String, dynamic>;
      final String type = data['type'] as String? ?? '';

      switch (type) {
        case 'hello':
          await _handleHelloMessage(data, peerId);
          print('hello');
          break;
        case 'verify_response':
          await _handleVerifyResponse(data, peerId);
          print('verify_response');
          break;
        case 'sync_request':
          await _handleSyncRequest(peerId);
          print('sync_request');
          break;
        case 'sync_data':
          print('sync_data before');
          await _handleSyncData(data, peerId, false);
          break;
        case 'sync_complete':
          print('sync_complete');
          // 数据同步传输成功后关闭弹窗，并提示成功的消息
          if (_onSyncSuccess != null) {
            _onSyncSuccess!();
          }
          break;
        default:
          // 未知消息类型
          _connectionManager.sendMessage(peerId, {
            'type': 'error',
            'message': '未知消息类型: $type',
          });
      }
    } catch (e) {
      print('处理消息时出错$e');
      _connectionManager.sendMessage(peerId, {
        'type': 'error',
        'message': '处理消息时出错: $e',
      });
    }
  }

  // 服务端：消息处理-Hello握手
  Future<void> _handleHelloMessage(
    Map<String, dynamic> data,
    String peerId,
  ) async {
    final String? clientDeviceId = data['deviceId'] as String?;
    final String? clientDeviceName =
        data['deviceName'] as String? ?? 'Unknown Device';

    if (clientDeviceId == null || clientDeviceId == _deviceId) {
      _connectionManager.sendMessage(peerId, {
        'type': 'error',
        'message': 'Invalid device ID',
      });
      await _connectionManager.closeConnection(peerId);
      return;
    }

    // 服务端：消息处理-生成验证码
    final String code = _generateVerificationCode();
    _activeVerificationCodes[peerId] = code;

    // 发送验证请求
    _connectionManager.sendMessage(peerId, {
      'type': 'verify_request',
      'code': code,
    });

    // 显示验证码给用户（服务端）
    if (_onServerCodeDisplay != null) {
      _onServerCodeDisplay!(clientDeviceName!, code, (bool approved) async {
        if (approved) {
          _connectionManager.markAsVerified(peerId);
          _connectionManager.sendMessage(peerId, {'type': 'verify_success'});
          print('客户端 $clientDeviceName 验证通过');
        } else {
          _connectionManager.sendMessage(peerId, {
            'type': 'verify_failed',
            'message': 'Server rejected the connection',
          });
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
      _connectionManager.sendMessage(peerId, {'type': 'verify_success'});
    } else {
      _connectionManager.sendMessage(peerId, {
        'type': 'verify_failed',
        'message': '验证码错误',
      });
      await _connectionManager.closeConnection(peerId);
    }
  }

  // 服务端：消息处理-数据同步
  Future<void> _handleSyncRequest(String peerId) async {
    if (!_connectionManager.isVerified(peerId)) {
      _connectionManager.sendMessage(peerId, {
        'type': 'error',
        'message': '验证码错误',
      });
      return;
    }

    // 获取本地数据并发送
    final List<Map<String, dynamic>> items = repository.itemsNotifier.value
        .map((PasswordItem e) => e.toMap())
        .toList();

    _connectionManager.sendMessage(peerId, {
      'type': 'sync_data',
      'items': items,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _handleSyncData(
    Map<String, dynamic> data,
    String peerId,
    bool isClient,
  ) async {
    if (!_connectionManager.isVerified(peerId)) {
      return;
    }

    final List<dynamic> items =
        (data['items'] as List<dynamic>? ?? <dynamic>[]);
    for (final dynamic raw in items) {
      final PasswordItem remote = PasswordItem.fromMap(
        raw as Map<String, dynamic>,
      );
      await _syncItemByTimestamp(remote, peerId);
    }
  }

  Future<void> _syncItemByTimestamp(PasswordItem remote, String peerId) async {
    final List<PasswordItem> localItems = repository.itemsNotifier.value;
    final PasswordItem? local = localItems
        .where((item) => item.id == remote.id)
        .firstOrNull;

    if (local == null) {
      await repository.addItem(remote);
    } else if (remote.updatedAt.isAfter(local.updatedAt)) {
      await repository.updateItem(remote);
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
  }

  void resetServer() async {
    await _server?.close();
    _server = null;
    _port = 0;
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
  }) async {
    _onServerCodeDisplay = onServerCodeDisplay;
    _onSyncSuccess = onSyncSuccess;

    try {
      await _ensureServerReady();

      // 启动广播
      await _discoveryManager.startBroadcast(_deviceId!, _deviceName!, _port);

      // 发现设备
      final peers = await _discoveryManager.discoverPeers(
        const Duration(seconds: 12),
        _deviceId!,
      );

      if (peers.isEmpty) {
        return {'status': false, 'message': '未找到设备'};
      }

      // Process only the first peer for now to avoid complexity
      if (peers.isNotEmpty) {
        final peer = peers.first;
        try {
          // 角色判断：设备ID较大的作为客户端
          final bool weAreClient = _deviceId!.compareTo(peer.id) < 0;

          if (weAreClient) {
            await _syncAsClient(peer, onClientCodeInput);
            return {'status': 'success', 'message': '同步成功'};
          } else {
            // 服务器角色，等待客户端连接
            // For server role, we should wait for incoming connections
            // The server logic is handled by _setupWebSocketServer and related handlers
            // We'll wait for a reasonable amount of time for the sync to complete
            // await Future.delayed(const Duration(seconds: 15));
            // return {'status': 'success', 'message': '同步成功'};
          }
        } catch (e) {
          print('局域网连接异常 ${peer.name}: $e');
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
    }
  }

  // 资源清理
  Future<void> _cleanupResources() async {
    try {
      await _connectionManager.closeAllConnections();
      await _discoveryManager.stopDiscovery();
      await _discoveryManager.stopBroadcast();
      _verificationManager.clearAllCodes();
      _server = null;
    } catch (e) {
      print('Error during cleanup: $e');
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
      final channel = await _connectionManager.connectToPeer(
        peer.id,
        peer.host,
        peer.port,
      );

      // 使用单一的消息监听器
      final Completer<bool> verificationCompleter = Completer<bool>();
      final Completer<void> syncCompleter = Completer<void>();

      // 设置消息监听器（只设置一次）
      final subscription = _connectionManager.getMessageStream(peer.id).listen((
        message,
      ) async {
        try {
          final data = jsonDecode(message) as Map<String, dynamic>;
          await _handleClientMessage(
            peer,
            data,
            onClientCodeInput,
            verificationCompleter,
            syncCompleter,
          );
        } catch (e) {
          print('Error handling client message: $e');
        }
      }, cancelOnError: true);

      // 发送hello消息开始握手
      _connectionManager.sendMessage(peer.id, {
        'type': 'hello',
        'deviceId': _deviceId,
        'deviceName': _deviceName,
      });

      // 创建手动控制的定时器来处理验证超时
      verificationTimer = Timer(const Duration(seconds: 120), () {
        if (!verificationCompleter.isCompleted) {
          print('验证超时: ${peer.name}');
          verificationCompleter.complete(false);
        }
      });

      final bool verified = await verificationCompleter.future;

      // 取消定时器，防止内存泄漏
      verificationTimer.cancel();
      verificationTimer = null;

      print('验证：$verified');
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

        // 取消同步定时器
        syncTimer.cancel();
        syncTimer = null;
        _connectionManager.sendMessage(peer.id, {'type': 'sync_complete'});
      } else {}

      // 清理资源
      await subscription.cancel();
      await _connectionManager.closeConnection(peer.id);
    } catch (e) {
      print('客户端同步错误 ${peer.name}: $e');
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
    _connectionManager.sendMessage(peerId, {'type': 'sync_request'});
    await Future.delayed(const Duration(seconds: 1));
    // 发送本地数据
    final List<Map<String, dynamic>> localData = _syncEngine
        .getLocalDataForSync();
    print('向服务端发送 sync_data');
    _connectionManager.sendMessage(peerId, {
      'type': 'sync_data',
      'items': localData,
    });
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
      final String type = data['type'] as String? ?? '';
      switch (type) {
        case 'verify_request':
          final String? code = data['code'] as String?;
          if (code != null) {
            onCodeEntered(peer.name, (String inputCode) {
              _connectionManager.sendMessage(peer.id, {
                'type': 'verify_response',
                'code': inputCode,
              });
            });
          }
          print('verify_request');
          break;

        case 'verify_success':
          _connectionManager.markAsVerified(peer.id);
          if (!verificationCompleter.isCompleted) {
            verificationCompleter.complete(true);
          }
          print('verify_success');
          break;

        case 'verify_failed':
          if (!verificationCompleter.isCompleted) {
            verificationCompleter.complete(false);
          }
          print('verify_failed');
          break;

        case 'sync_data':
          print('sync_data before');
          await _handleSyncData(data, peer.id, true);
          if (!syncCompleter.isCompleted) {
            syncCompleter.complete();
          }
          break;
        case 'sync_complete':
          print('sync_complete');
          // 数据同步传输成功后关闭连接，并提示成功的消息
          break;

        default:
          print('消息类型错误 from ${peer.name}: $type');
      }
    } catch (e) {
      print('处理消息时出错$e');
      _connectionManager.sendMessage(peer.id, {
        'type': 'error',
        'message': '处理消息时出错: $e',
      });
    }
  }
}
