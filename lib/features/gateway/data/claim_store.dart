import 'dart:convert';
import 'dart:io';

import 'package:nm_mobile/core/storage/app_storage.dart';

/// وضعیتِ محلیِ یک پیامکِ گرفته‌شده از NM.
enum ClaimPhase { sending, sent, failed }

class ClaimRecord {
  ClaimRecord({
    required this.uid,
    required this.to,
    required this.attempt,
    required this.phase,
    required this.atMs,
    this.errorCode = '',
    this.error = '',
    this.parts = 1,
    this.reported = false,
    this.deliveredMask = 0,
    this.deliveryReported = false,
  });

  factory ClaimRecord.fromJson(Map<String, dynamic> j) => ClaimRecord(
    uid: (j['uid'] ?? '').toString(),
    to: (j['to'] ?? '').toString(),
    attempt: (j['attempt'] as num?)?.toInt() ?? 1,
    phase: ClaimPhase.values.firstWhere(
      (p) => p.name == j['phase'],
      orElse: () => ClaimPhase.failed,
    ),
    atMs: (j['atMs'] as num?)?.toInt() ?? 0,
    errorCode: (j['errorCode'] ?? '').toString(),
    error: (j['error'] ?? '').toString(),
    parts: (j['parts'] as num?)?.toInt() ?? 1,
    reported: j['reported'] == true,
    deliveredMask: (j['deliveredMask'] as num?)?.toInt() ?? 0,
    deliveryReported: j['deliveryReported'] == true,
  );

  final String uid;
  final String to;
  int attempt;
  ClaimPhase phase;
  int atMs;
  String errorCode;
  String error;
  int parts;

  /// نتیجهٔ sent/failed به NM گزارش شده؟
  bool reported;

  /// بخش‌هایی از پیامک که گزارش تحویل‌شان رسیده (بیت‌مَسک)
  int deliveredMask;
  bool deliveryReported;

  bool get allPartsDelivered {
    final need = parts < 1 ? 1 : parts;
    for (var i = 0; i < need; i++) {
      if ((deliveredMask & (1 << i)) == 0) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'to': to,
    'attempt': attempt,
    'phase': phase.name,
    'atMs': atMs,
    'errorCode': errorCode,
    'error': error,
    'parts': parts,
    'reported': reported,
    'deliveredMask': deliveredMask,
    'deliveryReported': deliveryReported,
  };
}

/// ذخیرهٔ پایدار: قبل از هر ارسال، وضعیت «در حال ارسال» اینجا نوشته می‌شود تا
/// با کِرش/ری‌استارت هیچ پیامکی دوبار فرستاده نشود.
abstract class ClaimStore {
  Future<ClaimRecord?> get(String uid);
  Future<void> put(ClaimRecord record);

  /// رکوردهایی که نتیجه‌شان هنوز به NM گزارش نشده، یا تحویلشان گزارش نشده.
  Future<List<ClaimRecord>> unreported();

  Future<void> prune({Duration keep = const Duration(days: 3)});
}

class MemoryClaimStore implements ClaimStore {
  final Map<String, ClaimRecord> _m = {};

  @override
  Future<ClaimRecord?> get(String uid) async => _m[uid];

  @override
  Future<void> put(ClaimRecord record) async => _m[record.uid] = record;

  @override
  Future<List<ClaimRecord>> unreported() async => _m.values
      .where(
        (r) =>
            !r.reported ||
            (r.phase == ClaimPhase.sent &&
                r.allPartsDelivered &&
                !r.deliveryReported &&
                r.deliveredMask != 0),
      )
      .toList();

  @override
  Future<void> prune({Duration keep = const Duration(days: 3)}) async {
    final limit = DateTime.now().subtract(keep).millisecondsSinceEpoch;
    _m.removeWhere(
      (_, r) => r.atMs < limit && (r.reported || r.phase == ClaimPhase.sending),
    );
  }
}

class FileClaimStore implements ClaimStore {
  FileClaimStore({this.dirOverride});

  final String? dirOverride;
  Map<String, ClaimRecord>? _cache;

  Future<File> _file() async =>
      File('${dirOverride ?? await AppDir.path()}/nm_sms_claims.json');

  Future<Map<String, ClaimRecord>> _load() async {
    final c = _cache;
    if (c != null) return c;
    final out = <String, ClaimRecord>{};
    try {
      final f = await _file();
      if (await f.exists()) {
        final text = await f.readAsString();
        if (text.trim().isNotEmpty) {
          final list = jsonDecode(text) as List;
          for (final e in list) {
            final r = ClaimRecord.fromJson(
              Map<String, dynamic>.from(e as Map),
            );
            if (r.uid.isNotEmpty) out[r.uid] = r;
          }
        }
      }
    } catch (_) {}
    _cache = out;
    return out;
  }

  Future<void> _flush() async {
    final m = _cache;
    if (m == null) return;
    final f = await _file();
    await writeAtomicFile(
      f,
      jsonEncode(m.values.map((r) => r.toJson()).toList()),
    );
  }

  @override
  Future<ClaimRecord?> get(String uid) async => (await _load())[uid];

  @override
  Future<void> put(ClaimRecord record) async {
    (await _load())[record.uid] = record;
    await _flush();
  }

  @override
  Future<List<ClaimRecord>> unreported() async {
    final mem = MemoryClaimStore();
    for (final r in (await _load()).values) {
      await mem.put(r);
    }
    return mem.unreported();
  }

  @override
  Future<void> prune({Duration keep = const Duration(days: 3)}) async {
    final m = await _load();
    final limit = DateTime.now().subtract(keep).millisecondsSinceEpoch;
    final before = m.length;
    m.removeWhere(
      (_, r) => r.atMs < limit && (r.reported || r.phase == ClaimPhase.sending),
    );
    if (m.length != before) await _flush();
  }
}
