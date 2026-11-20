import '../models/models.dart';

/// انتخاب سریع‌ترین کانفیگ بر اساس پینگ واقعی TCP.
///
/// پینگ null یعنی هنوز تست نشده یا سرور در دسترس نیست؛ این کانفیگ‌ها
/// آخر صف می‌روند و هیچ‌وقت به‌عنوان «سریع‌ترین» انتخاب نمی‌شوند.
class BestServer {
  /// ایندکس سریع‌ترین کانفیگ در لیست اصلی، یا null اگر هیچ پینگی نیست.
  static int? fastestIndex(List<VpnConfig> configs) {
    int? bestIdx;
    int? bestPing;
    for (var i = 0; i < configs.length; i++) {
      final ping = configs[i].pingMs;
      if (ping == null) continue;
      if (bestPing == null || ping < bestPing) {
        bestPing = ping;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// کپی مرتب‌شده بر اساس پینگ (کم به زیاد)؛ بدون پینگ آخر می‌روند.
  static List<VpnConfig> ranked(List<VpnConfig> configs) {
    final sorted = List<VpnConfig>.of(configs);
    sorted.sort((a, b) {
      final pa = a.pingMs;
      final pb = b.pingMs;
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pa.compareTo(pb);
    });
    return sorted;
  }
}
