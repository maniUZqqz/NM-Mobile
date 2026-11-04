import 'package:nm_mobile/core/nm/json_util.dart';
import 'package:nm_mobile/features/gateway/data/claim_store.dart';
import 'package:nm_mobile/features/gateway/domain/sms_models.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// ارسال‌کنندهٔ پیامک (در برنامه SmsBridge.sendSms؛ در تست یک جعلی).
typedef SmsSender =
    Future<SmsSendResult> Function({
      required String to,
      required String message,
      required int subId,
      required String? ref,
      required bool delivery,
    });

/// انتخابِ شناسهٔ سیم‌کارت برای یک پیامک (simSlot از سرور، یا null).
typedef SubPicker = Future<int> Function(int? simSlot);

/// رویدادهای خط لوله، برای ساختنِ لاگ در سرویس پس‌زمینه.
class PipelineEvent {
  const PipelineEvent(
    this.type, {
    this.sms,
    this.uid = '',
    this.detail = '',
    this.result,
  });

  /// claimed | duplicate | sending | sent | failed | reported | report_failed |
  /// delivered | paused | limited
  final String type;
  final ClaimedSms? sms;

  /// شناسهٔ پیامک در NM (برای رویدادهایی که sms ندارند، مثل reported)
  final String uid;
  final String detail;
  final SmsSendResult? result;
}

/// کدی که به NM گزارش می‌شود (مطابق قرارداد: no_service|generic|radio_off|null_pdu|…).
String smsErrorCode(SmsSendResult r) {
  switch (r.code) {
    case -100:
      return 'timeout';
    case -101:
      return 'sim_inactive';
    case -103:
      return 'no_permission';
    case -104:
      return 'no_telephony';
    case -105:
      return 'bad_input';
    case -106:
      return 'plugin_missing';
    case 1:
      return 'generic';
    case 2:
      return 'radio_off';
    case 3:
      return 'null_pdu';
    case 4:
      return 'no_service';
    case 5:
      return 'limit_exceeded';
    case 7:
    case 8:
      return 'short_code';
    default:
      return 'generic';
  }
}

