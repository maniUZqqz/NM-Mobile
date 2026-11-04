import 'package:nm_mobile/core/nm/json_util.dart';
import 'package:nm_mobile/features/calls/domain/nm_call_models.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

/// آپلود فایل (در برنامه NmClient.postMultipart؛ در تست یک جعلی).
typedef MultipartUpload =
    Future<dynamic> Function(
      String path, {
      required Map<String, String> fields,
      required String filePath,
    });

/// دسترسی به بخش «تماس‌ها» ی API ِ NM.
class CallsApi {
  CallsApi(this.http, {this.upload});

  final NmHttp http;
  final MultipartUpload? upload;

  Future<List<NmCall>> list({String? number, String? status, int limit = 30, int offset = 0}) async {
    final data = await http.getJson(
      'calls/',
      query: {
        'limit': '$limit',
        'offset': '$offset',
        if (number != null && number.isNotEmpty) 'number': number,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    return asList(asMap(data)['results']).whereType<Map>().map((e) => NmCall.fromJson(asMap(e))).toList();
  }

  Future<NmCall> detail(String uid) async {
    final data = await http.getJson('calls/$uid/');
    return NmCall.fromJson(asMap(data));
  }

  /// ثبتِ تماس هنگام زنگ خوردن/گرفتن (پیش از آن‌که لاگ سیستم بسازدش).
  Future<LiveCall> live({
    required String number,
    required String direction,
    required DateTime startedAt,
  }) async {
    final data = await http.postJson('calls/live/', {
      'number': number,
      'direction': direction,
      'started_at': startedAt.toUtc().toIso8601String(),
      'client_id': null,
    });
    return LiveCall.fromJson(asMap(data));
  }

  /// آپلود دستهٔ ردیف‌های لاگ تماس؛ برای هر client_id همان uid ِ NM برمی‌گردد.
  Future<Map<String, String>> logCalls(List<NmLogEntry> rows) async {
    if (rows.isEmpty) return const <String, String>{};
    final data = await http.postJson('calls/log/', {
      'calls': rows.map((e) => e.toJson()).toList(),
    });
    final out = <String, String>{};
    for (final r in asList(asMap(data)['results']).whereType<Map>()) {
      final m = asMap(r);
      final cid = asStr(m['client_id']);
      final uid = asStr(m['uid']);
      if (cid.isNotEmpty && uid.isNotEmpty) out[cid] = uid;
    }
    return out;
  }

  Future<ConsentInfo> consent(String number) async {
    final data = await http.getJson('calls/consent/', query: {'number': number});
    return ConsentInfo.fromJson(asMap(data));
  }

  /// ثبتِ رضایتِ ضبط: how = verbal | written | contract
  Future<ConsentInfo> grantConsent(
    String number, {
    String how = 'verbal',
    required String obtainedHow,
  }) async {
    final data = await http.postJson('calls/consent/', {
      'number': number,
      'granted': true,
      'how': how,
      'obtained_how': obtainedHow,
    });
    return ConsentInfo.fromJson(asMap(data));
  }

  Future<void> revokeConsent(String number) async {
    await http.postJson('calls/consent/revoke/', {'number': number});
  }

  /// آپلودِ ضبط. اگر رضایت ثبت نباشد سرور ۴۰۳ ‹no_consent› می‌دهد (NmHttpException).
  Future<NmCall> uploadRecording(
    String callUid,
    String filePath, {
    String source = 'builtin_recorder',
    int? durationS,
  }) async {
    final up = upload;
    if (up == null) {
      throw NmHttpException(0, 'no_upload', 'آپلود فایل در این حالت در دسترس نیست.');
    }
    final data = await up(
      'calls/$callUid/recording/',
      fields: {'source': source, if (durationS != null) 'duration_s': '$durationS'},
      filePath: filePath,
    );
    final m = asMap(data);
    return NmCall(
      uid: asStr(m['uid'], callUid),
      number: '',
      normalized: '',
      direction: '',
      status: asStr(m['status'], 'UPLOADED'),
    );
  }

  Future<void> reprocess(String callUid) async {
    await http.postJson('calls/$callUid/reprocess/', <String, dynamic>{});
  }
}
