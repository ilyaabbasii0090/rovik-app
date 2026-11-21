import 'package:flutter/material.dart';

import '../theme.dart';

/// نوع دیالوگ روویک: موفقیت (سبز)، خطا (قرمز) یا اطلاع (طلایی).
enum RovikDialogKind { success, error, info }

/// دیالوگ وسط‌صفحه شیک روویک — جایگزین اسنک‌بار برای خطاها و
/// نتیجه ایمپورت.
///
/// گوشه‌های گرد، سطح تیره هماهنگ با تم اپ، آیکون دایره‌ای طلایی/سبز/قرمز
/// و یک دکمه شیک برای بستن. با زدن دکمه یا بیرون دیالوگ بسته می‌شود.
Future<void> showRovikDialog(
  BuildContext context, {
  required String title,
  required String message,
  required RovikDialogKind kind,
  String buttonLabel = 'متوجه شدم',
}) {
  final Color accent;
  final IconData icon;
  switch (kind) {
    case RovikDialogKind.success:
      accent = RovikTheme.mint;
      icon = Icons.check_circle_outline_rounded;
      break;
    case RovikDialogKind.error:
      accent = RovikTheme.coral;
      icon = Icons.error_outline_rounded;
      break;
    case RovikDialogKind.info:
      accent = RovikTheme.gold;
      icon = Icons.info_outline_rounded;
      break;
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Dialog(
      backgroundColor: RovikTheme.bgCardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: accent.withValues(alpha: 0.25)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.15),
                border: Border.all(
                  color: accent.withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.25),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(icon, size: 38, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: RovikTheme.textMain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.8,
                color: RovikTheme.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// پیام دوستانه فارسی برای خطای ایمپورت ساب‌لینک.
///
/// متن خام خطا (مثل SocketException یا stack trace) هرگز به کاربر نشان
/// داده نمی‌شود؛ خطاهای رایج به جمله‌های کوتاه فارسی تبدیل می‌شوند.
String friendlyImportError(Object e) {
  final text = e.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('connection') ||
      text.contains('network') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('timeout')) {
    return 'به اینترنت وصل نیستی یا ساب‌لینک باز نمی‌شه. اینترنتت رو چک کن و دوباره بزن.';
  }
  if (text.contains('500') ||
      text.contains('502') ||
      text.contains('503') ||
      text.contains('internal server error')) {
    return 'سرور اشتراک فعلاً جواب نمی‌ده. چند دقیقه دیگه دوباره بزن.';
  }
  if (text.contains('404') || text.contains('not found')) {
    return 'این ساب‌لینک پیدا نشد؛ شاید منقضی شده باشد. از ربات یک ساب‌لینک تازه بگیر.';
  }
  if (text.contains('formatexception') || text.contains('invalid')) {
    return 'ساب‌لینک خرابه یا کانفیگی توش نیست.';
  }
  return 'ایمپورت ممکن نشد. اینترنتت رو چک کن و دوباره بزن.';
}
