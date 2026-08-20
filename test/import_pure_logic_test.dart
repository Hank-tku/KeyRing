// 导入相关纯逻辑测试（阶段一）：二维码解析、OCR 抽取、有效性校验。
// 这些组件不依赖平台通道或数据库，可作纯 Dart 单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/models/password_item.dart';
import 'package:key_ring/services/qr_payload_parser.dart';
import 'package:key_ring/services/ocr_field_extractor.dart';
import 'package:key_ring/utils/import_validation.dart';

void main() {
  group('QrPayloadParser', () {
    const QrPayloadParser parser = QrPayloadParser();

    test('解析 KeyRing 标准 JSON（含 items 数组）', () {
      const String raw = '''
        {"app":"KeyRing","items":[
          {"id":"x1","title":"GitHub","username":"a@b.com","password":"pw1"}
        ]}
      ''';
      final QrParseResult r = parser.parse(raw);
      expect(r, isA<QrItemsResult>());
      expect((r as QrItemsResult).items.single.title, 'GitHub');
      expect(r.items.single.password, 'pw1');
    });

    test('解析裸数组 JSON', () {
      const String raw =
          '[{"title":"T","username":"u","password":"p"}]';
      final QrItemsResult r = parser.parse(raw) as QrItemsResult;
      expect(r.items.single.title, 'T');
    });

    test('解析自定义 keyring:// URI（含全部字段）', () {
      const String raw =
          'keyring://item?title=Bank&username=alice&password=s3cret&url=bank.com&notes=note';
      final QrItemsResult r = parser.parse(raw) as QrItemsResult;
      final PasswordItem it = r.items.single;
      expect(it.title, 'Bank');
      expect(it.username, 'alice');
      expect(it.password, 's3cret');
      expect(it.url, 'bank.com');
      expect(it.notes, 'note');
    });

    test('keyring:// URI 缺 title 和 password 视为无效', () {
      const String raw = 'keyring://item?username=only';
      final QrParseResult r = parser.parse(raw);
      expect(r, isA<QrUnrecognizedResult>());
    });

    test('解析 otpauth URI（提取 issuer/account）', () {
      const String raw =
          'otpauth://totp/MySite:alice%40x.com?secret=ABCDE&issuer=MySite';
      final QrItemsResult r = parser.parse(raw) as QrItemsResult;
      expect(r.items.single.title, 'MySite');
      expect(r.items.single.username, 'alice@x.com');
      expect(r.items.single.password, 'ABCDE');
    });

    test('无法识别的内容返回 Unrecognized', () {
      const String raw = 'hello world not a code';
      expect(parser.parse(raw), isA<QrUnrecognizedResult>());
    });

    test('空内容返回 Unrecognized', () {
      expect(parser.parse('  '), isA<QrUnrecognizedResult>());
    });
  });

  group('OcrFieldExtractor', () {
    const OcrFieldExtractor extractor = OcrFieldExtractor();

    test('按「标签 + 下一行值」抽取用户名/密码', () {
      const String text = 'GitHub 登录\n用户名\nalice@x.com\n密码\np@ssw0rd';
      final OcrExtraction e = extractor.extract(text);
      expect(e.username, 'alice@x.com');
      expect(e.password, 'p@ssw0rd');
      expect(e.confidence, greaterThan(0));
    });

    test('支持「标签: 值」同行写法', () {
      const String text = 'Account: bob\nPassword: hunter2';
      final OcrExtraction e = extractor.extract(text);
      expect(e.username, 'bob');
      expect(e.password, 'hunter2');
    });

    test('中英文标签都命中（username/账号）', () {
      const String text = '账号\nbob\npassword\nsecret';
      final OcrExtraction e = extractor.extract(text);
      expect(e.username, 'bob');
      expect(e.password, 'secret');
    });

    test('未识别行进入 notes，首行作 title', () {
      const String text = 'Some Site\nrandom line one\nrandom line two';
      final OcrExtraction e = extractor.extract(text);
      expect(e.title, 'Some Site');
      expect(e.notes, contains('random line one'));
      expect(e.notes, contains('random line two'));
    });

    test('toItem 转换保留各字段', () {
      const OcrExtraction e = OcrExtraction(
        title: 't',
        username: 'u',
        password: 'p',
        url: 'url',
        notes: 'n',
      );
      final PasswordItem item = const OcrFieldExtractor().toItem(e);
      expect(item.title, 't');
      expect(item.password, 'p');
      expect(item.url, 'url');
      expect(item.notes, 'n');
    });
  });

  group('ImportValidator', () {
    const ImportValidator v = ImportValidator();

    test('有 title 即有效', () {
      expect(v.isValid(PasswordItem(title: 't', username: '', password: '')),
          isTrue);
    });

    test('有 password 即有效', () {
      expect(v.isValid(PasswordItem(title: '   ', username: '', password: 'p')),
          isTrue);
    });

    test('title 与 password 都空为无效', () {
      expect(v.isValid(PasswordItem(title: '', username: 'u', password: '')),
          isFalse);
    });

    test('filter 返回有效列表与无效计数', () {
      final (:valid, :invalid) = v.filter(<PasswordItem>[
        PasswordItem(title: 'a', username: '', password: 'p'), // 有效
        PasswordItem(title: '', username: '', password: ''), // 无效
        PasswordItem(title: 'b', username: '', password: ''), // 有效（有 title）
      ]);
      expect(valid.length, 2);
      expect(invalid, 1);
    });
  });
}
