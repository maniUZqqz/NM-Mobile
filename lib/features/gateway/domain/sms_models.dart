import 'package:nm_mobile/core/nm/json_util.dart';

/// یک پیامک که NM به این گوشی سپرده تا بفرستد (پاسخ `sms/claim/`).
class ClaimedSms {
  const ClaimedSms({
    required this.uid,
    required this.to,
    required this.normalized,
    required this.body,
    required this.kind,
    this.simSlot,
    this.attempt = 1,
    this.leaseSeconds = 120,
  });

  factory ClaimedSms.fromJson(Map<String, dynamic> j) => ClaimedSms(
    uid: asStr(j['uid']),
    to: asStr(j['to']),
    normalized: asStr(j['normalized']),
    body: asStr(j['body']),
    kind: asStr(j['kind'], 'transactional'),
    simSlot: asIntN(j['sim_slot']),
    attempt: asIntN(j['attempt']) ?? 1,
    leaseSeconds: asIntN(j['lease_seconds']) ?? 120,
  );

  final String uid;
  final String to;
  final String normalized;
  final String body;

  /// otp | transactional | marketing
  final String kind;
  final int? simSlot;
  final int attempt;
  final int leaseSeconds;

  bool get valid => uid.isNotEmpty && to.isNotEmpty && body.isNotEmpty;
}

class ClaimResponse {
  const ClaimResponse({
    required this.messages,
    this.paused = false,
    this.limited,
    this.retryAfterS = 5,
    this.remainingHour,
    this.remainingDay,
  });

  factory ClaimResponse.fromJson(Map<String, dynamic> j) {
    final limits = asMap(j['limits']);
    return ClaimResponse(
      messages: asList(
        j['messages'],
      ).whereType<Map>().map((e) => ClaimedSms.fromJson(asMap(e))).toList(),
      paused: asBool(j['paused']),
      limited: asStrN(j['limited']),
      retryAfterS: asIntN(j['retry_after_s']) ?? 5,
      remainingHour: asIntN(limits['remaining_hour']),
      remainingDay: asIntN(limits['remaining_day']),
    );
  }

  final List<ClaimedSms> messages;
  final bool paused;

  /// null | hour | day
  final String? limited;
  final int retryAfterS;
  final int? remainingHour;
  final int? remainingDay;
}

/// تنظیماتی که سرور در `me/`، `pair/` و `heartbeat/` می‌دهد.
class NmSettings {
  const NmSettings({
    this.smsEnabled = true,
    this.forwardIncomingSms = false,
    this.callsUploadEnabled = true,
    this.asrEnabled = true,
    this.maxSmsPerHour = 120,
    this.maxSmsPerDay = 600,
    this.claimBatch = 5,
    this.pollIntervalS = 5,
  });

  factory NmSettings.fromJson(Map<String, dynamic> j) => NmSettings(
    smsEnabled: asBool(j['sms_enabled'], true),
    forwardIncomingSms: asBool(j['forward_incoming_sms']),
    callsUploadEnabled: asBool(j['calls_upload_enabled'], true),
    asrEnabled: asBool(j['asr_enabled'], true),
    maxSmsPerHour: asIntN(j['max_sms_per_hour']) ?? 120,
    maxSmsPerDay: asIntN(j['max_sms_per_day']) ?? 600,
    claimBatch: (asIntN(j['claim_batch']) ?? 5).clamp(1, 20),
    pollIntervalS: (asIntN(j['poll_interval_s']) ?? 5).clamp(2, 60),
  );

  final bool smsEnabled;
  final bool forwardIncomingSms;
  final bool callsUploadEnabled;
  final bool asrEnabled;
  final int maxSmsPerHour;
  final int maxSmsPerDay;
  final int claimBatch;
  final int pollIntervalS;
}
