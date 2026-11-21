import 'package:flutter/material.dart';

import '../theme.dart';

/// آموزش قدم‌به‌قدم اتصال — پنج مرحله ساده.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  static const _steps = [
    (
      icon: Icons.telegram,
      title: 'قدم ۱ — گرفتن اشتراک',
      body:
          'از ربات تلگرام روویک (@RovikVpn_bot) اشتراک بخر. بعد از خرید، دکمه سبز «متصل به برنامه» را بزن؛ اپ خودش باز می‌شود و کانفیگ‌ها وارد می‌شوند.',
    ),
    (
      icon: Icons.check_circle_outlined,
      title: 'قدم ۲ — فقط از دکمه سبز ربات',
      body:
          'کانفیگ‌ها فقط از دکمه سبز «متصل به برنامه» در ربات تلگرام وارد می‌شوند؛ راه دیگری برای وارد کردن کانفیگ نیست. همان دکمه را بزن تا اپ باز شود و ساب‌لینک را خودش بگیرد.',
    ),
    (
      icon: Icons.list_alt_outlined,
      title: 'قدم ۳ — انتخاب سرور',
      body:
          'در لیست «سرورها» روی سروری که می‌خواهی بزن. عدد کنار هر سرور، پینگ آن است؛ هرچه کمتر باشد بهتر است. دکمه «انتخاب خودکار بهترین سرور» کم‌پینگ‌ترین سرور را برایت انتخاب می‌کند.',
    ),
    (
      icon: Icons.power_settings_new,
      title: 'قدم ۴ — اتصال با یک ضربه',
      body:
          'دکمه بزرگ پاور را بزن. بار اول اندروید اجازه VPN می‌خواهد؛ «تأیید» را بزن. وقتی دکمه سبز شد، متصلی و سرعت دانلود و آپلود زنده را می‌بینی.',
    ),
    (
      icon: Icons.refresh_outlined,
      title: 'قدم ۵ — تمدید و تازه‌سازی',
      body:
          'حجم و روزهای باقی‌مانده‌ات را در کارت «بسته من» می‌بینی. وقتی تمام شد، از دکمه «خرید / تمدید» تمدید کن؛ بعد از تأیید ادمین، اشتراکت در همین اپ تازه می‌شود.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: RovikTheme.pageGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('آموزش اتصال')),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _steps.length,
                itemBuilder: (context, i) {
                  final step = _steps[i];
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                RovikTheme.neonBlue,
                                RovikTheme.neonCyan,
                              ],
                            ),
                            boxShadow: RovikTheme.neonGlow(),
                          ),
                          child: Icon(
                            step.icon,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: RovikTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          step.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.9,
                            color: RovikTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _page == i ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == i
                          ? RovikTheme.neonCyan
                          : RovikTheme.textMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_page < _steps.length - 1) {
                      _pageCtrl.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(
                    _page < _steps.length - 1 ? 'بعدی' : 'فهمیدم، بزن بریم',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
