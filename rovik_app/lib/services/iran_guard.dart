import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'native_bridge.dart';
import 'vpn_engine.dart';

/// تنظیمات «قطع خودکار برای اپ‌های ایرانی».
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

  /// مجموعه نهایی پکیج‌هایی که با باز شدنشان VPN قطع می‌شود.
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

/// قطع خودکار VPN وقتی اپ ایرانی جلوی صفحه است و وصل فوری بعد از خروج.
///
/// - فقط اتصالی را برمی‌گرداند که خودش قطع کرده؛ اگر VPN از اول خاموش
///   بود، هرگز آن را روشن نمی‌کند.
/// - وصل دوباره با همان مسیر [VpnEngine.connectWithFallback] انجام می‌شود
///   (سروری که قبلاً وصل بود اول، بعد بقیه به ترتیب).
/// - بدون مجوز Usage Access هیچ کاری نمی‌کند.
class IranGuard {
  IranGuard({required this.engine, required this.candidates});

  final VpnEngine engine;
  final List<({String remark, String link})> Function() candidates;

  /// پکیج‌های سیستمی که ظاهر شدنشان به معنی عوض شدن اپ نیست
  /// (پنجره مجوز، سایه اعلان‌ها، ...).
  static const Set<String> _ignored = {
    'android',
    'com.android.systemui',
    'com.google.android.permissioncontroller',
    'com.android.permissioncontroller',
    'com.miui.securitycenter',
    'com.lbe.security.miui',
  };

  Timer? _timer;
  bool _busy = false;
  bool _pausedByGuard = false;
  Set<String> _apps = <String>{};

  bool get isRunning => _timer != null;

  /// تنظیمات را دوباره می‌خواند و ردیاب را روشن/خاموش می‌کند.
  Future<void> refresh() async {
    _timer?.cancel();
    _timer = null;
    engine.bypassIranDomains = false;
    if (!VpnEngine.isSupported) return;
    final enabled = await IranGuardPrefs.loadEnabled();
    if (!enabled) {
      _pausedByGuard = false;
      return;
    }
    if (!await NativeBridge.hasUsageAccess()) {
      _pausedByGuard = false;
      return; // بدون مجوز، قابلیت خاموش است و VPN مثل قبل کار می‌کند.
    }
    final installed = await NativeBridge.installedApps();
    _apps = await IranGuardPrefs.effective(installed);
    engine.bypassIranDomains = true;
    _timer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _tick(),
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  List<({String remark, String link})> _ordered() {
    final list = candidates();
    final first = engine.lastConnectedLink;
    if (first == null) return list;
    final idx = list.indexWhere((c) => c.link == first);
    if (idx <= 0) return list;
    return [list[idx], ...list.where((c) => c.link != first)];
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final fg = await NativeBridge.foregroundPackage();
      if (fg == null || _ignored.contains(fg)) return;
      final iran = _apps.contains(fg);
      final st = engine.state;
      if (iran) {
        if (st == VpnConnectionState.connected) {
          // اپ ایرانی باز شد: اتصال را قطع کن و یادت بماند که خودت قطع کردی.
          _pausedByGuard = true;
          await engine.disconnect();
        }
        return;
      }
      if (!_pausedByGuard) return;
      if (st == VpnConnectionState.connected) {
        _pausedByGuard = false; // کاربر خودش دوباره وصل کرده.
        return;
      }
      if (st != VpnConnectionState.disconnected) return;
      // از اپ ایرانی بیرون آمد: همان لحظه وصل شو.
      _pausedByGuard = false;
      final list = _ordered();
      if (list.isEmpty) return;
      await engine.connectWithFallback(candidates: list);
    } catch (_) {
      // شکست وصل خودکار در گزارش عیب‌یابی موتور ثبت می‌شود؛ حلقه تکرار نمی‌شود.
      _pausedByGuard = false;
    } finally {
      _busy = false;
    }
  }
}
