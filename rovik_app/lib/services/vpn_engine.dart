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
  /// واقعاً برقرار نشده یا مهلت تمام نشده، آن را قطع‌شدن حساب نمی‌کنیم.
  DateTime? _connectStartedAt;
  Timer? _connectWatchdog;
  static const Duration _connectGrace = Duration(seconds: 20);

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
          _connectWatchdog?.cancel();
          _connectStartedAt = null;
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
    _connectStartedAt = DateTime.now();
    _state = VpnConnectionState.connecting;
    _emit();
    final parser = FlutterV2ray.parseFromURL(link);
    final config = parser.getFullConfiguration();
    final granted = await _client!.requestPermission();
    if (!granted) {
      _connectStartedAt = null;
      _state = VpnConnectionState.disconnected;
      _emit();
      throw Exception('اجازه VPN داده نشد.');
    }
    _connectStartedAt = DateTime.now();
    await _client!.startV2Ray(
      remark: remark,
      config: config,
      proxyOnly: false,
      notificationDisconnectButtonName: 'قطع اتصال',
    );
    // اگر تا پایان مهلت وضعیت «متصل» نیامد، به حالت قطع برمی‌گردیم.
    _connectWatchdog?.cancel();
    _connectWatchdog = Timer(_connectGrace, () {
      if (_state == VpnConnectionState.connecting) {
        _connectStartedAt = null;
        _state = VpnConnectionState.disconnected;
        _emit();
      }
    });
  }

  bool get _inConnectGrace =>
      _connectStartedAt != null &&
      DateTime.now().difference(_connectStartedAt!) < _connectGrace;

  Future<void> disconnect() async {
    if (!isSupported || _client == null) {
      _state = VpnConnectionState.disconnected;
      return;
    }
    _connectWatchdog?.cancel();
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
    _connectWatchdog?.cancel();
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
