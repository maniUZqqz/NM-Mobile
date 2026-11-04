import 'package:nm_mobile/core/nm/json_util.dart';

/// وضعیت‌هایی که سرور برای یک تماس می‌دهد.
const List<String> kCallStatuses = [
  'LOGGED',
  'NO_CONSENT',
  'UPLOADED',
  'TRANSCRIBING',
  'TRANSCRIBED',
  'ANALYSED',
  'FAILED',
];

String callStatusLabel(String s) {
  switch (s) {
    case 'LOGGED':
      return 'ثبت شد';
    case 'NO_CONSENT':
      return 'بدون رضایت ضبط';
    case 'UPLOADED':
      return 'ارسال شد';
    case 'TRANSCRIBING':
      return 'در حال تبدیل به متن';
    case 'TRANSCRIBED':
      return 'متن آماده است';
    case 'ANALYSED':
      return 'تحلیل شد';
    case 'FAILED':
      return 'خطا';
    default:
      return s.isEmpty ? 'نامشخص' : s;
  }
}

/// آیا پردازش سمت سرور هنوز ادامه دارد؟ (برای polling)
bool callStatusInProgress(String s) => s == 'UPLOADED' || s == 'TRANSCRIBING' || s == 'TRANSCRIBED';

String nmDirectionLabel(String d) {
  switch (d) {
    case 'in':
      return 'ورودی';
    case 'out':
      return 'خروجی';
    case 'missed':
      return 'بی‌پاسخ';
    case 'rejected':
      return 'ردشده';
    default:
      return d;
  }
}

class CallSegment {
  const CallSegment({required this.start, required this.end, required this.text});

  factory CallSegment.fromJson(Map<String, dynamic> j) => CallSegment(
    start: asDoubleN(j['start']) ?? 0,
    end: asDoubleN(j['end']) ?? 0,
    text: asStr(j['text']),
  );

  final double start;
  final double end;
  final String text;
}

/// یک تماس در NM (فهرست یا جزئیات).
class NmCall {
  const NmCall({
    required this.uid,
    required this.number,
    required this.normalized,
    required this.direction,
    this.startedAt,
    this.durationS,
    this.contactName,
    this.callerDisplay,
    this.callerKnown = false,
    required this.status,
    this.hasAudio = false,
    this.error = '',
    this.transcript = '',
    this.segments = const <CallSegment>[],
    this.asrEngine = '',
    this.summary = '',
    this.sentiment = '',
    this.objections = const <String>[],
    this.commitments = const <String>[],
    this.nextSteps = const <String>[],
  });

  factory NmCall.fromJson(Map<String, dynamic> j) {
    final caller = asMap(j['caller']);
    List<String> strings(dynamic v) =>
        asList(v).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    return NmCall(
      uid: asStr(j['uid']),
      number: asStr(j['number']),
      normalized: asStr(j['normalized']),
      direction: asStr(j['direction']),
      startedAt: asDate(j['started_at']),
      durationS: asIntN(j['duration_s']),
      contactName: asStrN(j['contact_name']),
      callerDisplay: asStrN(caller['display']),
      callerKnown: asBool(caller['known']),
      status: asStr(j['status'], 'LOGGED'),
      hasAudio: asBool(j['has_audio']),
      error: asStr(j['error']),
      transcript: asStr(j['transcript']),
      segments: asList(j['segments']).whereType<Map>().map((e) => CallSegment.fromJson(asMap(e))).toList(),
      asrEngine: asStr(j['asr_engine']),
      summary: asStr(j['summary']),
      sentiment: asStr(j['sentiment']),
      objections: strings(j['objections']),
      commitments: strings(j['commitments']),
      nextSteps: strings(j['next_steps']),
    );
  }

  final String uid;
  final String number;
  final String normalized;
  final String direction;
  final DateTime? startedAt;
  final int? durationS;
  final String? contactName;
  final String? callerDisplay;
  final bool callerKnown;
  final String status;
  final bool hasAudio;
  final String error;
  final String transcript;
  final List<CallSegment> segments;
  final String asrEngine;
  final String summary;
  final String sentiment;
  final List<String> objections;
  final List<String> commitments;
  final List<String> nextSteps;

  /// نامی که باید نشان داد: ابتدا آنچه NM می‌شناسد، بعد نامِ مخاطبِ گوشی.
  String? get displayName => callerDisplay ?? contactName;
}

/// رضایتِ ضبطِ یک شماره.
class ConsentInfo {
  const ConsentInfo({
    required this.number,
    required this.normalized,
    required this.granted,
    this.how,
    this.obtainedAt,
    this.source,
  });

  factory ConsentInfo.fromJson(Map<String, dynamic> j) => ConsentInfo(
    number: asStr(j['number']),
    normalized: asStr(j['normalized']),
    granted: asBool(j['granted']),
    how: asStrN(j['how']),
    obtainedAt: asDate(j['obtained_at']),
    source: asStrN(j['source']),
  );

  final String number;
  final String normalized;
  final bool granted;
  final String? how;
  final DateTime? obtainedAt;
  final String? source;
}

class LiveCall {
  const LiveCall({
    required this.uid,
    required this.normalized,
    this.display,
    this.known = false,
  });

  factory LiveCall.fromJson(Map<String, dynamic> j) {
    final caller = asMap(j['caller']);
    return LiveCall(
      uid: asStr(j['uid']),
      normalized: asStr(j['normalized']),
      display: asStrN(caller['display']),
      known: asBool(caller['known']),
    );
  }

  final String uid;
  final String normalized;
  final String? display;
  final bool known;
}

/// یک ردیف لاگ تماس که به NM فرستاده می‌شود.
class NmLogEntry {
  const NmLogEntry({
    required this.clientId,
    required this.number,
    required this.direction,
    required this.startedAt,
    required this.durationS,
    this.contactName,
  });

  final String clientId;
  final String number;
  final String direction;
  final DateTime startedAt;
  final int durationS;
  final String? contactName;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'number': number,
    'direction': direction,
    'started_at': startedAt.toUtc().toIso8601String(),
    'duration_s': durationS,
    'contact_name': contactName,
  };
}

/// نوع تماسِ لاگ اندروید ⇐ جهتِ قرارداد API.
String directionOfCallLogType(int type) {
  switch (type) {
    case 1:
      return 'in';
    case 2:
      return 'out';
    case 3:
      return 'missed';
    case 5:
    case 6:
      return 'rejected';
    default:
      return 'in';
  }
}
