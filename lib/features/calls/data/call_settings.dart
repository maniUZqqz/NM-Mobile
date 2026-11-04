import 'dart:convert';
import 'dart:io';

import 'package:nm_mobile/core/storage/app_storage.dart';
import 'package:nm_mobile/core/storage/file_mutex.dart';

/// تنظیمات ضبط تماس (برگرفته از SMS-and-call، سبک‌شده برای NM).
///
/// عمداً **نه** تنظیمِ تبدیل به متن (متن را فقط سرور NM می‌سازد)، **نه** آدرس سرورِ دلخواه برای
/// آپلود (فقط NM)، و **نه** ضبط‌کنندهٔ داخلی/دسترس‌پذیری (در این برنامه نیست).
class CallSettings {
  const CallSettings({
    this.consentAcceptedAt,
    this.setupCompleted = false,
    this.watchPhoneRecorder = true,
    this.autoUploadToNm = false,
    this.lastScanAtMillis = 0,
    this.importDays = 7,
  });

  /// کاربر اطلاعیهٔ مسئولیت ضبط تماس را پذیرفته است (زمان پذیرش).
  final DateTime? consentAcceptedAt;

  /// راه‌اندازی اولیه (راهنمای مرحله‌به‌مرحله) انجام شده است.
  final bool setupCompleted;

  /// پوشهٔ ضبط‌کنندهٔ خودِ گوشی رصد شود.
  final bool watchPhoneRecorder;

  /// ضبط‌های تازه خودکار به صف ارسال به NM بروند. **همیشه** با دروازهٔ رضایت: اگر رضایتِ
  /// ثبت‌شدهٔ آن شماره در NM نباشد، فایل ارسال نمی‌شود و منتظر تأییدِ کاربر می‌ماند.
  final bool autoUploadToNm;

  /// آخرین اسکن موفق پوشه‌ها (میلی‌ثانیه).
  final int lastScanAtMillis;

  /// در اولین اسکن، ضبط‌های چند روز اخیر وارد شود.
  final int importDays;

  bool get consentAccepted => consentAcceptedAt != null;

  CallSettings copyWith({
    DateTime? consentAcceptedAt,
    bool? setupCompleted,
    bool? watchPhoneRecorder,
    bool? autoUploadToNm,
    int? lastScanAtMillis,
    int? importDays,
  }) {
    return CallSettings(
      consentAcceptedAt: consentAcceptedAt ?? this.consentAcceptedAt,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      watchPhoneRecorder: watchPhoneRecorder ?? this.watchPhoneRecorder,
      autoUploadToNm: autoUploadToNm ?? this.autoUploadToNm,
      lastScanAtMillis: lastScanAtMillis ?? this.lastScanAtMillis,
      importDays: importDays ?? this.importDays,
    );
  }

  Map<String, dynamic> toJson() => {
    if (consentAcceptedAt != null) 'consentAcceptedAt': consentAcceptedAt!.millisecondsSinceEpoch,
    'setupCompleted': setupCompleted,
    'watchPhoneRecorder': watchPhoneRecorder,
    'autoUploadToNm': autoUploadToNm,
    'lastScanAtMillis': lastScanAtMillis,
    'importDays': importDays,
  };

  factory CallSettings.fromJson(Map<String, dynamic> json) {
    const d = CallSettings();
    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    final consent = json['consentAcceptedAt'];
    return CallSettings(
      consentAcceptedAt: consent is num && consent > 0 ? DateTime.fromMillisecondsSinceEpoch(consent.toInt()) : null,
      setupCompleted: flag('setupCompleted', d.setupCompleted),
      watchPhoneRecorder: flag('watchPhoneRecorder', d.watchPhoneRecorder),
      autoUploadToNm: flag('autoUploadToNm', d.autoUploadToNm),
      lastScanAtMillis: (json['lastScanAtMillis'] as num?)?.toInt() ?? 0,
      importDays: ((json['importDays'] as num?)?.toInt() ?? d.importDays).clamp(1, 90),
    );
  }
}

class CallSettingsStorage {
  /// فقط برای تست: پوشهٔ دلخواه به‌جای پوشهٔ برنامه.
  static String? dirOverride;

  static Future<String> _dir() async => dirOverride ?? await AppDir.path();

  static Future<File> _file() async => File('${await _dir()}/nm_call_settings.json');

  static Future<CallSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const CallSettings();
      final content = await file.readAsString();
      if (content.trim().isEmpty) return const CallSettings();
      return CallSettings.fromJson(Map<String, dynamic>.from(jsonDecode(content) as Map));
    } catch (_) {
      return const CallSettings();
    }
  }

  static Future<void> save(CallSettings settings) async {
    await writeAtomicFile(await _file(), jsonEncode(settings.toJson()));
  }

  /// فقط یک فیلد را در فایل به‌روز می‌کند (برای اسکنر سرویس، تا تنظیمات رابط را زیر پا نگذارد).
  static Future<void> update(CallSettings Function(CallSettings) change) async {
    final mutex = FileMutex('${await _dir()}/nm_call_settings.lock');
    await mutex.synchronized(() async {
      await save(change(await load()));
    });
  }
}
