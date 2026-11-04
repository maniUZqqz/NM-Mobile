import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/features/gateway/data/claim_store.dart';
import 'package:nm_mobile/features/gateway/services/incoming_uploader.dart';
import 'package:nm_mobile/features/gateway/services/sms_pipeline.dart';
import 'package:nm_mobile/features/gateway/services/stop_words.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:sms_bridge/sms_bridge.dart';

import 'support/helpers.dart';

Map<String, dynamic> _msg(String uid, {int attempt = 1, String to = '09121234567', String kind = 'transactional'}) => {
  'uid': uid,
  'to': to,
  'normalized': '98${to.substring(1)}',
  'body': 'کد شما 1234',
  'kind': kind,
  'sim_slot': null,
  'attempt': attempt,
  'lease_seconds': 120,
};

Map<String, dynamic> _claim(List<Map<String, dynamic>> msgs, {bool paused = false, String? limited}) => {
  'messages': msgs,
  'paused': paused,
  'limited': limited,
  'retry_after_s': 5,
  'limits': {'remaining_hour': 100, 'remaining_day': 500},
};

SmsSendResult _ok({int parts = 1}) => SmsSendResult(
  ok: true,
  code: 0,
  parts: parts,
  partsOk: parts,
  subId: 1,
  usedSubId: 1,
  modemCode: -1,
  error: '',
);

class _Rig {
  _Rig({this.claims = const []}) {
    nm = FakeNmHttp((method, path, payload) async {
      if (path == 'sms/claim/') {
        return claims.isEmpty ? _claim([]) : claims.removeAt(0);
      }
      if (path.endsWith('/report/')) {
        if (reportFails) throw NmHttpException(0, 'network', 'قطع');
        return {'ok': true, 'state': 'SENT'};
      }
      return <String, dynamic>{};
    });
    pipeline = SmsPipeline(
      http: nm,
      store: store,
      pickSub: (slot) async => 1,
      onEvent: events.add,
      sender: ({required to, required message, required subId, required ref, required delivery}) async {
        sent.add(to);
        // crash-safety: at the moment of sending, the uid must already be on disk
        final rec = await store.get(ref!);
        phaseAtSend.add(rec?.phase);
        return nextResult ?? _ok();
      },
    );
  }

  List<Map<String, dynamic>> claims;
  late final FakeNmHttp nm;
  late final SmsPipeline pipeline;
  final MemoryClaimStore store = MemoryClaimStore();
  final List<PipelineEvent> events = [];
  final List<String> sent = [];
  final List<ClaimPhase?> phaseAtSend = [];
  bool reportFails = false;
  SmsSendResult? nextResult;
}

