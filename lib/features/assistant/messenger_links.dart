import 'dart:convert';

import 'package:nm_mobile/features/calls/domain/recording_matcher.dart';

/// یک پیام‌رسان و لینک‌هایش (داده‌محور؛ از assets/messengers.json که از
/// docs/research/messengers.json می‌آید و فقط الگوهای تأییدشده را دارد).
class MessengerDef {
  const MessengerDef({
    required this.key,
    required this.labelFa,
    required this.packages,
    required this.phoneTemplates,
    this.supportsPhone = 'unverified',
    this.alive = 'yes',
  });

  factory MessengerDef.fromJson(Map<String, dynamic> j) {
    final phone = <String>[];
    final raw = j['phone_links'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map && e['template'] is String) phone.add(e['template'] as String);
      }
    }
    final pk = <String>[];
    final rawPk = j['android_packages'];
    if (rawPk is List) {
      for (final e in rawPk) {
        pk.add(e.toString());
      }
    }
    return MessengerDef(
      key: (j['key'] ?? '').toString(),
      labelFa: (j['label_fa'] ?? j['key'] ?? '').toString(),
      packages: pk,
      phoneTemplates: phone,
      supportsPhone: (j['supports_phone_deeplink'] ?? 'unverified').toString(),
      alive: (j['alive'] ?? 'yes').toString(),
    );
  }

  final String key;
  final String labelFa;
  final List<String> packages;
  final List<String> phoneTemplates;

  /// yes | partial | no | unverified
  final String supportsPhone;
  final String alive;

  /// آیا لینکِ تأییدشده‌ای برای باز کردن چت با شماره داریم؟
  bool get hasPhoneLink => phoneTemplates.isNotEmpty;
}

List<MessengerDef> parseMessengers(String jsonText) {
  final data = jsonDecode(jsonText);
  if (data is! List) return const [];
  return data.whereType<Map>().map((e) => MessengerDef.fromJson(Map<String, dynamic>.from(e))).toList();
}

/// شمارهٔ بین‌المللی فقط‌رقم برای لینک‌ها: ۰۹۱۲… ⇒ ۹۸۹۱۲…
/// (همان قاعدهٔ سرور: ۰۰/+ حذف، ۰ ابتدایی ۱۱رقمی ⇒ ۹۸، ۱۰رقمیِ ۹… ⇒ ۹۸).
String internationalDigits(String number) {
  var d = digitsOnly(number);
  if (d.isEmpty) return '';
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0') && d.length == 11) return '98${d.substring(1)}';
  if (d.length == 10 && d.startsWith('9')) return '98$d';
  return d;
}

/// لینک باز کردن چت با این شماره، یا null اگر این پیام‌رسان لینکِ شماره‌دارِ تأییدشده ندارد.
String? buildPhoneLink(MessengerDef m, String number) {
  if (!m.hasPhoneLink) return null;
  final digits = internationalDigits(number);
  if (digits.length < 8) return null;
  return m.phoneTemplates.first.replaceAll('{digits}', digits);
}
