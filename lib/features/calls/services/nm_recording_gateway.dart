import 'dart:io';

import 'package:nm_mobile/core/phone_util.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/domain/nm_call_models.dart';

/// آنچه خط لولهٔ ضبط‌ها از NM لازم دارد (برای تست با نسخهٔ جعلی عوض می‌شود).
///
/// مسیر: لاگِ تماس در NM ثبت شده ⇒ [resolveCallUid] ⇒ دروازهٔ رضایت ([consent]) ⇒ [upload]
/// ⇒ [detail] (چرخهٔ پرسش تا متن و یادداشت آماده شود). تبدیل به متن فقط در سرور NM است.
abstract class NmRecordingGateway {
  /// شناسهٔ تماسِ این ضبط در NM، یا null اگر هنوز لاگش به NM نرسیده.
  Future<String?> resolveCallUid(CallRecording recording);

  Future<ConsentInfo> consent(String number);

  Future<void> grantConsent(String number, String obtainedHow);

  /// خطای سرور به شکل NmHttpException پرتاب می‌شود (`no_consent` یعنی رضایت نیست).
  Future<void> upload(String callUid, File audio, {int? durationSeconds});

  Future<NmCall> detail(String callUid);
}

class CallsApiGateway implements NmRecordingGateway {
  CallsApiGateway(this.api, this.state);

  final CallsApi api;
  final CallStateStore state;

  @override
  Future<String?> resolveCallUid(CallRecording recording) async {
    final st = await state.load();
    return matchKnownCall(recording, st.recent)?.uid;
  }

  @override
  Future<ConsentInfo> consent(String number) => api.consent(number);

  @override
  Future<void> grantConsent(String number, String obtainedHow) async {
    await api.grantConsent(number, how: 'verbal', obtainedHow: obtainedHow);
  }

  @override
  Future<void> upload(String callUid, File audio, {int? durationSeconds}) async {
    await api.uploadRecording(callUid, audio.path, durationS: durationSeconds);
  }

  @override
  Future<NmCall> detail(String callUid) => api.detail(callUid);
}

/// تماسِ ثبت‌شده در NM که به این ضبط می‌خورد، یا null.
/// قاعده: اگر شمارهٔ ضبط معلوم است باید با شمارهٔ تماس یکی باشد؛ زمان هم باید جور باشد
/// (نزدیک‌ترین تماس برنده است).
KnownCall? matchKnownCall(CallRecording r, List<KnownCall> calls) {
  final want = r.number.isEmpty ? '' : numberTail(r.number, n: 9);
  KnownCall? best;
  var bestDiff = 1 << 40;
  for (final k in calls) {
    if (want.isNotEmpty && numberTail(k.number, n: 9) != want) continue;
    int diff;
    final started = r.callStartedAt;
    if (started != null) {
      diff = k.startedAt.difference(started).inSeconds.abs();
      if (diff > 180) continue;
    } else {
      // فقط زمان ضبط (پایانِ ضبط) را داریم: باید از شروع تماس تا ۳ دقیقه بعد از پایانش باشد
      final end = k.startedAt.add(Duration(seconds: k.durationS));
      if (r.recordedAt.isBefore(k.startedAt.subtract(const Duration(minutes: 1))) ||
          r.recordedAt.isAfter(end.add(const Duration(minutes: 3)))) {
        continue;
      }
      diff = r.recordedAt.difference(end).inSeconds.abs();
    }
    if (diff < bestDiff) {
      best = k;
      bestDiff = diff;
    }
  }
  return best;
}
