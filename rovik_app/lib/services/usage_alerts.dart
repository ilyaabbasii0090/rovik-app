import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../theme.dart';
import 'vpn_engine.dart';

/// یک هشدار حجم یا روز.
class UsageAlert {
  const UsageAlert({required this.id, required this.title, required this.body});

  /// volume | days
  final String id;
  final String title;
  final String body;
}

/// قواعد هشدار: حجم باقی‌مانده کمتر از ۲۰٪، یا ۳ روز (یا کمتر) تا انقضا.
class UsageAlerts {
  static const double volumeThreshold = 0.20;
  static const int daysThreshold = 3;

  static List<UsageAlert> evaluate(SubInfo info) {
    final out = <UsageAlert>[];
    if (!info.active) return out;
    if (info.totalGb > 0) {
      final frac = info.remainingGb / info.totalGb;
      if (frac < volumeThreshold) {
        final pct = FaFormat.digits('${(frac * 100).round()}');
        out.add(UsageAlert(
          id: 'volume',
          title: 'حجم اشتراکت رو به اتمام است',
          body:
              'فقط ${FaFormat.gb(info.remainingGb)} ($pct٪) از حجمت باقی مانده. برای تمدید به ربات سر بزن.',
        ));
      }
    }
    if (info.daysLeft >= 1 && info.daysLeft <= daysThreshold) {
      out.add(UsageAlert(
        id: 'days',
        title: 'اشتراکت به‌زودی تمام می‌شود',
        body:
            'فقط ${FaFormat.number(info.daysLeft)} روز تا پایان اشتراکت مانده است. برای تمدید به ربات سر بزن.',
      ));
    }
    return out;
  }
}

/// اعلان لوکال هشدارها (flutter_local_notifications). مجوز اعلان فقط
/// وقتی خواسته می‌شود که واقعاً هشداری برای ارسال باشد؛ نه موقع شروع اپ.
/// برای هر هشدار حداکثر یک اعلان در روز.
class AlertNotifier {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channelId = 'rovik_usage_alerts';
  static const _kAsked = 'rovik_notif_permission_asked_v1';
  static String _kDay(String id) => 'rovik_alert_day_${id}_v1';

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  static Future<bool> _init() async {
    if (_ready) return true;
    if (!VpnEngine.isSupported) return false;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static Future<bool> canSendToday(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kDay(id)) != _today();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> areEnabled() async {
    if (!await _init()) return false;
    try {
      return (await _android?.areNotificationsEnabled()) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> alreadyAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kAsked) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAsked, true);
    } catch (_) {}
  }

  static Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      return (await _android?.requestNotificationsPermission()) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// اعلان را نشان می‌دهد و ثبت می‌کند که امروز برای این هشدار فرستاده شد.
  static Future<bool> show(UsageAlert a) async {
    if (!await _init()) return false;
    try {
      await _plugin.show(
        a.id == 'volume' ? 2001 : 2002,
        a.title,
        a.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'هشدار حجم و روز',
            channelDescription: 'هشدار کم شدن حجم یا روزهای باقی‌مانده اشتراک',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDay(a.id), _today());
      return true;
    } catch (_) {
      return false;
    }
  }
}
