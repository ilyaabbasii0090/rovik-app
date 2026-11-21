import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// یک اپ نصب‌شده روی گوشی.
class InstalledApp {
  const InstalledApp({required this.package, required this.label});
  final String package;
  final String label;
}

/// پل نیتیو اندروید (MainActivity.kt): آمار ترافیک، مجوز Usage Access،
/// اپِ جلوی صفحه و فهرست اپ‌های نصب‌شده.
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

  static Future<bool> hasUsageAccess() async {
    if (!_ok) return false;
    try {
      return await _ch.invokeMethod<bool>('hasUsageAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUsageAccessSettings() async {
    if (!_ok) return;
    try {
      await _ch.invokeMethod<void>('openUsageAccessSettings');
    } catch (_) {}
  }

  /// پکیج اپی که الان جلوی صفحه است (null اگر معلوم نیست).
  static Future<String?> foregroundPackage() async {
    if (!_ok) return null;
    try {
      return await _ch.invokeMethod<String>('foregroundPackage');
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
}
