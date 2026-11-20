import 'dart:io';

/// پینگ واقعی: زمان اتصال TCP به هاست:پورت سرور (میلی‌ثانیه).
///
/// این پینگِ شبکه است، نه تست سرعت؛ برای انتخاب بهترین سرور کافی است.
/// اگر اتصال برقرار نشد، null برمی‌گردد (سرور در دسترس نیست).
class PingService {
  /// یک اتصال TCP کوتاه به هاست:پورت می‌زند و زمانش را برمی‌گرداند.
  /// [timeout] پیش‌فرض ۳ ثانیه است.
  static Future<int?> tcpPing(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (host.isEmpty || port <= 0) return null;
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// نمایش پینگ: «۴۲ ms» یا «—» وقتی تست نشده/ناموفق بوده.
  static String formatPing(int? pingMs) {
    if (pingMs == null) return '—';
    return '${_faDigits(pingMs)} ms';
  }

  static String _faDigits(int value) {
    const digits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    return value.toString().split('').map((c) {
      final d = int.tryParse(c);
      return d == null ? c : digits[d];
    }).join();
  }
}
