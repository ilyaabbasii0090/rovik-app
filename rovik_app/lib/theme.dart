import 'package:flutter/material.dart';

/// تم اپ روویک: سرمه‌ای تیره، اکسنت آبی، کارت‌های گرد، حالت متصل سبز.
/// هماهنگ با تم اپ فروشگاه (lib/theme.dart آن اپ) و چیدمان زونیکس.
class RovikTheme {
  static const Color bgDeep = Color(0xFF030816);
  static const Color bgMid = Color(0xFF081634);
  static const Color bgCard = Color(0xFF0B1838);
  static const Color bgCardLight = Color(0xFF12275A);
  static const Color neonBlue = Color(0xFF2F80FF);
  static const Color neonCyan = Color(0xFF29E0FF);
  static const Color gold = Color(0xFFFFC94D);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color mint = Color(0xFF34D399);
  static const Color textMain = Color(0xFFF2F6FF);
  static const Color textMuted = Color(0xFF9FB0D0);
  static const Color slate = Color(0xFF6B7FA8);
  static const Color hairline = Color(0x14FFFFFF);

  /// رنگ پینگ: سبز زیر ۱۵۰، طلایی زیر ۳۰۰، قرمز بالاتر؛ بدون پینگ خاکستری.
  static Color pingColor(int? ms) => ms == null
      ? textMuted
      : ms < 150
          ? mint
          : ms < 300
              ? gold
              : coral;

  static List<BoxShadow> softShadow() => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: neonBlue,
      secondary: neonCyan,
      tertiary: gold,
      error: coral,
      surface: bgCard,
      onSurface: textMain,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDeep,
      colorScheme: colorScheme,
      fontFamily: 'Vazirmatn',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          color: textMain,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: textMain),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: neonCyan,
          side: const BorderSide(color: neonCyan),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCard.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: neonBlue.withValues(alpha: 0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: neonBlue.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: neonCyan, width: 1.5),
        ),
        labelStyle: const TextStyle(fontFamily: 'Vazirmatn', color: textMuted),
        hintStyle: const TextStyle(fontFamily: 'Vazirmatn', color: textMuted),
      ),
      cardTheme: const CardThemeData(
        color: bgCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: hairline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bgCardLight,
        contentTextStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          color: textMain,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: hairline),
        ),
      ),
      splashFactory: InkSparkle.splashFactory,
      chipTheme: ChipThemeData(
        backgroundColor: bgCard,
        selectedColor: neonBlue.withValues(alpha: 0.35),
        labelStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          color: textMain,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: neonBlue.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF081634), Color(0xFF030816), Color(0xFF050E26)],
  );

  /// کارت نئونی: پس‌زمینه سرمه‌ای، حاشیه روشن و درخشش دو لایه.
  static BoxDecoration neonCard({
    Color color = neonBlue,
    double radius = 28,
    double glow = 0.28,
    double border = 0.65,
    List<Color>? fill,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: fill ?? const [Color(0xFF0D2252), Color(0xFF071230)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: color.withValues(alpha: border),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: glow),
            blurRadius: 26,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: color.withValues(alpha: glow * 0.5),
            blurRadius: 60,
            spreadRadius: 2,
          ),
        ],
      );

  static List<BoxShadow> neonGlow([Color color = neonBlue]) => [
        BoxShadow(
          color: color.withValues(alpha: 0.45),
          blurRadius: 22,
          spreadRadius: 1,
        ),
      ];
}

/// ابزارهای نمایشی مشترک: ارقام فارسی و قالب‌بندی حجم/سرعت.
class FaFormat {
  static const _faDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  static String digits(String s) => s.split('').map((c) {
        final d = int.tryParse(c);
        return d == null ? c : _faDigits[d];
      }).join();

  static String number(num value) {
    final negative = value < 0;
    var s = value.abs().toInt().toString();
    final buf = StringBuffer();
    var count = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      count++;
      if (count % 3 == 0 && i != 0) buf.write(',');
    }
    s = buf.toString().split('').reversed.join();
    return negative ? '-${digits(s)}' : digits(s);
  }

  static String price(int value) => '${number(value)} تومان';

  /// حجم به گیگابایت؛ اگر مقدار نامشخص باشد «—» برمی‌گرداند.
  static String gb(double? value) {
    if (value == null) return '—';
    if (value >= 1000) return '${number((value / 1000).round())} ترابایت';
    if (value == value.truncateToDouble()) return '${number(value)} گیگ';
    return digits('${value.toStringAsFixed(1)} گیگ');
  }

  /// سرعت لحظه‌ای (بایت بر ثانیه) به صورت خوانا.
  static String speed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '۰';
    if (bytesPerSecond < 1024) return '${number(bytesPerSecond)} B/s';
    final kb = bytesPerSecond / 1024;
    if (kb < 1024) return '${digits(kb.toStringAsFixed(1))} KB/s';
    final mb = kb / 1024;
    return '${digits(mb.toStringAsFixed(2))} MB/s';
  }

  /// حجم کل (بایت) به صورت خوانا.
  static String bytes(int bytes) {
    if (bytes <= 0) return '۰';
    if (bytes < 1024) return '${number(bytes)} B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${digits(kb.toStringAsFixed(1))} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${digits(mb.toStringAsFixed(1))} MB';
    return '${digits((mb / 1024).toStringAsFixed(2))} GB';
  }

  /// مدت اتصال «HH:MM:SS» (همان رشته‌ای که V2RayStatus می‌دهد).
  static String duration(String raw) => digits(raw);
}
