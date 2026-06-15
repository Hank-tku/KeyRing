import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/password_item.dart';
import '../services/password_repository.dart';
import '../utils/password_utils.dart';
import '../utils/theme_config.dart';

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
  // Removed unused _isGenerating to satisfy lints

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
      });
    }
  }

  Future<void> _save() async {
    final String title = _titleController.text.trim();
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();
    if (title.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('账号名和密码不能为空'),
          behavior: SnackBarBehavior.floating,
        ),
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
        const SnackBar(
          content: Text('账号名已存在，请使用其他账号名'),
          behavior: SnackBarBehavior.floating,
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '新增密码' : '编辑密码'),
        iconTheme: const IconThemeData(
          color: Colors.white, // 将返回按钮等图标的颜色设置为白色
        ),
        titleTextStyle: const TextStyle(
          color: Color(0xFF2DD4BF),
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.save),
            color: Colors.white,

            tooltip: '保存',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: <Widget>[
          // Ant Design 风格表单分组：基本信息
          _buildFormSection(
            title: '基本信息',
            children: <Widget>[
              _buildFormItem(
                label: '账号名',
                help: '网站或应用名称',
                control: TextField(
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
              _buildFormItem(
                label: '用户名',
                help: '登录用的用户名或邮箱',
                control: TextField(
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
              _buildPasswordItem(),
            ],
          ),

          const SizedBox(height: 12),

          // Ant Design 风格表单分组：可选信息（可折叠，默认收起）
          _buildOptionalSection(),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Ant Design 风格：分组卡片
  Widget _buildFormSection({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      color: ThemeConfig.fillColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: ThemeConfig.textColor,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  // Ant Design 风格：表单项（左标签右控件）
  Widget _buildFormItem({
    required String label,
    String? help,
    required Widget control,
    bool alignWithField = false,
    double? controlHeight,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: alignWithField
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: SizedBox(
              height: 40,
              child: Align(
                alignment: alignWithField
                    ? Alignment.topCenter
                    : Alignment.center,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ThemeConfig.textColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: controlHeight ?? (help == null ? 40 : null),
              child: control,
            ),
          ),
        ],
      ),
    );
  }

  // 密码强度条与提示
  Widget _buildPasswordStrength(String password) {
    if (password.isEmpty) {
      return Text(
        '请输入密码',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      );
    }

    int score = 0;
    if (password.length >= 8) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) score++;

    Color color;
    String label;
    switch (score) {
      case 0:
      case 1:
        color = Colors.red;
        label = '弱';
        break;
      case 2:
        color = Colors.orange;
        label = '一般';
        break;
      case 3:
        color = Colors.yellow.shade700;
        label = '中等';
        break;
      case 4:
        color = Colors.lightGreen;
        label = '强';
        break;
      default:
        color = Colors.green;
        label = '很强';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: score / 5,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '密码强度：$label',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // 自定义“密码”行：首行与输入框垂直居中，强度条另起一行缩进对齐
  Widget _buildPasswordItem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 72,
                height: 40,
                child: Center(
                  child: Text(
                    '密码',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ThemeConfig.textColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: ThemeConfig.textColor),
                    decoration: InputDecoration(
                      hintText: '输入密码',
                      hintStyle: const TextStyle(
                        color: ThemeConfig.hintTextColor,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: ThemeConfig.inputBorderColor,
                        ),
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            onPressed: _showPasswordGenerator,
                            icon: const Icon(Icons.auto_fix_high),
                            color: ThemeConfig.textColor,
                            tooltip: '生成密码',
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            color: ThemeConfig.textColor,
                            tooltip: _obscure ? '显示密码' : '隐藏密码',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72 + 8),
          child: _buildPasswordStrength(_passwordController.text),
        ),
      ],
    );
  }

  // 可选信息折叠卡片
  Widget _buildOptionalSection() {
    return Card(
      color: ThemeConfig.fillColor,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _optionalExpanded,
          onExpansionChanged: (bool v) {
            setState(() => _optionalExpanded = v);
            _saveOptionalExpanded(v);
          },
          collapsedIconColor: ThemeConfig.textColor,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          title: const Text(
            '可选信息',
            style: TextStyle(
              color: ThemeConfig.textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: <Widget>[
            _buildFormItem(
              label: '网址',
              control: TextField(
                controller: _urlController,
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
            _buildFormItem(
              label: '备注',
              alignWithField: true,
              controlHeight: 120,
              control: TextField(
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
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            _buildFormItem(
              label: '常用',
              control: Align(
                alignment: Alignment.centerLeft,
                child: Switch(
                  value: _isFavorite,
                  onChanged: (bool v) => setState(() => _isFavorite = v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
