import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/password_item.dart';
import '../services/password_repository.dart';
import '../utils/password_utils.dart';
import '../utils/theme_config.dart';
import '../widgets/shared/app_card.dart';
import '../widgets/shared/form_field_row.dart';
import '../widgets/shared/password_visibility_toggle.dart';
import '../widgets/shared/strength_indicator.dart';

class EditItemScreen extends StatefulWidget {
  const EditItemScreen({super.key, required this.repository, this.initial});

  final PasswordRepository repository;
  final PasswordItem? initial;

  @override
  State<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _urlController;
  late final TextEditingController _notesController;
  bool _isFavorite = false;
  bool _obscure = true;
  bool _optionalExpanded = false;

  // 是否有未保存改动，用于返回拦截。
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final PasswordItem? item = widget.initial;
    _titleController = TextEditingController(text: item?.title ?? '');
    _usernameController = TextEditingController(text: item?.username ?? '');
    _passwordController = TextEditingController(text: item?.password ?? '');
    _urlController = TextEditingController(text: item?.url ?? '');
    _notesController = TextEditingController(text: item?.notes ?? '');
    _isFavorite = item?.isFavorite ?? false;
    _loadOptionalExpanded();

    // 任一输入变化即标记为脏。
    for (final TextEditingController c in <TextEditingController>[
      _titleController,
      _usernameController,
      _passwordController,
      _urlController,
      _notesController,
    ]) {
      c.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadOptionalExpanded() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool v = prefs.getBool('edit_optional_expanded') ?? false;
    if (mounted) setState(() => _optionalExpanded = v);
  }

