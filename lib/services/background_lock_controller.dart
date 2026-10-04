import 'dart:async';

/// Application-wide background deadline, independent of the visible route.
/// Check wall time on return too: mobile suspension can pause Dart timers.
class BackgroundLockController {
  BackgroundLockController({
    required this.onLock,
    this.timeout = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final void Function() onLock;
  final Duration timeout;
  final DateTime Function() _now;
  Timer? _timer;
  DateTime? _backgroundAt;
  bool _foreground = true;
  bool _expired = false;

  void setForeground(bool value) {
    if (value == _foreground) {
      checkDeadline();
      return;
    }
    if (value) {
      checkDeadline();
      _timer?.cancel();
      _backgroundAt = null;
      _expired = false;
    } else {
      _backgroundAt = _now();
      _expired = false;
      _arm();
    }
    _foreground = value;
  }

  void didUnlock() {
    if (!_foreground) {
      _backgroundAt = _now();
      _expired = false;
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(timeout, checkDeadline);
  }

  void checkDeadline() {
    final since = _backgroundAt;
    if (!_expired && since != null && _now().difference(since) >= timeout) {
      _expired = true;
      _timer?.cancel();
      onLock();
    }
  }

  void dispose() => _timer?.cancel();
}
