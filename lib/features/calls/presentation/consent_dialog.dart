import 'package:flutter/material.dart';

/// می‌پرسد: «به طرف مقابل گفتید که تماس ضبط می‌شود و موافقت کرد؟»
/// اگر کاربر تأیید کند، توضیحِ «چطور رضایت گرفته شد» برگردانده می‌شود؛ وگرنه null
/// (و هیچ فایلی ارسال نمی‌شود).
Future<String?> askRecordingConsent(BuildContext context, String number) async {
  final ctrl = TextEditingController(text: 'در همان تماس گفتم ضبط می‌شود و موافقت کرد');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('رضایت ضبط تماس'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Directionality(textDirection: TextDirection.ltr, child: Text(number)),
          const SizedBox(height: 8),
          const Text(
            'به طرف مقابل گفتید که تماس ضبط می‌شود و موافقت کرد؟\n'
            'قانون NM: بدون ثبت رضایت، هیچ فایلی ذخیره نمی‌شود. این توضیح با نام شما در NM ثبت می‌شود.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'چطور رضایت گرفته شد؟'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('نه، ارسال نکن')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('بله، موافقت کرد')),
      ],
    ),
  );
  final text = ctrl.text.trim();
  ctrl.dispose();
  if (ok != true || text.isEmpty) return null;
  return text;
}
