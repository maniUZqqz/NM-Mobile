import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

import 'fakes.dart';

void main() {
  late FakeHttp http;
  late FakeRunner runner;
  late List<Duration> delays;
  late List<LookupProgress> progress;
  late LookupEngine engine;

  setUp(() {
    http = FakeHttp();
    runner = FakeRunner();
    delays = <Duration>[];
    progress = <LookupProgress>[];
    engine = LookupEngine(
      http: http,
      runner: runner,
      delay: (d) async => delays.add(d),
      random: Random(7),
    );
  });

  Future<LookupRunResult> run({String? callUid = 'call-1', bool manual = false, bool refresh = false}) =>
      engine.run(number: kNumber, callUid: callUid, manual: manual, refresh: refresh, onProgress: progress.add);

  String stateOf(String platform) => progress.lastWhere((p) => p.platform == platform).state;

  test('order per platform: config, then authorize -> run -> submit; telegram goes through lookups/server/', () async {
    http.config = cfg([plat('whatsapp'), plat('telegram', method: 'server'), plat('eitaa')]);
    final result = await run();
    expect(http.log, <String>[
      'GET lookups/config/',
      'POST lookups/authorize/',
      'POST lookups/',
      'POST lookups/authorize/',
      'POST lookups/server/',
      'POST lookups/authorize/',
      'POST lookups/',
    ]);
    expect(runner.calls, <String>['whatsapp:$kDigits', 'eitaa:$kDigits']);
    expect(http.postsTo('lookups/server/').single, <String, dynamic>{'ticket': 't-telegram'});
    expect(result.stopped, isFalse);
    expect(result.done.toSet(), <String>{'whatsapp', 'telegram', 'eitaa'});
  });

  test('the number handed to the adapter is digits only, and exactly one number is ever sent', () async {
    http.config = cfg([plat('whatsapp'), plat('eitaa')]);
    await run();
    expect(runner.calls.every((c) => c.endsWith(':$kDigits')), isTrue);
    for (final body in http.postsTo('lookups/authorize/')) {
      expect(body['number'], isA<String>());
      expect(body['number'], kNumber);
    }
  });

  test('the server normalized number wins over the local fallback', () async {
    http.config = cfg([plat('whatsapp')]);
    http.onPost = (path, body) => path == 'lookups/authorize/'
        ? <String, dynamic>{'allowed': true, 'ticket': 't', 'method': 'webview', 'normalized': '989129998877'}
        : null;
    await run();
    expect(runner.calls, <String>['whatsapp:989129998877']);
  });

  test('normalizeNumber: Iranian forms become 98...', () {
    expect(LookupEngine.normalizeNumber('0912 000 0001'), kDigits);
    expect(LookupEngine.normalizeNumber('+98 912 000 0001'), kDigits);
    expect(LookupEngine.normalizeNumber('00989120000001'), kDigits);
    expect(LookupEngine.normalizeNumber('9120000001'), kDigits);
    expect(LookupEngine.normalizeNumber('+44 20 7946 0000'), '442079460000');
  });

  test('cached answer: no run, no submit, no delay, reported as done', () async {
    http.config = cfg([plat('whatsapp'), plat('eitaa')]);
    http.onPost = (path, body) {
      if (path == 'lookups/authorize/' && body['platform'] == 'whatsapp') {
        return <String, dynamic>{'allowed': false, 'reason': 'cached', 'cached': <String, dynamic>{}};
      }
      return null;
    };
    await run();
    expect(runner.calls, <String>['eitaa:$kDigits']);
    expect(http.postsTo('lookups/').length, 1);
    expect(delays, isEmpty); // the only real lookup was the first real one
    expect(stateOf('whatsapp'), 'done');
    expect(progress.firstWhere((p) => p.platform == 'whatsapp' && p.state == 'done').message, contains('حافظه'));
  });

  test('platform_disabled and recently_refreshed skip that platform and continue', () async {
    http.config = cfg([plat('whatsapp'), plat('eitaa'), plat('bale')]);
    http.onPost = (path, body) {
      if (path != 'lookups/authorize/') return null;
      if (body['platform'] == 'whatsapp') return NmHttpException(403, 'platform_disabled', 'خاموش');
      if (body['platform'] == 'eitaa') return NmHttpException(409, 'recently_refreshed', 'تازه');
      return null;
    };
    final result = await run();
    expect(stateOf('whatsapp'), 'skipped');
    expect(stateOf('eitaa'), 'skipped');
    expect(stateOf('bale'), 'done');
    expect(result.stopped, isFalse);
    expect(runner.calls, <String>['bale:$kDigits']);
  });

  test('rate_limited stops the whole run at once; later platforms are never authorized', () async {
    http.config = cfg([plat('whatsapp'), plat('eitaa'), plat('bale'), plat('soroush')]);
    http.onPost = (path, body) {
      if (path == 'lookups/authorize/' && body['platform'] == 'eitaa') {
        return NmHttpException(429, 'rate_limited', 'سقف پر شد');
      }
      return null;
    };
    final result = await run();
    expect(result.stopped, isTrue);
    expect(result.stopCode, 'rate_limited');
    expect(result.stopMessage, 'سقف پر شد');
    expect(http.postsTo('lookups/authorize/').map((b) => b['platform']), <String>['whatsapp', 'eitaa']);
    expect(stateOf('bale'), 'skipped');
    expect(stateOf('soroush'), 'skipped');
    expect(runner.calls, <String>['whatsapp:$kDigits']);
  });

  test('bulk_blocked, no_matching_call and not_staff are stop codes too', () async {
    for (final code in <String>['bulk_blocked', 'no_matching_call', 'not_staff']) {
      http = FakeHttp(config: cfg([plat('whatsapp'), plat('eitaa')]));
      runner = FakeRunner();
      engine = LookupEngine(http: http, runner: runner, delay: (d) async {}, random: Random(1));
      http.onPost = (path, body) => path == 'lookups/authorize/' ? NmHttpException(403, code, 'x') : null;
      final r = await engine.run(number: kNumber, callUid: 'c');
      expect(r.stopCode, code);
      expect(http.postsTo('lookups/authorize/').length, 1, reason: code);
      expect(runner.calls, isEmpty);
    }
  });

  test('an unknown server error also stops (no hammering)', () async {
    http.config = cfg([plat('whatsapp'), plat('eitaa')]);
    http.onPost = (path, body) => path == 'lookups/authorize/' ? NmHttpException(500, 'server_error', 'خطا') : null;
    final r = await run();
    expect(r.stopped, isTrue);
    expect(http.postsTo('lookups/authorize/').length, 1);
  });

  test('polite spacing: no pause before the first real lookup, 4-9 s jitter between the others', () async {
    http.config = cfg([plat('whatsapp'), plat('eitaa'), plat('bale'), plat('soroush')]);
    await run();
    expect(runner.calls.length, 4);
    expect(delays.length, 3);
    for (final d in delays) {
      expect(d >= const Duration(seconds: 4), isTrue);
      expect(d <= const Duration(seconds: 9), isTrue);
    }
    // jitter: not all the same
    expect(delays.toSet().length, greaterThan(1));
  });

  test('platforms run strictly one after another (never in parallel)', () async {
    http.config = cfg([plat('whatsapp'), plat('eitaa')]);
    final order = <String>[];
    final slow = _SequenceRunner(order);
    final e = LookupEngine(http: http, runner: slow, delay: (d) async => order.add('delay'), random: Random(1));
    await e.run(number: kNumber, callUid: 'c');
    expect(order, <String>['start:whatsapp', 'end:whatsapp', 'delay', 'start:eitaa', 'end:eitaa']);
  });

  test('adapter says login_required: it is submitted as such and reported to the UI', () async {
    http.config = cfg([plat('whatsapp')]);
    runner.results['whatsapp'] = AdapterResult(status: 'login_required', error: 'wa_stage_qr');
    await run();
    final body = http.postsTo('lookups/').single;
    expect(body['status'], 'login_required');
    expect(body['ticket'], 't-whatsapp');
    expect(stateOf('whatsapp'), 'login_required');
  });

  test('adapter error is submitted with its code and reported as failed', () async {
    http.config = cfg([plat('whatsapp')]);
    runner.results['whatsapp'] = AdapterResult.error('no_query_module');
    await run();
    expect(http.postsTo('lookups/').single['error'], 'no_query_module');
    expect(stateOf('whatsapp'), 'failed');
  });

  test('submit body contains only what the platform returned', () async {
    http.config = cfg([plat('whatsapp')]);
    runner.results['whatsapp'] = const AdapterResult(
      status: 'found',
      onPlatform: true,
      displayName: 'Ali',
      username: null,
      bio: 'hi',
      deepLinkId: '98912',
      avatarB64: 'QUJD',
      fieldSources: <String, String>{'display_name': 'WhatsApp: push name'},
      extra: <String, dynamic>{'is_business': false},
    );
    await run();
    final body = http.postsTo('lookups/').single;
    expect(body.keys.toSet(), <String>{
      'ticket', 'status', 'on_platform', 'display_name', 'bio', 'deep_link_id', 'avatar_b64', 'field_sources', 'extra',
    });
    expect(body.containsKey('username'), isFalse);
    expect(body.containsKey('error'), isFalse);
  });

  test('not_found is submitted with on_platform=false', () async {
    http.config = cfg([plat('whatsapp')]);
    runner.results['whatsapp'] = const AdapterResult(status: 'not_found', onPlatform: false);
    await run();
    final body = http.postsTo('lookups/').single;
    expect(body['status'], 'not_found');
    expect(body['on_platform'], false);
    expect(stateOf('whatsapp'), 'done');
  });

  test('a crashing WebView fails that platform only; the next one still runs', () async {
    http.config = cfg([plat('whatsapp'), plat('eitaa')]);
    runner.throwFor.add('whatsapp');
    await run();
    expect(stateOf('whatsapp'), 'failed');
    expect(stateOf('eitaa'), 'done');
    expect(http.postsTo('lookups/').length, 1);
  });

  test('server-method failure (platform_not_ready) fails Telegram only', () async {
    http.config = cfg([plat('telegram', method: 'server'), plat('eitaa')]);
    http.onPost = (path, body) {
      if (path == 'lookups/authorize/' && body['platform'] == 'telegram') {
        return <String, dynamic>{'allowed': true, 'ticket': 'tt', 'method': 'server'};
      }
      if (path == 'lookups/server/') return NmHttpException(503, 'platform_not_ready', 'حساب وصل نیست');
      return null;
    };
    await run();
    expect(stateOf('telegram'), 'failed');
    expect(stateOf('eitaa'), 'done');
  });

  test('submit refused (ticket expired) is a failure, not a crash', () async {
    http.config = cfg([plat('whatsapp')]);
    http.onPost = (path, body) => path == 'lookups/' ? NmHttpException(400, 'ticket_invalid', 'بلیت منقضی شد') : null;
    await run();
    expect(stateOf('whatsapp'), 'failed');
    expect(progress.last.message, 'بلیت منقضی شد');
  });

  test('Rubika is never authorized or run: no safe method exists', () async {
    http.config = cfg([plat('rubika'), plat('whatsapp')]);
    await run();
    expect(http.postsTo('lookups/authorize/').map((b) => b['platform']), <String>['whatsapp']);
    expect(stateOf('rubika'), 'skipped');
  });

  test('disabled, not-ready and unknown platforms are skipped without any call', () async {
    http.config = cfg([plat('whatsapp', enabled: false), plat('eitaa', ready: false), plat('unknownmsg')]);
    await run();
    expect(http.postsTo('lookups/authorize/'), isEmpty);
    expect(progress.map((p) => p.state).toSet(), <String>{'skipped'});
    expect(runner.calls, isEmpty);
  });

  test('trigger and call_uid: call runs carry the call uid, manual runs carry none; refresh is forwarded', () async {
    http.config = cfg([plat('whatsapp')]);
    await run(callUid: 'abc', refresh: true);
    var body = http.postsTo('lookups/authorize/').single;
    expect(body['trigger'], 'call');
    expect(body['call_uid'], 'abc');
    expect(body['refresh'], true);

    http = FakeHttp(config: cfg([plat('whatsapp')]));
    engine = LookupEngine(http: http, runner: runner, delay: (d) async {}, random: Random(1));
    await engine.run(number: kNumber, manual: true);
    body = http.postsTo('lookups/authorize/').single;
    expect(body['trigger'], 'manual');
    expect(body.containsKey('call_uid'), isFalse);
    expect(body['refresh'], false);
  });

  test('a call lookup without a call uid is refused locally, before any request', () async {
    http.config = cfg([plat('whatsapp')]);
    final r = await run(callUid: null);
    expect(r.stopCode, 'no_call');
    expect(http.log, isEmpty);
  });

  test('a bad number is refused locally, before any request', () async {
    final r = await engine.run(number: '12', callUid: 'c');
    expect(r.stopCode, 'bad_number');
    expect(http.log, isEmpty);
  });

  test('config failure stops the run with the server message', () async {
    http.getError = NmHttpException(401, 'device_revoked', 'دستگاه لغو شد');
    final r = await run();
    expect(r.stopCode, 'device_revoked');
    expect(r.stopMessage, 'دستگاه لغو شد');
  });

  test('facade.runAll delegates to the engine and reports progress', () async {
    http.config = cfg([plat('whatsapp')]);
    final facade = LookupFacade(http, runner: runner, delay: (d) async {});
    final seen = <String>[];
    await facade.runAll(number: kNumber, callUid: 'c', onProgress: (p) => seen.add('${p.platform}:${p.state}'));
    expect(seen, <String>['whatsapp:authorizing', 'whatsapp:running', 'whatsapp:done']);
  });
}

/// Runner that records when each lookup starts and ends.
class _SequenceRunner implements AdapterRunner {
  _SequenceRunner(this.order);

  final List<String> order;

  @override
  Future<AdapterResult> lookup(PlatformSpec spec, String digits, {Duration timeout = const Duration(seconds: 1)}) async {
    order.add('start:${spec.key}');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    order.add('end:${spec.key}');
    return const AdapterResult(status: 'found', onPlatform: true, displayName: 'x');
  }

  @override
  Future<LoginProbe> probe(PlatformSpec spec) async => const LoginProbe(loggedIn: true);

  @override
  Future<void> clearSession(PlatformSpec spec) async {}
}
