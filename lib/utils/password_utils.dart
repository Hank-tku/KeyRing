import 'dart:math';

/// 密码工具类，提供密码相关的实用功能
class PasswordUtils {
  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _numbers = '0123456789';
  static const String _symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

  /// 生成随机密码，优化以减少字符重复
  static String generatePassword({
    int length = 16,
    bool includeUppercase = true,
    bool includeLowercase = true,
    bool includeNumbers = true,
    bool includeSymbols = true,
  }) {
    // 收集启用的字符池
    final pools = <String>[];
    if (includeUppercase) pools.add(_uppercase);
    if (includeLowercase) pools.add(_lowercase);
    if (includeNumbers) pools.add(_numbers);
    if (includeSymbols) pools.add(_symbols);

    if (pools.isEmpty) {
      pools.add(_lowercase);
      pools.add(_numbers);
    }

    final random = Random.secure();
    final List<String> passwordChars = [];
    String? lastChar;
    String? lastPool;

    // 确保每种类型至少有一个字符（且不连续相同）
    for (final pool in pools) {
      if (passwordChars.length >= length) break;
      String char;
      do {
        char = pool[random.nextInt(pool.length)];
      } while (char == lastChar);
      passwordChars.add(char);
      lastChar = char;
    }

    // 计算每个字符类型应该出现的次数（保持均匀分布）
    final int poolCount = pools.length;
    final int remaining = length - passwordChars.length;
    final int basePerPool = remaining ~/ poolCount;
    final int extra = remaining % poolCount;

    // 从每个字符池均匀选取字符
    for (int i = 0; i < poolCount; i++) {
      final pool = pools[i];
      final int count = basePerPool + (i < extra ? 1 : 0);

      for (int j = 0; j < count; j++) {
        String char;
        int attempts = 0;
        // 尝试避免与上一个字符相同
        do {
          char = pool[random.nextInt(pool.length)];
          attempts++;
        } while (char == lastChar && attempts < 10);
        passwordChars.add(char);
        lastChar = char;
      }
    }

    // 打乱顺序
    passwordChars.shuffle(Random.secure());
    return passwordChars.join();
  }

  /// 检查密码强度
  static PasswordStrength checkStrength(String password) {
    if (password.isEmpty) return PasswordStrength.veryWeak;

    int score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;

    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) score++;

    // 检查是否有重复字符
    if (!_hasRepeatingChars(password)) score++;

    // 检查是否有连续字符
    if (!_hasSequentialChars(password)) score++;

    if (score <= 2) return PasswordStrength.veryWeak;
    if (score <= 4) return PasswordStrength.weak;
    if (score <= 6) return PasswordStrength.fair;
    if (score <= 8) return PasswordStrength.good;
    if (score <= 10) return PasswordStrength.strong;
    return PasswordStrength.veryStrong;
  }

  /// 获取密码强度描述
  static String getStrengthDescription(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.veryWeak:
        return '非常弱';
      case PasswordStrength.weak:
        return '弱';
      case PasswordStrength.fair:
        return '一般';
      case PasswordStrength.good:
        return '良好';
      case PasswordStrength.strong:
        return '强';
      case PasswordStrength.veryStrong:
        return '非常强';
    }
  }

  /// 获取密码强度颜色
  static int getStrengthColor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.veryWeak:
        return 0xFFE53E3E; // 红色
      case PasswordStrength.weak:
        return 0xFFDD6B20; // 橙色
      case PasswordStrength.fair:
        return 0xFFD69E2E; // 黄色
      case PasswordStrength.good:
        return 0xFF38A169; // 绿色
      case PasswordStrength.strong:
        return 0xFF319795; // 青色
      case PasswordStrength.veryStrong:
        return 0xFF2F855A; // 深绿色
    }
  }

  /// 检查是否有重复字符
  static bool _hasRepeatingChars(String password) {
    for (int i = 0; i < password.length - 2; i++) {
      if (password[i] == password[i + 1] && password[i] == password[i + 2]) {
        return true;
      }
    }
    return false;
  }

  /// 检查是否有连续字符
  static bool _hasSequentialChars(String password) {
    for (int i = 0; i < password.length - 2; i++) {
      if (_isSequential(password[i], password[i + 1], password[i + 2])) {
        return true;
      }
    }
    return false;
  }

  /// 检查三个字符是否连续
  static bool _isSequential(String a, String b, String c) {
    if (a.codeUnitAt(0) + 1 == b.codeUnitAt(0) &&
        b.codeUnitAt(0) + 1 == c.codeUnitAt(0)) {
      return true;
    }
    if (a.codeUnitAt(0) - 1 == b.codeUnitAt(0) &&
        b.codeUnitAt(0) - 1 == c.codeUnitAt(0)) {
      return true;
    }
    return false;
  }

  /// 生成密码提示
  static List<String> generatePasswordTips(PasswordStrength strength) {
    final List<String> tips = <String>[];

    switch (strength) {
      case PasswordStrength.veryWeak:
      case PasswordStrength.weak:
        tips.addAll(['密码长度至少8位', '包含大小写字母', '包含数字', '包含特殊字符']);
        break;
      case PasswordStrength.fair:
        tips.addAll(['增加密码长度', '避免使用常见词汇', '避免使用个人信息']);
        break;
      case PasswordStrength.good:
        tips.addAll(['定期更换密码', '不同账户使用不同密码', '启用双因素认证']);
        break;
      case PasswordStrength.strong:
      case PasswordStrength.veryStrong:
        tips.addAll(['密码强度很好！', '建议定期更换', '保持安全习惯']);
        break;
    }

    return tips;
  }
}

/// 密码强度枚举
enum PasswordStrength { veryWeak, weak, fair, good, strong, veryStrong }
