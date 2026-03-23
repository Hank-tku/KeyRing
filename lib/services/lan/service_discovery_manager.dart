import 'dart:async';
import 'package:bonsoir/bonsoir.dart';

class ServiceDiscoveryManager {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription? _broadcastSub;
  StreamSubscription? _discoverySub;

  static const String serviceType = '_KeyRing._tcp';

  // 提前停止发现的回调
  Function(DiscoveredPeer)? _onValidPeerFound;
  Completer<void>? _discoveryCompleter;

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

    print('Started broadcasting service: $deviceName on port $port');
  }

  Future<Set<DiscoveredPeer>> discoverPeers(
    Duration timeout,
    String currentDeviceId,
  ) async {
    final Completer<Set<DiscoveredPeer>> completer = Completer();
    final Set<DiscoveredPeer> peers = {};

    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.initialize();

    _discoverySub = _discovery!.eventStream?.listen((event) {
      if (event is BonsoirDiscoveryServiceResolvedEvent) {
        final service = event.service;
        final host = service.host;
        final port = service.port;

        if (service != null) {
          final peerId = service.attributes?['id'];
          // 过滤自身
          if (peerId == currentDeviceId) {
            print('Filtering out self in discovery: $peerId');
            return;
          }
          // 过滤自身和无效设备
          if (peerId != null &&
              peerId.isNotEmpty &&
              host != null &&
              host.isNotEmpty &&
              port != null &&
              port > 0) {
            final peer = DiscoveredPeer(
              id: peerId,
              host: service.host ?? '',
              port: service.port ?? 0,
              name: service.name ?? 'Unknown Device',
            );
            peers.add(peer);
            print('Discovered peer: ${peer.name} at ${peer.host}:${peer.port}');
          }
        }
      } else if (event is BonsoirDiscoveryServiceFoundEvent) {
        //print('Found service, attempting to resolve');
        if (event.service != null) {
          event.service!.resolve(_discovery!.serviceResolver);
        }
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
    await _discoverySub?.cancel();
    await _discovery?.stop();
    _discovery = null;
    print('Stopped service discovery');
  }

  Future<void> stopBroadcast() async {
    await _broadcastSub?.cancel();
    await _broadcast?.stop();
    _broadcast = null;
    print('Stopped service broadcast');
  }

  void dispose() {
    print('执行dispose');
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
