import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/domain/nm_call_models.dart';
import 'package:nm_mobile/features/calls/services/nm_call_cycle.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:sms_bridge/sms_bridge.dart';

import 'support/helpers.dart';

CallEvent _ev(String type, {String number = '09121234567', String dir = 'in', int session = 1, DateTime? at}) =>
    CallEvent(type: type, number: number, direction: dir, session: session, at: at ?? DateTime(2026, 11, 4, 10, 0, 0));

void main() {
  group('NmCallCycle', () {
    NmCallCycle build({
      required FakeNmHttp nm,
      required MemoryCallStateStore store,
      required List<CallEvent> events,
      List<RawCallLogEntry> log = const [],
      DateTime? now,
    }) {
      return NmCallCycle(
        api: CallsApi(nm),
        store: store,
        drain: () async {
          final out = List<CallEvent>.of(events);
          events.clear();
          return out;
        },
        readLog: ({required since, required limit}) async => log,
        now: () => now ?? DateTime(2026, 11, 4, 10, 5, 0),
      );
    }

    test('a ringing call is registered in NM right away and becomes the active call', () async {
      final nm = FakeNmHttp((m, p, b) async {
        if (p == 'calls/live/') {
          return {
            'uid': 'call-1',
            'created': true,
            'normalized': '989121234567',
            'caller': {'display': 'علی رضایی', 'known': true},
          };
        }
        return <String, dynamic>{};
      });
      final store = MemoryCallStateStore();
      final cycle = build(nm: nm, store: store, events: [_ev('ring')]);
      final st = await cycle.process();
      expect(nm.calls, contains('POST calls/live/'));
      final body = nm.payloads[nm.calls.indexOf('POST calls/live/')] as Map;
      expect(body['number'], '09121234567');
      expect(body['direction'], 'in');
      expect(st.active!.uid, 'call-1');
      expect(st.active!.display, 'علی رضایی');
      expect(st.active!.ended, isFalse);
    });

    test('a failed registration is retried on the next cycle, not lost', () async {
      var fail = true;
      final nm = FakeNmHttp((m, p, b) async {
        if (p == 'calls/live/') {
          if (fail) throw NmHttpException(0, 'network', 'قطع');
          return {'uid': 'call-2', 'caller': {'known': false}};
        }
        return <String, dynamic>{};
      });
      final store = MemoryCallStateStore();
      final events = [_ev('ring')];
      final cycle = build(nm: nm, store: store, events: events);
      var st = await cycle.process();
      expect(st.active!.uid, isEmpty);
      fail = false;
      st = await cycle.process();
      expect(st.active!.uid, 'call-2');
    });

    test('the same ring seen twice does not register two calls', () async {
      final nm = FakeNmHttp((m, p, b) async => {'uid': 'c', 'caller': {}});
      final store = MemoryCallStateStore();
      final events = [_ev('ring'), _ev('ring')];
      final cycle = build(nm: nm, store: store, events: events);
      await cycle.process();
      expect(nm.calls.where((c) => c == 'POST calls/live/').length, 1);
    });

    test('when the call ends the call log is sent and the call becomes known for recordings', () async {
      final nm = FakeNmHttp((m, p, b) async {
        if (p == 'calls/live/') return {'uid': 'call-3', 'caller': {}};
        if (p == 'calls/log/') {
          return {
            'results': [
              {'client_id': 'cl-77', 'uid': 'call-3', 'created': false},
            ],
          };
        }
        return <String, dynamic>{};
      });
      final store = MemoryCallStateStore();
      final events = [_ev('ring')];
      var now = DateTime(2026, 11, 4, 10, 2, 0);
      // the periodic sync is not due; only the end of the call triggers it
      store.state.lastLogSyncMs = now.millisecondsSinceEpoch;
      final cycle = NmCallCycle(
        api: CallsApi(nm),
        store: store,
        drain: () async {
          final out = List<CallEvent>.of(events);
          events.clear();
          return out;
        },
        readLog: ({required since, required limit}) async => [
          RawCallLogEntry(id: 77, number: '09121234567', type: 1, startedAtMillis: DateTime(2026, 11, 4, 10, 0, 0).millisecondsSinceEpoch, durationSeconds: 95, name: ''),
        ],
        now: () => now,
      );
      await cycle.process(); // ring -> registered live
      events.addAll([_ev('answered'), _ev('ended')]);
      await cycle.process(); // ended -> log due in a few seconds
      expect(nm.calls.contains('POST calls/log/'), isFalse);
      now = now.add(const Duration(seconds: 30));
      final st = await cycle.process();
      expect(nm.calls.contains('POST calls/log/'), isTrue);
      final body = nm.payloads[nm.calls.indexOf('POST calls/log/')] as Map;
      final row = (body['calls'] as List).single as Map;
      expect(row['client_id'], 'cl-77');
      expect(row['direction'], 'in');
      expect(row['duration_s'], 95);
      expect(st.recent.single.uid, 'call-3');
      expect(st.active!.ended, isTrue);
    });

    test('directionOfCallLogType follows the contract words', () {
      expect(directionOfCallLogType(1), 'in');
      expect(directionOfCallLogType(2), 'out');
      expect(directionOfCallLogType(3), 'missed');
      expect(directionOfCallLogType(5), 'rejected');
    });
  });

  group('NmCall parsing', () {
    test('parses transcript and AI notes', () {
      final c = NmCall.fromJson({
        'uid': 'u',
        'number': '0912',
        'normalized': '98912',
        'direction': 'in',
        'started_at': '2026-11-04T10:00:00+03:30',
        'duration_s': 95,
        'caller': {'display': 'علی', 'known': true},
        'status': 'ANALYSED',
        'has_audio': true,
        'transcript': 'سلام',
        'segments': [
          {'start': 0.0, 'end': 3.2, 'text': 'سلام'},
        ],
        'asr_engine': 'node',
        'summary': 'مشتری قیمت پرسید',
        'sentiment': 'POSITIVE',
        'objections': ['گران است'],
        'commitments': [],
        'next_steps': ['زنگ بزنم'],
      });
      expect(c.displayName, 'علی');
      expect(c.segments.single.text, 'سلام');
      expect(c.objections, ['گران است']);
      expect(c.nextSteps, ['زنگ بزنم']);
      expect(callStatusInProgress('TRANSCRIBING'), isTrue);
      expect(callStatusInProgress('ANALYSED'), isFalse);
      expect(callStatusLabel('NO_CONSENT'), contains('رضایت'));
    });
  });

  test('SmsBridge CallEvent parses a native map', () {
    final e = CallEvent.fromMap({'type': 'ring', 'number': '0912', 'direction': 'in', 'session': 3, 'at': 1000});
    expect(e.type, 'ring');
    expect(e.session, 3);
  });
}
