import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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

  VpnConnectionState get state => _state;
  VpnStatusSnapshot get lastStatus => _last;

  /// آیا این پلتفرم موتور واقعی دارد؟ (فقط اندروید)
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    _client = FlutterV2ray(
      onStatusChanged: (status) {
        final mapped = _mapState(status.state);
        final snap = VpnStatusSnapshot.fromV2Ray(status);
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
    final granted = await _client!.requestPermission();
    if (!granted) {
      _state = VpnConnectionState.disconnected;
      _emit();
      throw const VpnPermissionDenied();
    }
    final ok = await _tryConnectOne(
      remark: remark,
      link: link,
      timeout: perAttemptTimeout,
    );
    if (!ok) {
      try {
        await disconnect();
      } catch (_) {}
      throw VpnConnectException(
        'سرور $remark تا ${perAttemptTimeout.inSeconds} ثانیه وصل نشد.',
      );
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
    // اجازه VPN یک بار اول گرفته می‌شود؛ اگر داده نشد، تلاش روی سرورها بی‌فایده است.
    final granted = await _client!.requestPermission();
    if (!granted) {
      _state = VpnConnectionState.disconnected;
      _emit();
      throw const VpnPermissionDenied();
    }
    var tried = 0;
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      tried++;
      onAttempt?.call(c.remark, i + 1, candidates.length);
      bool ok = false;
      try {
        ok = await _tryConnectOne(
          remark: c.remark,
          link: c.link,
          timeout: timeout,
        );
      } catch (_) {
        // خطای پارس لینک یا استارت؛ سرور بعدی را امتحان کن.
        ok = false;
      }
      if (ok || _state == VpnConnectionState.connected) {
        // در لحظه آخر هم وصل شده بود، همان را قبول کن.
        return VpnConnectResult(
          connected: true,
          connectedRemark: c.remark,
          connectedLink: c.link,
          triedCount: tried,
        );
      }
      // این سرور وصل نشد؛ سرویس را کامل قطع کن تا تلاش بعدی تمیز شروع شود.
      try {
        await disconnect();
      } catch (_) {}
      // مکث کوتاه تا سرویس قبلی کامل جمع شود.
      await Future.delayed(const Duration(milliseconds: 800));
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
    );
  }

  /// یک تلاش اتصال به یک سرور.
  ///
  /// اگر تا پایان [timeout] وضعیت «متصل» نیامد، false برمی‌گرداند
  /// (بدون پرتاب خطا) تا تماس‌گیرنده سرور بعدی را امتحان کند.
  /// اگر اجازه VPN داده نشد یا لینک خراب بود، خطا پرتاب می‌کند چون
  /// این‌ها مشکل سرور نیستند و تلاش روی سرور بعدی فایده ندارد.
  /// (اجازه VPN معمولاً قبل از حلقه توسط connectWithFallback گرفته شده؛
  /// این متد برای سازگاری با connect تکی هم آن را می‌گیرد.)
  Future<bool> _tryConnectOne({
    required String remark,
    required String link,
    required Duration timeout,
  }) async {
    _connectStartedAt = DateTime.now();
    _state = VpnConnectionState.connecting;
    _emit();
    final parser = FlutterV2ray.parseFromURL(link);
    final config = parser.getFullConfiguration();
    _connectStartedAt = DateTime.now();
    final completer = Completer<bool>();
    _connectCompleter = completer;
    await _client!.startV2Ray(
      remark: remark,
      config: config,
      proxyOnly: false,
      notificationDisconnectButtonName: 'قطع اتصال',
    );
    try {
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      if (_connectCompleter == completer) _connectCompleter = null;
    }
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
  });

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
