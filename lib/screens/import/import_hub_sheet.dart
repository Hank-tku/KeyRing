import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/password_repository.dart';
import '../../utils/theme_config.dart';
import 'qr_scan_screen.dart';
import 'screenshot_import_screen.dart';

/// 导入来源。
enum ImportSource { file, qr, screenshot }

/// 统一导入入口面板（底部弹层）。
///
/// 提供三个入口：从文件、扫描二维码、从截图识别。文件导入走调用方传入的
/// 回调（复用既有 `_importData` 流程），扫码与截图各自跳转独立页面。
class ImportHubSheet extends StatelessWidget {
  const ImportHubSheet({
    super.key,
    required this.repository,
    required this.onPickFile,
    required this.onResult,
  });

  final PasswordRepository repository;

  /// 用户选择「从文件导入」时触发（由 HomeScreen 执行既有 JSON 流程）。
  final VoidCallback onPickFile;

  /// 导入完成（扫码/截图页面返回）后回调，供 HomeSheet 刷新列表/提示。
  /// 传入人类可读的结果描述，null 表示无导入。
  final void Function(String? message) onResult;

  static Future<void> show(
    BuildContext context, {
    required PasswordRepository repository,
    required VoidCallback onPickFile,
    required void Function(String? message) onResult,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeConfig.fillColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ThemeConfig.radiusCard),
        ),
      ),
      builder: (_) => ImportHubSheet(
        repository: repository,
        onPickFile: onPickFile,
        onResult: onResult,
      ),
    );
  }

  Future<void> _go(
    BuildContext context,
    Widget Function() builder,
  ) async {
    final String? result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => builder()),
    );
    if (result != null) {
      onResult(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // OCR 仅在移动端可用（ML Kit 无桌面/Web 支持）。
    final bool ocrAvailable =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ThemeConfig.space16,
          ThemeConfig.space12,
          ThemeConfig.space16,
          ThemeConfig.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 顶部拖把。
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: ThemeConfig.space12),
                decoration: BoxDecoration(
                  color: ThemeConfig.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '导入数据',
              style: TextStyle(
                fontSize: ThemeConfig.fontSizeSubtitle,
                fontWeight: FontWeight.w600,
                color: ThemeConfig.textColor,
              ),
            ),
            const SizedBox(height: ThemeConfig.space4),
            const Text(
              '选择导入方式，按账号 ID 合并（较新者覆盖）',
              style: TextStyle(
                fontSize: ThemeConfig.fontSizeCaption,
                color: ThemeConfig.secondaryTextColor,
              ),
            ),
            const SizedBox(height: ThemeConfig.space16),
            _EntryTile(
              icon: Icons.insert_drive_file_outlined,
              title: '从文件导入',
              subtitle: 'KeyRing 导出的 JSON 文件',
              onTap: () {
                Navigator.of(context).pop();
                onPickFile();
              },
            ),
            _EntryTile(
              icon: Icons.qr_code_scanner,
              title: '扫描二维码',
              subtitle: 'JSON / otpauth / keyring 码',
              onTap: () => _go(
                context,
                () => QrScanScreen(repository: repository),
              ),
            ),
            _EntryTile(
              icon: Icons.image_outlined,
              title: '从截图识别',
              subtitle: ocrAvailable ? 'OCR 识别账号密码（需复核）' : '仅支持移动端',
              enabled: ocrAvailable,
              onTap: ocrAvailable
                  ? () => _go(
                        context,
                        () => ScreenshotImportScreen(repository: repository),
                      )
                  : null,
            ),
            const SizedBox(height: ThemeConfig.space8),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        enabled ? ThemeConfig.primaryColor : ThemeConfig.hintTextColor;
    final Color titleColor =
        enabled ? ThemeConfig.textColor : ThemeConfig.hintTextColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeConfig.space8),
      child: Material(
        color: ThemeConfig.surfaceColor,
        borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ThemeConfig.space12,
              vertical: ThemeConfig.space12,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(ThemeConfig.radiusSm),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: ThemeConfig.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: ThemeConfig.fontSizeBody,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: ThemeConfig.fontSizeCaption,
                          color: ThemeConfig.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: enabled
                      ? ThemeConfig.secondaryTextColor
                      : ThemeConfig.hintTextColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
