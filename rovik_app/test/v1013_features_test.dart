import 'package:flutter_test/flutter_test.dart';
import 'package:rovik_app/models/models.dart';
import 'package:rovik_app/services/ip_info.dart';
import 'package:rovik_app/services/network_memory.dart';
import 'package:rovik_app/services/usage_alerts.dart';

SubInfo _info({
  required double used,
  double total = 50,
  int days = 20,
  bool active = true,
}) =>
    SubInfo(
      username: 'u',
      usedGb: used,
      totalGb: total,
      daysLeft: days,
      expiresAt: '',
      active: active,
    );

void main() {
  group('آی‌پی و کشور', () {
    test('پرچم و نام فارسی کشور', () {
      expect(IpInfoService.flagFromCode('DE'), '🇩🇪');
      expect(IpInfoService.flagFromCode(''), '🌐');
      expect(IpInfoService.countryNameFa('DE', 'Germany'), 'آلمان');
      expect(IpInfoService.countryNameFa('XX', 'Somewhere'), 'Somewhere');
    });

    test('پارس پاسخ ipapi.co و ip-api.com', () {
      final a = IpInfoService.parseIpapi(
        '{"ip":"51.89.112.107","country_code":"DE","country_name":"Germany"}',
      );
      expect(a?.label, '🇩🇪 آلمان — 51.89.112.107');
      final b = IpInfoService.parseIpApi(
        '{"status":"success","country":"Germany","countryCode":"DE","query":"51.89.112.107"}',
      );
      expect(b?.label, '🇩🇪 آلمان — 51.89.112.107');
    });

    test('پاسخ خطا یعنی null (بدون خطا برای کاربر)', () {
      expect(IpInfoService.parseIpapi('{"error":true}'), isNull);
      expect(IpInfoService.parseIpApi('{"status":"fail"}'), isNull);
      expect(IpInfoService.parseIpapi('not json'), isNull);
    });
  });

  group('حافظه هوشمند سرور', () {
    test('نام فارسی اپراتور', () {
      expect(NetworkMemory.operatorFa('IR-MCI'), 'همراه اول');
      expect(NetworkMemory.operatorFa('Irancell'), 'ایرانسل');
      expect(NetworkMemory.operatorFa('RighTel'), 'رایتل');
    });

    test('کلید شبکه', () {
      final m = NetworkMemory.fromInfo(
        {'transport': 'mobile', 'operator': 'MCI'},
      );
      expect(m?.key, 'mobile:همراه اول');
      expect(m?.label, 'همراه اول');
      expect(
        NetworkMemory.fromInfo({'transport': 'wifi', 'ssid': 'Home'})?.key,
        'wifi:Home',
      );
      expect(NetworkMemory.fromInfo({'transport': 'wifi'})?.key, 'wifi');
      expect(NetworkMemory.fromInfo({'transport': 'mobile'})?.key, 'mobile');
      expect(NetworkMemory.fromInfo({'transport': 'none'}), isNull);
      expect(NetworkMemory.fromInfo(null), isNull);
    });
  });

  group('هشدار حجم و روز', () {
    test('کمتر از ۲۰٪ حجم', () {
      final a = UsageAlerts.evaluate(_info(used: 45));
      expect(a.map((e) => e.id), ['volume']);
    });

    test('دقیقاً ۲۰٪ هشدار نمی‌دهد', () {
      expect(UsageAlerts.evaluate(_info(used: 40)), isEmpty);
    });

    test('سه روز یا کمتر', () {
      expect(
        UsageAlerts.evaluate(_info(used: 10, days: 3)).map((e) => e.id),
        ['days'],
      );
      expect(UsageAlerts.evaluate(_info(used: 10, days: 4)), isEmpty);
      expect(UsageAlerts.evaluate(_info(used: 10, days: 0)), isEmpty);
    });

    test('هر دو هشدار و اشتراک غیرفعال', () {
      expect(
        UsageAlerts.evaluate(_info(used: 49, days: 1)).map((e) => e.id),
        ['volume', 'days'],
      );
      expect(
        UsageAlerts.evaluate(_info(used: 49, days: 1, active: false)),
        isEmpty,
      );
    });
  });
}
