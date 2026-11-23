import 'dart:async';

import 'package:flutter/widgets.dart';

import 'native_bridge.dart';
import 'vpn_engine.dart';

/// تشخیص خودکار اپ‌های ایرانی (بدون هیچ انتخاب دستی از طرف کاربر).
class IranGuardPrefs {
  /// اپ‌های پرکاربرد ایرانی که پکیجشان با «ir.» شروع نمی‌شود (فقط
  /// پکیج‌های مطمئن). هر پکیجی که با «ir.» شروع شود هم خودکار ایرانی
  /// حساب می‌شود و نیازی به ثبت اینجا ندارد.
  static const Set<String> knownPackages = {
    // بانک و مالی
    'com.samanpr.blu',
    // تاکسی اینترنتی و سفارش غذا
    'cab.snapp.passenger',
    'cab.snapp.driver',
    'cab.snapp.snappfood',
    // فروشگاه
    'com.digikala',
    // بازار اپ
    'com.farsitel.bazaar',
  };

  /// آیا این اپ ایرانیِ نیازمند آی‌پی ایران حساب می‌شود؟
  /// - پکیج با «ir.» شروع شود، یا در [knownPackages] باشد؛
  /// - نام نمایشی «بانک» داشته باشد یا پکیج «bank» داشته باشد.
  static bool isIranian(InstalledApp a) {
    final pkg = a.package.toLowerCase();
    if (pkg.startsWith('ir.')) return true;
    if (knownPackages.contains(pkg)) return true;
    if (a.label.contains('بانک')) return true;
    return pkg.contains('bank');
  }

  /// پکیج‌های اپ‌های ایرانیِ نصب‌شده روی گوشی؛ ترافیک این‌ها مستقیم
  /// (بدون VPN) می‌رود.
  static Set<String> effective(List<InstalledApp> installed) => {
        for (final a in installed)
          if (isIranian(a)) a.package,
      };

  /// فهرست مرتب نهایی برای blockedApps (در هر اتصال، از اپ‌های نصب‌شده).
  static Future<List<String>> resolveBlocked() async {
    final installed = await NativeBridge.installedApps();
    return effective(installed).toList()..sort();
  }
}

/// اعمال فهرست اپ‌های ایرانی روی موتور VPN (bypass تک‌اپ، بدون هیچ مجوز).
///
/// - قابلیت همیشه برای همه فعال است؛ نه کلید دارد نه انتخاب دستی.
///   فهرست در هر اتصال خودکار از اپ‌های نصب‌شده ساخته می‌شود.
/// - VPN همیشه روشن می‌ماند؛ ترافیک اپ‌های فهرست مستقیم (آی‌پی ایران) می‌رود
///   و بقیه ترافیک روی VPN می‌ماند.
/// - فهرست فقط موقع استارت VPN اثر دارد؛ پس اگر موقع وصل بودن فهرست عوض شد،
///   یک بار اتصال تمیز قطع و با همان مسیر [VpnEngine.connectWithFallback]
///   (سروری که وصل بود اول) دوباره وصل می‌شود.
class IranGuard with WidgetsBindingObserver {
  IranGuard({required this.engine, required this.candidates}) {
    engine.blockedAppsProvider = _resolve;
    WidgetsBinding.instance.addObserver(this);
    // نصب یا حذف اپ ایرانی در حین کار اپ را هم بگیر.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  final VpnEngine engine;
  final List<({String remark, String link})> Function() candidates;

  /// امضای فهرستی که روی اتصال فعلی اعمال شده (برای تشخیص نیاز به وصل مجدد).
  String _appliedSignature = '';
  String _wantedSignature = '';
  Timer? _debounce;
  Timer? _poll;
  bool _reconnecting = false;
  bool _disposed = false;

  static String _signature(List<String> apps) => apps.join(',');

  Future<List<String>> _resolve() async {
    return IranGuardPrefs.resolveBlocked();
  }

  List<({String remark, String link})> _ordered() {
    final list = candidates();
    final first = engine.lastConnectedLink;
    if (first == null) return list;
    final idx = list.indexWhere((c) => c.link == first);
    if (idx <= 0) return list;
    return [list[idx], ...list.where((c) => c.link != first)];
  }

  /// فهرست را از اپ‌های نصب‌شده دوباره می‌سازد و روی موتور اعمال می‌کند. اگر VPN وصل است و
  /// فهرست عوض شده، با کمی تأخیر (برای جمع شدن چند تیک پشت‌سرهم) اتصال را
  /// تمیز قطع و دوباره وصل می‌کند.
  Future<void> refresh() async {
    if (!VpnEngine.isSupported) return;
    final apps = await _resolve();
    if (_disposed) return;
    engine.blockedApps = apps;
    _wantedSignature = _signature(apps);

    if (engine.state != VpnConnectionState.connected) {
      // وصل نیست: فهرست جدید روی اتصال بعدی اثر می‌کند.
      _debounce?.cancel();
      _appliedSignature = _wantedSignature;
      return;
    }
    if (_wantedSignature == _appliedSignature) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), _reconnect);
  }

  /// اتصال را کامل قطع و با فهرست جدید دوباره وصل می‌کند.
  Future<void> _reconnect() async {
    if (_reconnecting || _disposed) return;
    if (engine.state != VpnConnectionState.connected) {
      _appliedSignature = _wantedSignature;
      return;
    }
    _reconnecting = true;
    try {
      final list = _ordered();
      if (list.isEmpty) return;
      await engine.disconnect();
      await Future.delayed(const Duration(milliseconds: 1500));
      final r = await engine.connectWithFallback(candidates: list);
      if (r.connected) _appliedSignature = _wantedSignature;
    } catch (_) {
      // شکست وصل مجدد در گزارش عیب‌یابی موتور ثبت می‌شود.
    } finally {
      _reconnecting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // برگشت به اپ (مثلاً بعد از نصب یک اپ ایرانی): فهرست را دوباره بساز.
    if (state == AppLifecycleState.resumed) refresh();
  }

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _debounce = null;
    if (engine.blockedAppsProvider == _resolve) engine.blockedAppsProvider = null;
  }
}
