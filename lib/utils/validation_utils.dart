/// 验证工具类，提供各种输入验证功能
class ValidationUtils {
  /// 验证邮箱格式
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;

    final RegExp emailRegex = RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+');
    return emailRegex.hasMatch(email);
  }

  /// 验证URL格式
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;

    // 检查是否包含协议
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    try {
      final Uri uri = Uri.parse(url);
      return uri.hasScheme && uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }

  /// 验证密码强度
  static bool isStrongPassword(String password) {
    if (password.length < 8) return false;

    final bool hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final bool hasLowercase = password.contains(RegExp(r'[a-z]'));
    final bool hasNumbers = password.contains(RegExp(r'[0-9]'));
    final bool hasSpecialChars = password.contains(
      RegExp(r'[!@#\$%^&*(),.?":{}|<>]'),
    );

    // 至少满足3个条件
    int conditionsMet = 0;
    if (hasUppercase) conditionsMet++;
    if (hasLowercase) conditionsMet++;
    if (hasNumbers) conditionsMet++;
    if (hasSpecialChars) conditionsMet++;

    return conditionsMet >= 3;
  }

  /// 验证用户名格式
  static bool isValidUsername(String username) {
    if (username.isEmpty || username.length < 3) return false;

    // 只允许字母、数字、下划线和连字符
    final RegExp usernameRegex = RegExp(r'^[a-zA-Z0-9_-]+$');
    return usernameRegex.hasMatch(username);
  }

  /// 验证账号名格式
  static bool isValidTitle(String title) {
    if (title.isEmpty || title.length > 100) return false;

    // 不允许只包含空白字符
    return title.trim().isNotEmpty;
  }

  /// 验证备注长度
  static bool isValidNotes(String notes) {
    if (notes.isEmpty) return true; // 备注是可选的

    return notes.length <= 500; // 最大500字符
  }

  /// 获取邮箱验证错误信息
  static String? getEmailError(String email) {
    if (email.isEmpty) return '邮箱不能为空';
    if (!isValidEmail(email)) return '请输入有效的邮箱地址';
    return null;
  }

  /// 获取URL验证错误信息
  static String? getUrlError(String url) {
    if (url.isEmpty) return null; // URL是可选的
    if (!isValidUrl(url)) return '请输入有效的网址';
    return null;
  }

  /// 获取密码验证错误信息
  static String? getPasswordError(String password) {
    if (password.isEmpty) return '密码不能为空';
    if (password.length < 8) return '密码长度至少8位';
    if (!isStrongPassword(password)) {
      return '密码应包含大小写字母、数字和特殊字符中的至少3种';
    }
    return null;
  }

  /// 获取用户名验证错误信息
  static String? getUsernameError(String username) {
    if (username.isEmpty) return '用户名不能为空';
    if (username.length < 3) return '用户名长度至少3位';
    if (!isValidUsername(username)) {
      return '用户名只能包含字母、数字、下划线和连字符';
    }
    return null;
  }

  /// 获取账号名验证错误信息
  static String? getTitleError(String title) {
    if (title.isEmpty) return '账号名不能为空';
    if (title.length > 100) return '账号名长度不能超过100字符';
    if (!isValidTitle(title)) return '请输入有效的账号名';
    return null;
  }

  /// 获取备注验证错误信息
  static String? getNotesError(String notes) {
    if (notes.length > 500) return '备注长度不能超过500字符';
    return null;
  }

  /// 验证密码项数据
  static Map<String, String?> validatePasswordItem({
    required String title,
    required String username,
    required String password,
    String? url,
    String? notes,
  }) {
    return {
      'title': getTitleError(title),
      'username': getUsernameError(username),
      'password': getPasswordError(password),
      'url': getUrlError(url ?? ''),
      'notes': getNotesError(notes ?? ''),
    };
  }

  /// 检查密码项是否有错误
  static bool hasValidationErrors(Map<String, String?> errors) {
    return errors.values.any((error) => error != null);
  }

  /// 获取第一个验证错误信息
  static String? getFirstValidationError(Map<String, String?> errors) {
    for (final error in errors.values) {
      if (error != null) return error;
    }
    return null;
  }

  /// 清理输入文本
  static String cleanInput(String input) {
    return input.trim();
  }

  /// 清理URL输入
  static String cleanUrl(String url) {
    url = url.trim();

    // 如果没有协议，添加https://
    if (url.isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      url = 'https://$url';
    }

    return url;
  }

  /// 验证输入长度
  static bool isValidLength(
    String input, {
    int minLength = 0,
    int maxLength = 1000,
  }) {
    if (input.length < minLength) return false;
    if (maxLength > 0 && input.length > maxLength) return false;
    return true;
  }

  /// 检查是否包含敏感信息
  static bool containsSensitiveInfo(String text) {
    final List<String> sensitivePatterns = [
      r'\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b', // 信用卡号
      r'\b\d{3}-\d{2}-\d{4}\b', // 社会安全号 (US)
      r'\b\d{2}-\d{2}-\d{2}-\d{3}-\d{3}\b', // 身份证号 (CN)
      r'\b\d{11}\b', // 手机号 (CN)
    ];

    for (final pattern in sensitivePatterns) {
      if (RegExp(pattern).hasMatch(text)) {
        return true;
      }
    }

    return false;
  }

  /// 获取输入建议
  static List<String> getInputSuggestions(
    String fieldName,
    String currentValue,
  ) {
    final List<String> suggestions = <String>[];

    switch (fieldName.toLowerCase()) {
      case 'title':
        if (currentValue.isEmpty) {
          suggestions.addAll(['网站名称', '应用名称', '服务名称', '账户类型']);
        }
        break;
      case 'username':
        if (currentValue.isEmpty) {
          suggestions.addAll(['邮箱地址', '用户名', '手机号', '会员ID']);
        }
        break;
      case 'url':
        if (currentValue.isEmpty) {
          suggestions.addAll([
            'https://www.example.com',
            'https://app.example.com',
            'https://login.example.com',
          ]);
        }
        break;
      case 'notes':
        if (currentValue.isEmpty) {
          suggestions.addAll(['账户用途', '特殊说明', '安全提示', '相关链接']);
        }
        break;
    }

    return suggestions;
  }
}
