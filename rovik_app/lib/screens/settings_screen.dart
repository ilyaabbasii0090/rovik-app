import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/rovik_file.dart';
import '../theme.dart';
import 'tutorial_screen.dart';

/// تنظیمات اپ: ایمپورت فایل روویک (.rovik)، آموزش، خروج از اشتراک.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onImportSub,
    required this.onLogout,
  });

  final void Function(String subUrl) onImportSub;
  final VoidCallback onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _message;
  bool _picking = false;

  Future<void> _pickRovikFile() async {
    setState(() {
      _picking = true;
      _message = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['rovik'],
      );
      if (file == null) {
        setState(() => _message = 'فایلی انتخاب نشد.');
        return;
      }
      // بایت‌های فایل روی همه پلتفرم‌ها (وب و اندروید) خوانده می‌شوند.
      final bytes = await file.readAsBytes();
      final content = String.fromCharCodes(bytes);
      final sub = RovikFile.parseSubUrl(content);
      if (sub == null) {
        setState(() {
          _message = 'این فایل روویک معتبر نیست. فایل باید JSON با فرمت rovick-subscription و فیلد "sub" باشد.';
        });
        return;
      }
      widget.onImportSub(sub);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فایل روویک وارد شد؛ اشتراک در حال دریافت است…')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _message = 'خطا در انتخاب فایل: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

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
                    Icons.file_upload_outlined,
                    color: RovikTheme.neonCyan,
                  ),
                  title: const Text('وارد کردن فایل روویک (.rovik)'),
                  subtitle: const Text(
                    'فایل اشتراکی که از ربات گرفتی را انتخاب کن تا کانفیگ‌ها وارد شوند.',
                  ),
                  trailing: _picking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_left),
                  onTap: _picking ? null : _pickRovikFile,
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RovikTheme.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: RovikTheme.gold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _message!,
                    style: const TextStyle(color: RovikTheme.gold),
                  ),
                ),
              ],
              const SizedBox(height: 12),
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
                    widget.onLogout();
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'روویک — نسخه ۱٫۰٫۰',
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
