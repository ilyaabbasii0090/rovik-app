import 'package:flutter/material.dart';

import '../theme.dart';
import 'tutorial_screen.dart';

/// تنظیمات اپ: آموزش، خروج از اشتراک.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onLogout,
  });

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: RovikTheme.pageGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('تنظیمات')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.school_outlined,
                    color: RovikTheme.mint,
                  ),
                  title: const Text('آموزش اتصال'),
                  subtitle: const Text(
                    'قدم‌به‌قدم یاد بگیر چطور به سرور وصل شوی.',
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TutorialScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.logout,
                    color: RovikTheme.coral,
                  ),
                  title: const Text('خروج و پاک کردن اشتراک'),
                  subtitle: const Text(
                    'همه کانفیگ‌ها از این گوشی پاک می‌شوند.',
                  ),
                  onTap: () {
                    onLogout();
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'RovikVpn — نسخه ۱٫۰٫۰',
                  style: TextStyle(color: RovikTheme.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
