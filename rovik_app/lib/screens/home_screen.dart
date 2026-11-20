import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/app_api.dart';
import '../services/ping_service.dart';
import '../services/sublink_parser.dart';
import '../services/subscription_store.dart';
import '../services/vpn_engine.dart';
import '../theme.dart';
import 'buy_screen.dart';
import 'settings_screen.dart';
import 'tutorial_screen.dart';

/// صفحه اصلی اپ روویک — چیدمان زونیکس:
/// نوار بالا (لوگو + نام کاربری + خروج)، کارت بزرگ اتصال با دکمه پاور،
/// سرعت زنده و حجم کل، کارت بسته (حجم و روزهای باقی‌مانده)،
/// لیست سرورها با پینگ واقعی و دکمه‌های پشتیبانی و خرید/تمدید.
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
  String? _subUrl;
  VpnStatusSnapshot _vpnStatus = const VpnStatusSnapshot();
  VpnConnectionState _vpnState = VpnConnectionState.disconnected;
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
      if (!mounted) return;
      setState(() {
        _configs = configs;
        _subUrl = subUrl;
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
    if (_configs.isNotEmpty) _refreshPings();
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

  Future<void> _refreshPings() async {
    if (_configs.isEmpty || _refreshingPing) return;
    setState(() => _refreshingPing = true);
    for (var i = 0; i < _configs.length; i++) {
      final ms = await PingService.tcpPing(_configs[i].host, _configs[i].port);
      if (!mounted) return;
      setState(() => _configs[i].pingMs = ms);
    }
    await widget.store.saveConfigs(_configs);
    if (mounted) setState(() => _refreshingPing = false);
  }

  /// ایمپورت اشتراک از ساب‌لینک (دیپ‌لینک یا فایل روویک).
  Future<void> _importSubscription(String subUrl) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final body = await widget.api.fetchSublink(subUrl);
      final configs = SublinkParser.parseBody(body);
      if (configs.isEmpty) {
        _snack('در این اشتراک کانفیگی پیدا نشد.');
        return;
      }
      await widget.store.saveSubUrl(subUrl);
      await widget.store.saveConfigs(configs);
      await widget.store.saveSelectedIndex(0);
      if (!mounted) return;
      setState(() {
        _configs = configs;
        _subUrl = subUrl;
        _selected = 0;
      });
      _snack('${configs.length} کانفیگ وارد شد.');
      await _refreshSubInfo();
      await _refreshPings();
    } catch (e) {
      _snack('ایمپورت ممکن نشد: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _onEngineStatus(VpnStatusSnapshot snap) {
    if (!mounted) return;
    setState(() {
      _vpnStatus = snap;
      _vpnState = widget.engine.state;
      if (snap.isConnected && _connectedSince == null) {
        _connectedSince = DateTime.now();
        _startElapsedTimer();
      } else if (!snap.isConnected) {
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
      } catch (e) {
        _snack('قطع اتصال ممکن نشد: $e');
      }
      _onEngineStatus(const VpnStatusSnapshot());
      return;
    }
    if (!VpnEngine.isSupported) {
      _snack('اتصال VPN فقط روی گوشی اندرویدی ممکن است.');
      return;
    }
    setState(() => _vpnState = VpnConnectionState.connecting);
    try {
      // اتصال مستقیم به کانفیگ انتخاب‌شده؛ بدون جست‌وجو و تست سرعت.
      await widget.engine.connect(remark: cfg.name, link: cfg.link);
      _onEngineStatus(widget.engine.lastStatus);
      _snack('متصل شدی — ${cfg.name}');
    } catch (e) {
      setState(() => _vpnState = VpnConnectionState.disconnected);
      _snack('اتصال ممکن نشد: $e');
    }
  }

  void _selectBest() {
    final withPing =
        _configs.where((c) => c.pingMs != null).toList()
          ..sort((a, b) => a.pingMs!.compareTo(b.pingMs!));
    if (withPing.isEmpty) {
      _snack('اول دکمه تازه‌سازی را بزن تا پینگ سرورها تست شود.');
      return;
    }
    final best = withPing.first;
    final idx = _configs.indexOf(best);
    setState(() => _selected = idx);
    widget.store.saveSelectedIndex(idx);
    _snack('بهترین سرور انتخاب شد: ${best.name}');
  }

  void _goBuy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BuyScreen(
          api: widget.api,
          hasService: _subInfo?.active == true,
          onImported: (url) => _importSubscription(url),
        ),
      ),
    );
  }

  void _goSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          onImportSub: (url) => _importSubscription(url),
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
      _snack('باز کردن تلگرام ممکن نشد.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: RovikTheme.pageGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await _refreshSubInfo();
              await _refreshPings();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(),
                  const SizedBox(height: 16),
                  _connectionCard(),
                  const SizedBox(height: 14),
                  _packageCard(),
                  const SizedBox(height: 18),
                  _serversHeader(),
                  const SizedBox(height: 10),
                  _serversList(),
                  const SizedBox(height: 18),
                  _bottomButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [RovikTheme.neonBlue, RovikTheme.neonCyan],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: RovikTheme.neonGlow(),
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
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'روویک',
                style: TextStyle(
                  fontSize: 19,
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
                  color: RovikTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _goTutorial,
          icon: const Icon(Icons.school_outlined),
          tooltip: 'آموزش اتصال',
        ),
        IconButton(
          onPressed: _goSettings,
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'تنظیمات',
        ),
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          tooltip: 'خروج',
        ),
      ],
    );
  }

  Widget _connectionCard() {
    final cfg = _selectedConfig;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _connected
                        ? RovikTheme.mint.withValues(alpha: 0.18)
                        : RovikTheme.textMuted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _connected
                              ? RovikTheme.mint
                              : RovikTheme.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _connected
                            ? 'متصل'
                            : _busy
                                ? 'در حال اتصال…'
                                : 'قطع',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _connected
                              ? RovikTheme.mint
                              : RovikTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_connected)
                  Text(
                    'مدت اتصال: $_elapsed',
                    style: const TextStyle(
                      fontSize: 12,
                      color: RovikTheme.textMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            // دکمه پاور بزرگ
            GestureDetector(
              onTap: _busy ? null : _toggleConnect,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final glow = _connected
                      ? 0.35 + 0.25 * _pulse.value
                      : 0.15;
                  return Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _connected
                            ? [RovikTheme.mint, const Color(0xFF0E9F6E)]
                            : [RovikTheme.neonBlue, RovikTheme.neonCyan],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_connected
                                  ? RovikTheme.mint
                                  : RovikTheme.neonBlue)
                              .withValues(alpha: glow),
                          blurRadius: 34,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: _busy
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Icon(
                            Icons.power_settings_new,
                            size: 62,
                            color: Colors.white,
                          ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (!_hasConfigs)
              const Text(
                'هنوز کانفیگی نداری — برای اتصال، اول اشتراک بخر یا وارد کن.',
                textAlign: TextAlign.center,
                style: TextStyle(color: RovikTheme.textMuted),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    cfg!.flag,
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      cfg.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: RovikTheme.textMain,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              _connected
                  ? 'برای قطع اتصال، دکمه قطع را بزن.'
                  : 'برای اتصال، دکمه پاور را بزن.',
              style: const TextStyle(
                fontSize: 12,
                color: RovikTheme.textMuted,
              ),
            ),
            if (_connected) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _speedBox(
                    'دانلود',
                    FaFormat.speed(_vpnStatus.downloadSpeed),
                    'مجموع: ${FaFormat.bytes(_vpnStatus.downloadTotal)}',
                    Icons.arrow_downward,
                    RovikTheme.neonCyan,
                  ),
                  _speedBox(
                    'آپلود',
                    FaFormat.speed(_vpnStatus.uploadSpeed),
                    'مجموع: ${FaFormat.bytes(_vpnStatus.uploadTotal)}',
                    Icons.arrow_upward,
                    RovikTheme.mint,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _toggleConnect,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('قطع اتصال'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RovikTheme.coral,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _speedBox(
    String label,
    String speed,
    String total,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: RovikTheme.bgDeep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: RovikTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            speed,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: RovikTheme.textMain,
            ),
          ),
          Text(
            total,
            style: const TextStyle(
              fontSize: 11,
              color: RovikTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _packageCard() {
    final info = _subInfo;
    final remaining =
        info == null ? null : info.remainingGb;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: RovikTheme.gold,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'بسته من',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: RovikTheme.textMain,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (info?.active == true)
                        ? RovikTheme.mint.withValues(alpha: 0.18)
                        : RovikTheme.textMuted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    info == null
                        ? 'نامشخص'
                        : info.active
                            ? 'بسته فعال'
                            : 'بسته غیرفعال',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: info?.active == true
                          ? RovikTheme.mint
                          : RovikTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingSub)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (info == null)
              const Text(
                'اطلاعات بسته در دسترس نیست — بعد از ایمپورت اشتراک، اینجا حجم و روزهای باقی‌مانده را می‌بینی.',
                style: TextStyle(color: RovikTheme.textMuted),
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: info.usedFraction,
                  minHeight: 10,
                  backgroundColor:
                      RovikTheme.textMuted.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    RovikTheme.neonCyan,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _packageStat(
                    'حجم باقی‌مانده',
                    FaFormat.gb(remaining),
                  ),
                  _packageStat(
                    'روزهای باقی‌مانده',
                    info.daysLeft <= 0
                        ? '—'
                        : FaFormat.number(info.daysLeft),
                  ),
                  _packageStat('مصرف‌شده', FaFormat.gb(info.usedGb)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _packageStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: RovikTheme.textMain,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: RovikTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _serversHeader() {
    return Row(
      children: [
        Text(
          'سرورها (${FaFormat.number(_configs.length)})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: RovikTheme.textMain,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _configs.isEmpty ? null : _selectBest,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('انتخاب خودکار بهترین سرور'),
        ),
        IconButton(
          onPressed: _refreshingPing ? null : _refreshPings,
          icon: _refreshingPing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: 'تازه‌سازی پینگ',
        ),
      ],
    );
  }

  Widget _serversList() {
    if (_importing) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!_hasConfigs) {
      return Card(
        child: InkWell(
          onTap: _goBuy,
          borderRadius: BorderRadius.circular(18),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 40,
                  color: RovikTheme.textMuted,
                ),
                SizedBox(height: 10),
                Text(
                  'هنوز سروری نداری',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: RovikTheme.textMain,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'برای دیدن سرورها، اشتراک بخر یا لینک اشتراکت را وارد کن. برای خرید، اینجا بزن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: RovikTheme.textMuted),
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
            padding: const EdgeInsets.only(bottom: 8),
            child: _serverRow(_configs[i], i),
          ),
      ],
    );
  }

  Widget _serverRow(VpnConfig cfg, int index) {
    final selected = index == _selected;
    return Card(
      color: selected ? RovikTheme.bgCardLight : RovikTheme.bgCard,
      child: InkWell(
        onTap: () {
          setState(() => _selected = index);
          widget.store.saveSelectedIndex(index);
        },
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Text(cfg.flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cfg.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: RovikTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cfg.protocol.toUpperCase()} • ${cfg.host}:${FaFormat.number(cfg.port)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: RovikTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected && _connected)
                const Icon(Icons.check_circle, color: RovikTheme.mint)
              else if (selected)
                const Icon(
                  Icons.radio_button_checked,
                  color: RovikTheme.neonCyan,
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: RovikTheme.bgDeep.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  PingService.formatPing(cfg.pingMs),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: RovikTheme.textMain,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openSupport,
            icon: const Icon(Icons.support_agent_outlined),
            label: const Text('پشتیبانی'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _goBuy,
            icon: const Icon(Icons.shopping_bag_outlined),
            label: Text(
              _subInfo?.active == true ? 'تمدید' : 'خرید / تمدید',
            ),
          ),
        ),
      ],
    );
  }
}

/// کپی کردن متن در کلیپ‌بورد با پیام تأیید.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کپی شد.')),
    );
  }
}
