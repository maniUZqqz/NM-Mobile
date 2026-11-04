import 'dart:convert';
import 'dart:io';

import 'package:nm_mobile/core/nm/json_util.dart';
import 'package:nm_mobile/core/storage/app_storage.dart';
import 'package:nm_mobile/features/gateway/services/stop_words.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// صفِ پایدارِ پیامک‌های دریافتیِ آمادهٔ ارسال (برای وقتی که شبکه قطع است).
abstract class PendingIncomingStore {
  Future<List<Map<String, dynamic>>> load();
  Future<void> save(List<Map<String, dynamic>> items);
}

class MemoryPendingStore implements PendingIncomingStore {
  List<Map<String, dynamic>> items = [];

  @override
  Future<List<Map<String, dynamic>>> load() async => List.of(items);

  @override
  Future<void> save(List<Map<String, dynamic>> v) async => items = List.of(v);
}

class FilePendingStore implements PendingIncomingStore {
  FilePendingStore({this.dirOverride});

  final String? dirOverride;

  Future<File> _file() async =>
      File('${dirOverride ?? await AppDir.path()}/nm_incoming_pending.json');

  @override
  Future<List<Map<String, dynamic>>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final text = await f.readAsString();
      if (text.trim().isEmpty) return [];
      return (jsonDecode(text) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<Map<String, dynamic>> items) async {
    final f = await _file();
    await writeAtomicFile(f, jsonEncode(items));
  }
}

class IncomingResult {
  const IncomingResult({
    this.uploaded = 0,
    this.skipped = 0,
    this.optOutsAdded = 0,
    this.failedTransient = false,
  });

  final int uploaded;

  /// پیامک‌های دریافتی که قانوناً/طبق تنظیم نباید بروند (و دور ریخته شدند).
  final int skipped;
  final int optOutsAdded;
  final bool failedTransient;
}

/// شناسهٔ پایدار برای جلوگیری از ثبت تکراری (FNV-1a روی فرستنده+زمان+متن).
String incomingClientId(String from, int atMs, String body) {
  var h = 0xcbf29ce484222325;
  for (final u in utf8.encode('$from|$atMs|$body')) {
    h ^= u;
    h = (h * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return 'in-${h.toRadixString(16)}';
}

/// قانون حریم خصوصی: پیامک‌های دریافتی **فقط** وقتی به NM می‌روند که
/// «ارسال پیامک‌های دریافتی» در NM روشن باشد، یا متن «لغو/stop» باشد.
class IncomingUploader {
  IncomingUploader({required this.http, required this.store, this.onStop});

  final NmHttp http;
  final PendingIncomingStore store;

  /// برای هر پیامکِ دریافتیِ «لغو/stop» (چه ارسال به NM روشن باشد چه نه) صدا زده می‌شود تا
  /// فرستنده در فهرست لغوِ محلیِ گوشی هم بیاید و کمپین‌های محلی دیگر به او پیام ندهند.
  final Future<void> Function(IncomingSms sms)? onStop;

  static bool shouldUpload(String body, {required bool forward}) =>
      forward || isStopWord(body);

  Future<IncomingResult> process(
    List<IncomingSms> fresh, {
    required bool forward,
  }) async {
    var skipped = 0;
    final batch = await store.load();
    for (final m in fresh) {
      if (isStopWord(m.body)) {
        final cb = onStop;
        if (cb != null) {
          try {
            await cb(m);
          } catch (_) {}
        }
      }
      if (!shouldUpload(m.body, forward: forward)) {
        skipped++;
        continue;
      }
      batch.add({
        'client_id': incomingClientId(
          m.from,
          m.at.millisecondsSinceEpoch,
          m.body,
        ),
        'from': m.from,
        'body': m.body,
        'received_at': m.at.toUtc().toIso8601String(),
        if (m.slot >= 0) 'sim_slot': m.slot,
      });
    }
    if (batch.isEmpty) return IncomingResult(skipped: skipped);

    var uploaded = 0;
    var optOuts = 0;
    var rest = List<Map<String, dynamic>>.of(batch);
    while (rest.isNotEmpty) {
      final chunk = rest.take(50).toList();
      try {
        final res = asMap(await http.postJson('sms/incoming/', {'messages': chunk}));
        uploaded += asIntN(res['accepted']) ?? 0;
        optOuts += asIntN(res['opt_outs_added']) ?? 0;
        rest = rest.skip(chunk.length).toList();
      } on NmHttpException catch (e) {
        if (e.status == 401 || e.status == 403) {
          await store.save(rest.take(300).toList());
          rethrow;
        }
        final transient = e.status == 0 || e.status >= 500 || e.status == 429;
        if (transient) {
          await store.save(rest.take(300).toList());
          return IncomingResult(
            uploaded: uploaded,
            skipped: skipped,
            optOutsAdded: optOuts,
            failedTransient: true,
          );
        }
        // خطای دائمی (۴xx): این دسته را دور می‌ریزیم تا صف گیر نکند
        rest = rest.skip(chunk.length).toList();
      }
    }
    await store.save(<Map<String, dynamic>>[]);
    return IncomingResult(
      uploaded: uploaded,
      skipped: skipped,
      optOutsAdded: optOuts,
    );
  }
}
