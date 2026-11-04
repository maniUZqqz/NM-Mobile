import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:nm_mobile/features/monitor/monitor_actions.dart';
import 'package:nm_mobile/features/monitor/monitor_models.dart';
import 'package:nm_mobile/features/monitor/monitor_page.dart';

import 'support/helpers.dart';

Map<String, dynamic> _summary() => {
  'generated_at': '2026-11-04T10:15:00+03:30',
  'health': {
    'status': 'degraded',
    'checks': [
      {'name': 'database', 'label': 'پایگاه داده', 'ok': true, 'detail': ''},
      {'name': 'redis', 'label': 'صف', 'ok': false, 'detail': 'قطع'},
    ],
  },
  'nodes': [
    {
      'id': 1,
      'name': 'gpu-1',
      'online': true,
      'enabled': true,
      'last_seen': '2026-11-04T10:14:00+03:30',
      'gpu': 'RTX 3060',
      'services': {'voice': true, 'ollama': false},
      'jobs_done': 12,
    },
  ],
  'queue': {
    'compute': {'queued': 2, 'running': 1},
    'jobs': {'queued': 0, 'processing': 2, 'waiting_approval': 1},
    'celery': null,
  },
  'failures': [
    {
      'kind': 'compute_job',
      'id': 'abc-123',
      'type': 'voice.asr',
      'error': 'timeout',
      'at': '2026-11-04T09:00:00+03:30',
    },
  ],
  'ai': {
    'priority': 'local_first',
    'priority_label': 'اول لوکال',
    'local': {'online': true, 'node': 'gpu-1', 'last_error': null},
    'metis': {'configured': true, 'last_error': null, 'circuit_open': false},
  },
  'disk': {
    'path': '/',
    'total_gb': 40.0,
    'used_gb': 37.3,
    'free_gb': null,
    'percent_used': null,
    'low': null,
  },
  'mobile': {'devices_online': 1, 'sms_queued': 0, 'sms_sent_today': 4, 'calls_today': null},
  'actions': [
    {
      'action': 'compute_job.cancel',
      'label': 'لغو کار',
      'target_kind': 'compute_job',
      'confirm_text': 'این کار لغو شود؟',
      'danger': false,
    },
    {'action': 'sms.pause', 'label': 'توقف صف پیامک', 'confirm_text': 'صف پیامک متوقف شود؟'},
  ],
};

void main() {
  group('MonitorSummary parsing', () {
    test('keeps unknown values as null instead of inventing numbers', () {
      final s = MonitorSummary.fromJson(_summary());
      expect(s.health.status, 'degraded');
      expect(s.health.checks.length, 2);
      expect(s.nodes.single.gpu, 'RTX 3060');
      expect(s.nodes.single.services['ollama'], isFalse);
      expect(s.queue.celery, isNull);
      expect(s.queue.computeQueued, 2);
      expect(s.disk.percentUsed, isNull);
      expect(s.disk.freeGb, isNull);
      expect(s.mobile.callsToday, isNull);
      expect(s.mobile.smsSentToday, 4);
      expect(s.actionsFor('compute_job').single.action, 'compute_job.cancel');
      expect(s.globalActions.single.action, 'sms.pause');
    });

    test('empty / garbage input does not crash', () {
      final s = MonitorSummary.fromJson(<String, dynamic>{});
      expect(s.nodes, isEmpty);
      expect(s.health.status, 'unknown');
      expect(s.disk.percentUsed, isNull);
    });
  });

  group('ActionRunner', () {
    final def = ActionDef.fromJson({
      'action': 'compute_job.cancel',
      'label': 'لغو کار',
      'target_kind': 'compute_job',
      'confirm_text': 'این کار لغو شود؟',
    });

    test('nothing is sent when the user does not confirm', () async {
      final fake = FakeNmHttp();
      String? shown;
      final r = await ActionRunner(fake).run(
        def,
        target: 'abc',
        confirm: (t) async {
          shown = t;
          return false;
        },
      );
      expect(r.executed, isFalse);
      expect(fake.calls, isEmpty);
      expect(shown, 'این کار لغو شود؟');
    });

    test('confirmed action posts the exact action, target and params', () async {
      final fake = FakeNmHttp((m, p, b) async => {'ok': true, 'message': 'لغو شد'});
      final r = await ActionRunner(fake).run(
        def,
        target: 'abc',
        targetLabel: 'voice.asr abc',
        confirm: (t) async {
          expect(t, contains('این کار لغو شود؟'));
          expect(t, contains('voice.asr abc'));
          return true;
        },
      );
      expect(r.executed, isTrue);
      expect(r.message, 'لغو شد');
      expect(fake.calls, ['POST monitor/actions/']);
      expect(fake.payloads.single, {'action': 'compute_job.cancel', 'target': 'abc', 'params': <String, dynamic>{}});
    });

    test('a default confirmation text is used when the server gives none', () {
      const d = ActionDef(action: 'sms.pause', label: 'x');
      expect(ActionRunner.confirmTextFor(d), ActionRunner.defaultConfirm);
    });

    test('server errors surface as NmHttpException', () async {
      final fake = FakeNmHttp((m, p, b) async => throw NmHttpException(409, 'bad_state', 'وضعیت اجازه نمی‌دهد'));
      expect(
        ActionRunner(fake).run(def, target: 'x', confirm: (_) async => true),
        throwsA(isA<NmHttpException>()),
      );
    });
  });

  testWidgets('monitor page: every action sits behind a confirmation dialog', (tester) async {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final posts = <http.Request>[];
    final store = MemorySessionStore()
      ..stored = const NmSessionData(
        serverUrl: 'http://nm.test',
        deviceToken: 'tok',
        deviceUid: 'd',
        deviceName: 'p',
        userId: 1,
        username: 'u',
        displayName: '',
      );
    final session = NmSession(
      store: store,
      httpClient: MockClient((req) async {
        if (req.method == 'POST') {
          posts.add(req);
          return jsonResp({'ok': true, 'message': 'کار لغو شد'});
        }
        return jsonResp(_summary());
      }),
    );
    await session.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: MonitorPage(session: session)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('voice.asr · شناسه abc-123'), findsOneWidget);
    // unknown disk numbers are shown as unknown, never as 0
    expect(find.text('نامشخص'), findsWidgets);

    // 1) tap the action, then cancel the dialog -> no POST
    await tester.tap(find.text('لغو کار'));
    await tester.pumpAndSettle();
    expect(find.text('تأیید اقدام'), findsOneWidget);
    expect(find.textContaining('این کار لغو شود؟'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(posts, isEmpty);

    // 2) tap again and confirm -> exactly one POST with the right body
    await tester.tap(find.text('لغو کار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بله، انجام بده'));
    await tester.pumpAndSettle();
    expect(posts.length, 1);
    final body = jsonDecode(posts.single.body) as Map<String, dynamic>;
    expect(body['action'], 'compute_job.cancel');
    expect(body['target'], 'abc-123');

    // dispose the page so its periodic timer is cancelled
    await tester.pumpWidget(const SizedBox());
  });
}