  Future<void> _saveOptionalExpanded(bool v) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('edit_optional_expanded', v);
  }

  Future<void> _showPasswordGenerator() async {
    int length = 16;
    bool includeUppercase = true;
    bool includeLowercase = true;
    bool includeNumbers = true;
    bool includeSymbols = true;

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            title: const Text('生成密码'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text('长度: '),
                    Expanded(
                      child: Slider(
                        value: length.toDouble(),
                        min: 8,
                        max: 32,
                        divisions: 24,
                        label: length.toString(),
                        onChanged: (double value) {
                          setDialogState(() => length = value.round());
                        },
                      ),
                    ),
                    Text('$length'),
                  ],
                ),
                CheckboxListTile(
                  title: const Text('包含大写字母'),
                  value: includeUppercase,
                  onChanged: (bool? value) {
                    setDialogState(() => includeUppercase = value ?? true);
                  },
                ),
                CheckboxListTile(
                  title: const Text('包含小写字母'),
                  value: includeLowercase,
                  onChanged: (bool? value) {
                    setDialogState(() => includeLowercase = value ?? true);
                  },
                ),
                CheckboxListTile(
                  title: const Text('包含数字'),
                  value: includeNumbers,
                  onChanged: (bool? value) {
                    setDialogState(() => includeNumbers = value ?? true);
                  },
                ),
                CheckboxListTile(
                  title: const Text('包含特殊字符'),
                  value: includeSymbols,
                  onChanged: (bool? value) {
                    setDialogState(() => includeSymbols = value ?? true);
                  },
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final String password = PasswordUtils.generatePassword(
                    length: length,
                    includeUppercase: includeUppercase,
                    includeLowercase: includeLowercase,
                    includeNumbers: includeNumbers,
                    includeSymbols: includeSymbols,
                  );
                  Navigator.of(context).pop(password);
                },
                child: const Text('生成'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      setState(() {
        _passwordController.text = result;
        _obscure = false;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    final String title = _titleController.text.trim();
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();
    if (title.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号名和密码不能为空')),
      );
      return;
    }
    // 校验账号名唯一性
    final bool exists = await widget.repository.titleExists(
      title,
      exceptId: widget.initial?.id,
    );
    if (!mounted) return;
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号名已存在，请使用其他账号名')),
      );
      return;
    }

    final PasswordItem item =
        (widget.initial ??
                PasswordItem(
                  title: title,
                  username: username,
                  password: password,
                ))
            .copyWith(
              title: title,
              username: username,
              password: password,
              url: _urlController.text.trim().isEmpty
                  ? null
                  : _urlController.text.trim(),
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
              updatedAt: DateTime.now(),
              isFavorite: _isFavorite,
            );

    if (widget.initial == null) {
      await widget.repository.addItem(item);
    } else {
      await widget.repository.updateItem(item);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除"${widget.initial?.title}"吗？此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: ThemeConfig.dangerColor),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.repository.removeItem(widget.initial!.id);
        if (mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  /// 返回拦截：有未保存改动时询问。
  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('你有未保存的修改，确定要离开吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: ThemeConfig.dangerColor),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initial != null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final NavigatorState navigator = Navigator.of(context);
        final bool shouldExit = await _confirmExit();
        if (shouldExit && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? '编辑密码' : '新增密码'),
          titleTextStyle: const TextStyle(
            color: ThemeConfig.primaryColor,
            fontSize: ThemeConfig.fontSizeTitle,
            fontWeight: FontWeight.w500,
          ),
          actions: <Widget>[
            if (isEditing)
              IconButton(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
              ),
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              tooltip: '保存',
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: <Widget>[
            _buildBasicSection(),
            const SizedBox(height: ThemeConfig.space12),
            _buildOptionalSection(),
            const SizedBox(height: ThemeConfig.space8),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeConfig.space16,
              ThemeConfig.space4,
              ThemeConfig.space16,
              ThemeConfig.space8,
            ),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: ThemeConfig.primaryColor,
                foregroundColor: const Color(0xFF0B1220),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                ),
              ),
              child: Text(
                isEditing ? '保存修改' : '保存',
                style: const TextStyle(
                  fontSize: ThemeConfig.fontSizeSubtitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBasicSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '基本信息',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ThemeConfig.textColor,
                ),
          ),
          const SizedBox(height: ThemeConfig.space12),
          FormFieldRow(
            label: '账号名',
            child: TextField(
              controller: _titleController,
              style: const TextStyle(color: ThemeConfig.textColor),
              decoration: const InputDecoration(
                hintText: '如：GitHub/微信',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          FormFieldRow(
            label: '用户名',
            child: TextField(
              controller: _usernameController,
              style: const TextStyle(color: ThemeConfig.textColor),
              decoration: const InputDecoration(
                hintText: '如：name@example.com',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          _buildPasswordField(),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FormFieldRow(
          label: '密码',
          child: TextField(
            controller: _passwordController,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: ThemeConfig.textColor),
            decoration: InputDecoration(
              hintText: '输入密码',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    onPressed: _showPasswordGenerator,
                    icon: const Icon(Icons.auto_fix_high),
                    tooltip: '生成密码',
                  ),
                  PasswordVisibilityToggle(
                    obscured: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                    iconSize: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72 + 8),
          child: StrengthIndicator(password: _passwordController.text),
        ),
      ],
    );
  }

  Widget _buildOptionalSection() {
    return AppCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _optionalExpanded,
          onExpansionChanged: (bool v) {
            setState(() => _optionalExpanded = v);
            _saveOptionalExpanded(v);
          },
          collapsedIconColor: ThemeConfig.textColor,
          iconColor: ThemeConfig.textColor,
          tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          childrenPadding: const EdgeInsets.only(top: ThemeConfig.space8),
          title: const Text(
            '可选信息',
            style: TextStyle(
              color: ThemeConfig.textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: <Widget>[
            FormFieldRow(
              label: '网址',
              child: TextField(
                controller: _urlController,
                style: const TextStyle(color: ThemeConfig.textColor),
                decoration: const InputDecoration(
                  hintText: 'https://example.com',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            FormFieldRow(
              label: '备注',
              alignWithField: true,
              child: TextField(
                controller: _notesController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 4,
                maxLines: 6,
                style: const TextStyle(
                  color: ThemeConfig.textColor,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  hintText: '如：安全问题答案、恢复邮箱等',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            FormFieldRow(
              label: '收藏',
              child: Align(
                alignment: Alignment.centerLeft,
                child: Switch(
                  value: _isFavorite,
                  onChanged: (bool v) => setState(() {
                    _isFavorite = v;
                    _dirty = true;
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
