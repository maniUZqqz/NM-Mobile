import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';

import 'support/helpers.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('adds http, strips slashes and pasted API/panel suffixes', () {
      expect(
        NmClient.normalizeBaseUrl('87.107.160.17:8040'),
        'http://87.107.160.17:8040',
      );
      expect(
        NmClient.normalizeBaseUrl(' http://nm.example.com/ '),
        'http://nm.example.com',
      );
      expect(
        NmClient.normalizeBaseUrl('https://nm.example.com/api/v1/mobile/'),
        'https://nm.example.com',
      );
      expect(
        NmClient.normalizeBaseUrl('http://87.107.160.17:8040/panel/'),
        'http://87.107.160.17:8040',
      );
      expect(NmClient.normalizeBaseUrl(''), '');
    });
  });

  group('NmClient', () {
    test('pair sends the credentials once and parses the device token', () async {
      late http.Request seen;
      final client = NmClient(
        baseUrl: 'http://nm.test:8040/',
        httpClient: MockClient((req) async {
          seen = req;
          return jsonResp({
            'device_token': 'nmd_abc',
            'device': {'uid': 'u-1', 'name': 'Pixel', 'created_at': '2026-11-04T10:00:00Z'},
            'user': {'id': 7, 'username': 'faraz', 'display_name': 'فراز'},
            'server': {'api_version': 1},
            'settings': {'sms_enabled': true},
          }, 201);
        }),
      );

      final r = await client.pairDevice(
        username: 'faraz',
        password: 'secret',
        deviceName: 'Pixel',
        installId: 'install-1',
        model: 'Pixel 7',
        androidVersion: '14',
      );

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://nm.test:8040/api/v1/mobile/pair/');
      expect(seen.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['username'], 'faraz');
      expect(body['install_id'], 'install-1');
      expect(r.deviceToken, 'nmd_abc');
      expect(r.deviceUid, 'u-1');
      expect(r.displayName, 'فراز');
      expect(r.userId, 7);
    });

    test('maps the server error message and code', () async {
      final client = NmClient(
        baseUrl: 'http://nm.test',
        httpClient: MockClient(
          (req) async => jsonResp({
            'error': {'code': 'bad_credentials', 'message': 'نام کاربری یا رمز درست نیست.'},
          }, 401),
        ),
      );
      try {
        await client.pairDevice(
          username: 'a',
          password: 'b',
          deviceName: 'x',
          installId: 'i',
        );
        fail('should throw');
      } on NmApiException catch (e) {
        expect(e.status, 401);
        expect(e.code, 'bad_credentials');
        expect(e.message, 'نام کاربری یا رمز درست نیست.');
        expect(e.isRevoked, isFalse);
      }
    });

    test('sends the device token and wipes via callback when revoked', () async {
      var revoked = 0;
      String? auth;
      final client = NmClient(
        baseUrl: 'http://nm.test',
        token: 'nmd_tok',
        onDeviceRevoked: () => revoked++,
        httpClient: MockClient((req) async {
          auth = req.headers['Authorization'];
          return jsonResp({
            'error': {'code': 'device_revoked', 'message': 'x'},
          }, 401);
        }),
      );
      try {
        await client.getJson('me/');
        fail('should throw');
      } on NmApiException catch (e) {
        expect(e.isRevoked, isTrue);
      }
      expect(auth, 'Device nmd_tok');
      expect(revoked, 1);
    });

    test('network failures become status 0 with a Persian message', () async {
      final client = NmClient(
        baseUrl: 'http://nm.test',
        httpClient: MockClient((req) async => throw const SocketException('down')),
      );
      try {
        await client.getJson('me/');
        fail('should throw');
      } on NmApiException catch (e) {
        expect(e.isNetwork, isTrue);
        expect(e.code, 'network');
        expect(e.message, contains('سرور'));
      }
    });

    test('timeouts are reported as timeout', () async {
      final client = NmClient(
        baseUrl: 'http://nm.test',
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((req) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return jsonResp({});
        }),
      );
      try {
        await client.getJson('me/');
        fail('should throw');
      } on NmApiException catch (e) {
        expect(e.code, 'timeout');
      }
    });

    test('a non-JSON success answer is rejected as bad_response', () async {
      final client = NmClient(
        baseUrl: 'http://nm.test',
        httpClient: MockClient((req) async => http.Response('<html>nginx</html>', 200)),
      );
      try {
        await client.getJson('me/');
        fail('should throw');
      } on NmApiException catch (e) {
        expect(e.code, 'bad_response');
      }
    });

    test('query parameters are added and POST bodies are JSON', () async {
      late http.Request seen;
      final client = NmClient(
        baseUrl: 'http://nm.test',
        token: 't',
        httpClient: MockClient((req) async {
          seen = req;
          return jsonResp({'ok': true});
        }),
      );
      await client.getJson('callerid/', query: {'number': '0912'});
      expect(seen.url.toString(), 'http://nm.test/api/v1/mobile/callerid/?number=0912');
      await client.postJson('sms/claim/', {'max': 5});
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), {'max': 5});
    });

    test('multipart upload carries the file and the token', () async {
      late http.BaseRequest seen;
      final dir = Directory.systemTemp.createTempSync('nm_up');
      final f = File('${dir.path}/a.m4a')..writeAsBytesSync([1, 2, 3, 4]);
      final client = NmClient(
        baseUrl: 'http://nm.test',
        token: 'tok',
        httpClient: _SendClient((req) async {
          seen = req;
          return jsonResp({'uid': 'c1', 'status': 'UPLOADED'}, 201);
        }),
      );
      final res = await client.postMultipart(
        'calls/c1/recording/',
        fields: {'source': 'builtin_recorder'},
        fileField: 'audio',
        filePath: f.path,
      );
      expect((res as Map)['status'], 'UPLOADED');
      expect(seen.headers['Authorization'], 'Device tok');
      expect(seen.url.path, '/api/v1/mobile/calls/c1/recording/');
      dir.deleteSync(recursive: true);
    });
  });
}

/// MockClient پشتیبانی send() ندارد؛ این کلاینت کوچک برای آزمونِ multipart است.
class _SendClient extends http.BaseClient {
  _SendClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    final res = await _handler(request);
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
      request: request,
    );
  }
}
