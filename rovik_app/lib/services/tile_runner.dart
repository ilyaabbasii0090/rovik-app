import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/models.dart';
import 'best_server.dart';
import 'iran_guard.dart';
import 'network_memory.dart';
import 'subscription_store.dart';
import 'vpn_engine.dart';

const MethodChannel _tile = MethodChannel('com.rovikvpn.app/tile');

/// نقطه ورود Dart برای کاشی تنظیمات سریع (موتور Flutter هدلس).
///
/// Kotlin (HeadlessVpn) این موتور را بدون هیچ اکتیویتی بالا می‌آورد؛ دستور
/// «connect» یا «disconnect» را می‌خواند، همان VpnEngine اپ را اجرا می‌کند
/// و نتیجه را با «done» برمی‌گرداند. مسیر اتصال همان connectWithFallback است
/// (سرور انتخاب‌شده/به‌یادمانده اول، بعد بقیه به‌ترتیب پینگ) و فهرست
/// اپ‌های ایرانی (blockedApps) هم مثل اتصال داخل اپ پاس داده می‌شود.
Future<void> runTileCommand() async {
  WidgetsFlutterBinding.ensureInitialized();
  var action = 'connect';
  try {
    action = (await _tile.invokeMethod<String>('command')) ?? 'connect';
  } catch (_) {}

  var ok = false;
  String? message;
  final engine = VpnEngine();
  try {
    if (action == 'disconnect') {
      await engine.initialize();
      await engine.disconnect();
      ok = true;
    } else {
      final r = await _connect(engine);
      ok = r.ok;
      message = r.message;
    }
  } catch (e) {
    message = e is VpnConnectException
        ? e.message
        : 'اتصال ممکن نشد؛ از داخل اپ امتحان کن.';
  } finally {
    engine.dispose();
  }
  try {
    await _tile.invokeMethod<void>('done', {'ok': ok, 'message': message});
  } catch (_) {}
}

Future<({bool ok, String? message})> _connect(VpnEngine engine) async {
  final store = SubscriptionStore();
  final configs = await store.loadConfigs();
  if (configs.isEmpty) {
    return (ok: false, message: 'اول اشتراک را از ربات وارد اپ کن.');
  }
  var selected =
      (await store.loadSelectedIndex()).clamp(0, configs.length - 1);
  final manual = await store.loadManualSelection();
  if (!manual) {
    final ctx = await NetworkMemory.current();
    final remembered = await NetworkMemory.recallIndex(ctx, configs);
    if (remembered != null) selected = remembered;
  }
  final candidates = orderedCandidates(configs, selected);

  engine.blockedAppsProvider = IranGuardPrefs.resolveBlocked;
  engine.assumePermissionGranted();
  final result = await engine.connectWithFallback(candidates: candidates);
  if (result.connected) return (ok: true, message: null);
  return (ok: false, message: 'هیچ سروری وصل نشد؛ از داخل اپ امتحان کن.');
}

/// اول سرور انتخاب‌شده، بعد بقیه به‌ترتیب پینگ (سریع‌ترین اول) —
/// همان ترتیب دکمه اتصال داخل اپ.
List<({String remark, String link})> orderedCandidates(
  List<VpnConfig> configs,
  int selected,
) {
  final cfg = configs[selected];
  final rest =
      BestServer.ranked(configs).where((c) => c.link != cfg.link).toList();
  return [
    (remark: cfg.name, link: cfg.link),
    for (final c in rest) (remark: c.name, link: c.link),
  ];
}
