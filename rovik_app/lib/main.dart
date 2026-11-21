import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'services/app_api.dart';
import 'services/subscription_store.dart';
import 'services/version_check.dart';
import 'services/vpn_engine.dart';
import 'theme.dart';

void main() {
  runApp(const RovikApp());
}

/// اپ اختصاصی VPN روویک.
///
/// - کاملاً فارسی و راست‌به‌چپ، تم تیره.
/// - دیپ‌لینک: rovik://import?sub=... و
///   https://rovikvpn.shop/app/import?sub=...
/// - در شروع، نسخه از GET /api/app/version چک می‌شود؛ اگر نسخه جدیدتر
///   باشد، دیالوگ مسدودکننده «باید آپدیت کنید» نمایش داده می‌شود.
class RovikApp extends StatefulWidget {
  const RovikApp({super.key});

  @override
  State<RovikApp> createState() => _RovikAppState();
}

class _RovikAppState extends State<RovikApp> {
  final _importRequests = ValueNotifier<String?>(null);
  final _api = RovikApi();
  final _store = SubscriptionStore();
  late final VpnEngine _engine;
  StreamSubscription<Uri>? _linkSub;
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    _engine = VpnEngine();
    _initDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _api.close();
    _importRequests.dispose();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    try {
      final appLinks = AppLinks();
      _linkSub = appLinks.uriLinkStream.listen(
        _handleIncomingUri,
        onError: (_) {},
      );
      final initial = await appLinks.getInitialLink();
      if (initial != null) _handleIncomingUri(initial);
    } catch (_) {
      // دیپ‌لینک روی این پلتفرم در دسترس نیست؛ اپ بدون آن کار می‌کند.
    }
  }

  void _handleIncomingUri(Uri uri) {
    final sub = _extractSubFromUri(uri);
    if (sub != null && sub.isNotEmpty) {
      _importRequests.value = sub;
    }
  }

  /// آدرس ساب‌لینک را از هر دو شکل دیپ‌لینک بیرون می‌کشد:
  /// rovik://import?sub=<url-encoded> و
  /// https://rovikvpn.shop/app/import?sub=<url-encoded>
  static String? _extractSubFromUri(Uri uri) {
    final isRovikScheme =
        uri.scheme == RovikConfig.deepLinkScheme && uri.host == 'import';
    final isAppLink = (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == RovikConfig.appLinkHost &&
        uri.path == RovikConfig.appLinkPath;
    if (!isRovikScheme && !isAppLink) return null;
    final sub = uri.queryParameters['sub'];
    if (sub == null || sub.isEmpty) return null;
    return sub;
  }

  Future<void> _checkUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    final info = await _api.fetchVersion();
    if (info == null || !mounted) return;
    final installed = RovikConfig.appVersion;
    final newerAvailable = isUpdateAvailable(installed, info.version);
    final belowMin = info.minVersion.isNotEmpty &&
        isBelowMinVersion(installed, info.minVersion);
    final mustUpdate =
        info.forceUpdate || belowMin || newerAvailable;
    if (!mustUpdate) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.system_update, color: RovikTheme.gold),
              SizedBox(width: 8),
              Text('باید آپدیت کنید'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'نسخه جدید روویک (${info.version}) منتشر شده است. برای ادامه باید اپ را آپدیت کنی.',
              ),
              const SizedBox(height: 8),
              Text(
                'نسخه فعلی تو: $installed',
                style: const TextStyle(color: RovikTheme.textMuted),
              ),
            ],
          ),
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final url = info.downloadUrl.isNotEmpty
                    ? info.downloadUrl
                    : RovikConfig.apkDownloadFallback;
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                } else {
                  // اگر لینک دانلود مستقیم باز نشد، کاربر را به ربات
                  // تلگرام بفرست تا APK جدید را از آنجا بگیرد.
                  final bot = Uri.parse(RovikConfig.supportUrl);
                  await launchUrl(bot,
                      mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('آپدیت'),
            ),
            TextButton.icon(
              onPressed: () async {
                final bot = Uri.parse(RovikConfig.supportUrl);
                await launchUrl(bot, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.telegram),
              label: const Text('دریافت از ربات تلگرام'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rovik',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: RovikTheme.dark(),
      home: HomeScreen(
        importRequests: _importRequests,
        api: _api,
        store: _store,
        engine: _engine,
      ),
    );
  }
}
