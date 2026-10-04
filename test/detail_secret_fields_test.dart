import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/models/password_item.dart';
import 'package:key_ring/models/secret_field.dart';
import 'package:key_ring/screens/detail_screen.dart';
import 'package:key_ring/services/app_lock_state.dart';
import 'package:key_ring/services/password_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'default names skip occupied numbers without renaming existing labels',
    () {
      expect(nextPasswordLabel([]), '密码2');
      expect(nextPasswordLabel(['密码2', '交易密码', '密码4']), '密码3');
    },
  );
  test(
    'nullable URL and notes can be cleared without losing unrelated fields',
    () {
      final item = PasswordItem(
        title: 'test',
        username: '',
        password: ' password ',
        url: 'https://example.test',
        notes: 'note',
      );
      expect(item.copyWith().url, item.url);
      final cleared = item.copyWith(url: null, notes: null);
      expect(cleared.url, null);
      expect(cleared.notes, null);
      expect(cleared.password, ' password ');
    },
  );
  testWidgets(
    'detail shows full URL and notes; edit preserves secret id and stays on detail',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      AppLockState.markUnlocked();
      final dir = Directory.systemTemp.createTempSync('keyring-detail-test');
      final repo = PasswordRepository(dbPathOverride: '${dir.path}/test.db');
      await tester.runAsync(repo.init);
      addTearDown(() async {
        await tester.runAsync(repo.dispose);
        dir.deleteSync(recursive: true);
      });
      final item = PasswordItem(
        title: 'Synthetic',
        username: 'user',
        password: ' secret ',
        url: 'https://example.test/a/very/long/path?value=long-value',
        notes: '第一行\n第二行',
        customFields: [
          SecretField(
            id: 'stable-id',
            label: '密码2',
            value: ' extra ',
            type: SecretFieldType.password,
            protected: true,
          ),
        ],
      );
      await tester.runAsync(() => repo.addItem(item));
      final saved = (await tester.runAsync(() => repo.getByIdAsync(item.id)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(item: saved, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(item.url!), findsOneWidget);
      final urlWidget = tester.widget<SelectableText>(find.byWidgetPredicate((w) => w is SelectableText && w.data == item.url));
      expect(urlWidget.maxLines, isNull);
      await tester.scrollUntilVisible(find.text('第一行\n第二行'), 150, scrollable: find.byType(Scrollable).first);
      expect(find.text('第一行\n第二行'), findsOneWidget);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      final primary = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == ' secret ',
      );
      await tester.enterText(primary, ' updated ');
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('保存'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('密码详情'), findsOneWidget);
      final updated = (await tester.runAsync(() => repo.getByIdAsync(item.id)))!;
      expect(updated.password, ' updated ');
      expect(updated.customFields.single.id, 'stable-id');
      expect(updated.customFields.single.value, ' extra ');
      expect(updated.customFields.single.protected, true);
    },
  );
}
