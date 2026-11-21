/// پیکربندی سراسری اپ اختصاصی روویک.
///
/// همه آدرس‌ها فقط همین‌جا عوض می‌شوند.
class RovikConfig {
  /// آدرس پایه وب‌سایت و API.
  static const String baseUrl = 'https://rovikvpn.shop';

  /// مسیر API فروشگاه (محصولات، سفارش، رسید).
  static const String shopApiPath = '/api/shop';

  /// مسیر API مخصوص اپ (اطلاعات اشتراک و نسخه).
  /// قرارداد: GET /api/app/sub-info?token=... و GET /api/app/version
  static const String appApiPath = '/api/app';

  /// ربات تلگرام روویک (همان مقدار lib/config.dart اپ فروشگاه).
  static const String supportBotUsername = 'RovikVpn_bot';
  static const String supportUrl = 'https://t.me/RovikVpn_bot';

  /// اسکیم دیپ‌لینک اختصاصی اپ: rovik://import?sub=<url-encoded sublink>
  static const String deepLinkScheme = 'rovik';

  /// App Link وب: https://rovikvpn.shop/app/import?sub=<url-encoded>
  static const String appLinkHost = 'rovikvpn.shop';
  static const String appLinkPath = '/app/import';

  /// لینک دانلود مستقیم APK (از پاسخ /api/app/version می‌آید).
  static const String apkDownloadFallback =
      'https://rovikvpn.shop/dl/rovik.apk';

  /// نسخه نصب‌شده (باید با pubspec.yaml هماهنگ بماند).
  static const String appVersion = '1.0.8';
}
