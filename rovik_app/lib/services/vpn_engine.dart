import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_v2ray/flutter_v2ray.dart';

/// وضعیت اتصال VPN در اپ.
enum VpnConnectionState { disconnected, connecting, connected, disconnecting }

/// لایه موتور VPN روی پلاگین flutter_v2ray (هسته Xray).
///
/// - روی اندروید: اتصال واقعی VPN از طریق سرویس VpnService پلاگین.
///   سرعت لحظه‌ای و حجم کل مستقیم از V2RayStatus پلاگین می‌آیند
///   (نه عدد ساختگی).
/// - روی وب/دسکتاپ/آی‌اواس: پلاگین پیاده‌سازی ندارد؛ متدها
///   UnsupportedError می‌دهند و UI دکمه اتصال را غیرفعال نشان می‌دهد.
///   (اتصال زنده فقط روی دستگاه اندرویدی قابل تست است؛ در این محیط
///   هیچ دستگاه/شبیه‌ساز اندرویدی نیست.)
class VpnEngine {
  VpnEngine({void Function(VpnStatusSnapshot snapshot)? onStatus})
      : _onStatus = onStatus;

  final void Function(VpnStatusSnapshot snapshot)? _onStatus;
  void Function(VpnStatusSnapshot snapshot)? _statusListener;

  /// شنونده وضعیت (صفحه اصلی آن را ست می‌کند).
  set onStatus(void Function(VpnStatusSnapshot snapshot)? cb) {
    _statusListener = cb;
  }

  FlutterV2ray? _client;
  bool _initialized = false;
  VpnConnectionState _state = VpnConnectionState.disconnected;
  VpnStatusSnapshot _last = const VpnStatusSnapshot();

  /// زمان شروع آخرین درخواست اتصال. پلاگین در همان ثانیه‌های اول
  /// ممکن است یک وضعیت گذرای DISCONNECTED بفرستد؛ تا وقتی اتصال
  /// واقعاً برقرار نشده یا مهلت تلاش تمام نشده، آن را قطع‌شدن حساب نمی‌کنیم.
  DateTime? _connectStartedAt;

  /// مهلت هر تلاش اتصال به یک سرور. اپ‌های کانفیگ معمولاً در ۱ تا ۳
  /// ثانیه وصل می‌شوند؛ اگر سروری تا این مهلت وصل نشد، مرده حساب
  /// می‌شود و سراغ سرور بعدی می‌رویم (به‌جای ۲۰ ثانیه چرخیدن روی یک
  /// سرور و بعد بی‌صدا قطع شدن).
  static const Duration perAttemptTimeout = Duration(seconds: 8);

  /// کامل‌کننده‌ای که وقتی وضعیت «متصل» رسید، تلاش جاری را موفق اعلام می‌کند.
  Completer<bool>? _connectCompleter;

  /// ثبت رویدادهای عیب‌یابی (آخرین ۱۲۰ خط) تا دلیل شکست روی گوشی دیده شود.
  final List<String> _log = <String>[];

  /// تعداد رویداد وضعیتی که پلاگین از شروع تلاش جاری فرستاده است.
  int _eventsSinceStart = 0;
  bool _sawConnecting = false;
  String _lastRaw = '';

