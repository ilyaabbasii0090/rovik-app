import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../theme.dart';

/// رنگ پس‌زمینه اسپلش؛ دقیقاً هم‌رنگ launch_background نیتیو (rovik_bg) تا
/// بین لانچ نیتیو و اسپلش اپ هیچ پرشی نباشد.
const Color kSplashBg = Color(0xFF020823);

/// اسپلش انیمیشنی روی صفحه اصلی.
///
/// صفحه اصلی از همان لحظه اول زیر اسپلش ساخته می‌شود و آماده‌سازی‌اش
/// (خواندن اشتراک و…) هم‌زمان با انیمیشن انجام می‌شود؛ پس اسپلش اپ را کند
/// نمی‌کند. وقتی انیمیشن تمام شد و صفحه اصلی آماده بود (یا حداکثر
/// [maxDuration] گذشت) اسپلش محو می‌شود.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    required this.ready,
    this.maxDuration = const Duration(milliseconds: 2500),
  });

  final Widget child;

  /// وقتی true شد یعنی آماده‌سازی صفحه اصلی تمام شده است.
  final ValueListenable<bool> ready;
  final Duration maxDuration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  static const String _name = 'RovikVpn';

  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _tagOpacity;
  Timer? _cap;
  bool _animDone = false;
  bool _finished = false;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    // لوگو از ۱٫۳ به ۱٫۰ «کوبیده می‌شود» (bounce).
    _scale = Tween<double>(begin: 1.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.0, 0.45, curve: Curves.bounceOut),
      ),
    );
    _logoOpacity = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.15, curve: Curves.easeOut),
    );
    _tagOpacity = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.80, 1.0, curve: Curves.easeIn),
    );
    widget.ready.addListener(_tryFinish);
    _cap = Timer(widget.maxDuration, _finish);
    _c.forward().whenComplete(() {
      _animDone = true;
      _tryFinish();
    });
  }

  void _tryFinish() {
    if (_animDone && widget.ready.value) _finish();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _cap?.cancel();
    setState(() {});
  }

  @override
  void dispose() {
    widget.ready.removeListener(_tryFinish);
    _cap?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// حرف‌به‌حرف تایپ شدن «RovikVpn» بین ۴۰٪ تا ۷۵٪ انیمیشن.
  String get _typed {
    final t = ((_c.value - 0.40) / 0.35).clamp(0.0, 1.0);
    final n = (t * _name.length).ceil().clamp(0, _name.length);
    return _name.substring(0, n);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_removed)
          IgnorePointer(
            ignoring: _finished,
            child: AnimatedOpacity(
              opacity: _finished ? 0 : 1,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              onEnd: () {
                // بعد از محو شدن کامل، اسپلش از درخت برداشته می‌شود.
                if (_finished && mounted) setState(() => _removed = true);
              },
              child: _splash(),
            ),
          ),
      ],
    );
  }

  Widget _splash() {
    return ColoredBox(
      color: kSplashBg,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: _logoOpacity.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(36),
                    child: Image.asset(
                      'assets/rovikvpn_icon.png',
                      width: 160,
                      height: 160,
                      cacheWidth: 480,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 36,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    _typed,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: RovikTheme.textMain,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Opacity(
                opacity: _tagOpacity.value,
                child: const Text(
                  'سریع • امن • آزاد',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 14,
                    color: RovikTheme.textMuted,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
