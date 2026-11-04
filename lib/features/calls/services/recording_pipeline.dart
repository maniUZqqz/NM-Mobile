import 'dart:io';

import 'package:nm_mobile/features/calls/data/recording_repository.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/services/nm_recording_gateway.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

/// صفِ «ارسال به NM». هر ضبط مرحله‌به‌مرحله پیش می‌رود (ساختار و رفتارِ صف از پروژهٔ
/// SMS-and-call، با این تفاوت که تبدیل به متن **فقط در سرور NM** انجام می‌شود):
///
///  ۱) در صف ارسال (`queued`) ⇐ تماسِ این ضبط در NM پیدا می‌شود (لاگ تماس باید رسیده باشد)
///  ۲) **دروازهٔ رضایت**: رضایتِ ثبت‌شدهٔ آن شماره در NM نیست ⇒ `needsConsent` و هیچ فایلی
///     ارسال نمی‌شود تا کاربر صریحاً تأیید کند
///  ۳) آپلود (`calls/<uid>/recording/`) ⇐ `running` ⇐ پرسش از NM تا متن و یادداشتِ هوش مصنوعی
///     آماده شود (`done`)
///
/// خطای موقت (شبکه، ۵xx) با فاصلهٔ فزاینده دوباره امتحان می‌شود؛ خطای دائمی تا دخالت کاربر نه.
class RecordingPipeline {
  RecordingPipeline({
    required this.repository,
    required this.gateway,
    DateTime Function()? clock,
    this.maxAttempts = 6,
    this.retryDelays = const [
      Duration(minutes: 2),
      Duration(minutes: 10),
      Duration(minutes: 30),
      Duration(hours: 2),
      Duration(hours: 6),
    ],
    this.lease = const Duration(minutes: 15),
    this.pollEvery = const Duration(seconds: 20),
    this.pollGiveUp = const Duration(minutes: 45),
  }) : _clock = clock ?? DateTime.now;

  final RecordingRepository repository;
  final NmRecordingGateway gateway;
  final int maxAttempts;
  final List<Duration> retryDelays;

  /// ضبطی که بیش از این مدت «در حال ارسال» مانده، یعنی سرویس وسط کار مرده و دوباره صف می‌شود.
  final Duration lease;

  /// فاصلهٔ پرسش از NM برای آماده‌شدن متن.
  final Duration pollEvery;

  /// اگر NM بعد از این مدت هنوز تمام نکرده، دیگر نمی‌پرسیم (در تب «تماس‌های NM» دیده می‌شود).
  final Duration pollGiveUp;
  final DateTime Function() _clock;

  bool _isDue(CallRecording r, DateTime now) {
    if (r.permanentFailure) return false;
    final next = r.nextAttemptAt;
    switch (r.transcriptStatus) {
      case TranscriptStatus.queued:
        return r.hasAudio && (next == null || !next.isAfter(now));
      case TranscriptStatus.running:
        // ارسال‌شده و منتظر NM، یا وسط ارسال که سرویس مرده (مهلت lease تمام شده)
        return next != null && !next.isAfter(now);
      case TranscriptStatus.failed:
        return next != null && !next.isAfter(now);
      case TranscriptStatus.none:
      case TranscriptStatus.done:
        return false;
    }
  }

  /// کارهای سررسیدشده را (حداکثر [max] ضبط) پردازش می‌کند. تعداد پردازش‌شده‌ها را برمی‌گرداند.
  Future<int> processDue({int max = 3}) async {
    final now = _clock();
    final due = (await repository.all()).where((r) => _isDue(r, now)).toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    var processed = 0;
    for (final recording in due.take(max)) {
      await processOne(recording);
      processed++;
    }
    return processed;
  }

  /// نزدیک‌ترین زمانِ کار بعدی (برای تصمیم دربارهٔ بیدار ماندن سرویس).
  Future<DateTime?> nextDueAt() async {
    final now = _clock();
    DateTime? best;
    for (final r in await repository.all()) {
      if (r.permanentFailure) continue;
      DateTime? at;
      if (_isDue(r, now)) {
        at = now;
      } else if (r.transcriptStatus != TranscriptStatus.none && r.transcriptStatus != TranscriptStatus.done) {
        at = r.nextAttemptAt;
      }
      if (at != null && (best == null || at.isBefore(best))) best = at;
    }
    return best;
  }

