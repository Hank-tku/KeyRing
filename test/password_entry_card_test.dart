import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/models/password_item.dart';
import 'package:key_ring/models/secret_field.dart';
import 'package:key_ring/utils/theme_config.dart';
import 'package:key_ring/widgets/password_entry_card.dart';

/// 构造覆盖主要形态的合成条目：主密码 + 密码2(password) + 自定义保护项 + 普通文本项。
PasswordItem _buildItem() => PasswordItem(
  id: 'card-item-1',
  title: 'GitHub',
  username: 'henry@example.com',
  password: 'main-secret',
  url: 'https://github.com/henry/projects',
  customFields: <SecretField>[
    SecretField(
      id: 'field-pwd2',
      label: '密码2',
      value: 'second-secret',
      type: SecretFieldType.password,
    ),
    SecretField(
      id: 'field-bank',
      label: '安全码',
      value: '4815162342',
      protected: true,
    ),
    SecretField(id: 'field-note', label: '备注', value: 'plain-value'),
  ],
);

Widget _harness(
  PasswordItem item, {
  required VoidCallback onTap,
  required VoidCallback onLongPress,
  required VoidCallback onToggleFavorite,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: ThemeConfig.appTheme,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: ListView(
        children: <Widget>[
          PasswordEntryCard(
            item: item,
            onTap: onTap,
            onLongPress: onLongPress,
            onToggleFavorite: onToggleFavorite,
          ),
        ],
      ),
    ),
  );
}

String? _lastCopied;

/// 拦截平台剪贴板通道，记录最后一次复制的文本。
void _spyClipboard(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        _lastCopied = (call.arguments as Map?)?['text'] as String?;
      }
      return null;
    },
  );
}

/// 点击复制按钮并让 SnackBar 完整入场/退场，避免遗留 pending timer。
Future<void> _tapCopyAndDismiss(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(); // 处理点击 + 入场首帧
  await tester.pump(const Duration(milliseconds: 300)); // 入场动画完成
  await tester.pump(const Duration(milliseconds: 1600)); // 计时器到期
  await tester.pumpAndSettle(); // 退场动画完成
}

