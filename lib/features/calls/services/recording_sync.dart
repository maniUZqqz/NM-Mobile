import 'package:nm_mobile/features/calls/data/call_settings.dart';
import 'package:nm_mobile/features/calls/data/recording_repository.dart';
import 'package:nm_mobile/features/calls/services/nm_recording_gateway.dart';
import 'package:nm_mobile/features/calls/services/recording_pipeline.dart';
import 'package:nm_mobile/features/calls/services/recording_scanner.dart';

class RecordingSyncReport {
  const RecordingSyncReport({this.scan, this.processed = 0, this.nextDueAt, this.skipped = false});

  final ScanReport? scan;
  final int processed;

  /// اگر کاری مانده (مثلاً تلاش دوباره‌ی یک ارسال یا پرسش از NM)، زمان سررسید آن.
  final DateTime? nextDueAt;

  /// چرخه اجرا نشد (اطلاعیهٔ مسئولیت هنوز پذیرفته نشده یا چرخهٔ دیگری در جریان است).
  final bool skipped;
}

/// یک «چرخه»: ضبط‌های تازهٔ پوشهٔ ضبط‌کنندهٔ گوشی را پیدا و وارد کن ⇐ به تماس وصل کن ⇐ به NM بفرست
/// (با دروازهٔ رضایت) ⇐ از NM بپرس متن و یادداشت آماده شد؟ هم سرویس پس‌زمینه و هم صفحهٔ ضبط‌ها
/// همین را اجرا می‌کنند. (ساختار از SMS-and-call؛ تبدیل به متن و ارسال به سرورِ دلخواه حذف شده.)
class RecordingSync {
  RecordingSync({
    required this.gateway,
    CallPlatform? platform,
    RecordingRepository? repository,
    this.timeBudget = const Duration(minutes: 8),
    DateTime Function()? clock,
  }) : platform = platform ?? const SmsBridgeCallPlatform(),
       repository = repository ?? RecordingRepository(),
       _clock = clock;

  final NmRecordingGateway gateway;
  final CallPlatform platform;
  final RecordingRepository repository;

  /// بیشینه‌ی زمانی که یک چرخه‌ی پردازش صف می‌تواند ادامه دهد.
  final Duration timeBudget;

  /// فقط برای تست
  final DateTime Function()? _clock;

  static bool _running = false;
  static bool get isRunning => _running;

  Future<RecordingSyncReport> run({bool scan = true, bool process = true}) async {
    if (_running) return const RecordingSyncReport(skipped: true);
    _running = true;
    try {
      var settings = await CallSettingsStorage.load();
      // بدون پذیرفتنِ اطلاعیهٔ مسئولیتِ ضبط هیچ کاری نمی‌کنیم
      if (!settings.consentAccepted) return const RecordingSyncReport(skipped: true);

      ScanReport? report;
      if (scan && settings.watchPhoneRecorder) {
        final scanner = RecordingScanner(platform: platform, repository: repository, settings: () => settings, clock: _clock);
        report = await scanner.scan();
        final safe = report.safeUntil;
        if (safe != null) {
          await CallSettingsStorage.update((current) => current.copyWith(lastScanAtMillis: safe.millisecondsSinceEpoch));
          settings = await CallSettingsStorage.load();
        }
      }

      var processed = 0;
      DateTime? next;
      if (process) {
        final pipeline = RecordingPipeline(repository: repository, gateway: gateway, clock: _clock);
        final deadline = DateTime.now().add(timeBudget);
        while (DateTime.now().isBefore(deadline)) {
          final count = await pipeline.processDue(max: 1);
          if (count == 0) break;
          processed += count;
        }
        next = await pipeline.nextDueAt();
      }
      return RecordingSyncReport(scan: report, processed: processed, nextDueAt: next);
    } finally {
      _running = false;
    }
  }
}
