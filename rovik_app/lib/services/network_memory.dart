import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'best_server.dart';
import 'native_bridge.dart';

/// شبکه‌ی فعلی گوشی برای «حافظه هوشمند سرور».
class NetworkContext {
  const NetworkContext({required this.key, required this.label});

  /// کلید حافظه: wifi:<SSID> ،wifi ،mobile:<اپراتور> یا mobile.
  final String key;

  /// نام فارسی قابل‌نمایش: «همراه اول»، «وای‌فای «Home»» و…
  final String label;
}

/// سریع‌ترین سرور را برای هر شبکه جدا به یاد می‌سپارد: روی وای‌فای با نام
/// شبکه (SSID)، روی دیتا با نام اپراتور. اگر نام در دسترس نباشد
/// (مثلاً اندروید بدون مجوز مکان SSID نمی‌دهد) به «wifi» / «mobile» برمی‌گردد.
class NetworkMemory {
  static const _prefix = 'rovik_fastest_server_v1:';

  /// نام اپراتور سیم‌کارت (هر نوشته‌ی رایج) → نام فارسی.
  static String operatorFa(String raw) {
    final n = raw.toLowerCase().trim();
    if (n.isEmpty) return '';
    if (n.contains('mci') ||
        n.contains('tci') ||
        n.contains('hamrah') ||
        n.contains('همراه')) {
      return 'همراه اول';
    }
    if (n.contains('irancell') || n.contains('mtn') || n.contains('ایرانسل')) {
      return 'ایرانسل';
    }
    if (n.contains('rightel') || n.contains('رایتل')) return 'رایتل';
    return raw.trim();
  }

  /// از خروجی نیتیو، کلید و نام شبکه را می‌سازد؛ null یعنی شبکه‌ای نیست.
  static NetworkContext? fromInfo(Map<String, String>? info) {
    if (info == null) return null;
    switch (info['transport']) {
      case 'wifi':
        final ssid = (info['ssid'] ?? '').trim();
        if (ssid.isNotEmpty) {
          return NetworkContext(key: 'wifi:$ssid', label: 'وای‌فای «$ssid»');
        }
        return const NetworkContext(key: 'wifi', label: 'وای‌فای');
      case 'mobile':
        final op = operatorFa(info['operator'] ?? '');
        if (op.isNotEmpty) {
          return NetworkContext(key: 'mobile:$op', label: op);
        }
        return const NetworkContext(key: 'mobile', label: 'دیتای موبایل');
      default:
        return null;
    }
  }

  static Future<NetworkContext?> current() async =>
      fromInfo(await NativeBridge.networkInfo());

  /// بعد از هر تست پینگ، سریع‌ترین سرور این شبکه را ذخیره می‌کند.
  static Future<void> rememberFastest(
    NetworkContext? ctx,
    List<VpnConfig> configs,
  ) async {
    if (ctx == null) return;
    final idx = BestServer.fastestIndex(configs);
    if (idx == null) return;
    final c = configs[idx];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefix${ctx.key}',
        jsonEncode({'link': c.link, 'host': c.host, 'port': c.port}),
      );
    } catch (_) {
      // ذخیره‌سازی در دسترس نیست؛ حافظه هوشمند فقط کار نمی‌کند.
    }
  }

  /// ایندکس سرور به‌یادمانده‌ی این شبکه در [configs]؛ null اگر نبود یا
  /// دیگر در اشتراک نیست.
  static Future<int?> recallIndex(
    NetworkContext? ctx,
    List<VpnConfig> configs,
  ) async {
    if (ctx == null || configs.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix${ctx.key}');
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final link = '${j['link'] ?? ''}';
      var idx = configs.indexWhere((c) => c.link == link);
      if (idx < 0) {
        final host = '${j['host'] ?? ''}';
        final port = (j['port'] as num?)?.toInt() ?? 0;
        idx = configs.indexWhere((c) => c.host == host && c.port == port);
      }
      return idx < 0 ? null : idx;
    } catch (_) {
      return null;
    }
  }
}
