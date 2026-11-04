import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/domain/recording_matcher.dart';
import 'package:nm_mobile/features/calls/services/call_cycle.dart';
import 'package:nm_mobile/features/calls/services/recording_cycle.dart';
import 'package:nm_mobile/features/calls/services/recording_source.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:sms_bridge/sms_bridge.dart';

import 'support/helpers.dart';

class _FakeSource implements CallRecordingSource {
  _FakeSource(this.files);

  final List<RecordingCandidate> files;
  final List<String> materialized = [];
  final List<String> released = [];
  bool configured = true;
  String? materializeResult = '/tmp/rec.m4a';

  @override
  String get id => 'fake';

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<List<RecordingCandidate>> scan({required DateTime since}) async => files;

  @override
  Future<String?> materialize(RecordingCandidate c) async {
    materialized.add(c.id);
    return materializeResult;
  }

  @override
  Future<void> release(String localPath) async => released.add(localPath);
}

CallEvent _ev(String type, {String number = '09121234567', String dir = 'in', int session = 1, DateTime? at}) =>
    CallEvent(type: type, number: number, direction: dir, session: session, at: at ?? DateTime(2026, 11, 4, 10, 0, 0));

void main() {
  group('recording matcher', () {
    test('parses timestamps from common recorder file names', () {
      expect(timestampFromFileName('Call recording 09121234567_231104_101530.m4a'), DateTime(2023, 11, 4, 10, 15, 30));
      expect(timestampFromFileName('Ali(09121234567)_20261104101530.mp3'), DateTime(2026, 11, 4, 10, 15, 30));
      expect(timestampFromFileName('rec_20261104-101530.amr'), DateTime(2026, 11, 4, 10, 15, 30));
      expect(timestampFromFileName('voice.m4a'), isNull);
    });

    test('digitsOnly and numberTail survive Persian digits and prefixes', () {
      expect(digitsOnly('۰۹۱۲-۱۲۳-۴۵۶۷'), '09121234567');
      expect(numberTail('+98 912 123 4567'), '21234567');
      expect(numberTail('09121234567'), '21234567');
    });

    final start = DateTime(2026, 11, 4, 10, 0, 0);
    final targets = [
      MatchTarget(uid: 'a', number: '09121234567', startedAt: start, durationS: 120),
      MatchTarget(uid: 'b', number: '09350000000', startedAt: start.add(const Duration(minutes: 30)), durationS: 60),
    ];

    test('time must match; number in the file name makes it a strong match', () {
      final f = RecordingCandidate(
        id: 'u1',
        name: 'Call 09121234567_20261104100002.m4a',
        modified: start.add(const Duration(minutes: 2, seconds: 5)),
        size: 1000,
      );
      final m = bestMatch(f, targets)!;
      expect(m.target.uid, 'a');
      expect(m.numberMatched, isTrue);
    });

    test('a file from a different time is never matched, even with the same number', () {
      final f = RecordingCandidate(
        id: 'u2',
        name: 'Call 09121234567_20261001100002.m4a',
        modified: DateTime(2026, 10, 1, 10, 2),
        size: 1000,
      );
      expect(bestMatch(f, targets), isNull);
    });

    test('picks the closest call when two overlap in time', () {
      final f = RecordingCandidate(
        id: 'u3',
        name: 'rec.m4a',
        modified: start.add(const Duration(minutes: 31)),
        size: 10,
      );
      expect(bestMatch(f, targets)!.target.uid, 'b');
    });
  });

  group('CallCycle', () {
    CallCycle build({
      required FakeNmHttp nm,
      required MemoryCallStateStore store,
      required List<CallEvent> events,
      List<CallLogRow> log = const [],
      DateTime? now,
    }) {
      return CallCycle(
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
      final cycle = CallCycle(
        api: CallsApi(nm),
        store: store,
        drain: () async {
          final out = List<CallEvent>.of(events);
          events.clear();
          return out;
        },
        readLog: ({required since, required limit}) async => [
          CallLogRow(id: 77, number: '09121234567', type: 1, date: DateTime(2026, 11, 4, 10, 0, 0), duration: 95, name: ''),
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

  group('RecordingCycle consent gate', () {
    final start = DateTime(2026, 11, 4, 10, 0, 0);
    final file = RecordingCandidate(
      id: 'content://x/1',
      name: 'Call 09121234567_20261104100002.m4a',
      modified: start.add(const Duration(minutes: 2)),
      size: 5000,
    );

    Future<(RecordingCycle, FakeNmHttp, _FakeSource, MemoryCallStateStore, List<String>)> rig({
      required bool consentGranted,
      Object? uploadError,
    }) async {
      final uploads = <String>[];
      final nm = FakeNmHttp((m, p, b) async {
        if (p == 'calls/consent/' && m == 'GET') {
          return {'number': '0912', 'normalized': '98912', 'granted': consentGranted};
        }
        if (p == 'calls/consent/' && m == 'POST') {
          return {'number': '0912', 'normalized': '98912', 'granted': true, 'how': 'verbal'};
        }
        return <String, dynamic>{};
      });
      final store = MemoryCallStateStore();
      store.state.recent.add(KnownCall(uid: 'call-9', number: '09121234567', startedAt: start, durationS: 120));
      final source = _FakeSource([file]);
      final api = CallsApi(
        nm,
        upload: (path, {required fields, required filePath}) async {
          uploads.add('$path|${fields['source']}|$filePath');
          if (uploadError != null) throw uploadError;
          return {'uid': 'call-9', 'status': 'UPLOADED'};
        },
      );
      return (RecordingCycle(source: source, api: api, store: store, now: () => start.add(const Duration(minutes: 5))), nm, source, store, uploads);
    }

    test('scan links a found file to the right call', () async {
      final (cycle, _, _, store, _) = await rig(consentGranted: true);
      expect(await cycle.scan(), 1);
      expect(store.state.pending.single.callUid, 'call-9');
      // scanning again does not add it twice
      expect(await cycle.scan(), 0);
    });

    test('NO consent and the user declines: nothing is read and nothing is uploaded', () async {
      final (cycle, nm, source, store, uploads) = await rig(consentGranted: false);
      await cycle.scan();
      final r = await cycle.upload(store.state.pending.single, askConsent: (_) async => null);
      expect(r.result, UploadResult.noConsent);
      expect(uploads, isEmpty);
      expect(source.materialized, isEmpty);
      expect(nm.calls.contains('POST calls/consent/'), isFalse);
      expect(store.state.pending.length, 1); // still waiting
    });

    test('NO consent but the user confirms: consent is recorded first, then the file is uploaded', () async {
      final (cycle, nm, source, store, uploads) = await rig(consentGranted: false);
      await cycle.scan();
      final r = await cycle.upload(store.state.pending.single, askConsent: (_) async => 'گفتم ضبط می‌شود');
      expect(r.result, UploadResult.uploaded);
      expect(nm.calls.contains('POST calls/consent/'), isTrue);
      final consentBody = nm.payloads[nm.calls.indexOf('POST calls/consent/')] as Map;
      expect(consentBody['granted'], true);
      expect(consentBody['obtained_how'], 'گفتم ضبط می‌شود');
      expect(uploads.single, startsWith('calls/call-9/recording/|builtin_recorder|/tmp/rec.m4a'));
      expect(source.released, ['/tmp/rec.m4a']);
      expect(store.state.pending, isEmpty);
      expect(store.state.uploaded, contains('content://x/1'));
    });

    test('existing consent: uploads without asking', () async {
      final (cycle, _, _, store, uploads) = await rig(consentGranted: true);
      await cycle.scan();
      var asked = 0;
      final r = await cycle.upload(store.state.pending.single, askConsent: (_) async {
        asked++;
        return null;
      });
      expect(r.result, UploadResult.uploaded);
      expect(asked, 0);
      expect(uploads.length, 1);
    });

    test('the server refusing with no_consent is reported as noConsent', () async {
      final (cycle, _, source, store, _) = await rig(
        consentGranted: true,
        uploadError: NmHttpException(403, 'no_consent', 'رضایت ثبت نشده'),
      );
      await cycle.scan();
      final r = await cycle.upload(store.state.pending.single, askConsent: (_) async => null);
      expect(r.result, UploadResult.noConsent);
      expect(source.released, ['/tmp/rec.m4a']);
      expect(store.state.pending.length, 1);
    });

    test('an unreadable file is reported and never uploaded', () async {
      final (cycle, _, source, store, uploads) = await rig(consentGranted: true);
      source.materializeResult = null;
      await cycle.scan();
      final r = await cycle.upload(store.state.pending.single, askConsent: (_) async => null);
      expect(r.result, UploadResult.unreadable);
      expect(uploads, isEmpty);
    });

    test('auto upload only sends numbers that already have consent and never asks', () async {
      final (noConsent, _, _, store1, uploads1) = await rig(consentGranted: false);
      await noConsent.scan();
      expect(await noConsent.autoUpload(), 0);
      expect(uploads1, isEmpty);
      expect(store1.state.pending.length, 1);

      final (withConsent, _, _, store2, uploads2) = await rig(consentGranted: true);
      await withConsent.scan();
      expect(await withConsent.autoUpload(), 1);
      expect(uploads2.length, 1);
      expect(store2.state.pending, isEmpty);
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
