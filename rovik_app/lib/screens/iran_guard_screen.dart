import 'package:flutter/material.dart';

import '../services/iran_guard.dart';
import '../services/native_bridge.dart';
import '../theme.dart';
import '../widgets/rovik_dialog.dart';

/// کارت تنظیمات «قطع خودکار برای اپ‌های ایرانی» (داخل صفحه تنظیمات).
class IranGuardCard extends StatefulWidget {
  const IranGuardCard({super.key, this.onChanged});

  /// بعد از هر تغییر (روشن/خاموش یا تغییر فهرست) صدا زده می‌شود.
  final VoidCallback? onChanged;

  @override
  State<IranGuardCard> createState() => _IranGuardCardState();
}

class _IranGuardCardState extends State<IranGuardCard>
    with WidgetsBindingObserver {
  bool _enabled = false;
  bool _hasAccess = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // برگشت از صفحه تنظیمات اندروید: وضعیت مجوز را دوباره بخوان.
    if (state == AppLifecycleState.resumed) _load(notify: true);
  }

  Future<void> _load({bool notify = false}) async {
    final enabled = await IranGuardPrefs.loadEnabled();
    final access = await NativeBridge.hasUsageAccess();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _hasAccess = access;
      _loaded = true;
    });
    if (notify) widget.onChanged?.call();
  }

  Future<void> _toggle(bool v) async {
    await IranGuardPrefs.saveEnabled(v);
    setState(() => _enabled = v);
    if (v && !await NativeBridge.hasUsageAccess()) {
      if (!mounted) return;
      await showRovikDialog(
        context,
        title: 'دسترسی لازم است',
        message:
            'برای تشخیص اینکه کدام اپ جلوی صفحه است، گوشی باید به روویک اجازه «دسترسی به استفاده از اپ‌ها (Usage Access)» بدهد. در صفحه‌ای که باز می‌شود روویک را پیدا کن و آن را روشن کن.',
        kind: RovikDialogKind.info,
      );
      await NativeBridge.openUsageAccessSettings();
    }
    widget.onChanged?.call();
    await _load();
  }

  Future<void> _openApps() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IranAppsScreen(onChanged: widget.onChanged),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inactive = _loaded && _enabled && !_hasAccess;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            SwitchListTile(
              secondary: const Icon(
                Icons.swap_horiz_rounded,
                color: RovikTheme.mint,
              ),
              title: const Text('قطع خودکار برای اپ‌های ایرانی'),
              subtitle: const Text(
                'وقتی اپی مثل همراه بانک را باز کنی، VPN خودش قطع می‌شود و به‌محض خروج از آن اپ دوباره وصل می‌شود. سایت‌های «.ir» هم مستقیم باز می‌شوند.',
              ),
              value: _enabled,
              onChanged: _loaded ? _toggle : null,
            ),
            if (inactive)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'این قابلیت فعال نیست چون دسترسی «Usage Access» به روویک داده نشده. VPN مثل قبل کار می‌کند. برای فعال شدن، کلید را خاموش و دوباره روشن کن و دسترسی را بده.',
                  style: TextStyle(color: RovikTheme.coral, height: 1.7),
                ),
              ),
            ListTile(
              leading: const Icon(
                Icons.apps_rounded,
                color: RovikTheme.mint,
              ),
              title: const Text('انتخاب اپ‌های ایرانی'),
              subtitle: const Text('اضافه یا حذف اپ از فهرست'),
              trailing: const Icon(Icons.chevron_left),
              onTap: _openApps,
            ),
          ],
        ),
      ),
    );
  }
}

/// فهرست اپ‌های نصب‌شده؛ تیک‌خورده‌ها با باز شدنشان VPN قطع می‌شود.
class IranAppsScreen extends StatefulWidget {
  const IranAppsScreen({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<IranAppsScreen> createState() => _IranAppsScreenState();
}

class _IranAppsScreenState extends State<IranAppsScreen> {
  List<InstalledApp> _apps = const <InstalledApp>[];
  Set<String> _added = <String>{};
  Set<String> _removed = <String>{};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await NativeBridge.installedApps();
    final added = await IranGuardPrefs.loadAdded();
    final removed = await IranGuardPrefs.loadRemoved();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _added = added;
      _removed = removed;
      _loading = false;
    });
  }

  bool _checked(InstalledApp a) {
    if (_added.contains(a.package)) return true;
    if (_removed.contains(a.package)) return false;
    return IranGuardPrefs.isDefault(a);
  }

  Future<void> _set(InstalledApp a, bool v) async {
    setState(() {
      if (v) {
        _removed.remove(a.package);
        if (!IranGuardPrefs.isDefault(a)) _added.add(a.package);
      } else {
        _added.remove(a.package);
        if (IranGuardPrefs.isDefault(a)) _removed.add(a.package);
      }
    });
    await IranGuardPrefs.saveLists(_added, _removed);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = _apps
        .where((a) =>
            q.isEmpty ||
            a.label.toLowerCase().contains(q) ||
            a.package.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final ca = _checked(a) ? 0 : 1;
        final cb = _checked(b) ? 0 : 1;
        if (ca != cb) return ca - cb;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return Container(
      decoration: const BoxDecoration(gradient: RovikTheme.pageGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('اپ‌های ایرانی')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'جست‌وجوی اپ',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'اپ‌های تیک‌خورده با باز شدنشان VPN را قطع می‌کنند.',
                style: TextStyle(color: RovikTheme.textMuted),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                      ? const Center(child: Text('اپی پیدا نشد.'))
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final a = shown[i];
                            return CheckboxListTile(
                              value: _checked(a),
                              onChanged: (v) => _set(a, v ?? false),
                              title: Text(a.label),
                              subtitle: Text(
                                a.package,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
