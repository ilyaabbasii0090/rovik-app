/// یک کانفیگ VPN واردشده از ساب‌لینک (vless:// ،ss:// ،trojan:// ،vmess://).
class VpnConfig {
  VpnConfig({
    required this.link,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.pingMs,
  });

  /// لینک کامل اشتراک‌گذاری (مثل vless://...).
  final String link;

  /// نام نمایشی (remark) کانفیگ.
  final String name;

  /// پروتکل: vless | ss | trojan | vmess
  final String protocol;

  /// هاست/آی‌پی سرور.
  final String host;

  /// پورت سرور.
  final int port;

  /// آخرین پینگ اندازه‌گیری‌شده (میلی‌ثانیه)؛ null یعنی هنوز تست نشده.
  int? pingMs;

  /// پرچم کشور بر اساس هاست/آی‌پی سرور.
  String get flag => flagForHost(host);

  Map<String, dynamic> toJson() => {
        'link': link,
        'name': name,
        'protocol': protocol,
        'host': host,
        'port': port,
        'pingMs': pingMs,
      };

  factory VpnConfig.fromJson(Map<String, dynamic> json) => VpnConfig(
        link: (json['link'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        protocol: (json['protocol'] as String?) ?? '',
        host: (json['host'] as String?) ?? '',
        port: (json['port'] as num?)?.toInt() ?? 0,
        pingMs: (json['pingMs'] as num?)?.toInt(),
      );
}

/// پرچم کشور بر اساس هاست یا آی‌پی سرور.
///
/// سرورهای شناخته‌شده روویک اول بررسی می‌شوند؛ بقیه با حدس از روی
/// نام هاست (nl، de، fi، fr، tr و...) و در نهایت پرچم عمومی 🌐.
String flagForHost(String host) {
  final h = host.toLowerCase().trim();
  // سرورهای شناخته‌شده روویک.
  if (h == '176.65.151.202' || h.contains('176.65.151.')) return '🇳🇱';
  if (h == '51.89.112.107' ||
      h.startsWith('51.89.112.') ||
      h.contains('51.89.112.')) {
    return '🇩🇪';
  }
  // حدس از روی نام هاست.
  if (h.contains('netherlands') || h.contains('.nl') || h.contains('-nl') || h.contains('nl-')) return '🇳🇱';
  if (h.contains('germany') || h.contains('.de') || h.contains('-de') || h.contains('de-')) return '🇩🇪';
  if (h.contains('finland') || h.contains('.fi') || h.contains('-fi') || h.contains('fi-')) return '🇫🇮';
  if (h.contains('france') || h.contains('.fr') || h.contains('-fr') || h.contains('fr-')) return '🇫🇷';
  if (h.contains('turkey') || h.contains('turkiye') || h.contains('-tr') || h.contains('tr-')) return '🇹🇷';
  if (h.contains('britain') || h.contains('united-kingdom') || h.contains('.uk') || h.contains('-uk')) return '🇬🇧';
  if (h.contains('usa') || h.contains('united-states') || h.contains('.us') || h.contains('-us')) return '🇺🇸';
  if (h.contains('canada') || h.contains('-ca') || h.contains('ca-')) return '🇨🇦';
  if (h.contains('sweden') || h.contains('-se') || h.contains('se-')) return '🇸🇪';
  if (h.contains('switzerland') || h.contains('-ch') || h.contains('ch-')) return '🇨🇭';
  if (h.contains('poland') || h.contains('-pl') || h.contains('pl-')) return '🇵🇱';
  if (h.contains('spain') || h.contains('-es') || h.contains('es-')) return '🇪🇸';
  if (h.contains('italy') || h.contains('-it') || h.contains('it-')) return '🇮🇹';
  if (h.contains('japan') || h.contains('-jp') || h.contains('jp-')) return '🇯🇵';
  if (h.contains('singapore') || h.contains('-sg') || h.contains('sg-')) return '🇸🇬';
  if (h.contains('austria') || h.contains('-at') || h.contains('at-')) return '🇦🇹';
  if (h.contains('norway') || h.contains('-no') || h.contains('no-')) return '🇳🇴';
  if (h.contains('denmark') || h.contains('-dk') || h.contains('dk-')) return '🇩🇰';
  if (h.contains('belgium') || h.contains('-be') || h.contains('be-')) return '🇧🇪';
  if (h.contains('australia') || h.contains('-au') || h.contains('au-')) return '🇦🇺';
  return '🌐';
}

/// اطلاعات اشتراک از GET /api/app/sub-info?token=...
///
/// قرارداد دقیق:
/// {"ok":true,"username":"...","used_gb":12.5,"total_gb":50.0,
///  "days_left":25,"expires_at":"...","active":true}
class SubInfo {
  SubInfo({
    required this.username,
    required this.usedGb,
    required this.totalGb,
    required this.daysLeft,
    required this.expiresAt,
    required this.active,
  });

  factory SubInfo.fromJson(Map<String, dynamic> json) => SubInfo(
        username: (json['username'] as String?) ?? '',
        usedGb: _asDouble(json['used_gb']),
        totalGb: _asDouble(json['total_gb']),
        daysLeft: _asInt(json['days_left']),
        expiresAt: (json['expires_at'] as String?) ?? '',
        active: json['active'] == true,
      );

  final String username;
  final double usedGb;
  final double totalGb;
  final int daysLeft;
  final String expiresAt;
  final bool active;

  /// حجم باقی‌مانده (گیگ).
  double get remainingGb => (totalGb - usedGb).clamp(0, double.infinity);

  /// درصد مصرف‌شده (۰ تا ۱) برای نوار پیشرفت.
  double get usedFraction {
    if (totalGb <= 0) return 0;
    return (usedGb / totalGb).clamp(0, 1);
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// اطلاعات نسخه از GET /api/app/version (عمومی).
///
/// قرارداد دقیق:
/// {"ok":true,"version":"1.0.0","min_version":"1.0.0",
///  "download_url":"https://rovikvpn.shop/dl/rovik.apk","force_update":false}
class AppVersionInfo {
  AppVersionInfo({
    required this.version,
    required this.minVersion,
    required this.downloadUrl,
    required this.forceUpdate,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) =>
      AppVersionInfo(
        version: (json['version'] as String?) ?? '',
        minVersion: (json['min_version'] as String?) ?? '',
        downloadUrl: (json['download_url'] as String?) ?? '',
        forceUpdate: json['force_update'] == true,
      );

  final String version;
  final String minVersion;
  final String downloadUrl;
  final bool forceUpdate;
}

/// یک محصول فروشگاه (GET /api/shop/products) — قیمت‌ها از سرور می‌آیند.
class ShopProduct {
  ShopProduct({
    required this.id,
    required this.planKey,
    required this.label,
    required this.gb,
    required this.days,
    required this.price,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
        id: _asInt(json['id']),
        planKey: (json['plan_key'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        gb: _asInt(json['gb']),
        days: _asInt(json['days']),
        price: _asInt(json['price']),
      );

  final int id;
  final String planKey;
  final String label;
  final int gb;
  final int days;
  final int price;

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