void main() {
  group('SmsPipeline', () {
    test('claim -> persist -> send -> report sent', () async {
      final rig = _Rig(claims: [_claim([_msg('u1')])]);
      final res = await rig.pipeline.tick();

      expect(res.messages.length, 1);
      expect(rig.sent, ['09121234567']);
      // written to disk BEFORE the SMS API was called
      expect(rig.phaseAtSend, [ClaimPhase.sending]);
      final rec = (await rig.store.get('u1'))!;
      expect(rec.phase, ClaimPhase.sent);
      expect(rec.reported, isTrue);

      final reports = rig.nm.calls.where((c) => c.endsWith('/report/')).toList();
      expect(reports, ['POST sms/u1/report/']);
      final payload = rig.nm.payloads[rig.nm.calls.indexOf('POST sms/u1/report/')] as Map;
      expect(payload['state'], 'sent');
      expect(payload['parts'], 1);
    });

    test('failures are reported with an error code and never retried blindly', () async {
      final rig = _Rig(claims: [_claim([_msg('u2')])])
        ..nextResult = const SmsSendResult(
          ok: false,
          code: 4,
          parts: 0,
          partsOk: 0,
          subId: 1,
          usedSubId: 1,
          modemCode: -1,
          error: '',
        );
      await rig.pipeline.tick();
      final payload = rig.nm.payloads[rig.nm.calls.indexOf('POST sms/u2/report/')] as Map;
      expect(payload['state'], 'failed');
      expect(payload['error_code'], 'no_service');
      expect((await rig.store.get('u2'))!.phase, ClaimPhase.failed);
    });

    test('a message that was already sent is only re-reported, never re-sent', () async {
      final rig = _Rig(claims: [_claim([_msg('u3')])]);
      await rig.store.put(ClaimRecord(
        uid: 'u3',
        to: '09121234567',
        attempt: 1,
        phase: ClaimPhase.sent,
        atMs: DateTime.now().millisecondsSinceEpoch,
      ));
      await rig.pipeline.tick();
      expect(rig.sent, isEmpty);
      expect(rig.nm.calls.contains('POST sms/u3/report/'), isTrue);
      final payload = rig.nm.payloads[rig.nm.calls.indexOf('POST sms/u3/report/')] as Map;
      expect(payload['state'], 'sent');
    });

    test('crash while sending: same attempt is not re-sent, it is reported unknown', () async {
      final rig = _Rig(claims: [_claim([_msg('u4', attempt: 1)])]);
      await rig.store.put(ClaimRecord(
        uid: 'u4',
        to: '09121234567',
        attempt: 1,
        phase: ClaimPhase.sending,
        atMs: DateTime.now().millisecondsSinceEpoch,
      ));
      await rig.pipeline.tick();
      expect(rig.sent, isEmpty);
      final payload = rig.nm.payloads[rig.nm.calls.indexOf('POST sms/u4/report/')] as Map;
      expect(payload['state'], 'failed');
      expect(payload['error_code'], 'unknown_after_restart');
    });

    test('when the server re-issues with a higher attempt it is sent again', () async {
      final rig = _Rig(claims: [_claim([_msg('u5', attempt: 2)])]);
      await rig.store.put(ClaimRecord(
        uid: 'u5',
        to: '09121234567',
        attempt: 1,
        phase: ClaimPhase.sending,
        atMs: DateTime.now().millisecondsSinceEpoch,
      ));
      await rig.pipeline.tick();
      expect(rig.sent.length, 1);
      expect((await rig.store.get('u5'))!.phase, ClaimPhase.sent);
    });

    test('a report lost to the network is retried before the next claim', () async {
      final rig = _Rig(claims: [_claim([_msg('u6')]), _claim([])])..reportFails = true;
      await rig.pipeline.tick();
      var rec = (await rig.store.get('u6'))!;
      expect(rec.phase, ClaimPhase.sent);
      expect(rec.reported, isFalse);
      expect(rig.events.any((e) => e.type == 'report_failed'), isTrue);

      rig.reportFails = false;
      await rig.pipeline.tick();
      rec = (await rig.store.get('u6'))!;
      expect(rec.reported, isTrue);
      expect(rig.sent.length, 1); // still sent exactly once
    });

    test('paused and limited answers send nothing', () async {
      final rig = _Rig(claims: [_claim([], paused: true), _claim([], limited: 'hour')]);
      final a = await rig.pipeline.tick();
      final b = await rig.pipeline.tick();
      expect(a.paused, isTrue);
      expect(b.limited, 'hour');
      expect(rig.sent, isEmpty);
      expect(rig.events.map((e) => e.type), containsAll(['paused', 'limited']));
    });

    test('an invalid number is failed without touching the SIM', () async {
      final rig = _Rig(claims: [_claim([_msg('u7', to: '12')])]);
      await rig.pipeline.tick();
      expect(rig.sent, isEmpty);
      final payload = rig.nm.payloads[rig.nm.calls.indexOf('POST sms/u7/report/')] as Map;
      expect(payload['error_code'], 'bad_number');
    });

    test('a rejected report (404 cancelled) is not retried forever', () async {
      final rig = _Rig(claims: [_claim([_msg('u8')]), _claim([])]);
      rig.nm.handler = (method, path, payload) async {
        if (path == 'sms/claim/') return rig.claims.isEmpty ? _claim([]) : rig.claims.removeAt(0);
        throw NmHttpException(404, 'not_found', 'نیست');
      };
      await rig.pipeline.tick();
      expect((await rig.store.get('u8'))!.reported, isTrue);
      final before = rig.nm.calls.where((c) => c.endsWith('/report/')).length;
      await rig.pipeline.tick();
      expect(rig.nm.calls.where((c) => c.endsWith('/report/')).length, before);
    });

    test('delivery reports from all parts produce one delivered report', () async {
      final rig = _Rig(claims: [_claim([_msg('u9')])])..nextResult = _ok(parts: 2);
      await rig.pipeline.tick();
      await rig.pipeline.handleDelivery(const [
        DeliveryEvent(ref: 'u9', part: 0, total: 2, ok: true, status: 0),
      ]);
      expect(rig.nm.payloads.whereType<Map>().where((p) => p['state'] == 'delivered'), isEmpty);
      await rig.pipeline.handleDelivery(const [
        DeliveryEvent(ref: 'u9', part: 1, total: 2, ok: true, status: 0),
      ]);
      final delivered = rig.nm.payloads.whereType<Map>().where((p) => p['state'] == 'delivered');
      expect(delivered.length, 1);
    });

    test('smsErrorCode maps Android result codes', () {
      SmsSendResult r(int c) => SmsSendResult.failure(c, '');
      expect(smsErrorCode(r(2)), 'radio_off');
      expect(smsErrorCode(r(3)), 'null_pdu');
      expect(smsErrorCode(r(4)), 'no_service');
      expect(smsErrorCode(r(-100)), 'timeout');
      expect(smsErrorCode(r(99)), 'generic');
    });
  });

  group('FileClaimStore', () {
    test('survives a process restart (a new store instance on the same folder)', () async {
      final dir = Directory.systemTemp.createTempSync('nm_claims');
      final a = FileClaimStore(dirOverride: dir.path);
      await a.put(ClaimRecord(
        uid: 'x1',
        to: '0912',
        attempt: 1,
        phase: ClaimPhase.sending,
        atMs: DateTime.now().millisecondsSinceEpoch,
      ));
      final b = FileClaimStore(dirOverride: dir.path);
      final rec = await b.get('x1');
      expect(rec, isNotNull);
      expect(rec!.phase, ClaimPhase.sending);
      dir.deleteSync(recursive: true);
    });
  });

  group('STOP words', () {
    test('Persian, Arabic-digit and English forms are recognised', () {
      for (final t in ['لغو', 'لغو ۱۱', 'لغو11', 'لغو عضویت', 'توقف', 'STOP', ' stop. ', 'Stop!', 'unsubscribe', 'لغو لطفا', 'لغو؟']) {
        expect(isStopWord(t), isTrue, reason: t);
      }
    });

    test('normal messages and long texts are not STOP words', () {
      for (final t in ['سلام', 'سفارش من کی میرسه؟', 'stopping by tomorrow', '', 'لغو می‌کنم چون دیر رسید و راضی نبودم خیلی']) {
        expect(isStopWord(t), isFalse, reason: t);
      }
    });

    test('normalizeText unifies Arabic letters and digits', () {
      expect(normalizeText('كيف ۱۲٣'), 'کیف 123');
    });
  });

  group('IncomingUploader', () {
    IncomingSms sms(String body) => IncomingSms(from: '09121234567', body: body, at: DateTime(2026, 11, 4, 10), slot: 0);

    test('with forwarding OFF only STOP words are uploaded', () async {
      final nm = FakeNmHttp((m, p, b) async => {'accepted': 1, 'duplicates': 0, 'opt_outs_added': 1, 'forwarding': false});
      final up = IncomingUploader(http: nm, store: MemoryPendingStore());
      final r = await up.process([sms('سلام، قیمت چنده؟'), sms('لغو')], forward: false);
      expect(r.skipped, 1);
      expect(r.uploaded, 1);
      expect(r.optOutsAdded, 1);
      final msgs = ((nm.payloads.single as Map)['messages'] as List);
      expect(msgs.length, 1);
      expect((msgs.single as Map)['body'], 'لغو');
    });

    test('with forwarding ON everything is uploaded', () async {
      final nm = FakeNmHttp((m, p, b) async => {'accepted': 2, 'duplicates': 0, 'opt_outs_added': 0});
      final up = IncomingUploader(http: nm, store: MemoryPendingStore());
      final r = await up.process([sms('سلام'), sms('لغو')], forward: true);
      expect(r.uploaded, 2);
      expect(r.skipped, 0);
    });

    test('when the network is down the messages wait and go later', () async {
      var down = true;
      final nm = FakeNmHttp((m, p, b) async {
        if (down) throw NmHttpException(0, 'network', 'قطع');
        return {'accepted': 1, 'opt_outs_added': 1};
      });
      final store = MemoryPendingStore();
      final up = IncomingUploader(http: nm, store: store);
      final r1 = await up.process([sms('لغو')], forward: false);
      expect(r1.failedTransient, isTrue);
      expect(store.items.length, 1);
      down = false;
      final r2 = await up.process(const [], forward: false);
      expect(r2.uploaded, 1);
      expect(store.items, isEmpty);
    });

    test('client ids are stable so a repeat is a duplicate on the server', () {
      final a = incomingClientId('0912', 1000, 'لغو');
      final b = incomingClientId('0912', 1000, 'لغو');
      final c = incomingClientId('0912', 1001, 'لغو');
      expect(a, b);
      expect(a == c, isFalse);
    });
  });
}
