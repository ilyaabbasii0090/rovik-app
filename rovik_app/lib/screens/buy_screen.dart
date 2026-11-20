import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/app_api.dart';
import '../theme.dart';
import 'home_screen.dart';

/// صفحه خرید / تمدید.
///
/// - محصولات واقعی از GET /api/shop/products می‌آیند (قیمت هاردکد نشده).
/// - بعد از انتخاب محصول، سفارش ثبت می‌شود و شماره کارت با دکمه کپی
///   نمایش داده می‌شود؛ سپس کد پیگیری رسید ثبت می‌شود
///   (POST /api/shop/receipt با order_id).
/// - ثبت سفارش/رسید در API فروشگاه نیاز به ورود دارد؛ اگر کاربر هنوز
///   وارد نشده باشد، اپ شماره کارت را نشان می‌دهد و خرید را از طریق
///   ربات تلگرام هدایت می‌کند.
class BuyScreen extends StatefulWidget {
  const BuyScreen({
    super.key,
    required this.api,
    required this.hasService,
    required this.onImported,
  });

  final RovikApi api;
  final bool hasService;
  final void Function(String subUrl) onImported;

  @override
  State<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  List<ShopProduct>? _products;
  String? _error;
  ShopProduct? _selected;
  String? _cardNumber;
  String? _cardOwner;
  int? _orderId;
  bool _creatingOrder = false;
  bool _submittingReceipt = false;
  String? _orderError;
  String? _receiptMessage;
  final _trackingCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _trackingCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final products = await widget.api.fetchProducts();
      final payment = await widget.api.fetchPaymentInfo();
      if (!mounted) return;
      setState(() {
        _products = products;
        _cardNumber = payment.cardNumber;
        _cardOwner = payment.cardOwner;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'دریافت محصولات ممکن نشد: $e');
    }
  }

  Future<void> _createOrder() async {
    final product = _selected;
    if (product == null) return;
    setState(() {
      _creatingOrder = true;
      _orderError = null;
      _orderId = null;
    });
    try {
      final res = await widget.api.createOrder(planKey: product.planKey);
      final order = res['order'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _orderId = (order?['id'] as num?)?.toInt();
        _cardNumber =
            (res['card_number'] as String?) ?? _cardNumber;
        _cardOwner = (res['card_owner'] as String?) ?? _cardOwner;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _orderError =
            'ثبت سفارش از داخل اپ نیاز به ورود دارد. می‌توانی مبلغ را به همین کارت واریز کنی و رسید را از ربات تلگرام بفرستی — یا بعد از ورود دوباره تلاش کنی.';
      });
    } finally {
      if (mounted) setState(() => _creatingOrder = false);
    }
  }

  Future<void> _submitReceipt() async {
    final orderId = _orderId;
    final tracking = _trackingCtrl.text.trim();
    if (orderId == null) {
      setState(() => _receiptMessage = 'اول سفارش را ثبت کن.');
      return;
    }
    if (tracking.isEmpty) {
      setState(() => _receiptMessage = 'کد پیگیری رسید را بنویس.');
      return;
    }
    setState(() => _submittingReceipt = true);
    try {
      await widget.api.submitReceipt(
        orderId: orderId,
        trackingCode: tracking,
      );
      if (!mounted) return;
      setState(() {
        _receiptMessage =
            'رسید ثبت شد و در صف بررسی ادمین قرار گرفت. بعد از تأیید، اشتراکت در همین اپ تازه می‌شود.';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _receiptMessage = 'ثبت رسید ممکن نشد: $e');
      }
    } finally {
      if (mounted) setState(() => _submittingReceipt = false);
    }
  }

  Future<void> _openBot() async {
    final uri = Uri.parse(RovikConfig.supportUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: RovikTheme.pageGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.hasService ? 'تمدید اشتراک' : 'خرید اشتراک'),
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('تلاش دوباره'),
                      ),
                    ],
                  ),
                ),
              )
            : _products == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'یک بسته انتخاب کن:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: RovikTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final p in _products!) _productCard(p),
                        const SizedBox(height: 8),
                        if (_selected != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _creatingOrder ? null : _createOrder,
                              child: _creatingOrder
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('ثبت سفارش'),
                            ),
                          ),
                          if (_orderError != null) ...[
                            const SizedBox(height: 12),
                            _infoBox(_orderError!, RovikTheme.gold),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _openBot,
                              icon: const Icon(Icons.telegram),
                              label: const Text('خرید از ربات تلگرام'),
                            ),
                          ],
                          if (_orderId != null || _orderError != null)
                            ..._paymentSection(),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  List<Widget> _paymentSection() {
    return [
      const SizedBox(height: 18),
      const Text(
        'پرداخت با کارت',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: RovikTheme.textMain,
        ),
      ),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'شماره کارت',
                style: TextStyle(
                  fontSize: 12,
                  color: RovikTheme.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _cardNumber ?? '—',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: RovikTheme.textMain,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _cardNumber == null
                        ? null
                        : () => copyToClipboard(context, _cardNumber!),
                    icon: const Icon(Icons.copy),
                    tooltip: 'کپی شماره کارت',
                  ),
                ],
              ),
              if (_cardOwner != null)
                Text(
                  'به نام: $_cardOwner',
                  style: const TextStyle(color: RovikTheme.textMuted),
                ),
              const SizedBox(height: 8),
              const Text(
                'مبلغ بسته را به این کارت واریز کن و کد پیگیری رسید را پایین وارد کن.',
                style: TextStyle(
                  fontSize: 12,
                  color: RovikTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'ثبت رسید',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: RovikTheme.textMain,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _trackingCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'کد پیگیری رسید',
          hintText: 'مثال: 123456789',
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _submittingReceipt ? null : _submitReceipt,
          child: _submittingReceipt
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('ارسال رسید'),
        ),
      ),
      if (_receiptMessage != null) ...[
        const SizedBox(height: 12),
        _infoBox(_receiptMessage!, RovikTheme.mint),
      ],
      const SizedBox(height: 12),
      const Text(
        'بعد از تأیید ادمین، اشتراک جدیدت به‌صورت خودکار در صفحه اصلی اپ تازه می‌شود.',
        style: TextStyle(fontSize: 12, color: RovikTheme.textMuted),
      ),
    ];
  }

  Widget _productCard(ShopProduct p) {
    final selected = _selected?.id == p.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: selected ? RovikTheme.bgCardLight : RovikTheme.bgCard,
        child: InkWell(
          onTap: () => setState(() => _selected = p),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? RovikTheme.neonCyan
                      : RovikTheme.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: RovikTheme.textMain,
                    ),
                  ),
                ),
                Text(
                  FaFormat.price(p.price),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: RovikTheme.gold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoBox(String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}
