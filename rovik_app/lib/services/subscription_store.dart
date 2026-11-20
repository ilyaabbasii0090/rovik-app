import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// ذخیره‌سازی محلی: کانفیگ‌ها، توکن اشتراک و سرور انتخاب‌شده.
///
/// توجه: لینک‌های کانفیگ حاوی UUID کاربر هستند؛ shared_preferences
/// روی اندروید در فضای خصوصی اپ ذخیره می‌شود و با بقیه اپ‌ها
/// به اشتراک گذاشته نمی‌شود.
class SubscriptionStore {
  static const _kConfigs = 'rovik_configs_v1';
  static const _kSubUrl = 'rovik_sub_url_v1';
  static const _kSelectedIndex = 'rovik_selected_index_v1';
  static const _kUsername = 'rovik_username_v1';
  static const _kManualSelection = 'rovik_manual_selection_v1';

  Future<List<VpnConfig>> loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kConfigs);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(VpnConfig.fromJson)
          .where((c) => c.link.isNotEmpty && c.host.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConfigs(List<VpnConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kConfigs,
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }

  Future<String?> loadSubUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSubUrl);
  }

  Future<void> saveSubUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSubUrl, url);
  }

  Future<String?> loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUsername);
  }

  Future<void> saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUsername, username);
  }

  Future<int> loadSelectedIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kSelectedIndex) ?? 0;
  }

  Future<void> saveSelectedIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSelectedIndex, index);
  }

  /// آیا کاربر خودش دستی یک سرور را انتخاب کرده است؟
  ///
  /// اگر true باشد، انتخاب خودکار سریع‌ترین سرور دیگر انتخاب کاربر را
  /// عوض نمی‌کند؛ اگر false باشد، بعد از هر بار تست پینگ، سریع‌ترین
  /// سرور به‌صورت خودکار انتخاب می‌شود.
  Future<bool> loadManualSelection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kManualSelection) ?? false;
  }

  Future<void> saveManualSelection(bool manual) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kManualSelection, manual);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kConfigs);
    await prefs.remove(_kSubUrl);
    await prefs.remove(_kSelectedIndex);
    await prefs.remove(_kManualSelection);
    await prefs.remove(_kUsername);
  }
}
