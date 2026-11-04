import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/domain/recording_matcher.dart';
import 'package:nm_mobile/features/calls/services/recording_source.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

enum UploadResult {
  /// فایل رفت و پردازش شروع شد
  uploaded,

  /// رضایتِ ضبط نیست یا کاربر ندادن؛ هیچ فایلی ارسال نشد
  noConsent,

  /// فایل خوانده نشد
  unreadable,

  /// سرور نپذیرفت یا خطا
  failed,
}

class UploadOutcome {
  const UploadOutcome(this.result, [this.message = '']);

  final UploadResult result;
  final String message;
}

/// پیداکردنِ فایل‌های ضبط، وصل‌کردنشان به تماس‌ها و ارسال به NM.
///
/// قانون رضایت (همان قانون NM): **بدون رضایتِ ثبت‌شدهٔ این شماره هیچ فایلی ارسال نمی‌شود.**
/// ارسال همیشه صریح است (دکمهٔ کاربر)؛ فقط اگر «ارسال خودکار» روشن باشد و رضایتِ آن شماره
/// قبلاً در NM ثبت شده باشد، خودکار می‌رود.
class RecordingCycle {
  RecordingCycle({
    required this.source,
    required this.api,
    required this.store,
    DateTime Function()? now,
    this.lookback = const Duration(hours: 36),
  }) : _now = now ?? DateTime.now;

  final CallRecordingSource source;
  final CallsApi api;
  final CallStateStore store;
  final DateTime Function() _now;
  final Duration lookback;

  /// فایل‌های تازه را پیدا می‌کند و به تماس‌های شناخته‌شده وصل می‌کند.
  /// تعداد فایل‌هایی که تازه به «در انتظار ارسال» اضافه شد را برمی‌گرداند.
  Future<int> scan() async {
    if (!await source.isConfigured()) return 0;
    final st = await store.load();
    final nowMs = _now().millisecondsSinceEpoch;
    final since = st.lastScanMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(st.lastScanMs).subtract(const Duration(minutes: 10))
        : _now().subtract(lookback);
    final files = await source.scan(since: since);
    final targets = st.recent
        .map((k) => MatchTarget(uid: k.uid, number: k.number, startedAt: k.startedAt, durationS: k.durationS))
        .toList();
    var added = 0;
    for (final f in files) {
      if (st.uploaded.contains(f.id) || st.pending.any((p) => p.uri == f.id)) continue;
      final m = bestMatch(f, targets);
      if (m == null) continue;
      st.pending.add(
        PendingRecording(
          uri: f.id,
          name: f.name,
          modified: f.modified,
          size: f.size,
          callUid: m.target.uid,
          number: m.target.number,
          note: m.numberMatched ? 'شماره و زمان جور است' : 'فقط زمان جور است',
        ),
      );
      added++;
    }
    st.lastScanMs = nowMs;
    await store.save(st);
    return added;
  }

  /// ارسال یک فایلِ در انتظار.
  /// [askConsent]: اگر رضایتِ ثبت‌شده نیست، از کاربر می‌پرسد («به طرف مقابل گفتید ضبط می‌شود و
  /// موافقت کرد؟»). متنِ «چطور رضایت گرفته شد» را برمی‌گرداند، یا null اگر کاربر نخواست.
  Future<UploadOutcome> upload(
    PendingRecording p, {
    required Future<String?> Function(String number) askConsent,
  }) async {
    try {
      final consent = await api.consent(p.number);
      if (!consent.granted) {
        final how = await askConsent(p.number);
        if (how == null || how.trim().isEmpty) {
          return const UploadOutcome(UploadResult.noConsent, 'رضایت ثبت نشد؛ فایل ارسال نشد.');
        }
        await api.grantConsent(p.number, how: 'verbal', obtainedHow: how.trim());
      }
    } on NmHttpException catch (e) {
      return UploadOutcome(UploadResult.failed, e.message);
    }

    final cand = RecordingCandidate(id: p.uri, name: p.name, modified: p.modified, size: p.size);
    final local = await source.materialize(cand);
    if (local == null) {
      return const UploadOutcome(UploadResult.unreadable, 'فایل ضبط خوانده نشد (دسترسی پوشه را دوباره بدهید).');
    }
    try {
      await api.uploadRecording(p.callUid, local);
    } on NmHttpException catch (e) {
      await source.release(local);
      if (e.code == 'no_consent') {
        return UploadOutcome(UploadResult.noConsent, e.message);
      }
      return UploadOutcome(UploadResult.failed, e.message);
    }
    await source.release(local);

    final st = await store.load();
    st.pending.removeWhere((x) => x.uri == p.uri);
    st.uploaded.add(p.uri);
    await store.save(st);
    return const UploadOutcome(UploadResult.uploaded);
  }

  /// ارسال خودکار: فقط فایل‌هایی که رضایتِ شمارهٔ آن‌ها همین الان در NM ثبت است.
  /// هرگز از کاربر نمی‌پرسد و رضایت نمی‌سازد.
  Future<int> autoUpload() async {
    final st = await store.load();
    var sent = 0;
    for (final p in List<PendingRecording>.of(st.pending)) {
      try {
        final consent = await api.consent(p.number);
        if (!consent.granted) continue;
      } on NmHttpException {
        continue;
      }
      final r = await upload(p, askConsent: (_) async => null);
      if (r.result == UploadResult.uploaded) sent++;
    }
    return sent;
  }

  /// کاربر نخواست این فایل ارسال شود.
  Future<void> dismiss(PendingRecording p) async {
    final st = await store.load();
    st.pending.removeWhere((x) => x.uri == p.uri);
    st.uploaded.add(p.uri);
    await store.save(st);
  }
}
