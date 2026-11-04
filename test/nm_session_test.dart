import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/connect/connect_screen.dart';

import 'support/helpers.dart';

http.Response _pairOk() => jsonResp({
  'device_token': 'nmd_secret_token',
  'device': {'uid': 'dev-1', 'name': 'Pixel of Ali', 'created_at': '2026-11-04T10:00:00Z'},
  'user': {'id': 3, 'username': 'ali', 'display_name': 'علی'},
  'server': {'api_version': 1},
  'settings': {},
}, 201);

void main() {
  group('NmSession', () {
    test('pairing stores the token and never the password', () async {
      final dir = Directory.systemTemp.createTempSync('nm_sess');
      final bodies = <String>[];
      final session = NmSession(
        store: SessionStore(dirOverride: dir.path),
        httpClient: MockClient((req) async {
          bodies.add(req.body);
          return _pairOk();
        }),
      );
      await session.load();
      expect(session.paired, isFalse);

      final data = await session.pair(
        serverUrl: '87.107.160.17:8040',
        username: 'ali',
        password: 'my-password-123',
        deviceName: 'Pixel of Ali',
      );

      expect(session.paired, isTrue);
      expect(data.serverUrl, 'http://87.107.160.17:8040');
      expect(data.deviceToken, 'nmd_secret_token');
      expect(jsonDecode(bodies.single)['password'], 'my-password-123');

      // what is on disk: token yes, password no
      for (final f in dir.listSync().whereType<File>()) {
        expect(f.readAsStringSync().contains('my-password-123'), isFalse);
      }
      final saved = File('${dir.path}/nm_session.json').readAsStringSync();
      expect(saved.contains('nmd_secret_token'), isTrue);

      // a new process sees the same pairing
      final again = NmSession(store: SessionStore(dirOverride: dir.path));
      await again.load();
      expect(again.paired, isTrue);
      expect(again.data!.username, 'ali');
      dir.deleteSync(recursive: true);
    });

    test('install id survives unpair and re-pair', () async {
      final store = MemorySessionStore();
      final session = NmSession(store: store, httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/unpair/')) return jsonResp({'ok': true});
        return _pairOk();
      }));
      await session.pair(serverUrl: 'http://nm.test', username: 'ali', password: 'p', deviceName: 'd');
      final id1 = store.install;
      await session.unpair();
      expect(session.paired, isFalse);
      expect(store.stored, isNull);
      await session.pair(serverUrl: 'http://nm.test', username: 'ali', password: 'p', deviceName: 'd');
      expect(store.install, id1);
    });

    test('a revoked token wipes the local session', () async {
      final store = MemorySessionStore();
      final session = NmSession(
        store: store,
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/pair/')) return _pairOk();
          return jsonResp({'error': {'code': 'device_revoked', 'message': 'x'}}, 401);
        }),
      );
      await session.pair(serverUrl: 'http://nm.test', username: 'ali', password: 'p', deviceName: 'd');
      expect(session.paired, isTrue);
      try {
        await session.client!.getJson('me/');
        fail('should throw');
      } on NmApiException catch (e) {
        expect(e.isRevoked, isTrue);
      }
      await Future<void>.delayed(Duration.zero);
      expect(session.paired, isFalse);
      expect(store.clears, greaterThan(0));
    });

    test('newUuid has the v4 shape', () {
      final id = newUuid();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
    });
  });

  testWidgets('connect screen pairs, warns about http and shows server errors', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var calls = 0;
    final store = MemorySessionStore();
    final session = NmSession(
      store: store,
      httpClient: MockClient((req) async {
        calls++;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (body['password'] == 'wrong') {
          return jsonResp({'error': {'code': 'bad_credentials', 'message': 'نام کاربری یا رمز درست نیست.'}}, 401);
        }
        return _pairOk();
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ConnectScreen(session: session, notifyService: false),
        ),
      ),
    );
    await tester.pump();

    // the suggested address is plain http: the warning must be visible
    expect(find.textContaining('این آدرس http است'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'ali');
    await tester.enterText(fields.at(2), 'wrong');
    await tester.tap(find.text('اتصال و جفت‌سازی'));
    await tester.pumpAndSettle();
    expect(find.text('نام کاربری یا رمز درست نیست.'), findsOneWidget);
    expect(session.paired, isFalse);

    await tester.enterText(fields.at(2), 'right');
    await tester.tap(find.text('اتصال و جفت‌سازی'));
    await tester.pumpAndSettle();
    expect(session.paired, isTrue);
    expect(calls, 2);
    expect(store.stored!.deviceToken, 'nmd_secret_token');
    // the password field is cleared after pairing
    expect((tester.widget(fields.at(2)) as TextField).controller!.text, '');
  });
}
