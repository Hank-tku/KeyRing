import 'package:flutter/material.dart';

import '../../services/app_lock_state.dart';
import '../../services/password_repository.dart';
import '../../services/workspace_access_service.dart';

Future<bool> authorizeWorkspace(
  BuildContext context,
  PasswordRepository repository,
  String id, {
  bool force = false,
}) async {
  if (AppLockState.isLocked) return false;
  if (!repository.workspacesNotifier.value.any((w) => w.id == id)) return false;
  if (repository.access.canAccess(id) && !force) return true;
  if (!repository.access.isProtected(id)) return true;
  if (force) repository.access.lock(id);
  if (repository.access.modeFor(id) == WorkspaceUnlockMode.system) {
    final ok = await repository.access.verifySystem(
      id,
      isCurrent: () => context.mounted,
    );
    if (!ok && context.mounted && !AppLockState.isLocked) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('系统验证未完成，工作区保持锁定')));
    }
    return ok && context.mounted && !AppLockState.isLocked;
  }
  final name = repository.workspacesNotifier.value
      .where((w) => w.id == id)
      .first
      .name;
  final result = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _WorkspacePasswordDialog(access: repository.access, id: id, name: name),
  );
  return result == true &&
      !AppLockState.isLocked &&
      repository.access.canAccess(id);
}

class _WorkspacePasswordDialog extends StatefulWidget {
  const _WorkspacePasswordDialog({
    required this.access,
    required this.id,
    required this.name,
  });
  final WorkspaceAccessService access;
  final String id;
  final String name;
  @override
  State<_WorkspacePasswordDialog> createState() =>
      _WorkspacePasswordDialogState();
}

class _WorkspacePasswordDialogState extends State<_WorkspacePasswordDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _accepted = false;
  bool _cancelled = false;
  String? _error;
  @override
  void dispose() {
    _cancelled = true;
    _password.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.access.verify(
      widget.id,
      _password.text,
      isCurrent: () => mounted && !_cancelled,
    );
    if (!mounted) return;
    if (ok) {
      _accepted = true;
      Navigator.pop(context, true);
      return;
    }
    final seconds = widget.access.cooldownSeconds(widget.id);
    setState(() {
      _busy = false;
      _error = seconds > 0 ? '请 $seconds 秒后重试' : '密码不正确或验证已失效';
    });
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop && !_accepted) _cancelled = true;
    },
    child: AlertDialog(
      title: Text('解锁 ${widget.name}'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          onSubmitted: (_) => _verify(),
          decoration: InputDecoration(labelText: '本机工作区密码', errorText: _error),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context, false);
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(_busy ? '验证中…' : '解锁'),
        ),
      ],
    ),
  );
}

/// Rebuilds when access expires, including while an editor/detail route is open.
class WorkspaceGuard extends StatelessWidget {
  const WorkspaceGuard({
    super.key,
    required this.repository,
    required this.workspaceId,
    required this.child,
  });
  final PasswordRepository repository;
  final String workspaceId;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository.access,
    builder: (context, _) => repository.access.canAccess(workspaceId)
        ? child
        : Center(
            child: FilledButton.icon(
              onPressed: () =>
                  authorizeWorkspace(context, repository, workspaceId),
              icon: const Icon(Icons.lock_outline),
              label: const Text('解锁工作区'),
            ),
          ),
  );
}
