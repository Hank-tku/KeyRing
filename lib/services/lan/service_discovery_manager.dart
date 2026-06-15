import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

class ServiceDiscoveryManager {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription? _broadcastSub;
  StreamSubscription? _discoverySub;
  Completer<Set<DiscoveredPeer>>? _discoveryCompleter;
  Set<DiscoveredPeer>? _discoveredPeers;

  static const String serviceType = '_KeyRing._tcp';

  Future<void> startBroadcast(
    String deviceId,
    String deviceName,
    int port,
  ) async {
    final service = BonsoirService(
      name: deviceName,
      type: serviceType,
      port: port,
      attributes: <String, String>{'id': deviceId},
    );

    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();

    debugPrint('Started broadcasting service: $deviceName on port $port');
  }

  Future<Set<DiscoveredPeer>> discoverPeers(
    Duration timeout,
    String currentDeviceId,
  ) async {
    final Completer<Set<DiscoveredPeer>> completer = Completer();
    final Set<DiscoveredPeer> peers = {};
    _discoveryCompleter = completer;
    _discoveredPeers = peers;

    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.initialize();

    _discoverySub = _discovery!.eventStream?.listen((event) {
      if (event is BonsoirDiscoveryServiceResolvedEvent) {
        final service = event.service;
        final host = service.host;
        final port = service.port;

        final peerId = service.attributes['id'];
        // 过滤自身
        if (peerId == currentDeviceId) {
          debugPrint('Filtering out self in discovery: $peerId');
          return;
        }
        // 过滤自身和无效设备
        if (peerId != null &&
            peerId.isNotEmpty &&
            host != null &&
            host.isNotEmpty &&
            port > 0) {
          final peer = DiscoveredPeer(
            id: peerId,
            host: host,
            port: port,
            name: service.name,
          );
          peers.add(peer);
          debugPrint(
            'Discovered peer: ${peer.name} at ${peer.host}:${peer.port}',
          );
        }
      } else if (event is BonsoirDiscoveryServiceFoundEvent) {
        //debugPrint('Found service, attempting to resolve');
        event.service.resolve(_discovery!.serviceResolver);
      }
    });

    await _discovery!.start();

    // Set timeout
    Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(peers);
      }
    });

    return completer.future;
  }

  Future<void> stopDiscovery() async {
    if (_discoveryCompleter != null && !_discoveryCompleter!.isCompleted) {
      _discoveryCompleter!.complete(_discoveredPeers ?? <DiscoveredPeer>{});
    }
    await _discoverySub?.cancel();
    await _discovery?.stop();
    _discoveryCompleter = null;
    _discoveredPeers = null;
    _discovery = null;
    debugPrint('Stopped service discovery');
  }

  Future<void> stopBroadcast() async {
    await _broadcastSub?.cancel();
    await _broadcast?.stop();
    _broadcast = null;
    debugPrint('Stopped service broadcast');
  }

  void dispose() {
    debugPrint('执行dispose');
    _discoverySub?.cancel();
    _broadcastSub?.cancel();
    _discovery?.stop();
    _broadcast?.stop();
  }
}

class DiscoveredPeer {
  final String id;
  final String host;
  final int port;
  final String name;

  const DiscoveredPeer({
    required this.id,
    required this.host,
    required this.port,
    required this.name,
  });

  @override
  bool operator ==(Object other) => other is DiscoveredPeer && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'DiscoveredPeer{id: $id, name: $name, host: $host, port: $port}';
  }
}
