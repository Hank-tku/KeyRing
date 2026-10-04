import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import '../screens/auth_service.dart';
import '../services/app_lock_state.dart';
import '../services/foreground_app_service.dart';
import '../services/keyboard_inject_service.dart';
import '../services/password_repository.dart';
import '../services/workspace_access_service.dart';

/// Main-isolate host. Only the dedicated panel is shown. Password values stay in
/// this isolate; every fill rechecks application and workspace authorization.
class QuickFillHost {
  QuickFillHost({
    required this.repository,
    required this.onFeedback,
    this.onVisibilityChanged,
  }) {
    AppLockState.listenable.addListener(_accessChanged);
    repository.access.addListener(_accessChanged);
  }
  final PasswordRepository repository;
  final void Function(bool)? onVisibilityChanged;
  final void Function(String, bool) onFeedback;
  static const _cmdChannel = WindowMethodChannel(
    'keyring.quickfill/cmd',
    mode: ChannelMode.unidirectional,
  );
  WindowController? _window;
  bool _visible = false;
  bool _filling = false;
  bool _opening = false;
  bool _authenticating = false;
  bool _hasTarget = false;
  int _session = 0;
  bool get isVisible => _visible;

  void _accessChanged() {
    if (_visible) unawaited(_push('refresh'));
  }

  Future<void> toggle() async {
    if (_opening || _authenticating) return;
    if (_visible) {
      await hide(restoreTarget: true);
    } else {
      await show();
    }
  }

  Future<void> _showPanel() async {
    if (Platform.isMacOS) {
      await ForegroundAppService.showPanel();
    } else {
      await _window?.show();
    }
  }

  Future<void> show() async {
    if (_opening) return;
    _opening = true;
    _session++;
    try {
      _hasTarget = await ForegroundAppService.remember();
      if (_window == null) {
        _window = await WindowController.create(
          const WindowConfiguration(
            arguments: 'quick_fill',
            hiddenAtLaunch: true,
          ),
        );
        await _window!.setWindowMethodHandler(_onWindowCall);
      }
      _visible = true;
      onVisibilityChanged?.call(true);
      await _push('refresh');
      await _showPanel();
    } catch (_) {
      _visible = false;
      onVisibilityChanged?.call(false);
      rethrow;
    } finally {
      _opening = false;
    }
  }

  Future<void> hide({bool restoreTarget = false}) async {
    _session++;
    _visible = false;
    onVisibilityChanged?.call(false);
    if (Platform.isMacOS) {
      await ForegroundAppService.hidePanel();
    } else {
      await _window?.hide();
    }
    if (restoreTarget && _hasTarget) await ForegroundAppService.activate();
  }

  Future<void> dispose() async {
    AppLockState.listenable.removeListener(_accessChanged);
    repository.access.removeListener(_accessChanged);
    if (_window != null) await hide();
  }

  Future<void> _push(String method, [dynamic args]) async {
    try {
      await _cmdChannel.invokeMethod<dynamic>(method, args);
    } catch (_) {}
  }

  Future<dynamic> _onWindowCall(MethodCall call) async {
    switch (call.method) {
      case 'requestItems':
        final locked = AppLockState.isLocked;
        final workspaces = repository.workspacesNotifier.value;
        return jsonEncode({
          'locked': locked,
          'workspaces': locked
              ? []
              : [
                  for (final w in workspaces)
                    if (!repository.access.canAccess(w.id))
                      {
                        'id': w.id,
                        'name': w.name,
                        'mode': repository.access.modeFor(w.id).name,
                      },
                ],
          'items': locked
              ? []
              : [
                  for (final item in repository.itemsNotifier.value)
                    if (repository.access.canAccess(item.workspaceId))
                      {
                        'id': item.id,
                        'title': item.title,
                        'username': item.username,
                        'url': item.url ?? '',
                        'workspace':
                            workspaces
                                .where((w) => w.id == item.workspaceId)
                                .firstOrNull
                                ?.name ??
                            '',
                      },
                ],
        });
      case 'unlockApp':
        if (_authenticating) return false;
        _authenticating = true;
        final session = _session;
        final generation = repository.access.generation;
        try {
          await ForegroundAppService.setPanelAuthenticating(true);
          final ok = await AuthService().authenticateWithSystemPassword();
          if (ok &&
              session == _session &&
              generation == repository.access.generation &&
              _visible) {
            AppLockState.markUnlocked();
          }
          if (_visible) await _showPanel();
          return !AppLockState.isLocked;
        } finally {
          _authenticating = false;
          await ForegroundAppService.setPanelAuthenticating(false);
        }
      case 'unlockWorkspace':
        if (AppLockState.isLocked || !_visible) return false;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final session = _session;
        final id = args['id'] as String;
        final isSystem =
            repository.access.modeFor(id) == WorkspaceUnlockMode.system;
        bool current() =>
            session == _session && _visible && !AppLockState.isLocked;
        if (isSystem) {
          _authenticating = true;
          await ForegroundAppService.setPanelAuthenticating(true);
        }
        try {
          return isSystem
              ? await repository.access.verifySystem(id, isCurrent: current)
              : await repository.access.verify(
                  id,
                  args['password'] as String? ?? '',
                  isCurrent: current,
                );
        } finally {
          if (isSystem) {
            if (_visible) await _showPanel();
            _authenticating = false;
            await ForegroundAppService.setPanelAuthenticating(false);
          }
        }
      case 'cancelWorkspaceUnlock':
        repository.access.lock(call.arguments as String);
        return null;
      case 'fill':
        final id = call.arguments as String?;
        if (id != null && !_filling) {
          await hide();
          unawaited(_fill(id));
        }
        return null;
      case 'panelHidden':
        if (!_authenticating) await hide(restoreTarget: call.arguments == true);
        return null;
      default:
        return null;
    }
  }

  Future<void> _notifyPanelError(String message) async {
    _visible = true;
    onVisibilityChanged?.call(true);
    await _showPanel();
    await _push('refresh');
    await _push('feedback', {'message': message, 'ok': false});
  }

  Future<void> _fill(String id) async {
    if (_filling) return;
    _filling = true;
    final generation = repository.access.generation;
    try {
      final item = await repository.getByIdAsync(id);
      if (item == null ||
          AppLockState.isLocked ||
          !repository.access.canAccess(item.workspaceId)) {
        await _notifyPanelError('请先解锁对应工作区');
        return;
      }
      if (!_hasTarget || !await ForegroundAppService.activate()) {
        await _notifyPanelError('无法返回目标应用，请在目标输入框中重新按快捷键');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (generation != repository.access.generation ||
          AppLockState.isLocked ||
          !repository.access.canAccess(item.workspaceId) ||
          !await ForegroundAppService.isTargetActive()) {
        return;
      }
      final ok = await KeyboardInjectService.typeCredentials(
        username: item.username,
        password: item.password,
      );
      onFeedback(ok ? '已填充' : '填充失败', ok);
      if (!ok) await _notifyPanelError('填充失败，请检查系统辅助功能权限');
    } catch (_) {
      await _notifyPanelError('填充失败，请重新选择目标输入框');
    } finally {
      _filling = false;
    }
  }
}
