import 'dart:convert';
import 'dart:io';

import 'package:nm_mobile/core/storage/app_storage.dart';
import 'package:nm_mobile/features/calls/domain/recording_matcher.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// تنظیمات بخش ضبط تماس.
class CallSettings {
  CallSettings({this.treeUri = '', this.treeName = '', this.autoUpload = false});

  factory CallSettings.fromJson(Map<String, dynamic> j) => CallSettings(
    treeUri: (j['treeUri'] ?? '').toString(),
    treeName: (j['treeName'] ?? '').toString(),
    autoUpload: j['autoUpload'] == true,
  );

  String treeUri;
  String treeName;

  /// فقط برای شماره‌هایی که رضایت ضبطشان قبلاً در NM ثبت شده، خودکار بفرست.
  bool autoUpload;

  bool get hasFolder => treeUri.isNotEmpty;

  Map<String, dynamic> toJson() => {'treeUri': treeUri, 'treeName': treeName, 'autoUpload': autoUpload};
}

class CallSettingsStore {
  CallSettingsStore({this.dirOverride});

  final String? dirOverride;

  Future<File> _file() async => File('${dirOverride ?? await AppDir.path()}/nm_call_settings.json');

  Future<CallSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return CallSettings();
      final text = await f.readAsString();
      if (text.trim().isEmpty) return CallSettings();
      return CallSettings.fromJson(Map<String, dynamic>.from(jsonDecode(text) as Map));
    } catch (_) {
      return CallSettings();
    }
  }

  Future<void> save(CallSettings s) async {
    final f = await _file();
    await writeAtomicFile(f, jsonEncode(s.toJson()));
  }
}

/// منبعِ فایل‌های ضبط تماس. در فاز ۱ فقط یک منبع داریم (پوشهٔ ضبطِ خودِ گوشی از راه SAF)
/// و ماژولِ ضبط تماسِ پروژهٔ SMS-and-call می‌تواند بعداً همین رابط را پیاده کند.
///
/// صادقانه: اندروید ۱۰+ به برنامه‌های عادی اجازهٔ ضبط صدای تماس را نمی‌دهد؛ این منبع
/// فقط فایل‌هایی را می‌خواند که ضبط‌کنندهٔ داخلی گوشی ساخته است.
abstract class CallRecordingSource {
  String get id;

  Future<bool> isConfigured();

  /// فایل‌های صوتیِ تازه‌تر از [since].
  Future<List<RecordingCandidate>> scan({required DateTime since});

  /// فایل را به مسیرِ محلیِ قابل‌آپلود کپی می‌کند؛ ناموفق ⇒ null.
  Future<String?> materialize(RecordingCandidate c);

  /// فایل کپی‌شده را پاک می‌کند.
  Future<void> release(String localPath);
}

class SafFolderSource implements CallRecordingSource {
  SafFolderSource(this.settings);

  final CallSettingsStore settings;

  @override
  String get id => 'saf_folder';

  @override
  Future<bool> isConfigured() async => (await settings.load()).hasFolder;

  @override
  Future<List<RecordingCandidate>> scan({required DateTime since}) async {
    final s = await settings.load();
    if (!s.hasFolder) return const [];
    final files = await SmsBridge.listRecordings(tree: s.treeUri, since: since);
    return files
        .map((f) => RecordingCandidate(id: f.uri, name: f.name, modified: f.modified, size: f.size))
        .toList();
  }

  @override
  Future<String?> materialize(RecordingCandidate c) => SmsBridge.copyToCache(c.id, c.name);

  @override
  Future<void> release(String localPath) => SmsBridge.deleteCacheFile(localPath);
}
