import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'native_bridge.dart';
import 'vpn_engine.dart';

/// تنظیمات «اپ‌های ایرانی» (bypass تک‌اپ: ترافیک این اپ‌ها مستقیم می‌رود).
class IranGuardPrefs {
  static const _kEnabled = 'rovik_iran_guard_enabled_v1';
  static const _kAdded = 'rovik_iran_guard_added_v1';
  static const _kRemoved = 'rovik_iran_guard_removed_v1';

  /// اپ‌های ایرانی رایج (بانکی، دولتی و پرکاربرد). علاوه بر این فهرست،
  /// اپ‌هایی که نامشان «بانک» دارد هم پیش‌فرض حساب می‌شوند.
  static const Set<String> knownPackages = {
    'com.samanpr.blu',
    'ir.mobillet.app',
    'ir.tejaratbank.tata.mobile.android.tejarat',
    'ir.mci.ecareapp',
    'ir.medu.shad',
    'com.farsitel.bazaar',
    'ir.mservices.market',
  };

  /// آیا این اپ به‌طور پیش‌فرض ایرانیِ نیازمند آی‌پی ایران حساب می‌شود؟
  static bool isDefault(InstalledApp a) {
    if (knownPackages.contains(a.package)) return true;
    if (a.label.contains('بانک')) return true;
    return a.package.startsWith('ir.') && a.package.contains('bank');
  }

  static Future<bool> loadEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? false;
  }

  static Future<void> saveEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
  }

  static Future<Set<String>> loadAdded() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kAdded) ?? const <String>[]).toSet();
  }

  static Future<Set<String>> loadRemoved() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kRemoved) ?? const <String>[]).toSet();
  }

  static Future<void> saveLists(Set<String> added, Set<String> removed) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kAdded, added.toList());
    await p.setStringList(_kRemoved, removed.toList());
  }

  /// مجموعه نهایی پکیج‌هایی که ترافیکشان مستقیم (بدون VPN) می‌رود.
  static Future<Set<String>> effective(List<InstalledApp> installed) async {
    final added = await loadAdded();
    final removed = await loadRemoved();
    final defaults = <String>{
      ...knownPackages,
      for (final a in installed)
        if (isDefault(a)) a.package,
    };
    return (defaults.difference(removed)).union(added);
  }
}

/// اعمال فهرست اپ‌های ایرانی روی موتور VPN (bypass تک‌اپ، بدون هیچ مجوز).
///
/// - VPN همیشه روشن می‌ماند؛ ترافیک اپ‌های فهرست مستقیم (آی‌پی ایران) می‌رود
///   و بقیه ترافیک روی VPN می‌ماند.
/// - فهرست فقط موقع استارت VPN اثر دارد؛ پس اگر موقع وصل بودن کلید یا فهرست
///   عوض شد، یک بار اتصال تمیز قطع و با همان مسیر
///   [VpnEngine.connectWithFallback] (سروری که وصل بود اول) دوباره وصل می‌شود.
/// - اگر قابلیت خاموش است، فهرست خالی می‌ماند و VPN مثل قبل کار می‌کند.
class IranGuard {
  IranGuard({required this.engine, required this.candidates});

  final VpnEngine engine;
  final List<({String remark, String link})> Function() candidates;

  /// امضای فهرستی که روی اتصال فعلی اعمال شده (برای تشخیص نیاز به وصل مجدد).
  String _appliedSignature = '';
  String _wantedSignature = '';
  Timer? _debounce;
  bool _reconnecting = false;
  bool _disposed = false;

  static String _signature(bool enabled, Set<String> apps) {
    if (!enabled) return '';
    final l = apps.toList()..sort();
    return l.join(',');
  }

  List<({String remark, String link})> _ordered() {
    final list = candidates();
    final first = engine.lastConnectedLink;
    if (first == null) return list;
    final idx = list.indexWhere((c) => c.link == first);
    if (idx <= 0) return list;
    return [list[idx], ...list.where((c) => c.link != first)];
  }

  /// تنظیمات را دوباره می‌خواند و روی موتور اعمال می‌کند. اگر VPN وصل است و
  /// تنظیمات عوض شده، با کمی تأخیر (برای جمع شدن چند تیک پشت‌سرهم) اتصال را
  /// تمیز قطع و دوباره وصل می‌کند.
  Future<void> refresh() async {
    if (!VpnEngine.isSupported) return;
    final enabled = await IranGuardPrefs.loadEnabled();
    var apps = <String>{};
    if (enabled) {
      final installed = await NativeBridge.installedApps();
      apps = await IranGuardPrefs.effective(installed);
    }
    if (_disposed) return;
    engine.bypassIranDomains = enabled;
    engine.blockedApps = enabled ? (apps.toList()..sort()) : const <String>[];
    _wantedSignature = _signature(enabled, apps);

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

  /// موتور هر بار که استارت می‌شود فهرست فعلی را استفاده می‌کند؛ این متد
  /// را بعد از اتصال دستیِ کاربر صدا بزن تا امضای اعمال‌شده هم‌گام شود.
  void markApplied() => _appliedSignature = _wantedSignature;

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
  }
}
