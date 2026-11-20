import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';

/// کلاینت API اپ روویک.
///
/// - فروشگاه: GET /api/shop/products ،GET /api/shop/settings ،
///   POST /api/shop/order ،POST /api/shop/receipt
///   (همان قرارداد اپ فروشگاه و rovik_shop_api/app.py).
/// - اپ: GET /api/app/sub-info?token=... و GET /api/app/version
///   (قرارداد مشخص‌شده در تسک؛ اگر سرور هنوز آن‌ها را پیاده نکرده باشد،
///   این متدها ApiUnavailable می‌دهند و UI به‌جای عدد «—» نشان می‌دهد).
class RovikApi {
  RovikApi({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Map<String, dynamic>? _decode(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}
    return null;
  }

  /// GET /api/app/sub-info?token=<subscription-token>
  /// پاسخ: {"ok":true,"username":"...","used_gb":12.5,"total_gb":50.0,
  ///        "days_left":25,"expires_at":"...","active":true}
  Future<SubInfo?> fetchSubInfo(String token) async {
    final uri = Uri.parse(
      '${RovikConfig.baseUrl}${RovikConfig.appApiPath}/sub-info',
    ).replace(queryParameters: {'token': token});
    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 10));
      final data = _decode(res);
      if (data == null || data['ok'] != true) return null;
      return SubInfo.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// GET /api/app/version (عمومی)
  /// پاسخ: {"ok":true,"version":"1.0.0","min_version":"1.0.0",
  ///        "download_url":"https://rovikvpn.shop/dl/rovik.apk",
  ///        "force_update":false}
  Future<AppVersionInfo?> fetchVersion() async {
    final uri = Uri.parse(
      '${RovikConfig.baseUrl}${RovikConfig.appApiPath}/version',
    );
    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 10));
      final data = _decode(res);
      if (data == null || data['ok'] != true) return null;
      return AppVersionInfo.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// GET /api/shop/products — لیست واقعی محصولات؛ قیمت‌ها هاردکد نشده‌اند.
  Future<List<ShopProduct>> fetchProducts() async {
    final uri = Uri.parse(
      '${RovikConfig.baseUrl}${RovikConfig.shopApiPath}/products',
    );
    final res = await _http.get(uri).timeout(const Duration(seconds: 10));
    final data = _decode(res);
    if (data == null || data['ok'] != true) {
      throw Exception('دریافت محصولات ممکن نشد.');
    }
    final list = (data['products'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ShopProduct.fromJson)
        .toList();
    return list;
  }

  /// GET /api/shop/settings — شماره کارت و صاحب کارت برای پرداخت.
  Future<({String? cardNumber, String? cardOwner})> fetchPaymentInfo() async {
    final uri = Uri.parse(
      '${RovikConfig.baseUrl}${RovikConfig.shopApiPath}/settings',
    );
    final res = await _http.get(uri).timeout(const Duration(seconds: 10));
    final data = _decode(res);
    if (data == null) return (cardNumber: null, cardOwner: null);
    final payment = data['payment'] as Map<String, dynamic>?;
    return (
      cardNumber: (payment?['card_number'] ??
              data['card_number']) as String?,
      cardOwner: (payment?['card_owner'] ?? data['card_owner']) as String?,
    );
  }

  /// POST /api/shop/order — ثبت سفارش خرید/تمدید.
  /// برای خرید بدون ورود، سرور ممکن است خطا بدهد؛ در آن صورت کاربر
  /// از طریق ربات تلگرام هدایت می‌شود.
  Future<Map<String, dynamic>> createOrder({
    required String planKey,
    String paymentMethod = 'card',
  }) async {
    final uri = Uri.parse(
      '${RovikConfig.baseUrl}${RovikConfig.shopApiPath}/order',
    );
    final res = await _http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'plan_key': planKey,
            'quantity': 1,
            'payment_method': paymentMethod,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decode(res);
    if (data == null) throw Exception('پاسخ سرور خوانا نیست.');
    if (data['ok'] != true) {
      throw Exception((data['error'] as String?) ?? 'ثبت سفارش ممکن نشد.');
    }
    return data;
  }

  /// POST /api/shop/receipt — ثبت رسید پرداخت سفارش.
  /// قرارداد rovik_shop_api/app.py: {order_id, method: "card"|"crypto",
  /// tracking_code, amount?} — نیاز به توکن ورود فروشگاه دارد.
  Future<Map<String, dynamic>> submitReceipt({
    required int orderId,
    required String trackingCode,
    String method = 'card',
  }) async {
    final uri = Uri.parse(
      '${RovikConfig.baseUrl}${RovikConfig.shopApiPath}/receipt',
    );
    final res = await _http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'order_id': orderId,
            'method': method,
            'tracking_code': trackingCode,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decode(res);
    if (data == null) throw Exception('پاسخ سرور خوانا نیست.');
    if (data['ok'] != true) {
      throw Exception((data['error'] as String?) ?? 'ثبت رسید ممکن نشد.');
    }
    return data;
  }

  /// دانلود ساب‌لینک: بدنه base64 برمی‌گردد.
  Future<String> fetchSublink(String subUrl) async {
    final uri = Uri.parse(subUrl);
    final res = await _http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('دریافت اشتراک ممکن نشد (کد ${res.statusCode}).');
    }
    return res.body;
  }

  void close() => _http.close();
}
