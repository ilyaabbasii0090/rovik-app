import 'dart:convert';

/// فایل روویک (.rovik) — یک JSON با این شکل:
/// {"format":"rovik-subscription","version":1,
///  "sub":"https://panel17.rovikvpn.shop/sub/<token>","name":"Rovik"}
///
/// خروجی: آدرس ساب‌لینک (فیلد "sub") یا null اگر فایل معتبر نباشد.
class RovikFile {
  /// محتوای متنی فایل را پارس می‌کند و آدرس ساب‌لینک را برمی‌گرداند.
  static String? parseSubUrl(String content) {
    try {
      final data = jsonDecode(content.trim());
      if (data is! Map<String, dynamic>) return null;
      if ((data['format'] as String?) != 'rovik-subscription') return null;
      final sub = (data['sub'] as String?)?.trim();
      if (sub == null || sub.isEmpty) return null;
      final uri = Uri.tryParse(sub);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
      return sub;
    } catch (_) {
      return null;
    }
  }

  /// نام نمایشی داخل فایل (اختیاری).
  static String? parseName(String content) {
    try {
      final data = jsonDecode(content.trim());
      if (data is! Map<String, dynamic>) return null;
      final name = (data['name'] as String?)?.trim();
      return name == null || name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }
}
