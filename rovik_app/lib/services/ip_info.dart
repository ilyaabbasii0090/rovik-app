import 'dart:convert';

import 'package:http/http.dart' as http;

/// آی‌پی خروجی و کشور سرور (بعد از اتصال VPN).
class IpInfo {
  const IpInfo({
    required this.ip,
    required this.countryCode,
    required this.countryName,
  });

  final String ip;

  /// کد دوحرفی کشور (مثل DE)؛ ممکن است خالی باشد.
  final String countryCode;

  /// نام انگلیسی کشور از API (برای کشورهای خارج از نگاشت فارسی).
  final String countryName;

  /// پرچم از روی کد کشور؛ بدون کد، 🌐.
  String get flag => IpInfoService.flagFromCode(countryCode);

  /// نام فارسی کشور (یا همان نام انگلیسی اگر در نگاشت نباشد).
  String get countryFa =>
      IpInfoService.countryNameFa(countryCode, countryName);

  /// مثل «🇩🇪 آلمان — 51.89.112.107»
  String get label => '$flag $countryFa — $ip';
}

/// گرفتن آی‌پی و کشور از API عمومی؛ اول ipapi.co، اگر نشد ip-api.com.
/// هیچ خطایی بیرون نمی‌دهد: شکست یعنی null و UI چیزی نشان نمی‌دهد.
class IpInfoService {
  static const Duration timeout = Duration(seconds: 4);

  static Future<IpInfo?> fetch({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final a = await _get(c, 'https://ipapi.co/json/', parseIpapi);
      if (a != null) return a;
      return await _get(c, 'http://ip-api.com/json/', parseIpApi);
    } finally {
      if (client == null) c.close();
    }
  }

  static Future<IpInfo?> _get(
    http.Client c,
    String url,
    IpInfo? Function(String body) parse,
  ) async {
    try {
      final r = await c.get(Uri.parse(url)).timeout(timeout);
      if (r.statusCode != 200) return null;
      return parse(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// پاسخ ipapi.co: {"ip":"..","country_code":"DE","country_name":"Germany"}
  static IpInfo? parseIpapi(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map || j['error'] == true) return null;
      final ip = '${j['ip'] ?? ''}'.trim();
      if (ip.isEmpty) return null;
      return IpInfo(
        ip: ip,
        countryCode: '${j['country_code'] ?? ''}'.trim(),
        countryName: '${j['country_name'] ?? ''}'.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// پاسخ ip-api.com: {"status":"success","country":"..","countryCode":"DE","query":".."}
  static IpInfo? parseIpApi(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map || j['status'] != 'success') return null;
      final ip = '${j['query'] ?? ''}'.trim();
      if (ip.isEmpty) return null;
      return IpInfo(
        ip: ip,
        countryCode: '${j['countryCode'] ?? ''}'.trim(),
        countryName: '${j['country'] ?? ''}'.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// پرچم از کد دوحرفی (حروف نشانگر منطقه‌ای)؛ نامعتبر → 🌐
  static String flagFromCode(String code) {
    final c = code.trim().toUpperCase();
    if (c.length != 2) return '🌐';
    final a = c.codeUnitAt(0);
    final b = c.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return '🌐';
    return String.fromCharCode(0x1F1E6 + a - 65) +
        String.fromCharCode(0x1F1E6 + b - 65);
  }

  /// نام فارسی کشور؛ اگر کد در نگاشت نبود همان نام انگلیسی، و اگر آن هم
  /// نبود خود کد.
  static String countryNameFa(String code, String englishName) {
    final fa = _fa[code.trim().toUpperCase()];
    if (fa != null) return fa;
    if (englishName.isNotEmpty) return englishName;
    return code.trim().toUpperCase();
  }

  static const Map<String, String> _fa = {
    'DE': 'آلمان',
    'NL': 'هلند',
    'FI': 'فنلاند',
    'FR': 'فرانسه',
    'TR': 'ترکیه',
    'GB': 'بریتانیا',
    'US': 'آمریکا',
    'CA': 'کانادا',
    'SE': 'سوئد',
    'CH': 'سوئیس',
    'PL': 'لهستان',
    'ES': 'اسپانیا',
    'IT': 'ایتالیا',
    'JP': 'ژاپن',
    'SG': 'سنگاپور',
    'AT': 'اتریش',
    'NO': 'نروژ',
    'DK': 'دانمارک',
    'BE': 'بلژیک',
    'AU': 'استرالیا',
    'IE': 'ایرلند',
    'PT': 'پرتغال',
    'CZ': 'چک',
    'RO': 'رومانی',
    'BG': 'بلغارستان',
    'HU': 'مجارستان',
    'UA': 'اوکراین',
    'RU': 'روسیه',
    'LT': 'لیتوانی',
    'LV': 'لتونی',
    'EE': 'استونی',
    'LU': 'لوکزامبورگ',
    'IS': 'ایسلند',
    'GR': 'یونان',
    'AE': 'امارات',
    'IN': 'هند',
    'HK': 'هنگ‌کنگ',
    'KR': 'کره جنوبی',
    'TW': 'تایوان',
    'IL': 'اسرائیل',
    'BR': 'برزیل',
    'AR': 'آرژانتین',
    'MX': 'مکزیک',
    'ZA': 'آفریقای جنوبی',
    'AM': 'ارمنستان',
    'GE': 'گرجستان',
    'AZ': 'آذربایجان',
    'KZ': 'قزاقستان',
    'IR': 'ایران',
    'IQ': 'عراق',
    'SA': 'عربستان',
    'QA': 'قطر',
    'MD': 'مولداوی',
    'RS': 'صربستان',
    'HR': 'کرواسی',
    'SK': 'اسلواکی',
    'SI': 'اسلوونی',
    'CY': 'قبرس',
    'MT': 'مالت',
    'NZ': 'نیوزیلند',
  };
}