  Future<void> processOne(CallRecording recording) async {
    final started = _clock();
    // «ادعا» کردن ضبط: اگر ایزولهٔ دیگری (سرویس یا رابط کاربری) همین الان رویش کار می‌کند، رد می‌شویم
    final claimed = await repository.claim(recording.id, now: started, lease: lease);
    if (claimed == null) return;
    try {
      if (claimed.uploadedAt != null && claimed.nmCallUid.isNotEmpty) {
        await _poll(claimed);
      } else {
        await _send(claimed);
      }
    } on NmHttpException catch (e) {
      if (e.status == 401) {
        // توکن لغو شده: صف را رها می‌کنیم؛ ضبط سر جایش می‌ماند
        await repository.update(
          claimed.id,
          (r) => r.copyWith(
            transcriptStatus: TranscriptStatus.queued,
            attempts: 0,
            nextAttemptAt: started.add(const Duration(minutes: 5)),
          ),
        );
        return;
      }
      await _fail(claimed, e.message, retryable: _transient(e));
    } catch (e) {
      await _fail(claimed, 'خطای غیرمنتظره: $e', retryable: true);
    }
  }

  bool _transient(NmHttpException e) => e.status == 0 || e.status >= 500 || e.status == 429 || e.status == 408;

  Future<void> _send(CallRecording current) async {
    if (current.number.trim().isEmpty) {
      await _fail(current, 'شمارهٔ این ضبط معلوم نیست؛ به هیچ تماسی در لاگ وصل نشده.', retryable: false);
      return;
    }
    final audio = File(current.audioPath);
    if (!current.hasAudio || !await audio.exists()) {
      await _fail(current, 'فایل صوتی پیدا نشد.', retryable: false);
      return;
    }

    // ۱) تماسِ این ضبط در NM
    final uid = current.nmCallUid.isNotEmpty ? current.nmCallUid : await gateway.resolveCallUid(current);
    if (uid == null || uid.isEmpty) {
      // لاگِ تماس هنوز به NM نرسیده (یا ضبط به تماسی وصل نشده)؛ بعداً دوباره
      await _fail(
        current,
        current.linked
            ? 'تماس هنوز در NM ثبت نشده؛ بعد از ارسال لاگ تماس دوباره امتحان می‌شود.'
            : 'این ضبط هنوز به تماسی در لاگ گوشی وصل نشده.',
        retryable: true,
      );
      return;
    }

    // ۲) دروازهٔ رضایت: بدون رضایتِ ثبت‌شده هیچ فایلی خوانده/فرستاده نمی‌شود
    final consent = await gateway.consent(current.number);
    if (!consent.granted) {
      await repository.update(
        current.id,
        (r) => r.copyWith(
          nmCallUid: uid,
          needsConsent: true,
          transcriptStatus: TranscriptStatus.none,
          transcriptError: '',
          clearNextAttempt: true,
          attempts: 0,
        ),
      );
      return;
    }

    // ۳) آپلود
    try {
      await gateway.upload(uid, audio, durationSeconds: current.durationMs > 0 ? current.durationMs ~/ 1000 : null);
    } on NmHttpException catch (e) {
      if (e.code == 'no_consent') {
        await repository.update(
          current.id,
          (r) => r.copyWith(
            nmCallUid: uid,
            needsConsent: true,
            transcriptStatus: TranscriptStatus.none,
            clearNextAttempt: true,
            attempts: 0,
          ),
        );
        return;
      }
      rethrow;
    }
    final now = _clock();
    await repository.update(
      current.id,
      (r) => r.copyWith(
        nmCallUid: uid,
        needsConsent: false,
        uploadedAt: now,
        transcriptStatus: TranscriptStatus.running,
        transcriptError: '',
        attempts: 0,
        nextAttemptAt: now.add(pollEvery),
        permanentFailure: false,
      ),
    );
  }

