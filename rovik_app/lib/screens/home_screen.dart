import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/app_api.dart';
import '../services/best_server.dart';
import '../services/ping_service.dart';
import '../services/sublink_parser.dart';
import '../services/subscription_store.dart';
import '../services/vpn_engine.dart';
import '../theme.dart';
import '../widgets/rovik_dialog.dart';
import 'buy_screen.dart';
import 'settings_screen.dart';
import 'tutorial_screen.dart';

/// صفحه اصلی اپ روویک — چیدمان زونیکس:
/// نوار بالا (لوگو + نام کاربری + آموزش/تنظیمات/خروج)، کارت بزرگ اتصال
/// با دکمه پاور و وضعیت و مدت اتصال و سرعت زنده، کارت بسته (حجم و
/// روزهای باقی‌مانده با نوار پیشرفت)، چیپ‌های اپراتور، لیست سرورها با
/// پینگ واقعی و انتخاب خودکار، و دکمه‌های خرید/تمدید و پشتیبانی.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.importRequests,
    required this.api,
    required this.store,
    required this.engine,
  });

  /// هر بار یک آدرس ساب‌لینک جدید در آن گذاشته شود، ایمپورت می‌شود.
  final ValueNotifier<String?> importRequests;
  final RovikApi api;
  final SubscriptionStore store;
  final VpnEngine engine;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  List<VpnConfig> _configs = [];
  int _selected = 0;
  SubInfo? _subInfo;
  bool _loadingSub = true;
  bool _refreshingPing = false;
  bool _importing = false;
  // true یعنی کاربر خودش دستی یک سرور را زده است؛ در این حالت انتخاب
  // خودکار سریع‌ترین سرور دیگر انتخاب او را عوض نمی‌کند.
  bool _manualSelection = false;
  // اپراتور انتخاب‌شده برای تست بهترین سرور؛ null یعنی همه سرورها.
  String? _activeOperator;
  bool _operatorTesting = false;
  String? _subUrl;
  VpnStatusSnapshot _vpnStatus = const VpnStatusSnapshot();
  VpnConnectionState _vpnState = VpnConnectionState.disconnected;
  // نام سروری که همین حالا دارد امتحان می‌شود (در حین اتصال چندسروره).
  String? _connectingTo;
  Timer? _durationTimer;
  String _elapsed = '۰۰:۰۰:۰۰';
  DateTime? _connectedSince;

  late final AnimationController _pulse;

  bool get _connected => _vpnState == VpnConnectionState.connected;
  bool get _busy =>
      _vpnState == VpnConnectionState.connecting ||
      _vpnState == VpnConnectionState.disconnecting;
  bool get _hasConfigs => _configs.isNotEmpty;

  VpnConfig? get _selectedConfig =>
      _hasConfigs && _selected < _configs.length ? _configs[_selected] : null;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    widget.importRequests.addListener(_onImportRequest);
    widget.engine.onStatus = _onEngineStatus;
    widget.engine.initialize().catchError((_) {});
    _loadLocal();
  }

  @override
  void dispose() {
    widget.importRequests.removeListener(_onImportRequest);
    _durationTimer?.cancel();
    _pulse.dispose();
    widget.engine.dispose();
    super.dispose();
  }

  void _onImportRequest() {
    final url = widget.importRequests.value;
    if (url != null && url.isNotEmpty) {
      widget.importRequests.value = null;
      _importSubscription(url);
    }
  }

  Future<void> _loadLocal() async {
    try {
      final configs = await widget.store.loadConfigs();
      final subUrl = await widget.store.loadSubUrl();
      final selected = await widget.store.loadSelectedIndex();
      final manual = await widget.store.loadManualSelection();
      if (!mounted) return;
      setState(() {
        _configs = configs;
        _subUrl = subUrl;
        _manualSelection = manual;
        _selected = configs.isEmpty
            ? 0
            : selected.clamp(0, configs.length - 1);
      });
    } catch (_) {
      // ذخیره‌سازی محلی در دسترس نیست؛ اپ با حالت خالی ادامه می‌دهد.
      if (!mounted) return;
      setState(() => _loadingSub = false);
      return;
    }
    await _refreshSubInfo();
    // بعد از لود، همه سرورها با پینگ واقعی تست می‌شوند و اگر کاربر
    // قبلاً دستی سروری را انتخاب نکرده باشد، سریع‌ترین سرور
    // به‌صورت خودکار انتخاب می‌شود.
    if (_configs.isNotEmpty) {
      await _refreshPings(autoSelect: !_manualSelection);
    }
  }

  Future<void> _refreshSubInfo() async {
    setState(() => _loadingSub = true);
    SubInfo? info;
    final subUrl = _subUrl;
    if (subUrl != null) {
      final token = SublinkParser.extractToken(subUrl);
      if (token != null) info = await widget.api.fetchSubInfo(token);
    }
    if (!mounted) return;
    setState(() {
      _subInfo = info;
      _loadingSub = false;
    });
    if (info != null && info.username.isNotEmpty) {
      await widget.store.saveUsername(info.username);
    }
  }

  /// همه سرورها را با پینگ واقعی TCP تست می‌کند.
  ///
  /// اگر [autoSelect] درست باشد و کاربر دستی سروری را انتخاب نکرده
  /// باشد، بعد از تست، سریع‌ترین سرور (کمترین پینگ) به‌صورت خودکار
  /// انتخاب می‌شود. اگر [announce] درست باشد، انتخاب خودکار با پیام
  /// به کاربر گفته می‌شود.
  Future<void> _refreshPings({
    bool autoSelect = false,
    bool announce = false,
  }) async {
    if (_configs.isEmpty || _refreshingPing) return;
    setState(() => _refreshingPing = true);
    for (var i = 0; i < _configs.length; i++) {
      final ms = await PingService.tcpPing(_configs[i].host, _configs[i].port);
      if (!mounted) return;
      setState(() => _configs[i].pingMs = ms);
    }
    await widget.store.saveConfigs(_configs);
    if (!mounted) return;
    setState(() => _refreshingPing = false);
    if (autoSelect && !_manualSelection) _autoSelectFastest(announce: announce);
  }

  /// سریع‌ترین سرور (کمترین پینگ) را انتخاب می‌کند.
  ///
  /// اگر هیچ پینگی ثبت نشده باشد، انتخاب عوض نمی‌شود.
  /// برمی‌گرداند آیا انتخاب عوض شد.
  bool _autoSelectFastest({bool announce = false}) {
    final bestIdx = BestServer.fastestIndex(_configs);
    if (bestIdx == null) return false;
    final changed = bestIdx != _selected;
    setState(() => _selected = bestIdx);
    widget.store.saveSelectedIndex(bestIdx);
    if (announce && changed) {
      _snack('سریع‌ترین سرور انتخاب شد: ${_configs[bestIdx].name}');
    }
    return changed;
  }

  /// ایمپورت اشتراک از ساب‌لینک (دیپ‌لینک یا فایل روویک).
  Future<void> _importSubscription(String subUrl) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final body = await widget.api.fetchSublink(subUrl);
      final configs = SublinkParser.parseBody(body);
      if (configs.isEmpty) {
        _showRovikDialog(
          title: 'کانفیگی پیدا نشد',
          message:
              'در این اشتراک کانفیگی پیدا نشد. اگر اشتراکت تازه‌ست، از ربات یک ساب‌لینک تازه بگیر و دوباره بزن.',
          kind: RovikDialogKind.error,
        );
        return;
      }
      await widget.store.saveSubUrl(subUrl);
      await widget.store.saveConfigs(configs);
      await widget.store.saveSelectedIndex(0);
      // ایمپورت تازه یعنی انتخاب خودکار از اول شروع می‌شود.
      await widget.store.saveManualSelection(false);
      if (!mounted) return;
      setState(() {
        _configs = configs;
        _subUrl = subUrl;
        _selected = 0;
        _manualSelection = false;
        _activeOperator = null;
      });
      _showRovikDialog(
        title: 'اشتراک وارد شد',
        message: '${FaFormat.number(configs.length)} کانفیگ وارد شد.',
        kind: RovikDialogKind.success,
      );
      await _refreshSubInfo();
      await _refreshPings(autoSelect: true, announce: true);
    } catch (e) {
      _showRovikDialog(
        title: 'ایمپورت ممکن نشد',
        message: friendlyImportError(e),
        kind: RovikDialogKind.error,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _onEngineStatus(VpnStatusSnapshot snap) {
    if (!mounted) return;
    setState(() {
      _vpnStatus = snap;
      _vpnState = widget.engine.state;
      if (_vpnState == VpnConnectionState.connected) {
        _connectingTo = null;
      }
      if (_vpnState == VpnConnectionState.connected &&
          _connectedSince == null) {
        _connectedSince = DateTime.now();
        _startElapsedTimer();
      } else if (_vpnState == VpnConnectionState.disconnected) {
        _connectingTo = null;
        _connectedSince = null;
        _durationTimer?.cancel();
        _elapsed = '۰۰:۰۰:۰۰';
      }
    });
  }

  void _startElapsedTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedSince == null) return;
      final d = DateTime.now().difference(_connectedSince!);
      final h = d.inHours.toString().padLeft(2, '0');
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _elapsed = FaFormat.digits('$h:$m:$s'));
    });
  }

  Future<void> _toggleConnect() async {
    if (!_hasConfigs) {
      _goBuy();
      return;
    }
    final cfg = _selectedConfig!;
    if (_connected) {
      setState(() => _vpnState = VpnConnectionState.disconnecting);
      try {
        await widget.engine.disconnect();
      } catch (_) {
        _showRovikDialog(
          title: 'قطع اتصال ممکن نشد',
          message: 'قطع اتصال ممکن نشد. دوباره بزن.',
          kind: RovikDialogKind.error,
        );
      }
      _onEngineStatus(const VpnStatusSnapshot());
      return;
    }
    if (!VpnEngine.isSupported) {
      _showRovikDialog(
        title: 'فقط اندروید',
        message: 'اتصال VPN فقط روی گوشی اندرویدی ممکن است.',
        kind: RovikDialogKind.info,
      );
      return;
    }
    setState(() => _vpnState = VpnConnectionState.connecting);
    try {
      // اول سرور انتخاب‌شده، بعد بقیه سرورها به‌ترتیب پینگ (سریع‌ترین اول).
      // اگر سروری وصل نشد، موتور خودش سراغ بعدی می‌رود؛ مثل بقیه اپ‌های
      // کانفیگ که در یک ثانیه روی یک سرور سالم وصل می‌شوند.
      final ordered = <VpnConfig>[];
      ordered.add(cfg);
      final rest = BestServer.ranked(_configs)
          .where((c) => c.link != cfg.link)
          .toList();
      ordered.addAll(rest);
      final result = await widget.engine.connectWithFallback(
        candidates: [
          for (final c in ordered) (remark: c.name, link: c.link),
        ],
        onAttempt: (remark, attempt, total) {
          if (mounted) {
            setState(() => _connectingTo = remark);
          }
        },
      );
      if (mounted) setState(() => _connectingTo = null);
      if (!result.connected) {
        // هیچ‌کدام از سرورها وصل نشد؛ دلیل را واضح بگو.
        if (mounted) setState(() => _vpnState = VpnConnectionState.disconnected);
        _showRovikDialog(
          title: 'هیچ سروری وصل نشد',
          message:
              '${FaFormat.number(result.triedCount)} سرور امتحان شد و هیچ‌کدام وصل نشد. اینترنتت رو چک کن و اگر باز نشد، یک سرور دیگه رو دستی انتخاب کن.',
          kind: RovikDialogKind.error,
        );
        return;
      }
      // اگر سرور دیگری (نه انتخاب‌شده) وصل شد، انتخاب را به همان عوض کن.
      if (mounted && result.connectedLink != null) {
        final idx = _configs.indexWhere((c) => c.link == result.connectedLink);
        if (idx >= 0 && idx != _selected) {
          setState(() {
            _selected = idx;
            _manualSelection = true;
          });
          widget.store.saveSelectedIndex(idx);
          widget.store.saveManualSelection(true);
        }
      }
      // وضعیت نهایی (متصل) را خود موتور از طریق onStatus اعلام می‌کند؛
      // اینجا وضعیت قدیمی را دوباره نمی‌فرستیم تا اتصال تازه قطع‌شده
      // دیده نشود.
      if (mounted) setState(() => _vpnState = widget.engine.state);
    } catch (e) {
      if (mounted) {
        setState(() {
          _vpnState = VpnConnectionState.disconnected;
          _connectingTo = null;
        });
      }
      _showRovikDialog(
        title: 'اتصال ممکن نشد',
        message: e is VpnPermissionDenied
            ? 'اجازه VPN داده نشد. از تنظیمات گوشی اجازه VPN را بده و دوباره بزن.'
            : e is VpnConnectException
                ? e.message
                : 'اتصال ممکن نشد. اینترنتت رو چک کن و یک سرور دیگه رو امتحان کن.',
        kind: RovikDialogKind.error,
      );
    }
  }

  void _selectBest() {
    if (_configs.isEmpty) return;
    final bestIdx = BestServer.fastestIndex(_configs);
    if (bestIdx == null) {
      _snack('اول پینگ سرورها را تازه‌سازی کن.');
      return;
    }
    setState(() => _selected = bestIdx);
    widget.store.saveSelectedIndex(bestIdx);
    _snack('بهترین سرور انتخاب شد: ${_configs[bestIdx].name}');
  }

  /// تست بهترین سرور برای یک اپراتور.
  ///
  /// کاربر روی اپراتور خودش (همراه اول / ایرانسل / رایتل) می‌زند؛ اپ
  /// همه سرورها را با اینترنت همین لحظه کاربر (روی همان اپراتور) با
  /// پینگ واقعی TCP دوباره تست می‌کند، سریع‌ترین را انتخاب می‌کند و
  /// سه تای برتر را جداگانه نشان می‌دهد. زدن دوباره همان اپراتور،
  /// فیلتر را برمی‌دارد.
  Future<void> _testForOperator(String name) async {
    if (_configs.isEmpty) {
      _snack('اول اشتراک وارد کن.');
      return;
    }
    if (_operatorTesting || _refreshingPing) return;
    if (_activeOperator == name) {
      setState(() => _activeOperator = null);
      return;
    }
    setState(() {
      _activeOperator = name;
      _operatorTesting = true;
    });
    await _refreshPings(autoSelect: true);
    if (!mounted) return;
    setState(() => _operatorTesting = false);
    _snack('بهترین سرور برای $name انتخاب شد.');
  }

  void _goBuy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BuyScreen(
          api: widget.api,
          hasService: _subInfo?.active == true,
        ),
      ),
    );
  }

  void _goSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          onLogout: _logout,
        ),
      ),
    );
  }

  void _goTutorial() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TutorialScreen()),
    );
  }

  Future<void> _logout() async {
    if (_connected) {
      try {
        await widget.engine.disconnect();
      } catch (_) {}
    }
    await widget.store.clearAll();
    if (!mounted) return;
    setState(() {
      _configs = [];
      _selected = 0;
      _manualSelection = false;
      _activeOperator = null;
      _operatorTesting = false;
      _subInfo = null;
      _subUrl = null;
      _vpnStatus = const VpnStatusSnapshot();
      _vpnState = VpnConnectionState.disconnected;
    });
    _snack('خارج شدی؛ اشتراک از اپ پاک شد.');
  }

  Future<void> _openSupport() async {
    final uri = Uri.parse(RovikConfig.supportUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showRovikDialog(
        title: 'باز نشد',
        message: 'باز کردن تلگرام ممکن نشد.',
        kind: RovikDialogKind.error,
      );
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// دیالوگ وسط‌صفحه شیک روویک — برای خطاها و نتیجه ایمپورت.
  /// پیام‌های کوچک (مثل «متصل شدی» یا «کپی شد») همچنان اسنک‌بار می‌مانند.
  void _showRovikDialog({
    required String title,
    required String message,
    required RovikDialogKind kind,
  }) {
    if (!mounted) return;
    showRovikDialog(context, title: title, message: message, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: RovikTheme.pageGradient),
      child: Stack(
        children: [
          // درخشش محیطی بالای صفحه: متصل سبز، قطع آبی آرام.
          Positioned(
            top: -140,
            left: -60,
            right: -60,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                height: 380,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      (_connected ? RovikTheme.mint : RovikTheme.neonBlue)
                          .withValues(alpha: _connected ? 0.20 : 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -160,
            left: -80,
            right: -80,
            child: IgnorePointer(
              child: Container(
                height: 340,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      RovikTheme.neonCyan.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: RefreshIndicator(
            color: RovikTheme.neonCyan,
            backgroundColor: RovikTheme.bgCardLight,
            onRefresh: () async {
              await _refreshSubInfo();
              await _refreshPings();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FadeIn(index: 0, child: _topBar()),
                  const SizedBox(height: 24),
                  _FadeIn(index: 1, child: _connectionCard()),
                  const SizedBox(height: 16),
                  _FadeIn(index: 2, child: _packageCard()),
                  const SizedBox(height: 24),
                  _FadeIn(index: 3, child: _operatorSection()),
                  const SizedBox(height: 24),
                  _FadeIn(
                    index: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _serversHeader(),
                        const SizedBox(height: 8),
                        if (_hasConfigs) ...[
                          _autoSelectRow(),
                          const SizedBox(height: 8),
                        ],
                        _serversList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _FadeIn(index: 5, child: _bottomButtons()),
                  const SizedBox(height: 16),
                  const Text(
                    'سایت‌ها و اپ‌های ایرانی بدون فیلترشکن باز می‌شوند.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: RovikTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [RovikTheme.neonBlue, RovikTheme.neonCyan],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: RovikTheme.neonCyan.withValues(alpha: 0.55),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            'R',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rovik',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.3,
                  fontWeight: FontWeight.w900,
                  color: RovikTheme.textMain,
                ),
              ),
              Text(
                _subInfo?.username.isNotEmpty == true
                    ? _subInfo!.username
                    : (_hasConfigs ? 'کاربر روویک' : 'مهمان'),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: RovikTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        _topIconButton(
          icon: Icons.school_rounded,
          tooltip: 'آموزش اتصال',
          onPressed: _goTutorial,
        ),
        const SizedBox(width: 8),
        _topIconButton(
          icon: Icons.settings_rounded,
          tooltip: 'تنظیمات',
          onPressed: _goSettings,
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded,
              size: 20, color: RovikTheme.textMuted),
          label: const Text(
            'خروج',
            style: TextStyle(fontSize: 13, color: RovikTheme.textMuted),
          ),
        ),
      ],
    );
  }

  /// دکمه دایره‌ای ظریف نوار بالا (همه آیکون‌ها هم‌اندازه و هم‌وزن).
  Widget _topIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: _Pressable(
        onTap: onPressed,
        scale: 0.9,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: RovikTheme.bgCard,
            shape: BoxShape.circle,
            border: Border.all(color: RovikTheme.hairline),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: RovikTheme.textMain),
        ),
      ),
    );
  }

  /// کارت بزرگ اتصال: دکمه پاور یک طرف، وضعیت و مدت اتصال طرف دیگر
  /// و پایین کارت سرعت زنده. متصل: درخشش سبز ملایم؛ قطع: آبی-خاکستری آرام.
  Widget _connectionCard() {
    final cfg = _selectedConfig;
    final statusText = _connected
        ? 'متصل به ${cfg?.flag ?? ''} ${cfg?.name ?? ''}'
        : _vpnState == VpnConnectionState.connecting
            ? (_connectingTo != null
                ? 'در حال اتصال به $_connectingTo…'
                : 'در حال اتصال…')
            : _vpnState == VpnConnectionState.disconnecting
                ? 'در حال قطع…'
                : 'قطع';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(24),
      decoration: RovikTheme.neonCard(
        color: RovikTheme.neonBlue,
        glow: _connected ? 0.34 : 0.20,
        border: _connected ? 0.85 : 0.55,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _connected
                                ? RovikTheme.mint
                                : RovikTheme.slate,
                            shape: BoxShape.circle,
                            boxShadow: _connected
                                ? [
                                    BoxShadow(
                                      color: RovikTheme.mint
                                          .withValues(alpha: 0.7),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              statusText,
                              key: ValueKey(statusText),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                height: 1.4,
                                fontWeight: FontWeight.w800,
                                color: RovikTheme.textMain,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _connected
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'مدت اتصال',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: RovikTheme.textMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _elapsed,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: RovikTheme.textMain,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 40,
                                  child: ElevatedButton(
                                    onPressed: _busy ? null : _toggleConnect,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: RovikTheme.neonBlue,
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: RovikTheme.neonCyan
                                            .withValues(alpha: 0.6),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                    ),
                                    child: const Text('قطع اتصال'),
                                  ),
                                ),
                              ],
                            )
                          : Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _hasConfigs
                                    ? 'برای اتصال، دکمه را بزن'
                                    : 'هنوز کانفیگی نداری',
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                  color: RovikTheme.textMuted,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _powerButton(),
            ],
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _speedCell(
                  'دانلود',
                  Icons.arrow_downward_rounded,
                  _vpnStatus.downloadSpeed,
                  _vpnStatus.downloadTotal,
                  RovikTheme.neonCyan,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: _speedCell(
                  'آپلود',
                  Icons.arrow_upward_rounded,
                  _vpnStatus.uploadSpeed,
                  _vpnStatus.uploadTotal,
                  RovikTheme.mint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// دکمه پاور با حلقه‌های موج‌دار. متصل: حلقه و درخشش سبز نبض‌دار؛
  /// قطع: آبی-خاکستری آرام. فشردن: کوچک‌شدن نرم.
  Widget _powerButton() {
    final accent = _connected ? RovikTheme.mint : RovikTheme.neonBlue;
    return _Pressable(
      enabled: !_busy,
      scale: 0.93,
      onTap: _busy ? null : _toggleConnect,
      child: SizedBox(
        width: 132,
        height: 132,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = _connected ? _pulse.value : 0.0;
            final glow = _connected ? 0.30 + 0.25 * t : 0.12;
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (final entry in const [(132.0, 0.0), (114.0, 0.5)])
                  Container(
                    width: entry.$1 + (_connected ? 4 * t : 0),
                    height: entry.$1 + (_connected ? 4 * t : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _connected
                            ? RovikTheme.mint.withValues(
                                alpha: 0.22 + 0.25 * (1 - t) - entry.$2 * 0.08,
                              )
                            : RovikTheme.neonBlue.withValues(
                                alpha: 0.22 - entry.$2 * 0.08,
                              ),
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _connected
                          ? RovikTheme.mint
                          : RovikTheme.neonCyan.withValues(alpha: 0.9),
                      width: 3,
                    ),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1F5BFF), Color(0xFF0A2A9E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: glow + 0.25),
                        blurRadius: 34,
                        spreadRadius: 3,
                      ),
                      BoxShadow(
                        color: RovikTheme.neonBlue.withValues(alpha: 0.35),
                        blurRadius: 60,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _busy
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.power_settings_new_rounded,
                            key: ValueKey('power'),
                            size: 48,
                            color: Colors.white,
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _speedCell(
    String label,
    IconData icon,
    int speed,
    int total,
    Color color,
  ) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: RovikTheme.textMuted,
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 16, color: color),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          FaFormat.speed(speed),
          style: TextStyle(
            fontSize: 18,
            height: 1.3,
            fontWeight: FontWeight.w900,
            color: RovikTheme.textMain,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.8), blurRadius: 12),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'مجموع ${FaFormat.bytes(total)}',
          style: const TextStyle(fontSize: 11, color: RovikTheme.textMuted),
        ),
      ],
    );
  }

  /// کارت بسته: نام بسته و برچسب وضعیت، نوار پیشرفت و دو عدد بزرگ.
  Widget _packageCard() {
    final info = _subInfo;
    return Container(
      decoration: RovikTheme.neonCard(glow: 0.14, border: 0.45, radius: 28),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: RovikTheme.gold,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'بسته من',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: RovikTheme.textMain,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (info?.active == true)
                        ? RovikTheme.mint.withValues(alpha: 0.16)
                        : RovikTheme.textMuted.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (info?.active == true)
                          ? RovikTheme.mint.withValues(alpha: 0.35)
                          : RovikTheme.hairline,
                    ),
                  ),
                  child: Text(
                    info == null
                        ? 'نامشخص'
                        : info.active
                            ? 'بسته فعال'
                            : 'بسته غیرفعال',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: info?.active == true
                          ? RovikTheme.mint
                          : RovikTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadingSub)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              )
            else if (info == null)
              const Text(
                'پس از ایمپورت اشتراک، اطلاعات بسته اینجا می‌آید.',
                style: TextStyle(
                  height: 1.7,
                  color: RovikTheme.textMuted,
                ),
              )
            else ...[
              _remainingBar(1 - info.usedFraction),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _bigStat(
                      'حجم باقی‌مانده',
                      FaFormat.gb(info.remainingGb),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 48,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  Expanded(
                    child: _bigStat(
                      'زمان باقی‌مانده',
                      info.daysLeft <= 0
                          ? '—'
                          : '${FaFormat.number(info.daysLeft)} روز',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// نوار پیشرفت گرادیانی؛ از راست پر می‌شود، نرم انیمیت می‌شود و
  /// با کم‌شدن حجم طلایی و بعد قرمز می‌شود.
  Widget _remainingBar(double remainingFraction) {
    final f = remainingFraction.clamp(0.0, 1.0);
    final colors = f < 0.1
        ? const [RovikTheme.coral, Color(0xFFFF8F6B)]
        : f < 0.25
            ? const [RovikTheme.gold, Color(0xFFFFAA4D)]
            : const [RovikTheme.neonBlue, RovikTheme.neonCyan];
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 12,
        color: RovikTheme.textMuted.withValues(alpha: 0.18),
        alignment: Alignment.centerRight,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: f),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => FractionallySizedBox(
            alignment: Alignment.centerRight,
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: colors.last.withValues(alpha: 0.7),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bigStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            height: 1.3,
            fontWeight: FontWeight.w900,
            color: RovikTheme.textMain,
            shadows: [Shadow(color: RovikTheme.neonBlue, blurRadius: 14)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: RovikTheme.textMuted),
        ),
      ],
    );
  }

  /// بخش «بهترین سرور برای اپراتور من» با سه چیپ همراه اول، ایرانسل، رایتل.
  Widget _operatorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(
              Icons.signal_cellular_alt_rounded,
              size: 20,
              color: RovikTheme.neonCyan,
            ),
            SizedBox(width: 8),
            Text(
              'بهترین سرور برای اپراتور من',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: RovikTheme.textMain,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'اپراتورت را بزن؛ بهترین سرور برای آن تست می‌شود.',
          style: TextStyle(fontSize: 12, color: RovikTheme.textMuted),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final op in _operatorOptions)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: op == _operatorOptions.last ? 0 : 8,
                  ),
                  child: _operatorChip(op),
                ),
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _activeOperator != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _operatorResultCard(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// چیپ اپراتور: نقطه رنگ برند + نام؛ فعال با گرادیان برند.
  Widget _operatorChip(_OperatorOption op) {
    final active = _activeOperator == op.name;
    final busy = _operatorTesting && active;
    final blocked = (_operatorTesting || _refreshingPing) && !active;
    return _Pressable(
      enabled: !blocked,
      onTap: blocked ? null : () => _testForOperator(op.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 56,
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [op.color, op.color2],
                )
              : null,
          color: active ? null : RovikTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? Colors.transparent
                : op.color.withValues(alpha: blocked ? 0.2 : 0.5),
            width: 1.2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: op.color.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                active ? Icons.check_rounded : op.icon,
                size: 20,
                color: active ? op.onColor : op.color,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                op.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: active ? op.onColor : RovikTheme.textMain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// سه سرور برتر برای اپراتور انتخاب‌شده؛ زدن روی ردیف، آن را دستی
  /// انتخاب می‌کند.
  Widget _operatorResultCard() {
    final op = _operatorOptions.firstWhere(
      (o) => o.name == _activeOperator,
      orElse: () => _operatorOptions.first,
    );
    final ranked = BestServer.ranked(_configs)
        .where((c) => c.pingMs != null)
        .take(3)
        .toList();
    return Card(
      color: RovikTheme.bgCardLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_rounded, size: 20, color: op.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'بهترین سرورها برای ${op.name}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: RovikTheme.textMain,
                    ),
                  ),
                ),
                if (_operatorTesting)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (ranked.isEmpty)
              Text(
                _operatorTesting ? 'در حال تست پینگ…' : 'پینگی ثبت نشده است.',
                style: const TextStyle(color: RovikTheme.textMuted),
              )
            else
              for (var i = 0; i < ranked.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == ranked.length - 1 ? 0 : 8,
                  ),
                  child: _operatorResultRow(ranked[i], i, op.color),
                ),
          ],
        ),
      ),
    );
  }

  Widget _operatorResultRow(VpnConfig cfg, int rank, Color accent) {
    final selected = _configs.indexOf(cfg) == _selected;
    const medals = ['🥇', '🥈', '🥉'];
    return _Pressable(
      scale: 0.98,
      onTap: () {
        final idx = _configs.indexOf(cfg);
        if (idx < 0) return;
        setState(() {
          _selected = idx;
          _manualSelection = true;
        });
        widget.store.saveSelectedIndex(idx);
        widget.store.saveManualSelection(true);
        _snack('انتخاب شد: ${cfg.name}');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.15)
              : RovikTheme.bgDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Text(medals[rank], style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(cfg.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cfg.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: RovikTheme.textMain,
                ),
              ),
            ),
            if (selected) ...[
              Icon(Icons.check_circle_rounded, size: 20, color: accent),
              const SizedBox(width: 8),
            ],
            _pingPill(cfg.pingMs),
          ],
        ),
      ),
    );
  }

  Widget _serversHeader() {
    return Row(
      children: [
        const Icon(Icons.dns_rounded, size: 20, color: RovikTheme.neonCyan),
        const SizedBox(width: 8),
        Text(
          'سرورها (${FaFormat.number(_configs.length)})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: RovikTheme.textMain,
          ),
        ),
        const Spacer(),
        Tooltip(
          message: 'تازه‌سازی پینگ',
          child: _Pressable(
            enabled: !_refreshingPing,
            scale: 0.9,
            onTap: _refreshingPing ? null : _refreshPings,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: RovikTheme.bgCard,
                shape: BoxShape.circle,
                border: Border.all(color: RovikTheme.hairline),
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _refreshingPing
                    ? const SizedBox(
                        key: ValueKey('spin'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                        key: ValueKey('refresh'),
                        size: 20,
                        color: RovikTheme.textMain,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// ردیف «انتخاب خودکار» بالای لیست سرورها.
  Widget _autoSelectRow() {
    return _Pressable(
      scale: 0.98,
      onTap: _selectBest,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: RovikTheme.neonCard(
          color: RovikTheme.gold,
          radius: 20,
          glow: 0.10,
          border: 0.35,
          fill: const [Color(0xFF0C1A3C), Color(0xFF081330)],
        ),
        child: const Row(
          children: [
            Icon(
              Icons.bolt_rounded,
              color: RovikTheme.gold,
              size: 20,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'انتخاب خودکار',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: RovikTheme.textMain,
                ),
              ),
            ),
            Text(
              'بهترین سرور',
              style: TextStyle(fontSize: 12, color: RovikTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serversList() {
    if (_importing) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!_hasConfigs) {
      return Card(
        child: InkWell(
          onTap: _goBuy,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: RovikTheme.neonBlue.withValues(alpha: 0.12),
                    border: Border.all(
                      color: RovikTheme.neonBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    size: 32,
                    color: RovikTheme.neonCyan,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'هنوز سروری نداری',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: RovikTheme.textMain,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'از ربات روویک اشتراک بخر و دکمه سبز «متصل به برنامه» را بزن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.8,
                    fontSize: 13,
                    color: RovikTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _configs.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == _configs.length - 1 ? 0 : 8),
            child: _serverRow(_configs[i], i),
          ),
      ],
    );
  }

  /// ردیف سرور: رادیو، پرچم، نام و پروتکل، و پینگ. ردیف انتخاب‌شده
  /// حاشیه و درخشش آبی دارد.
  Widget _serverRow(VpnConfig cfg, int index) {
    final selected = index == _selected;
    return _Pressable(
      scale: 0.98,
      onTap: () {
        // انتخاب دستی کاربر؛ از اینجا به بعد انتخاب خودکار
        // سریع‌ترین سرور، انتخاب او را عوض نمی‌کند.
        setState(() {
          _selected = index;
          _manualSelection = true;
        });
        widget.store.saveSelectedIndex(index);
        widget.store.saveManualSelection(true);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: selected
            ? RovikTheme.neonCard(
                radius: 20,
                glow: 0.32,
                border: 0.95,
                fill: const [Color(0xFF0F2A66), Color(0xFF081634)],
              )
            : RovikTheme.neonCard(
                radius: 20,
                glow: 0.0,
                border: 0.18,
                fill: const [Color(0xFF0B1838), Color(0xFF071029)],
              ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                key: ValueKey(selected),
                color: selected ? RovikTheme.neonBlue : RovikTheme.textMuted,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Text(cfg.flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cfg.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w800,
                      color: RovikTheme.textMain,
                    ),
                  ),
                  Text(
                    cfg.protocol.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      color: RovikTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _pingPill(cfg.pingMs),
          ],
        ),
      ),
    );
  }

  /// برچسب پینگ با نقطه رنگی؛ سبز < ۱۵۰، طلایی < ۳۰۰، قرمز بالاتر.
  Widget _pingPill(int? pingMs) {
    final color = RovikTheme.pingColor(pingMs);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            PingService.formatPing(pingMs),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// دکمه‌های پایین: خرید/تمدید آبی و پشتیبانی تیره.
  Widget _bottomButtons() {
    return Row(
      children: [
        Expanded(
          child: _Pressable(
            scale: 0.97,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: RovikTheme.neonBlue.withValues(alpha: 0.65),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _goBuy,
                  icon: const Icon(Icons.shopping_cart_rounded, size: 20),
                  label: Text(
                    _subInfo?.active == true ? 'تمدید' : 'خرید / تمدید',
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _Pressable(
            scale: 0.97,
            child: SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _openSupport,
                icon: const Icon(Icons.headset_mic_rounded, size: 20),
                label: const Text('پشتیبانی'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: RovikTheme.bgCard,
                  foregroundColor: RovikTheme.textMain,
                  side: BorderSide(
                    color: RovikTheme.neonBlue.withValues(alpha: 0.6),
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// بازخورد فشردن: کوچک‌شدن نرم و سریع (بدون دخالت در ژست‌های داخلی).
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool enabled;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final inner = Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && widget.enabled ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
    if (widget.onTap == null) return inner;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: inner,
    );
  }
}

/// ورود نرم بخش‌ها: محو شدن + کمی بالا آمدن، با تأخیر پلکانی.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: c),
      ),
      child: child,
    );
  }
}

/// یک اپراتور موبایل با استایل اختصاصی خودش.
///
/// هر اپراتور رنگ برند خودش را دارد تا در یک نگاه از هم جدا شوند:
/// همراه اول آبی، ایرانسل زرد، رایتل بنفش.
class _OperatorOption {
  const _OperatorOption({
    required this.name,
    required this.color,
    required this.color2,
    required this.onColor,
    required this.icon,
  });

  final String name;

  /// رنگ اصلی برند.
  final Color color;

  /// رنگ دوم گرادیان دکمه فعال.
  final Color color2;

  /// رنگ متن/آیکون روی دکمه فعال.
  final Color onColor;
  final IconData icon;
}

const _operatorOptions = [
  _OperatorOption(
    name: 'همراه اول',
    color: Color(0xFF1E88E5),
    color2: Color(0xFF00BCD4),
    onColor: Colors.white,
    icon: Icons.signal_cellular_alt_rounded,
  ),
  _OperatorOption(
    name: 'ایرانسل',
    color: Color(0xFFFFC107),
    color2: Color(0xFFFF8F00),
    onColor: Color(0xFF212121),
    icon: Icons.sim_card_rounded,
  ),
  _OperatorOption(
    name: 'رایتل',
    color: Color(0xFF7C3AED),
    color2: Color(0xFFAB47BC),
    onColor: Colors.white,
    icon: Icons.network_cell_rounded,
  ),
];

/// کپی کردن متن در کلیپ‌بورد با پیام تأیید.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کپی شد.')),
    );
  }
}
