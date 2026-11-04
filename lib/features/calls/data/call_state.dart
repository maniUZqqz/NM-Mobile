import 'dart:convert';
import 'dart:io';

import 'package:nm_mobile/core/json_extra.dart';
import 'package:nm_mobile/core/storage/app_storage.dart';

/// تماسِ در جریان (از لحظهٔ زنگ تا پایان). سرویس پس‌زمینه می‌نویسد، UI می‌خواند.
class ActiveCall {
  ActiveCall({
    required this.session,
    required this.number,
    required this.direction,
    required this.startedAt,
    this.uid = '',
    this.display,
    this.known = false,
    this.answered = false,
    this.ended = false,
    this.endedAt,
  });

  factory ActiveCall.fromJson(Map<String, dynamic> j) => ActiveCall(
    session: (j['session'] as num?)?.toInt() ?? 0,
    number: (j['number'] ?? '').toString(),
    direction: (j['direction'] ?? 'in').toString(),
    startedAt: DateTime.tryParse((j['startedAt'] ?? '').toString()) ?? DateTime.now(),
    uid: (j['uid'] ?? '').toString(),
    display: j['display'] as String?,
    known: j['known'] == true,
    answered: j['answered'] == true,
    ended: j['ended'] == true,
    endedAt: DateTime.tryParse((j['endedAt'] ?? '').toString()),
  );

  final int session;
  String number;
  String direction;
  DateTime startedAt;
  String uid;
  String? display;
  bool known;
  bool answered;
  bool ended;
  DateTime? endedAt;

  Map<String, dynamic> toJson() => {
    'session': session,
    'number': number,
    'direction': direction,
    'startedAt': startedAt.toIso8601String(),
    'uid': uid,
    'display': display,
    'known': known,
    'answered': answered,
    'ended': ended,
    'endedAt': endedAt?.toIso8601String(),
  };
}

/// تماسی که لاگش به NM رفته و uid دارد (برای وصل‌کردنِ فایلِ ضبط).
class KnownCall {
  const KnownCall({required this.uid, required this.number, required this.startedAt, required this.durationS});

  factory KnownCall.fromJson(Map<String, dynamic> j) => KnownCall(
    uid: (j['uid'] ?? '').toString(),
    number: (j['number'] ?? '').toString(),
    startedAt: DateTime.tryParse((j['startedAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0),
    durationS: (j['durationS'] as num?)?.toInt() ?? 0,
  );

  final String uid;
  final String number;
  final DateTime startedAt;
  final int durationS;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'number': number,
    'startedAt': startedAt.toIso8601String(),
    'durationS': durationS,
  };
}

class CallState {
  CallState({
    this.active,
    this.lastLogMs = 0,
    this.lastLogSyncMs = 0,
    this.logDueAtMs = 0,
    this.nextTryMs = 0,
    List<KnownCall>? recent,
  }) : recent = recent ?? <KnownCall>[];

  factory CallState.fromJson(Map<String, dynamic> j) {
    final a = j['active'];
    return CallState(
      active: a is Map ? ActiveCall.fromJson(Map<String, dynamic>.from(a)) : null,
      lastLogMs: (j['lastLogMs'] as num?)?.toInt() ?? 0,
      lastLogSyncMs: (j['lastLogSyncMs'] as num?)?.toInt() ?? 0,
      logDueAtMs: (j['logDueAtMs'] as num?)?.toInt() ?? 0,
      nextTryMs: (j['nextTryMs'] as num?)?.toInt() ?? 0,
      recent: mapList(j['recent']).map(KnownCall.fromJson).toList(),
    );
  }

  ActiveCall? active;
  int lastLogMs;
  int lastLogSyncMs;
  int logDueAtMs;

  /// برای جلوگیری از فشار روی سرور پس از خطا
  int nextTryMs;
  final List<KnownCall> recent;

  Map<String, dynamic> toJson() => {
    'active': active?.toJson(),
    'lastLogMs': lastLogMs,
    'lastLogSyncMs': lastLogSyncMs,
    'logDueAtMs': logDueAtMs,
    'nextTryMs': nextTryMs,
    'recent': recent.map((e) => e.toJson()).toList(),
  };
}

abstract class CallStateStore {
  Future<CallState> load();
  Future<void> save(CallState state);
}

class MemoryCallStateStore implements CallStateStore {
  CallState state = CallState();

  @override
  Future<CallState> load() async => state;

  @override
  Future<void> save(CallState s) async => state = s;
}

class FileCallStateStore implements CallStateStore {
  FileCallStateStore({this.dirOverride});

  final String? dirOverride;

  Future<File> _file() async => File('${dirOverride ?? await AppDir.path()}/nm_call_state.json');

  @override
  Future<CallState> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return CallState();
      final text = await f.readAsString();
      if (text.trim().isEmpty) return CallState();
      return CallState.fromJson(Map<String, dynamic>.from(jsonDecode(text) as Map));
    } catch (_) {
      return CallState();
    }
  }

  @override
  Future<void> save(CallState s) async {
    final f = await _file();
    await writeAtomicFile(f, jsonEncode(s.toJson()));
  }
}