void main() {
  setUp(() {
    _lastCopied = null;
  });

  testWidgets('renders labeled rows, host and default masks', (tester) async {
    await tester.pumpWidget(
      _harness(
        _buildItem(),
        onTap: () {},
        onLongPress: () {},
        onToggleFavorite: () {},
      ),
    );

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('密码2'), findsOneWidget);
    expect(find.text('安全码'), findsOneWidget);
    expect(find.text('备注'), findsOneWidget);
    expect(find.text('网址'), findsOneWidget);

    expect(find.text('henry@example.com'), findsOneWidget);
    expect(find.text('plain-value'), findsOneWidget);
    expect(find.text('github.com'), findsOneWidget);

    // 保密项默认掩码：原始值不可见。
    expect(find.text('main-secret'), findsNothing);
    expect(find.text('second-secret'), findsNothing);
    expect(find.text('4815162342'), findsNothing);

    // 收藏 / 眼睛 / 复制槽位齐全。
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsOneWidget);
    expect(find.byTooltip('显示密码2'), findsOneWidget);
    expect(find.byTooltip('显示安全码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorite and copy right edges are aligned in 44x44 slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _buildItem(),
        onTap: () {},
        onLongPress: () {},
        onToggleFavorite: () {},
      ),
    );

    final Rect favorite = tester.getRect(find.byTooltip('收藏'));
    final Rect copyUsername = tester.getRect(find.byTooltip('复制用户名'));
    final Rect copyPassword = tester.getRect(find.byTooltip('复制密码'));
    final Rect copyPassword2 = tester.getRect(find.byTooltip('复制密码2'));

    expect(favorite.width, closeTo(44, 0.1));
    expect(favorite.height, closeTo(44, 0.1));
    expect(copyUsername.right, closeTo(favorite.right, 0.1));
    expect(copyPassword.right, closeTo(favorite.right, 0.1));
    expect(copyPassword2.right, closeTo(favorite.right, 0.1));
    expect(copyPassword.width, closeTo(44, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'each secret field reveals independently and re-masks on change',
    (tester) async {
      final PasswordItem item = _buildItem();
      await tester.pumpWidget(
        _harness(
          item,
          onTap: () {},
          onLongPress: () {},
          onToggleFavorite: () {},
        ),
      );

      // 只显示主密码：密码2 仍掩码。
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pump();
      expect(find.text('main-secret'), findsOneWidget);
      expect(find.text('second-secret'), findsNothing);
      expect(find.text('4815162342'), findsNothing);

      // 再显示密码2：主密码不受影响。
      await tester.tap(find.byTooltip('显示密码2'));
      await tester.pump();
      expect(find.text('second-secret'), findsOneWidget);
      expect(find.text('main-secret'), findsOneWidget);

      // 单独隐藏主密码：密码2 保持明文。
      await tester.tap(find.byTooltip('隐藏密码'));
      await tester.pump();
      expect(find.text('main-secret'), findsNothing);
      expect(find.text('second-secret'), findsOneWidget);

      // 记录变化（新对象）后统一重新掩码。
      await tester.pumpWidget(
        _harness(
          item.copyWith(updatedAt: DateTime.now()),
          onTap: () {},
          onLongPress: () {},
          onToggleFavorite: () {},
        ),
      );
      expect(find.text('second-secret'), findsNothing);
      expect(find.text('main-secret'), findsNothing);
    },
  );

  testWidgets('copy buttons copy raw values without opening detail', (
    tester,
  ) async {
    _spyClipboard(tester);
    int taps = 0;
    await tester.pumpWidget(
      _harness(
        _buildItem(),
        onTap: () => taps++,
        onLongPress: () {},
        onToggleFavorite: () {},
      ),
    );

    await _tapCopyAndDismiss(tester, find.byTooltip('复制用户名'));
    expect(_lastCopied, 'henry@example.com');

    // 掩码状态下复制密码仍复制原始值。
    await _tapCopyAndDismiss(tester, find.byTooltip('复制密码'));
    expect(_lastCopied, 'main-secret');

    await _tapCopyAndDismiss(tester, find.byTooltip('复制密码2'));
    expect(_lastCopied, 'second-secret');

    await _tapCopyAndDismiss(tester, find.byTooltip('复制安全码'));
    expect(_lastCopied, '4815162342');

    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row buttons do not trigger detail; body tap does', (
    tester,
  ) async {
    int taps = 0;
    int favorites = 0;
    await tester.pumpWidget(
      _harness(
        _buildItem(),
        onTap: () => taps++,
        onLongPress: () {},
        onToggleFavorite: () => favorites++,
      ),
    );

    await tester.tap(find.byTooltip('收藏'));
    await tester.pump();
    expect(favorites, 1);
    expect(taps, 0);

    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(taps, 0);

    await _tapCopyAndDismiss(tester, find.byTooltip('复制密码'));
    expect(taps, 0);

    // 点击非按钮区域（标题文本）才触发详情。
    await tester.tap(find.text('GitHub'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets(
    '360dp width with long content and large text does not overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final PasswordItem longItem = PasswordItem(
        id: 'card-item-long',
        title: '一个特别特别特别特别长的账号标题名称用于验证截断行为',
        username: 'very-long-username-that-keeps-going@example-domain.com',
        password: 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789VeryLongSecret',
        url: 'https://sub.domain.very-long-example-site-name.example.com/path',
        customFields: <SecretField>[
          SecretField(
            id: 'field-long-label',
            label: '这是一个非常长的自定义保密项字段名称示例',
            value: 'some-rather-long-custom-secret-value-here',
            type: SecretFieldType.password,
          ),
          SecretField(
            id: 'field-long-label-2',
            label: '第二个非常长的自定义保密项字段名称示例',
            value: 'another-long-value',
            protected: true,
          ),
        ],
      );

      await tester.pumpWidget(
        _harness(
          longItem,
          onTap: () {},
          onLongPress: () {},
          onToggleFavorite: () {},
          textScale: 1.3,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('AbCdEfGhIjKlMnOpQrStUvWxYz0123456789VeryLongSecret'),
        findsNothing,
      );
    },
  );
}
