import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

import 'fakes.dart';

void main() {
  group('AdapterResult', () {
    test('parses the JSON text the page returns; absent and blank fields stay null', () {
      final r = AdapterResult.fromJsonString(
        '{"status":"found","on_platform":true,"display_name":"Ali","username":"  ","bio":null,'
        '"field_sources":{"display_name":"src"},"extra":{"k":1}}',
      );
      expect(r.status, 'found');
      expect(r.onPlatform, true);
      expect(r.displayName, 'Ali');
      expect(r.username, isNull);
      expect(r.bio, isNull);
      expect(r.fieldSources, <String, String>{'display_name': 'src'});
      expect(r.extra['k'], 1);
    });

    test('garbage from the page becomes a bad_adapter_output error, never an exception', () {
      expect(AdapterResult.fromJsonString('not json').error, 'bad_adapter_output');
      expect(AdapterResult.fromJsonString('[1,2]').status, 'error');
    });

    test('toSubmitBody sends the ticket and only present fields', () {
      const r = AdapterResult(status: 'not_found', onPlatform: false);
      expect(r.toSubmitBody('T'), <String, dynamic>{'ticket': 'T', 'status': 'not_found', 'on_platform': false});
    });
  });

  group('LoginProbe', () {
    test('parses', () {
      final p = LoginProbe.fromJsonString('{"logged_in":true,"stage":"signed_in"}');
      expect(p.loggedIn, isTrue);
      expect(p.stage, 'signed_in');
      expect(LoginProbe.fromJsonString('x').loggedIn, isFalse);
    });
  });

  group('config', () {
    test('LookupConfig parses platforms, rules, cache days and the server method', () {
      final c = LookupConfig.fromJson(<String, dynamic>{
        'cache_days': 30,
        'rules': 'R',
        'platforms': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'telegram', 'label': 'تلگرام', 'enabled': true, 'method': 'server', 'ready': false, 'warning': 'W', 'left_today': 5},
          <String, dynamic>{'key': 'whatsapp', 'label': 'واتساپ', 'enabled': false, 'method': 'webview', 'ready': true},
        ],
      });
      expect(c.cacheDays, 30);
      expect(c.rules, 'R');
      expect(c.platforms.first.isServer, isTrue);
      expect(c.platforms.first.ready, isFalse);
      expect(c.platforms.first.leftToday, 5);
      expect(c.platforms.last.enabled, isFalse);
    });
  });

  group('ProfileView / facade.latest', () {
    test('fromJson maps the profile object of the API contract', () {
      final p = ProfileView.fromJson(<String, dynamic>{
        'platform': 'whatsapp',
        'label': 'واتساپ',
        'status': 'found',
        'on_platform': true,
        'display_name': 'Ali',
        'username': 'ali',
        'bio': 'hi',
        'avatar_url': '/api/v1/mobile/lookups/u1/avatar/',
        'field_sources': <String, dynamic>{'bio': 'WhatsApp: about'},
        'looked_up_at': '2026-11-04T10:00:00+03:30',
        'age_days': 3,
        'stale': false,
        'method': 'webview',
      });
      expect(p.displayName, 'Ali');
      expect(p.avatarPath, '/api/v1/mobile/lookups/u1/avatar/');
      expect(p.fieldSources['bio'], 'WhatsApp: about');
      expect(p.ageDays, 3);
      expect(p.lookedUpAt, isNotNull);
    });

    test('latest() reads the profiles list from lookups/latest/', () async {
      final http = FakeHttp(latest: <Map<String, dynamic>>[
        <String, dynamic>{'platform': 'bale', 'label': 'بله', 'status': 'not_found', 'on_platform': false},
      ]);
      final facade = LookupFacade(http, runner: FakeRunner());
      final list = await facade.latest(kNumber);
      expect(list.single.platform, 'bale');
      expect(list.single.onPlatform, isFalse);
      expect(http.log, <String>['GET lookups/latest/']);
    });
  });

  group('messages', () {
    test('the server message wins, then our Persian fallback, then a generic line', () {
      expect(lookupMessage('rate_limited', 'سقف پر شد'), 'سقف پر شد');
      expect(lookupMessage('rate_limited'), contains('سقف'));
      expect(lookupMessage('adapter_unavailable: x'), contains('راه امنی'));
      expect(lookupMessage('totally_new_code'), contains('totally_new_code'));
    });
  });

  group('platform specs', () {
    test('five WebView platforms; Rubika is the unavailable one; ban warning text exists', () {
      expect(kWebViewPlatforms.map((p) => p.key), <String>['whatsapp', 'eitaa', 'bale', 'soroush', 'rubika']);
      expect(platformSpecFor('rubika')!.unavailable, isTrue);
      expect(platformSpecFor('whatsapp')!.unavailable, isFalse);
      expect(platformSpecFor('telegram'), isNull); // server side
      expect(kBanRiskWarning, contains('مسدود'));
    });
  });
}
