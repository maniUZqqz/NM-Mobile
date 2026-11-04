import 'dart:math';

import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/domain/nm_call_models.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:sms_bridge/sms_bridge.dart';

typedef DrainCallEvents = Future<List<CallEvent>> Function();
typedef ReadCallLog = Future<List<RawCallLogEntry>> Function({required DateTime since, required int limit});

/// منطق سرویس پس‌زمینه برای تماس‌ها (بدون وابستگی به UI و قابل تست):
///  ۱) رویدادهای زنگ/گرفتن/پایان را می‌خواند و تماس را فوراً در NM ثبت می‌کند (`calls/live/`)؛
///  ۲) بعد از پایان تماس (و هر ۱۰ دقیقه) لاگ تماس گوشی را به NM می‌فرستد (`calls/log/`).
/// هیچ صدایی ضبط نمی‌شود.
class NmCallCycle {
  NmCallCycle({
    required this.api,
    required this.store,
    required this.drain,
    required this.readLog,
    DateTime Function()? now,
    this.logDelay = const Duration(seconds: 6),
    this.syncEvery = const Duration(minutes: 10),
    this.retryAfter = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final CallsApi api;
  final CallStateStore store;
  final DrainCallEvents drain;
  final ReadCallLog readLog;
  final DateTime Function() _now;
  final Duration logDelay;
  final Duration syncEvery;
  final Duration retryAfter;

  Future<CallState> process() async {
    final st = await store.load();
    var changed = false;

    final events = await drain();
    for (final ev in events) {
      if (_onEvent(st, ev)) changed = true;
    }

    final a = st.active;
    if (a != null && !a.ended && a.uid.isEmpty && a.number.isNotEmpty) {
      if (await _register(st, a)) changed = true;
    }

    final nowMs = _now().millisecondsSinceEpoch;
    final callOngoing = a != null && !a.ended;
    final due = (st.logDueAtMs != 0 && nowMs >= st.logDueAtMs) || (nowMs - st.lastLogSyncMs >= syncEvery.inMilliseconds);
    if (due && !callOngoing && nowMs >= st.nextTryMs) {
      if (await _syncLog(st)) changed = true;
    }

    if (changed) await store.save(st);
    return st;
  }

  bool _onEvent(CallState st, CallEvent ev) {
    final nowMs = _now().millisecondsSinceEpoch;
    switch (ev.type) {
      case 'ring':
      case 'dial':
        final a = st.active;
        if (a == null || a.session != ev.session) {
          st.active = ActiveCall(
            session: ev.session,
            number: ev.number,
            direction: ev.direction.isEmpty ? (ev.type == 'dial' ? 'out' : 'in') : ev.direction,
            startedAt: ev.at,
          );
          return true;
        }
        if (ev.number.isNotEmpty && a.number != ev.number) {
          a.number = ev.number;
          a.uid = '';
          return true;
        }
        return false;
      case 'answered':
        final a = st.active;
        if (a != null && a.session == ev.session && !a.answered) {
          a.answered = true;
          return true;
        }
        return false;
      case 'ended':
        final a = st.active;
        if (a != null && a.session == ev.session && !a.ended) {
          a.ended = true;
          a.endedAt = ev.at;
          st.logDueAtMs = nowMs + logDelay.inMilliseconds;
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  /// ثبتِ تماسِ زنده در NM. خطای شبکه/سرور بی‌صدا رد می‌شود (دور بعد دوباره)؛ ۴۰۱ به بالا می‌رسد.
  Future<bool> _register(CallState st, ActiveCall a) async {
    try {
      final live = await api.live(number: a.number, direction: a.direction, startedAt: a.startedAt);
      a.uid = live.uid;
      a.display = live.display;
      a.known = live.known;
      return true;
    } on NmHttpException catch (e) {
      if (e.status == 401) rethrow;
      return false;
    }
  }

  Future<bool> _syncLog(CallState st) async {
    final nowMs = _now().millisecondsSinceEpoch;
    final since = st.lastLogMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(st.lastLogMs)
        : _now().subtract(const Duration(hours: 24));
    final rows = (await readLog(since: since, limit: 100)).where((r) => r.number.trim().isNotEmpty).toList();
    if (rows.isEmpty) {
      st.lastLogSyncMs = nowMs;
      st.logDueAtMs = 0;
      return true;
    }
    final entries = rows
        .map(
          (r) => NmLogEntry(
            clientId: 'cl-${r.id}',
            number: r.number,
            direction: directionOfCallLogType(r.type),
            startedAt: DateTime.fromMillisecondsSinceEpoch(r.startedAtMillis),
            durationS: r.durationSeconds,
            contactName: r.name.isEmpty ? null : r.name,
          ),
        )
        .toList();
    try {
      final byClient = <String, String>{};
      for (var i = 0; i < entries.length; i += 50) {
        byClient.addAll(await api.logCalls(entries.sublist(i, min(i + 50, entries.length))));
      }
      var newest = st.lastLogMs;
      for (final r in rows) {
        newest = max(newest, r.startedAtMillis);
        final uid = byClient['cl-${r.id}'];
        if (uid != null && !st.recent.any((k) => k.uid == uid)) {
          st.recent.add(KnownCall(uid: uid, number: r.number, startedAt: DateTime.fromMillisecondsSinceEpoch(r.startedAtMillis), durationS: r.durationSeconds));
        }
      }
      st.recent.sort((x, y) => y.startedAt.compareTo(x.startedAt));
      if (st.recent.length > 60) st.recent.removeRange(60, st.recent.length);
      st.lastLogMs = newest;
      st.lastLogSyncMs = nowMs;
      st.logDueAtMs = 0;
      return true;
    } on NmHttpException catch (e) {
      if (e.status == 401) rethrow;
      st.nextTryMs = nowMs + retryAfter.inMilliseconds;
      return true;
    }
  }
}
