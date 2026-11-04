import 'package:flutter/material.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/assistant/assistant_page.dart';

/// تب «دستیار»: خارج از تماس هم می‌شود یک شماره را شناسایی کرد (جست‌وجوی دستی)
/// یا فقط محصول جست‌وجو کرد و پیشنهادِ پاسخ گرفت.
class AssistantHomeTab extends StatefulWidget {
  const AssistantHomeTab({super.key});

  @override
  State<AssistantHomeTab> createState() => _AssistantHomeTabState();
}

class _AssistantHomeTabState extends State<AssistantHomeTab> {
  final _number = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _open(String number) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AssistantPage(number: number)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'دستیار فروش',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 6),
        const Text(
          'هنگام تماس، دستیار خودکار باز می‌شود. اینجا می‌توانید خارج از تماس هم یک شماره را شناسایی کنید یا محصول جست‌وجو کنید.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.7),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('شناسایی یک شماره', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                TextField(
                  controller: _number,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: '0912…', prefixIcon: Icon(Icons.call_rounded)),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _open(v.trim());
                  },
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () {
                    final v = _number.text.trim();
                    if (v.isNotEmpty) _open(v);
                  },
                  icon: const Icon(Icons.manage_search_rounded),
                  label: const Text('بازکردن دستیار برای این شماره'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'شناسایی از روی پروفایل پیام‌رسان‌ها فقط برای شماره‌ی تماس‌های واقعی و یک جست‌وجوی دستیِ کارمند است؛ فهرست‌های انبوه ممکن نیست.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _open(''),
          icon: const Icon(Icons.inventory_2_rounded),
          label: const Text('فقط جست‌وجوی محصول و پیشنهاد پاسخ'),
        ),
      ],
    );
  }
}
