import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'connection_state_manager.dart';

class WebSocketConnectionManager {
  final Map<String, WebSocketChannel> _channels = {};
  final Map<String, bool> _verifiedPeers = {};
  final ConnectionStateManager _stateManager;
  final Map<String, StreamController<dynamic>> _messageControllers = {};

  WebSocketConnectionManager(this._stateManager);

  Future<WebSocketChannel> connectToPeer(
    String peerId,
    String host,
    int port,
  ) async {
    if (_channels.containsKey(peerId)) {
      await closeConnection(peerId);
    }

    final socket = await WebSocket.connect(
      'ws://$host:$port/sync',
    ).timeout(const Duration(seconds: 5));

    final channel = IOWebSocketChannel(socket);
    _channels[peerId] = channel;

    // 为每个连接创建独立的消息控制器
    final controller = StreamController<dynamic>.broadcast();
    _messageControllers[peerId] = controller;

    // 设置单一的消息监听器
    channel.stream.listen(
      (message) {
        controller.add(message);
      },
      onError: (error) {
        print('WebSocket error for $peerId: $error');
        controller.addError(error);
      },
      onDone: () {
        controller.close();
        _messageControllers.remove(peerId);
      },
      cancelOnError: true,
    );

    return channel;
  }

  void registerConnection(String peerId, WebSocketChannel channel) {
    _channels[peerId] = channel;

    final controller = StreamController<dynamic>.broadcast();
    _messageControllers[peerId] = controller;

    channel.stream.listen(
      (message) {
        controller.add(message);
      },
      onError: (error) {
        print('WebSocket error for $peerId: $error');
        controller.addError(error);
      },
      onDone: () {
        controller.close();
        _messageControllers.remove(peerId);
        _channels.remove(peerId);
        _verifiedPeers.remove(peerId);
      },
      cancelOnError: true,
    );
  }

  Stream<dynamic> getMessageStream(String peerId) {
    final controller = _messageControllers[peerId];
    return controller?.stream ?? const Stream.empty();
  }

  void sendMessage(String peerId, Map<String, dynamic> message) {
    final channel = _channels[peerId];
    if (channel != null) {
      try {
        channel.sink.add(jsonEncode(message));
      } catch (e) {
        print('Error sending message to $peerId: $e');
      }
    }
  }

  Future<void> closeConnection(String peerId) async {
    final channel = _channels[peerId];
    final controller = _messageControllers[peerId];

    if (controller != null) {
      await controller.close();
      _messageControllers.remove(peerId);
    }

    if (channel != null) {
      await channel.sink.close();
      _channels.remove(peerId);
      _verifiedPeers.remove(peerId);
    }
  }

  Future<void> closeAllConnections() async {
    for (final peerId in _channels.keys.toList()) {
      await closeConnection(peerId);
    }
  }

  void markAsVerified(String peerId) {
    _verifiedPeers[peerId] = true;
  }

  bool isVerified(String peerId) => _verifiedPeers[peerId] == true;

  void dispose() {
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    _messageControllers.clear();
  }
}
