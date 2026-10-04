import 'package:flutter/material.dart';
import '../models/workspace.dart';
import '../services/password_repository.dart';
import '../services/workspace_access_service.dart';

class WorkspacePasswordScreen extends StatefulWidget {
  const WorkspacePasswordScreen({
    super.key,
    required this.repository,
    required this.workspace,
  });
  final PasswordRepository repository;
  final Workspace workspace;
  @override
  State<WorkspacePasswordScreen> createState() =>
      _WorkspacePasswordScreenState();
}

class _WorkspacePasswordScreenState extends State<WorkspacePasswordScreen> {
  final _old = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late WorkspaceUnlockMode _mode;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.repository.access.modeFor(widget.workspace.id);
  }

  @override
  void dispose() {
    _old.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_mode == WorkspaceUnlockMode.password &&
        (_password.text.length < 6 || _password.text != _confirm.text)) {
      setState(() => _error = '密码至少需要 6 个字符，且两次输入需一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final access = widget.repository.access;
    try {
      switch (_mode) {
        case WorkspaceUnlockMode.none:
          if (access.isProtected(widget.workspace.id)) {
            await access.removePassword(widget.workspace.id, _old.text);
          }
        case WorkspaceUnlockMode.system:
          await access.setSystemUnlock(
            widget.workspace.id,
            oldPassword: _old.text,
          );
        case WorkspaceUnlockMode.password:
          await access.setPassword(
            widget.workspace.id,
            _password.text,
            oldPassword: _old.text,
          );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = '未能保存。请完成当前验证，并确认系统支持所选解锁方式。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.repository.access.modeFor(widget.workspace.id);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.workspace.name} · 访问验证')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                '切换到此工作区时',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text('选择适合你的解锁方式。设置仅在本机生效，不随同步或备份传输。'),
              const SizedBox(height: 16),
              RadioGroup<WorkspaceUnlockMode>(
                groupValue: _mode,
                onChanged: (value) {
                  if (!_busy && value != null) {
                    setState(() {
                      _mode = value;
                      _error = null;
                    });
                  }
                },
                child: Column(
                  children: [
                    RadioListTile<WorkspaceUnlockMode>(
                      value: WorkspaceUnlockMode.none,
                      enabled: !_busy,
                      title: const Text('无需额外验证'),
                      subtitle: const Text('应用解锁后可直接进入'),
                    ),
                    RadioListTile<WorkspaceUnlockMode>(
                      value: WorkspaceUnlockMode.system,
                      enabled: !_busy,
                      title: const Text('系统验证'),
                      subtitle: const Text('使用指纹、面容或设备密码，以系统支持为准'),
                    ),
                    RadioListTile<WorkspaceUnlockMode>(
                      value: WorkspaceUnlockMode.password,
                      enabled: !_busy,
                      title: const Text('自定义密码'),
                      subtitle: const Text('为此工作区单独设置密码'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (current == WorkspaceUnlockMode.password) ...[
                TextField(
                  controller: _old,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '当前工作区密码',
                    helperText: '更改或关闭验证时需要输入',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (current == WorkspaceUnlockMode.system) ...[
                const Text('保存修改时需先完成系统验证。'),
                const SizedBox(height: 16),
              ],
              if (_mode == WorkspaceUnlockMode.password) ...[
                TextField(
                  controller: _password,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: '新密码（至少 6 个字符）'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: '再次输入新密码'),
                ),
                const SizedBox(height: 16),
              ],
              if (_mode != WorkspaceUnlockMode.none)
                const Text('受保护工作区不参与手机系统自动填充。'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? '验证并保存中…' : '保存验证方式'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
