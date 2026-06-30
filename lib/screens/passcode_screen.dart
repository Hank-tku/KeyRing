import 'package:flutter/material.dart';

import '../utils/theme_config.dart';
import 'auth_service.dart';

/// 系统密码验证页（委托 OS local_auth，biometricOnly=false）。
///
/// 应用内仅展示验证状态与重试入口；真正的密码输入由系统弹窗完成。
class PasscodeScreen extends StatefulWidget {
  const PasscodeScreen({super.key, required this.onCorrect});

  final VoidCallback onCorrect;

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  final AuthService _authService = AuthService();
  bool _isVerifying = false;

  Future<void> _verifySystemPassword() async {
    setState(() => _isVerifying = true);
    try {
      final bool authenticated =
          await _authService.authenticateWithSystemPassword();
      if (!mounted) return;
      if (authenticated) {
        Navigator.of(context).pop();
        widget.onCorrect();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('验证失败，请重试'),
            backgroundColor: ThemeConfig.dangerColor,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('验证出错: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // 页面打开后自动触发系统密码验证。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifySystemPassword();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统密码验证'),
        titleTextStyle: const TextStyle(
          color: ThemeConfig.primaryColor,
          fontSize: ThemeConfig.fontSizeTitle,
          fontWeight: FontWeight.w500,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              ThemeConfig.mainBgColor,
              Color(0xFF0B0D12),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: ThemeConfig.primarySoft,
                    borderRadius: BorderRadius.circular(ThemeConfig.space20),
                    border: Border.all(
                      color: ThemeConfig.primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _isVerifying
                        ? Icons.lock_clock_outlined
                        : Icons.lock_outline,
                    color: ThemeConfig.primaryColor,
                    size: 38,
                  ),
                ),
                const SizedBox(height: ThemeConfig.space20),
                if (_isVerifying) ...<Widget>[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(height: ThemeConfig.space12),
                  const Text(
                    '正在验证...',
                    style: TextStyle(color: ThemeConfig.secondaryTextColor),
                  ),
                ] else ...<Widget>[
                  const Text(
                    '需要验证系统密码',
                    style: TextStyle(
                      color: ThemeConfig.textColor,
                      fontSize: ThemeConfig.fontSizeSubtitle,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: ThemeConfig.space8),
                  const Text(
                    '验证失败或取消时，可点此重新验证',
                    style: TextStyle(color: ThemeConfig.secondaryTextColor),
                  ),
                  const SizedBox(height: ThemeConfig.space20),
                  FilledButton.icon(
                    onPressed: _verifySystemPassword,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新验证'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeConfig.primaryColor,
                      foregroundColor: const Color(0xFF0B0D12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: ThemeConfig.space24,
                        vertical: ThemeConfig.space12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeConfig.radiusMd),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
