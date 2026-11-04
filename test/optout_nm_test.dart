import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/features/gateway/services/incoming_uploader.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:nm_mobile/features/optout/nm_optout_sync.dart';
import 'package:nm_mobile/features/optout/optout.dart';
import 'package:sms_bridge/sms_bridge.dart';

import 'support/helpers.dart';

void main() {
  group('NmOptOutSync (NM global list -> local campaigns list)', () {
    test('pulls every page, keeps the cursor and adds numbers as NM entries', () async {
      final pages = [
        {'numbers': ['989121234567', '989351111111'], 'next_since': '2026-11-04T10:00:00Z', 'has_more': true},
        {'numbers': ['989122222222'], 'next_since': '2026-11-04T11:00:00Z', 'has_more': false},
      ];
      final queries = <Object?>[];
      final nm = FakeNmHttp((m, p, q) async {
        queries.add(q);
        return pages.removeAt(0);
      });
      final added = <OptOutEntry>[];
      final cursor = MemoryOptOutCursor();
      final sync = NmOptOutSync(
        http: nm,
        cursor: cursor,
        add: (entries) async {
          added.addAll(entries);
          return entries.length;
        },
      );
      expect(await sync.sync(), 3);
      expect(added.map((e) => e.source).toSet(), {OptOutSource.nm});
      expect(added.first.phone, '+989121234567');
      expect(cursor.value, '2026-11-04T11:00:00Z');
      // the second page asked from where the first one ended
      expect((queries[1] as Map)['since'], '2026-11-04T10:00:00Z');
    });

    test('a server without the endpoint is skipped quietly and not asked again', () async {
      final nm = FakeNmHttp((m, p, q) async => throw NmHttpException(404, 'http_404', 'نیست'));
      final sync = NmOptOutSync(http: nm, cursor: MemoryOptOutCursor(), add: (e) async => 0);
      expect(await sync.sync(), 0);
      expect(sync.unsupported, isTrue);
      expect(await sync.sync(), 0);
      expect(nm.calls.length, 1);
    });

    test('other errors are not hidden', () async {
      final nm = FakeNmHttp((m, p, q) async => throw NmHttpException(401, 'device_revoked', 'x'));
      final sync = NmOptOutSync(http: nm, cursor: MemoryOptOutCursor(), add: (e) async => 0);
      expect(sync.sync(), throwsA(isA<NmHttpException>()));
    });
  });

  group('STOP replies reach the local opt-out list', () {
    IncomingSms sms(String from, String body) =>
        IncomingSms(from: from, body: body, at: DateTime(2026, 11, 4, 10), slot: 0);

    test('a STOP reply is remembered locally even when forwarding to NM is OFF', () async {
      final stops = <String>[];
      final up = IncomingUploader(
        http: FakeNmHttp((m, p, b) async => {'accepted': 1, 'opt_outs_added': 1}),
        store: MemoryPendingStore(),
        onStop: (m) async => stops.add(m.from),
      );
      await up.process([sms('09121234567', 'لغو'), sms('09350000000', 'قیمت چنده؟')], forward: false);
      expect(stops, ['09121234567']);
    });

    test('a failing local store never blocks the upload to NM', () async {
      final nm = FakeNmHttp((m, p, b) async => {'accepted': 1, 'opt_outs_added': 1});
      final up = IncomingUploader(
        http: nm,
        store: MemoryPendingStore(),
        onStop: (m) async => throw StateError('disk full'),
      );
      final r = await up.process([sms('09121234567', 'STOP')], forward: false);
      expect(r.uploaded, 1);
    });

    test('the local entry key matches the number whatever its prefix', () {
      final a = OptOutEntry.create(phone: '09121234567', source: OptOutSource.reply);
      final b = OptOutEntry.create(phone: '+989121234567', source: OptOutSource.nm);
      expect(a.key, b.key);
    });
  });
}
