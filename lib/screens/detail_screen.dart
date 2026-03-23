import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/password_item.dart';
import '../utils/theme_config.dart';
import 'edit_item_screen.dart';
import '../services/password_repository.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item, required this.repository});

  final PasswordItem item;
  final PasswordRepository repository;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _obscurePassword = true;

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _edit() async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            EditItemScreen(repository: widget.repository, initial: widget.item),
      ),
    );
    if (changed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('密码详情'),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: ThemeConfig.primaryColor,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _edit,
            icon: const Icon(Icons.edit),
            color: Colors.white,
            tooltip: '编辑',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[_buildDetailCard()],
      ),
    );
  }

  Widget _buildDetailCard() {
    return Card(
      color: ThemeConfig.fillColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildDetailRow(
              label: '账号名',
              value: widget.item.title,
              showCopy: true,
            ),
            const Divider(height: 24, color: ThemeConfig.inputBorderColor),
            _buildDetailRow(
              label: '用户名',
              value: widget.item.username,
              showCopy: widget.item.username.isNotEmpty,
            ),
            const Divider(height: 24, color: ThemeConfig.inputBorderColor),
            _buildPasswordRow(),
            const Divider(height: 24, color: ThemeConfig.inputBorderColor),
            _buildDetailRow(
              label: '网址',
              value: widget.item.url ?? '',
              showCopy: widget.item.url != null && widget.item.url!.isNotEmpty,
              emptyText: '未设置',
            ),
            const Divider(height: 24, color: ThemeConfig.inputBorderColor),
            _buildNotesRow(),
            const Divider(height: 24, color: ThemeConfig.inputBorderColor),
            _buildDetailRow(
              label: '常用',
              value: widget.item.isFavorite ? '是' : '否',
              showCopy: false,
            ),
            const Divider(height: 24, color: ThemeConfig.inputBorderColor),
            _buildDetailRow(
              label: '创建时间',
              value: _formatDateTime(widget.item.createdAt),
              showCopy: false,
            ),
            const Divider(height: 24, color: ThemeConfig.inputBorderColor),
            _buildDetailRow(
              label: '更新时间',
              value: _formatDateTime(widget.item.updatedAt),
              showCopy: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required bool showCopy,
    String? emptyText,
    int? maxLines = 1,
  }) {
    final bool isEmpty = value.isEmpty;
    final String displayValue = isEmpty ? (emptyText ?? '') : value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: ThemeConfig.hintTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            displayValue,
            maxLines: maxLines,
            overflow: maxLines == 1 ? TextOverflow.ellipsis : null,
            style: TextStyle(
              color: isEmpty
                  ? ThemeConfig.hintTextColor
                  : ThemeConfig.textColor,
              fontSize: 15,
            ),
          ),
        ),
        if (showCopy && !isEmpty)
          InkWell(
            onTap: () => _copy(value, label),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.copy, size: 18, color: Colors.grey[400]),
            ),
          ),
      ],
    );
  }

  Widget _buildPasswordRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(
          width: 80,
          child: Text(
            '密码',
            style: TextStyle(
              color: ThemeConfig.hintTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _obscurePassword ? '••••••••' : widget.item.password,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ThemeConfig.textColor, fontSize: 15),
          ),
        ),
        InkWell(
          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: Icon(
              _obscurePassword ? Icons.visibility : Icons.visibility_off,
              size: 18,
              color: Colors.grey[400],
            ),
          ),
        ),
        InkWell(
          onTap: () => _copy(widget.item.password, '密码'),
          child: Padding(
            padding: const EdgeInsets.only(left: 0),
            child: Icon(Icons.copy, size: 18, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesRow() {
    final String notes = widget.item.notes ?? '';
    final bool isEmpty = notes.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              '备注',
              style: TextStyle(
                color: ThemeConfig.hintTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            if (!isEmpty)
              InkWell(
                onTap: () => _copy(notes, '备注'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.copy, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      '复制',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isEmpty
                ? ThemeConfig.fillColor.withOpacity(0.5)
                : ThemeConfig.inputBorderColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: ThemeConfig.inputBorderColor.withOpacity(0.5),
              width: 1,
            ),
          ),
          constraints: const BoxConstraints(minHeight: 80),
          child: isEmpty
              ? Text(
                  '未设置',
                  style: TextStyle(
                    color: ThemeConfig.hintTextColor,
                    fontSize: 15,
                  ),
                )
              : Text(
                  notes,
                  style: const TextStyle(
                    color: ThemeConfig.textColor,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
        ),
      ],
    );
  }
}
