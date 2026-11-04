import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

/// پاسخ JSON با UTF-8 (برای MockClient).
http.Response jsonResp(Object? body, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// ذخیرهٔ نشست در حافظه (بدون فایل) تا تست‌های ویجت به IO واقعی نیاز نداشته باشند.
class MemorySessionStore extends SessionStore {
  MemorySessionStore() : super(dirOverride: '/unused');

  NmSessionData? stored;
  String? install;
  int saves = 0;
  int clears = 0;

  @override
  Future<NmSessionData?> load() async => stored;

  @override
  Future<void> save(NmSessionData data) async {
    stored = data;
    saves++;
  }

  @override
  Future<void> clear() async {
    stored = null;
    clears++;
  }

  @override
  Future<String> installId() async => install ??= newUuid();
}

/// NmHttp جعلی: هر درخواست را ثبت می‌کند و جوابش را [handler] می‌دهد.
class FakeNmHttp implements NmHttp {
  FakeNmHttp([this.handler]);

  Future<dynamic> Function(String method, String path, Object? payload)?
  handler;
  final List<String> calls = [];
  final List<Object?> payloads = [];

  Future<dynamic> _do(String method, String path, Object? payload) async {
    calls.add('$method $path');
    payloads.add(payload);
    final h = handler;
    if (h == null) return <String, dynamic>{};
    return h(method, path, payload);
  }

  @override
  Future<dynamic> getJson(String path, {Map<String, String>? query}) =>
      _do('GET', path, query);

  @override
  Future<dynamic> postJson(String path, Object? body) =>
      _do('POST', path, body);
}