  /// پرسش از NM: متن و یادداشتِ هوش مصنوعی آماده شد؟
  Future<void> _poll(CallRecording current) async {
    final now = _clock();
    final call = await gateway.detail(current.nmCallUid);
    switch (call.status) {
      case 'ANALYSED':
        await repository.update(
          current.id,
          (r) => r.copyWith(
            transcriptStatus: TranscriptStatus.done,
            transcribedAt: now,
            transcriptProvider: 'nm',
            transcriptError: '',
            clearNextAttempt: true,
          ),
        );
        return;
      case 'FAILED':
        await repository.update(
          current.id,
          (r) => r.copyWith(
            transcriptStatus: TranscriptStatus.failed,
            transcriptError: call.error.isEmpty ? 'NM نتوانست این ضبط را پردازش کند.' : call.error,
            permanentFailure: true,
            clearNextAttempt: true,
          ),
        );
        return;
      default:
        break;
    }
    final since = current.uploadedAt ?? current.importedAt;
    final waited = now.difference(since);
    if ((call.status == 'TRANSCRIBED' && waited > const Duration(minutes: 3)) || waited > pollGiveUp) {
      // متن آماده است ولی تحلیل دیر شد (یا NM خیلی طول کشید): دیگر نمی‌پرسیم
      await repository.update(
        current.id,
        (r) => r.copyWith(
          transcriptStatus: call.status == 'TRANSCRIBED' ? TranscriptStatus.done : TranscriptStatus.failed,
          transcriptError: call.status == 'TRANSCRIBED' ? '' : 'NM هنوز پردازش را تمام نکرده؛ در تب «تماس‌های NM» ببینید.',
          transcriptProvider: 'nm',
          clearNextAttempt: true,
        ),
      );
      return;
    }
    await repository.update(
      current.id,
      (r) => r.copyWith(transcriptStatus: TranscriptStatus.running, attempts: 0, nextAttemptAt: now.add(pollEvery)),
    );
  }

  Future<void> _fail(CallRecording recording, String message, {required bool retryable}) async {
    final now = _clock();
    await repository.update(recording.id, (r) {
      // repository.claim() already counted this attempt
      final exhausted = r.attempts >= maxAttempts;
      final permanent = !retryable || exhausted;
      final delay = retryDelays[(r.attempts - 1).clamp(0, retryDelays.length - 1)];
      return r.copyWith(
        transcriptStatus: TranscriptStatus.failed,
        transcriptError: exhausted && retryable ? '$message (بعد از چند تلاش متوقف شد؛ دستی دوباره امتحان کنید)' : message,
        permanentFailure: permanent,
        nextAttemptAt: permanent ? null : now.add(delay),
        clearNextAttempt: permanent,
      );
    });
  }

  // ───────────────────────── کارهای صریحِ کاربر ─────────────────────────

  /// «ارسال به NM» (یا «دوباره تلاش»): شمارنده و خطا پاک می‌شود و ضبط به صف برمی‌گردد.
  /// دروازهٔ رضایت همچنان در [processOne] اجرا می‌شود.
  Future<void> requestSend(String id) async {
    await repository.update(
      id,
      (r) => r.copyWith(
        transcriptStatus: TranscriptStatus.queued,
        transcriptError: '',
        attempts: 0,
        permanentFailure: false,
        clearNextAttempt: true,
      ),
    );
  }

  /// کاربر تأیید کرد که طرف مقابل از ضبط باخبر بود و موافقت کرد: اول رضایت در NM ثبت می‌شود،
  /// بعد ضبط به صف می‌رود. [obtainedHow] توضیحِ «چطور رضایت گرفته شد» است (الزامی).
  Future<void> confirmConsentAndSend(String id, String obtainedHow) async {
    final r = await repository.get(id);
    if (r == null) return;
    if (obtainedHow.trim().isEmpty) {
      throw ArgumentError('obtainedHow is required');
    }
    await gateway.grantConsent(r.number, obtainedHow.trim());
    await repository.update(id, (x) => x.copyWith(needsConsent: false));
    await requestSend(id);
  }
}
