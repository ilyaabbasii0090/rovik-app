import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rovik_app/models/models.dart';
import 'package:rovik_app/services/best_server.dart';
import 'package:rovik_app/services/ping_service.dart';
import 'package:rovik_app/services/rovik_file.dart';
import 'package:rovik_app/services/sublink_parser.dart';
import 'package:rovik_app/services/version_check.dart';

void main() {
  group('پارس ساب‌لینک', () {
    test('بدنه base64 با چند کانفیگ vless و ss', () {
      const vless =
          'vless://11111111-2222-3333-4444-555555555555@176.65.151.202:443?encryption=none&security=reality#ilya%20NL';
      const ss =
          'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@51.89.112.107:1080#ilya%20DE%20SS';
      final body = base64Encode(utf8.encode('$vless\n$ss\n'));
      final configs = SublinkParser.parseBody(body);
      expect(configs.length, 2);
      expect(configs[0].protocol, 'vless');
      expect(configs[0].host, '176.65.151.202');
      expect(configs[0].port, 443);
      expect(configs[0].name, 'ilya NL');
      expect(configs[1].protocol, 'ss');
      expect(configs[1].host, '51.89.112.107');
      expect(configs[1].port, 1080);
    });

    test('متن ساده (بدون base64) هم پارس می‌شود', () {
      const body =
          'trojan://pass@1.2.3.4:443?security=tls#Tehran\n'
          'vless://uuid@5.6.7.8:8443#Test';
      final configs = SublinkParser.parseBody(body);
      expect(configs.length, 2);
      expect(configs[0].protocol, 'trojan');
      expect(configs[1].host, '5.6.7.8');
    });

    test('vmess لینک base64 از JSON است', () {
      final payload = base64Encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'vmess-test',
        'add': '9.9.9.9',
        'port': '443',
        'id': 'uuid',
      })));
      final cfg = SublinkParser.parseLink('vmess://$payload');
      expect(cfg, isNotNull);
      expect(cfg!.protocol, 'vmess');
      expect(cfg.host, '9.9.9.9');
      expect(cfg.name, 'vmess-test');
    });

    test('خط خراب نادیده گرفته می‌شود', () {
      const body = 'not-a-link\nvless://uuid@1.1.1.1:443#ok';
      final configs = SublinkParser.parseBody(body);
      expect(configs.length, 1);
      expect(configs.first.name, 'ok');
    });

    test('توکن از آدرس ساب‌لینک بیرون کشیده می‌شود', () {
      expect(
        SublinkParser.extractToken(
          'https://panel17.rovikvpn.shop/sub/abc123token',
        ),
        'abc123token',
      );
      expect(SublinkParser.extractToken('not a url'), isNull);
    });
  });

  group('پرچم کشور', () {
    test('سرورهای شناخته‌شده روویک', () {
      expect(flagForHost('176.65.151.202'), '🇳🇱');
      expect(flagForHost('51.89.112.107'), '🇩🇪');
      expect(flagForHost('51.89.112.105'), '🇩🇪');
    });

    test('حدس از نام هاست و fallback', () {
      expect(flagForHost('fi-node.example.com'), '🇫🇮');
      expect(flagForHost('server-fr-01.example.net'), '🇫🇷');
      expect(flagForHost('unknown.example.com'), '🌐');
    });
  });

  group('قالب‌بندی پینگ', () {
    test('عدد به فارسی با ms', () {
      expect(PingService.formatPing(42), '۴۲ ms');
      expect(PingService.formatPing(0), '۰ ms');
    });

    test('پینگ نامشخص «—» است', () {
      expect(PingService.formatPing(null), '—');
    });
  });

  group('مقایسه نسخه', () {
    test('نسخه جدیدتر درست تشخیص داده می‌شود', () {
      expect(isUpdateAvailable('1.0.0', '1.0.1'), isTrue);
      expect(isUpdateAvailable('1.0.0', '1.1.0'), isTrue);
      expect(isUpdateAvailable('1.9.0', '1.10.0'), isTrue);
      expect(isUpdateAvailable('1.0.0', '1.0.0'), isFalse);
      expect(isUpdateAvailable('2.0.0', '1.9.9'), isFalse);
    });

    test('حداقل نسخه اجباری', () {
      expect(isBelowMinVersion('1.0.0', '1.0.1'), isTrue);
      expect(isBelowMinVersion('1.0.1', '1.0.1'), isFalse);
      expect(compareVersions('1.0', '1.0.0'), 0);
    });
  });

  group('فایل روویک (.rovik)', () {
    test('فایل معتبر آدرس sub را می‌دهد', () {
      const content = '''
{"format":"rovik-subscription","version":1,
 "sub":"https://panel17.rovikvpn.shop/sub/abc123","name":"Rovik"}''';
      expect(
        RovikFile.parseSubUrl(content),
        'https://panel17.rovikvpn.shop/sub/abc123',
      );
      expect(RovikFile.parseName(content), 'Rovik');
    });

    test('فایل نامعتبر رد می‌شود', () {
      expect(RovikFile.parseSubUrl('not json'), isNull);
      expect(
        RovikFile.parseSubUrl('{"format":"other","sub":"https://x.co/s"}'),
        isNull,
      );
      expect(
        RovikFile.parseSubUrl('{"format":"rovik-subscription"}'),
        isNull,
      );
      expect(
        RovikFile.parseSubUrl(
          '{"format":"rovik-subscription","sub":"not-a-url"}',
        ),
        isNull,
      );
    });
  });

  group('انتخاب سریع‌ترین سرور', () {
    VpnConfig cfg(String name, int? ping) => VpnConfig(
          link: 'vless://uuid@1.1.1.1:443#$name',
          name: name,
          protocol: 'vless',
          host: '1.1.1.1',
          port: 443,
          pingMs: ping,
        );

    test('کمترین پینگ انتخاب می‌شود', () {
      final configs = [cfg('a', 120), cfg('b', 42), cfg('c', 300)];
      expect(BestServer.fastestIndex(configs), 1);
    });

    test('بدون پینگ، انتخابی نیست', () {
      final configs = [cfg('a', null), cfg('b', null)];
      expect(BestServer.fastestIndex(configs), isNull);
      expect(BestServer.fastestIndex([]), isNull);
    });

    test('بدون پینگ آخر صف می‌رود', () {
      final configs = [cfg('a', null), cfg('b', 90), cfg('c', 50)];
      final ranked = BestServer.ranked(configs);
      expect(ranked.map((c) => c.name).toList(), ['c', 'b', 'a']);
    });
  });

  group('مدل SubInfo', () {
    test('حجم باقی‌مانده و درصد مصرف', () {
      final info = SubInfo.fromJson({
        'username': 'ilya',
        'used_gb': 12.5,
        'total_gb': 50.0,
        'days_left': 25,
        'expires_at': '2026-12-20',
        'active': true,
      });
      expect(info.remainingGb, 37.5);
      expect(info.usedFraction, 0.25);
      expect(info.active, isTrue);
    });
  });
}