  void _trace(String message) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _log.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $message');
    if (_log.length > 120) _log.removeAt(0);
  }

  /// گزارش کامل عیب‌یابی برای نمایش در اپ.
  String diagnosticReport() {
    final head = <String>[
      'اندروید: ${isSupported ? "بله" : "خیر"}',
      'مقداردهی هسته: ${_initialized ? "انجام شد" : "انجام نشد"}',
      'وضعیت فعلی: ${_state.name} (آخرین رویداد پلاگین: ${_lastRaw.isEmpty ? "هیچ" : _lastRaw})',
      '—',
    ];
    final body = _log.isEmpty ? <String>['(هنوز رویدادی ثبت نشده)'] : _log;
    return [...head, ...body].join('\n');
  }

  VpnConnectionState get state => _state;
  VpnStatusSnapshot get lastStatus => _last;

  /// آیا این پلتفرم موتور واقعی دارد؟ (فقط اندروید)
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void>? _initFuture;

  /// مقداردهی هسته؛ چند بار صدا زدن (initState + دکمه اتصال) فقط یک
  /// بار پلاگین را مقداردهی می‌کند. خطا هیچ‌وقت قورت داده نمی‌شود.
  Future<void> initialize() {
    if (!isSupported || _initialized) return Future<void>.value();
    return _initFuture ??= _initOnce();
  }

  Future<void> _initOnce() async {
    try {
      _client = FlutterV2ray(
        onStatusChanged: (status) {
          final mapped = _mapState(status.state);
          final snap = VpnStatusSnapshot.fromV2Ray(status);
          final raw = status.state.toUpperCase();
          _eventsSinceStart++;
          if (raw == 'CONNECTING') _sawConnecting = true;
          if (raw != _lastRaw) {
            _lastRaw = raw;
            _trace('رویداد پلاگین: $raw');
          }
          if (mapped == VpnConnectionState.disconnected &&
              _state == VpnConnectionState.connecting &&
              _inConnectGrace) {
            // وضعیت گذرای قطع در حین برقراری اتصال؛ نادیده گرفته می‌شود.
            return;
          }
          if (mapped == VpnConnectionState.connected) {
            _connectStartedAt = null;
            final c = _connectCompleter;
            if (c != null && !c.isCompleted) c.complete(true);
            _connectCompleter = null;
          }
          _last = snap;
          _state = mapped;
          _emit();
        },
      );
      await _client!.initializeV2Ray();
      _initialized = true;
      _trace('initializeV2Ray موفق');
    } catch (e) {
      _trace('initializeV2Ray شکست خورد: $e');
      _initFuture = null;
      _client = null;
      throw VpnStartException('مقداردهی هسته V2Ray شکست خورد: $e');
    }
  }

  /// بررسی اینکه هسته Xray واقعاً بارگذاری شده است. اگر کتابخانه
  /// نیتیو لود نشود (مثلاً R8 یا ABI نامناسب) اینجا خطای واضح می‌دهد.
  Future<void> _verifyCore() async {
    try {
      final v = await _client!.getCoreVersion();
      _trace('نسخه هسته: ${v.isEmpty ? "(خالی)" : v}');
    } catch (e) {
      _trace('getCoreVersion شکست خورد: $e');
      throw VpnStartException(
        'هسته Xray روی این گوشی بارگذاری نشد: $e',
      );
    }
  }

  Future<bool> _requestPermission() async {
    try {
      final granted = await _client!.requestPermission();
      _trace('requestPermission → $granted');
      return granted;
    } on PlatformException catch (e) {
      _trace('requestPermission خطا: ${e.code} ${e.message}');
      throw VpnStartException(
        'درخواست مجوز VPN خطا داد (${e.code}): ${e.message ?? ""}',
      );
    }
  }

  /// اتصال مستقیم به کانفیگ انتخاب‌شده — بدون جست‌وجوی خودکار و
  /// بدون تست سرعت قبل از اتصال.
  ///
  /// اگر سرور تا پایان [perAttemptTimeout] وصل نشد، [VpnConnectException]
  /// پرتاب می‌کند تا UI به‌جای چرخیدن بی‌صدا، دلیل را نشان دهد.
  Future<void> connect({
    required String remark,
    required String link,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'اتصال VPN فقط روی اندروید ممکن است.',
      );
    }
    await initialize();
    await _verifyCore();
    final granted = await _requestPermission();
    if (!granted) {
      _state = VpnConnectionState.disconnected;
      _emit();
      throw const VpnPermissionDenied();
    }
    final reason = await _tryConnectOne(
      remark: remark,
      link: link,
      timeout: perAttemptTimeout,
    );
    if (reason != null) {
      try {
        await disconnect();
      } catch (_) {}
      throw VpnConnectException('سرور $remark: $reason');
    }
  }

  /// اتصال با تلاش خودکار روی چند سرور (سریع‌ترین اول).
  ///
  /// سرورها را به‌ترتیب امتحان می‌کند؛ هر سرور تا [perAttemptTimeout]
  /// فرصت دارد «متصل» شود. اگر سروری وصل شد همان را برمی‌گرداند؛ اگر
  /// هیچ‌کدام وصل نشد، نتیجه ناموفق برمی‌گرداند تا UI پیام درست نشان
  /// دهد (به‌جای ۲۰ ثانیه چرخیدن روی یک سرور مرده و بعد بی‌صدا قطع شدن).
  /// [onAttempt] قبل از هر تلاش صدا زده می‌شود تا UI نشان دهد روی کدام
  /// سرور است.
  Future<VpnConnectResult> connectWithFallback({
    required List<({String remark, String link})> candidates,
    Duration timeout = perAttemptTimeout,
    void Function(String remark, int attempt, int total)? onAttempt,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'اتصال VPN فقط روی اندروید ممکن است.',
      );
    }
    if (candidates.isEmpty) {
      return const VpnConnectResult(
        connected: false,
        connectedRemark: null,
        connectedLink: null,
        triedCount: 0,
      );
    }
    await initialize();
    await _verifyCore();
    // اجازه VPN یک بار اول گرفته می‌شود؛ اگر داده نشد، تلاش روی سرورها بی‌فایده است.
    final granted = await _requestPermission();
    if (!granted) {
      _state = VpnConnectionState.disconnected;
      _emit();
      throw const VpnPermissionDenied();
    }
    var tried = 0;
    final failures = <String>[];
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      tried++;
      onAttempt?.call(c.remark, i + 1, candidates.length);
      String? reason;
      try {
        reason = await _tryConnectOne(
          remark: c.remark,
          link: c.link,
          timeout: timeout,
        );
      } catch (e) {
        // خطای غیرمنتظره؛ دلیلش ثبت می‌شود و سرور بعدی امتحان می‌شود.
        reason = 'خطای غیرمنتظره: $e';
      }
      if (reason == null || _state == VpnConnectionState.connected) {
        // در لحظه آخر هم وصل شده بود، همان را قبول کن.
        return VpnConnectResult(
          connected: true,
          connectedRemark: c.remark,
          connectedLink: c.link,
          triedCount: tried,
        );
      }
      // این سرور وصل نشد؛ دلیلش را نگه دار (هیچ شکستی بی‌صدا نیست).
      failures.add('${c.remark}: $reason');
      _trace('شکست ${c.remark}: $reason');
      // سرویس را کامل قطع کن تا تلاش بعدی تمیز شروع شود.
      try {
        await disconnect();
      } catch (_) {}
      // مکث تا سرویس قبلی کامل جمع شود (پلاگین استارت تکراری با همان
      // امضا را نادیده می‌گیرد، پس نباید عجله کرد).
      await Future.delayed(const Duration(milliseconds: 1500));
      if (_state == VpnConnectionState.connected) {
        return VpnConnectResult(
          connected: true,
          connectedRemark: c.remark,
          connectedLink: c.link,
          triedCount: tried,
        );
      }
    }
    return VpnConnectResult(
      connected: false,
      connectedRemark: null,
      connectedLink: null,
      triedCount: tried,
      failures: failures,
    );
  }

  /// یک تلاش اتصال به یک سرور. موفق = null؛ شکست = دلیل فارسی دقیق.
  ///
  /// هیچ مسیری بی‌صدا نیست: پارس‌نشدن لینک، خالی‌بودن کانفیگ، رد شدن
  /// startV2Ray توسط پلاگین و تمام‌شدن مهلت، همگی دلیل برمی‌گردانند. در
  /// حالت مهلت، با تست مستقیم هسته (getServerDelay) مشخص می‌شود مشکل از
  /// سرور است یا از سرویس VPN/tun2socks گوشی.
  Future<String?> _tryConnectOne({
    required String remark,
    required String link,
    required Duration timeout,
  }) async {
    _connectStartedAt = DateTime.now();
    _eventsSinceStart = 0;
    _sawConnecting = false;
    _state = VpnConnectionState.connecting;
    _emit();

    String config;
    try {
      final parser = FlutterV2ray.parseFromURL(link);
      config = parser.getFullConfiguration();
    } catch (e) {
      return 'لینک کانفیگ پارس نشد ($e)';
    }
    if (config.trim().isEmpty) {
      return 'کانفیگ تولیدشده خالی است (پارس لینک ناموفق).';
    }
    try {
      final decoded = jsonDecode(config);
      if (decoded is! Map || decoded['outbounds'] == null) {
        return 'کانفیگ تولیدشده outbound ندارد.';
      }
    } catch (e) {
      return 'کانفیگ تولیدشده JSON معتبر نیست ($e)';
    }

    _connectStartedAt = DateTime.now();
    final completer = Completer<bool>();
    _connectCompleter = completer;
    _trace('startV2Ray → $remark');
    try {
      await _client!.startV2Ray(
        remark: remark,
        config: config,
        proxyOnly: false,
        notificationDisconnectButtonName: 'قطع اتصال',
      );
    } on PlatformException catch (e) {
      if (_connectCompleter == completer) _connectCompleter = null;
      return 'پلاگین استارت را رد کرد (${e.code}): ${e.message ?? ""}';
    } catch (e) {
      if (_connectCompleter == completer) _connectCompleter = null;
      return 'استارت سرویس VPN خطا داد: $e';
    }
    bool ok;
    try {
      ok = await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      if (_connectCompleter == completer) _connectCompleter = null;
    }
    if (ok) return null;
    if (_state == VpnConnectionState.connected) return null;

    // --- شکست: دلیلش را پیدا کن ---
    final secs = timeout.inSeconds;
    String why;
    if (_eventsSinceStart == 0) {
      why = 'در $secs ثانیه هیچ رویدادی از سرویس VPN نیامد؛ هسته یا '
          'سرویس VPN اصلاً بالا نیامد (استارت بی‌صدا شکست خورد).';
    } else if (_sawConnecting) {
      why = 'سرویس شروع به اتصال کرد ولی تا $secs ثانیه «متصل» نشد '
          'یا خودش متوقف شد (آخرین رویداد: $_lastRaw).';
    } else {
      why = 'فقط وضعیت «$_lastRaw» رسید و اتصال برقرار نشد.';
    }
    try {
      await _client!.stopV2Ray();
    } catch (_) {}
    try {
      final ms = await _client!
          .getServerDelay(config: config)
          .timeout(const Duration(seconds: 6));
      if (ms > 0) {
        why += ' تست مستقیم هسته: سرور جواب می‌دهد (${ms}ms) پس مشکل '
            'از سرویس VPN/tun2socks همین گوشی است، نه از سرور.';
      } else {
        why += ' تست مستقیم هسته هم جواب نگرفت؛ سرور یا مسیر شبکه مشکل دارد.';
      }
    } catch (e) {
      why += ' تست مستقیم هسته هم خطا داد ($e).';
    }
    return why;
  }

  bool get _inConnectGrace =>
      _connectStartedAt != null &&
      DateTime.now().difference(_connectStartedAt!) < perAttemptTimeout;

  Future<void> disconnect() async {
    if (!isSupported || _client == null) {
      _state = VpnConnectionState.disconnected;
      return;
    }
    final c = _connectCompleter;
    if (c != null && !c.isCompleted) c.complete(false);
    _connectCompleter = null;
    _connectStartedAt = null;
    _state = VpnConnectionState.disconnecting;
    _emit();
    await _client!.stopV2Ray();
    _state = VpnConnectionState.disconnected;
    _last = const VpnStatusSnapshot();
    _emit();
  }

  /// تاخیر واقعی سرور از طریق هسته V2Ray (فقط اندروید).
  Future<int?> serverDelay(String link) async {
    if (!isSupported) return null;
    try {
      await initialize();
      final parser = FlutterV2ray.parseFromURL(link);
      final ms = await _client!.getServerDelay(
        config: parser.getFullConfiguration(),
      );
      return ms;
    } catch (_) {
      return null;
    }
  }

  void _emit() {
    _onStatus?.call(_last);
    _statusListener?.call(_last);
  }

  void dispose() {
    final c = _connectCompleter;
    if (c != null && !c.isCompleted) c.complete(false);
    _connectCompleter = null;
  }

  static VpnConnectionState _mapState(String raw) {
    switch (raw.toUpperCase()) {
      case 'CONNECTED':
        return VpnConnectionState.connected;
      case 'CONNECTING':
        return VpnConnectionState.connecting;
      case 'DISCONNECTING':
        return VpnConnectionState.disconnecting;
      default:
        return VpnConnectionState.disconnected;
    }
  }
}

