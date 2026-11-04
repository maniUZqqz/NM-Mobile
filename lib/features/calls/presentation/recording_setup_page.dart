import 'package:flutter/material.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/calls/services/recording_source.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// تنظیم ضبط تماس. صادقانه: برنامه صدا ضبط نمی‌کند؛ فقط پوشهٔ ضبط‌کنندهٔ داخلیِ گوشی را می‌خواند.
class RecordingSetupPage extends StatefulWidget {
  const RecordingSetupPage({super.key});

  @override
  State<RecordingSetupPage> createState() => _RecordingSetupPageState();
}

class _RecordingSetupPageState extends State<RecordingSetupPage> {
  final CallSettingsStore _store = CallSettingsStore();
  CallSettings _s = CallSettings();
  bool _loaded = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _store.load();
    if (mounted) {
      setState(() {
        _s = s;
        _loaded = true;
      });
    }
  }

  Future<void> _pick() async {
    try {
      final f = await SmsBridge.pickRecordingsFolder();
      if (f == null) return;
      _s.treeUri = f.tree;
      _s.treeName = f.name;
      await _store.save(_s);
      if (mounted) setState(() => _msg = 'پوشه ذخیره شد.');
    } catch (e) {
      if (mounted) setState(() => _msg = 'انتخاب پوشه ممکن نشد: $e');
    }
  }

  Future<void> _toggleAuto(bool v) async {
    _s.autoUpload = v;
    await _store.save(_s);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیم ضبط تماس')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _Note(
                  icon: Icons.info_outline_rounded,
                  color: AppColors.secondary,
                  text: 'اندروید از نسخهٔ ۱۰ به برنامه‌های عادی اجازهٔ ضبط صدای تماس نمی‌دهد. '
                      'NM-Mobile صدا ضبط نمی‌کند؛ فقط فایل‌هایی را می‌خواند که ضبط‌کنندهٔ داخلیِ خودِ گوشی ساخته است.',
                ),
                const SizedBox(height: 10),
                const _Note(
                  icon: Icons.verified_user_rounded,
                  color: AppColors.success,
                  text: 'بدون ثبتِ رضایتِ طرف مقابل، هیچ فایلی به NM فرستاده نمی‌شود. '
                      'قبل از هر ارسال می‌پرسیم: «به او گفتید ضبط می‌شود و موافقت کرد؟»',
                ),
                const SizedBox(height: 16),
                const Text('مراحل', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  '۱) در برنامهٔ تماسِ گوشی، «ضبط تماس» را روشن کنید (مسیرش بسته به برند فرق دارد؛ '
                  'روی بعضی گوشی‌ها یا در بعضی کشورها این گزینه وجود ندارد).\n'
                  '۲) در ضبط‌کننده، ذخیره‌شدن فایل‌ها در حافظهٔ گوشی را فعال بگذارید. '
                  'در برنامهٔ «Phone» گوگل فایل‌ها داخل خودِ برنامه می‌مانند و از بیرون خوانده نمی‌شوند.\n'
                  '۳) پایین «انتخاب پوشه» را بزنید و پوشهٔ ضبط‌های تماس را انتخاب کنید '
                  '(مثلاً Recordings ‹ Call یا MIUI ‹ sound_recorder ‹ call_rec). سپس «اجازه» بدهید.',
                  style: TextStyle(height: 1.8),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_open_rounded, color: AppColors.primary),
                    title: Text(_s.hasFolder ? 'پوشهٔ انتخاب‌شده' : 'هنوز پوشه‌ای انتخاب نشده'),
                    subtitle: _s.hasFolder
                        ? Directionality(textDirection: TextDirection.ltr, child: Text(_s.treeName))
                        : null,
                    trailing: FilledButton(onPressed: _pick, child: Text(_s.hasFolder ? 'تغییر' : 'انتخاب پوشه')),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: SwitchListTile(
                    value: _s.autoUpload,
                    onChanged: _s.hasFolder ? _toggleAuto : null,
                    title: const Text('ارسال خودکار'),
                    subtitle: const Text(
                      'فقط برای شماره‌هایی که رضایتِ ضبطشان قبلاً در NM ثبت شده. بقیه منتظرِ تأییدِ شما می‌مانند.',
                      style: TextStyle(height: 1.5),
                    ),
                  ),
                ),
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_msg!, style: const TextStyle(color: AppColors.primary)),
                  ),
              ],
            ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.7, fontSize: 13))),
        ],
      ),
    );
  }
}
