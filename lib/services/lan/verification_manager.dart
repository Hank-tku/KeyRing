import 'dart:math';
import 'connection_state_manager.dart';

class VerificationManager {
  final Map<String, String> _activeCodes = {};
  final Map<String, String> _peerNames = {};
  final Map<String, DateTime> _codeExpiry = {};
  final Random _random = Random.secure();
  final ConnectionStateManager _stateManager;

  static const Duration _codeExpiryDuration = Duration(minutes: 10);

  VerificationManager(this._stateManager);

  String generateVerificationCode() {
    return (100000 + _random.nextInt(900000)).toString();
  }

  String generateAndStoreCode(String peerId, {String? peerName}) {
    _cleanExpiredCodes();

    final String code = generateVerificationCode();
    _activeCodes[peerId] = code;
    _peerNames[peerId] = peerName ?? 'Unknown Device';
    _codeExpiry[peerId] = DateTime.now().add(_codeExpiryDuration);

    _stateManager.updateState(
      peerId,
      ConnectionState(
        peerId: peerId,
        peerName: peerName,
        status: ConnectionStatus.waitingVerification,
        lastUpdated: DateTime.now(),
        verificationCode: code,
      ),
    );

    print('Generated verification code: $code for peer: $peerId');
    return code;
  }

  bool verifyCode(String peerId, String code) {
    _cleanExpiredCodes();

    final String? storedCode = _activeCodes[peerId];
    final bool isValid = storedCode == code;

    if (isValid) {
      _activeCodes.remove(peerId);
      _peerNames.remove(peerId);
      _codeExpiry.remove(peerId);

      _stateManager.markAsVerified(peerId);
      print('Verification successful for peer: $peerId');
    } else {
      _stateManager.markAsError(peerId, 'Verification code mismatch');
      print(
        'Verification failed for peer: $peerId. Expected: $storedCode, Received: $code',
      );
    }

    return isValid;
  }

  void removeCode(String peerId) {
    _activeCodes.remove(peerId);
    _peerNames.remove(peerId);
    _codeExpiry.remove(peerId);

    _stateManager.updateState(
      peerId,
      ConnectionState(
        peerId: peerId,
        status: ConnectionStatus.waitingVerification,
        lastUpdated: DateTime.now(),
      ),
    );

    print('Removed verification code for peer: $peerId');
  }

  String? getStoredCode(String peerId) {
    _cleanExpiredCodes();
    return _activeCodes[peerId];
  }

  String? getPeerName(String peerId) {
    return _peerNames[peerId];
  }

  bool hasPendingVerification(String peerId) {
    _cleanExpiredCodes();
    return _activeCodes.containsKey(peerId);
  }

  // 清除所有验证码
  void clearAllCodes() {
    print('Clearing all verification codes. Count: ${_activeCodes.length}');

    for (final peerId in _activeCodes.keys) {
      _stateManager.updateState(
        peerId,
        ConnectionState(
          peerId: peerId,
          status: ConnectionStatus.disconnected,
          lastUpdated: DateTime.now(),
        ),
      );
    }

    _activeCodes.clear();
    _peerNames.clear();
    _codeExpiry.clear();

    print('All verification codes cleared');
  }

  // 新增：清除特定设备的验证码
  void clearCodesForDevice(String peerId) {
    if (_activeCodes.containsKey(peerId)) {
      _activeCodes.remove(peerId);
      _peerNames.remove(peerId);
      _codeExpiry.remove(peerId);

      _stateManager.updateState(
        peerId,
        ConnectionState(
          peerId: peerId,
          status: ConnectionStatus.disconnected,
          lastUpdated: DateTime.now(),
        ),
      );

      print('Cleared verification code for peer: $peerId');
    }
  }

  // 获取所有待验证的设备
  Map<String, String> getPendingVerifications() {
    _cleanExpiredCodes();
    return Map<String, String>.from(_activeCodes);
  }

  // 检查验证码是否过期
  bool isCodeExpired(String peerId) {
    final DateTime? expiry = _codeExpiry[peerId];
    if (expiry == null) return true;
    return DateTime.now().isAfter(expiry);
  }

  // 清理过期验证码
  void _cleanExpiredCodes() {
    final List<String> expiredPeers = [];

    for (final entry in _codeExpiry.entries) {
      if (DateTime.now().isAfter(entry.value)) {
        expiredPeers.add(entry.key);
      }
    }

    for (final peerId in expiredPeers) {
      print('Removing expired verification code for peer: $peerId');
      _activeCodes.remove(peerId);
      _peerNames.remove(peerId);
      _codeExpiry.remove(peerId);

      _stateManager.markAsError(peerId, 'Verification code expired');
    }
  }

  // 获取验证码统计信息
  Map<String, dynamic> getVerificationStats() {
    _cleanExpiredCodes();
    return {
      'activeCodes': _activeCodes.length,
      'expiredCodes': _codeExpiry.length - _activeCodes.length,
      'pendingPeers': _activeCodes.keys.toList(),
    };
  }

  void dispose() {
    clearAllCodes();
  }
}