/// نتیجه تلاش اتصال با چند سرور.
class VpnConnectResult {
  const VpnConnectResult({
    required this.connected,
    required this.connectedRemark,
    required this.connectedLink,
    required this.triedCount,
    this.failures = const <String>[],
  });

  /// دلیل شکست هر سرور («نام سرور: دلیل») به ترتیب تلاش.
  final List<String> failures;

  /// آیا بالاخره یک سرور وصل شد؟
  final bool connected;

  /// نام سروری که وصل شد (اگر وصل شد).
  final String? connectedRemark;

  /// لینک سروری که وصل شد (اگر وصل شد).
  final String? connectedLink;

  /// چند سرور امتحان شد.
  final int triedCount;
}

/// خطای اتصال به یک سرور (مهلت تمام شد یا هسته وصل نشد).
class VpnConnectException implements Exception {
  const VpnConnectException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// خطای شروع هسته/سرویس (مقداردهی، بارگذاری هسته، مجوز).
class VpnStartException extends VpnConnectException {
  const VpnStartException(super.message);
}

/// خطای اجازه VPN (کاربر اجازه نداد).
class VpnPermissionDenied implements Exception {
  const VpnPermissionDenied();
  @override
  String toString() => 'اجازه VPN داده نشد.';
}

/// عکس لحظه‌ای وضعیت که مستقیم از V2RayStatus پلاگین ساخته می‌شود.
class VpnStatusSnapshot {
  const VpnStatusSnapshot({
    this.duration = '00:00:00',
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.downloadTotal = 0,
    this.uploadTotal = 0,
    this.rawState = 'DISCONNECTED',
  });

  factory VpnStatusSnapshot.fromV2Ray(V2RayStatus s) => VpnStatusSnapshot(
        duration: s.duration,
        downloadSpeed: s.downloadSpeed,
        uploadSpeed: s.uploadSpeed,
        downloadTotal: s.download,
        uploadTotal: s.upload,
        rawState: s.state,
      );

  /// مدت اتصال «HH:MM:SS».
  final String duration;

  /// سرعت دانلود لحظه‌ای (بایت بر ثانیه) — از هسته V2Ray.
  final int downloadSpeed;

  /// سرعت آپلود لحظه‌ای (بایت بر ثانیه) — از هسته V2Ray.
  final int uploadSpeed;

  /// حجم کل دانلودشده در این اتصال (بایت).
  final int downloadTotal;

  /// حجم کل آپلودشده در این اتصال (بایت).
  final int uploadTotal;

  final String rawState;

  bool get isConnected => rawState.toUpperCase() == 'CONNECTED';
}