/// «گرفتن از NM ⇐ ذخیره روی گوشی ⇐ فرستادن ⇐ گزارش» بدون هیچ وابستگی به UI.
///
/// قواعد ایمنی:
///  * شناسهٔ پیامک **قبل** از فراخوانی SMS روی دیسک نوشته می‌شود (phase=sending)؛
///  * اگر همان شناسه با همان attempt دوباره آمد و ما فقط «sending» داریم، نتیجه
///    نامعلوم است ⇒ دوباره نمی‌فرستیم و «failed/unknown_after_restart» گزارش می‌کنیم؛
///  * فقط وقتی سرور attempt بزرگ‌تری بدهد (خودش دوباره صف کرده) دوباره می‌فرستیم؛
///  * اگر «sent» داریم ولی گزارش نشده، فقط گزارش می‌کنیم (ارسال دوباره نه)؛
///  * گزارش ناموفق (شبکه) بعداً دوباره امتحان می‌شود.
class SmsPipeline {
  SmsPipeline({
    required this.http,
    required this.sender,
    required this.store,
    required this.pickSub,
    this.onEvent,
    this.deliveryReports = true,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final NmHttp http;
  final SmsSender sender;
  final ClaimStore store;
  final SubPicker pickSub;
  final void Function(PipelineEvent event)? onEvent;
  final bool deliveryReports;
  final DateTime Function() _now;

  void _emit(
    String type, {
    ClaimedSms? sms,
    String? uid,
    String detail = '',
    SmsSendResult? result,
  }) {
    final cb = onEvent;
    if (cb != null) {
      cb(
        PipelineEvent(
          type,
          sms: sms,
          uid: uid ?? sms?.uid ?? '',
          detail: detail,
          result: result,
        ),
      );
    }
  }

  /// یک دور: گزارش‌های عقب‌افتاده ⇐ گرفتن ⇐ ارسال و گزارش هر پیامک.
  /// خطای شبکه/سرور برای `sms/claim/` به بالا می‌رسد (موتور خودش تصمیم می‌گیرد).
  Future<ClaimResponse> tick({int max = 5, int? simSlot}) async {
    await flushReports();
    final raw = await http.postJson('sms/claim/', {
      'max': max,
      if (simSlot != null) 'sim_slot': simSlot,
    });
    final res = ClaimResponse.fromJson(asMap(raw));
    if (res.paused) _emit('paused');
    if (res.limited != null) _emit('limited', detail: res.limited!);
    for (final m in res.messages) {
      if (!m.valid) continue;
      await _handle(m);
    }
    await store.prune();
    return res;
  }

  /// گزارش‌هایی که قبلاً به خاطر قطعی شبکه نرفته بودند.
  Future<void> flushReports() async {
    final pending = await store.unreported();
    for (final r in pending) {
      // phase=sending ⇒ نتیجهٔ ارسال نامعلوم است؛ هرگز «sent» گزارش نمی‌کنیم.
      // سرور یا دوباره صف می‌کند (attempt بزرگ‌تر) یا با lease خودش تمامش می‌کند.
      if (r.phase == ClaimPhase.sending) continue;
      if (!r.reported) {
        await _reportResult(r);
      }
      if (r.phase == ClaimPhase.sent &&
          r.allPartsDelivered &&
          r.deliveredMask != 0 &&
          !r.deliveryReported) {
        await _reportDelivered(r);
      }
    }
  }

  Future<void> _handle(ClaimedSms m) async {
    _emit('claimed', sms: m);
    final rec = await store.get(m.uid);

    if (rec != null) {
      if (rec.phase == ClaimPhase.sent || rec.phase == ClaimPhase.failed) {
        // قبلاً تصمیم گرفته شده؛ فقط گزارش را تکرار می‌کنیم (idempotent).
        _emit('duplicate', sms: m, detail: 'قبلاً ${rec.phase.name} شده بود');
        if (m.attempt > rec.attempt && rec.phase == ClaimPhase.failed) {
          // سرور خودش دوباره صف کرده؛ یک تلاش تازه
          await _sendFresh(m);
          return;
        }
        rec.reported = false;
        await _reportResult(rec);
        return;
      }
      // phase == sending
      if (m.attempt <= rec.attempt) {
        rec
          ..phase = ClaimPhase.failed
          ..errorCode = 'unknown_after_restart'
          ..error = 'برنامه وسط ارسال بسته شد؛ معلوم نیست پیامک رفته یا نه'
          ..reported = false
          ..atMs = _now().millisecondsSinceEpoch;
        await store.put(rec);
        _emit('duplicate', sms: m, detail: 'نتیجهٔ ارسال قبلی نامعلوم؛ دوباره نفرستادیم');
        await _reportResult(rec);
        return;
      }
    }
    await _sendFresh(m);
  }

  Future<void> _sendFresh(ClaimedSms m) async {
    final digits = RegExp(r'\d').allMatches(m.to).length;
    final rec = ClaimRecord(
      uid: m.uid,
      to: m.to,
      attempt: m.attempt,
      phase: ClaimPhase.sending,
      atMs: _now().millisecondsSinceEpoch,
    );
    if (digits < 5) {
      rec
        ..phase = ClaimPhase.failed
        ..errorCode = 'bad_number'
        ..error = 'شمارهٔ گیرنده نامعتبر است';
      await store.put(rec);
      _emit('failed', sms: m, detail: rec.error);
      await _reportResult(rec);
      return;
    }

    // ۱) اول روی دیسک، ۲) بعد ارسال
    await store.put(rec);
    _emit('sending', sms: m);

    SmsSendResult r;
    try {
      final subId = await pickSub(m.simSlot);
      r = await sender(
        to: m.to,
        message: m.body,
        subId: subId,
        ref: m.uid,
        delivery: deliveryReports,
      );
    } catch (e) {
      r = SmsSendResult.failure(-102, e.toString());
    }

    rec.atMs = _now().millisecondsSinceEpoch;
    rec.parts = r.parts < 1 ? 1 : r.parts;
    if (r.ok) {
      rec
        ..phase = ClaimPhase.sent
        ..errorCode = ''
        ..error = '';
      await store.put(rec);
      _emit('sent', sms: m, result: r);
    } else {
      rec
        ..phase = ClaimPhase.failed
        ..errorCode = smsErrorCode(r)
        ..error = r.error.isNotEmpty ? r.error : 'کد خطا ${r.code}';
      await store.put(rec);
      _emit('failed', sms: m, detail: rec.error, result: r);
    }
    await _reportResult(rec);
  }

  /// گزارش sent/failed به NM. خطای موقت (شبکه، ۵xx، ۴۲۹) ⇒ بعداً دوباره؛
  /// خطای دائمی (۴xx مثل «لغو شده») ⇒ تمام شده حساب می‌شود؛ ۴۰۱/۴۰۳ به بالا می‌رسد.
  Future<void> _reportResult(ClaimRecord r) async {
    final failed = r.phase == ClaimPhase.failed;
    try {
      await http.postJson('sms/${r.uid}/report/', {
        'state': failed ? 'failed' : 'sent',
        if (failed) 'error_code': r.errorCode,
        if (failed) 'error': r.error,
        'at': DateTime.fromMillisecondsSinceEpoch(r.atMs).toUtc().toIso8601String(),
        'parts': r.parts,
      });
      r.reported = true;
      await store.put(r);
      _emit('reported', uid: r.uid, detail: failed ? 'failed' : 'sent');
    } on NmHttpException catch (e) {
      if (e.status == 401 || e.status == 403) rethrow;
      final transient = e.status == 0 || e.status >= 500 || e.status == 429;
      if (!transient) {
        r.reported = true;
        await store.put(r);
        _emit('reported', uid: r.uid, detail: 'سرور نپذیرفت (${e.status}): ${e.message}');
      } else {
        _emit('report_failed', uid: r.uid, detail: e.message);
      }
    }
  }

  Future<void> _reportDelivered(ClaimRecord r) async {
    try {
      await http.postJson('sms/${r.uid}/report/', {
        'state': 'delivered',
        'at': _now().toUtc().toIso8601String(),
        'parts': r.parts,
      });
      r.deliveryReported = true;
      await store.put(r);
      _emit('delivered', uid: r.uid);
    } on NmHttpException catch (e) {
      if (e.status == 401 || e.status == 403) rethrow;
      final transient = e.status == 0 || e.status >= 500 || e.status == 429;
      if (!transient) {
        r.deliveryReported = true;
        await store.put(r);
      } else {
        _emit('report_failed', uid: r.uid, detail: e.message);
      }
    }
  }

  /// گزارش‌های تحویلِ رسیده از لایهٔ بومی. وقتی همهٔ بخش‌های یک پیامک تحویل شد،
  /// «delivered» گزارش می‌شود. گزارش‌های تحویلِ ناموفق فقط نادیده گرفته می‌شوند.
  Future<void> handleDelivery(List<DeliveryEvent> events) async {
    for (final ev in events) {
      if (ev.ref.isEmpty || !ev.delivered) continue;
      final rec = await store.get(ev.ref);
      if (rec == null || rec.phase != ClaimPhase.sent) continue;
      if (ev.part >= 0 && ev.part < 60) {
        rec.deliveredMask |= (1 << ev.part);
      }
      if (ev.total > rec.parts) rec.parts = ev.total;
      await store.put(rec);
      if (rec.allPartsDelivered && !rec.deliveryReported) {
        await _reportDelivered(rec);
      }
    }
  }
}
