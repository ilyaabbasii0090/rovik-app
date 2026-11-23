import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// یک اپ نصب‌شده روی گوشی.
class InstalledApp {
  const InstalledApp({required this.package, required this.label});
  final String package;
  final String label;
}

/// پل نیتیو اندروید (NativeChannel.kt): آمار ترافیک، فهرست اپ‌های نصب‌شده،
/// شبکه فعلی و سرعت زنده‌ی اعلان (هیچ‌کدام مجوز خطرناکی نمی‌خواهند).
class NativeBridge {
  static const MethodChannel _ch = MethodChannel('com.rovikvpn.app/native');

  static bool get _ok => !kIsWeb && Platform.isAndroid;

  /// بایت‌های دریافتی/ارسالی کل اپ (UID هسته VPN)؛ null اگر در دسترس نبود.
  static Future<({int rx, int tx})?> trafficBytes() async {
    if (!_ok) return null;
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('trafficBytes');
      if (r == null || r.length < 2) return null;
      final rx = (r[0] as num).toInt();
      final tx = (r[1] as num).toInt();
      if (rx < 0 || tx < 0) return null;
      return (rx: rx, tx: tx);
    } catch (_) {
      return null;
    }
  }

  static Future<List<InstalledApp>> installedApps() async {
    if (!_ok) return const <InstalledApp>[];
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('installedApps');
      if (r == null) return const <InstalledApp>[];
      return [
        for (final e in r)
          if (e is Map)
            InstalledApp(
              package: '${e['package']}',
              label: '${e['label']}',
            ),
      ];
    } catch (_) {
      return const <InstalledApp>[];
    }
  }

  /// شبکه فیزیکی فعلی: transport = wifi | mobile | none، و در صورت
  /// دسترسی ssid (وای‌فای) یا operator (نام اپراتور). null یعنی در دسترس نیست.
  static Future<Map<String, String>?> networkInfo() async {
    if (!_ok) return null;
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('networkInfo');
      if (r == null) return null;
      return {for (final e in r.entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return null;
    }
  }

  /// روشن/خاموش کردن به‌روزرسانی سرعت زنده داخل اعلان دائمی VPN.
  static Future<void> setSpeedNotifier(bool enabled) async {
    if (!_ok) return;
    try {
      await _ch.invokeMethod<void>('speedNotifier', {'enabled': enabled});
    } catch (_) {
      // اعلان سرعت اختیاری است؛ شکستش نباید اتصال را بهم بزند.
    }
  }
}
