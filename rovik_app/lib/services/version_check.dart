/// مقایسه معنایی نسخه‌ها: "1.2.3" در برابر "1.10.0".
///
/// برمی‌گرداند:
/// - عدد منفی اگر a قدیمی‌تر از b باشد،
/// - صفر اگر برابر باشند،
/// - عدد مثبت اگر a جدیدتر باشد.
int compareVersions(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

List<int> _parts(String v) {
  final core = v.trim().split(RegExp(r'[-+]')).first;
  return core.split('.').map((s) => int.tryParse(s) ?? 0).toList();
}

/// آیا نسخه سرور از نسخه نصب‌شده جدیدتر است؟
bool isUpdateAvailable(String installed, String server) =>
    compareVersions(installed, server) < 0;

/// آیا نسخه نصب‌شده از حداقل نسخه اجباری قدیمی‌تر است؟
bool isBelowMinVersion(String installed, String minVersion) =>
    compareVersions(installed, minVersion) < 0;
