import 'package:flutter/material.dart';

import '../services/iran_guard.dart';
import '../services/native_bridge.dart';
import '../theme.dart';

/// کارت تنظیمات «اپ‌های ایرانی» (داخل صفحه تنظیمات).
class IranGuardCard extends StatefulWidget {
  const IranGuardCard({super.key, this.onChanged});

  /// بعد از هر تغییر (روشن/خاموش یا تغییر فهرست) صدا زده می‌شود.
  final VoidCallback? onChanged;

  @override
  State<IranGuardCard> createState() => _IranGuardCardState();
}

class _IranGuardCardState extends State<IranGuardCard> {
  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await IranGuardPrefs.loadEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loaded = true;
    });
  }

  Future<void> _toggle(bool v) async {
    await IranGuardPrefs.saveEnabled(v);
    setState(() => _enabled = v);
    widget.onChanged?.call();
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
              title: const Text('اپ‌های ایرانی بدون قطع VPN'),
              subtitle: const Text(
                'VPN همیشه روشن می‌ماند و اپ‌هایی مثل همراه بانک خودکار با آی‌پی ایران کار می‌کنند؛ بقیه ترافیک روی VPN می‌ماند. سایت‌های «.ir» هم مستقیم باز می‌شوند.',
              ),
              value: _enabled,
              onChanged: _loaded ? _toggle : null,
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

/// فهرست اپ‌های نصب‌شده؛ ترافیک تیک‌خورده‌ها مستقیم (آی‌پی ایران) می‌رود.
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
                'ترافیک اپ‌های تیک‌خورده بدون VPN و مستقیم می‌رود؛ VPN روشن می‌ماند.',
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
