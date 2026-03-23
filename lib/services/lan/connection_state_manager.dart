import 'dart:async';

class ConnectionStateManager {
  final Map<String, ConnectionState> _connectionStates = {};
  final StreamController<Map<String, ConnectionState>> _stateController =
      StreamController<Map<String, ConnectionState>>.broadcast();

  Stream<Map<String, ConnectionState>> get stateStream =>
      _stateController.stream;

  void updateState(String peerId, ConnectionState state) {
    _connectionStates[peerId] = state;
    _notifyListeners();
  }

  ConnectionState? getState(String peerId) => _connectionStates[peerId];

  void removeState(String peerId) {
    _connectionStates.remove(peerId);
    _notifyListeners();
  }

  void updateVerificationCode(String peerId, String code) {
    final currentState = _connectionStates[peerId];
    if (currentState != null) {
      _connectionStates[peerId] = currentState.copyWith(verificationCode: code);
      _notifyListeners();
    }
  }

  void markAsVerified(String peerId) {
    final currentState = _connectionStates[peerId];
    if (currentState != null) {
      _connectionStates[peerId] = currentState.copyWith(
        status: ConnectionStatus.verified,
        verificationCode: null,
      );
      _notifyListeners();
    }
  }

  void markAsError(String peerId, String error) {
    final currentState = _connectionStates[peerId];
    if (currentState != null) {
      _connectionStates[peerId] = currentState.copyWith(
        status: ConnectionStatus.error,
        error: error,
      );
      _notifyListeners();
    }
  }

  void _notifyListeners() {
    if (!_stateController.isClosed) {
      _stateController.add(
        Map<String, ConnectionState>.from(_connectionStates),
      );
    }
  }

  void dispose() {
    _stateController.close();
  }
}

class ConnectionState {
  final String peerId;
  final String? peerName;
  final ConnectionStatus status;
  final DateTime lastUpdated;
  final String? verificationCode;
  final String? error;

  const ConnectionState({
    required this.peerId,
    this.peerName,
    required this.status,
    required this.lastUpdated,
    this.verificationCode,
    this.error,
  });

  ConnectionState copyWith({
    String? peerName,
    ConnectionStatus? status,
    String? verificationCode,
    String? error,
  }) {
    return ConnectionState(
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      status: status ?? this.status,
      lastUpdated: DateTime.now(),
      verificationCode: verificationCode ?? this.verificationCode,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return 'ConnectionState(peerId: $peerId, status: $status, verificationCode: $verificationCode)';
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  waitingVerification,
  verified,
  syncing,
  completed,
  error,
}
