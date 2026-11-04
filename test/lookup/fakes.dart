import 'package:nm_mobile/features/lookup/lookup_facade.dart';

/// Scripted NM API. Nothing here touches the network. All numbers are made up.
class FakeHttp implements NmHttp {
  FakeHttp({this.config, this.latest = const <Map<String, dynamic>>[]});

  Object? config;
  List<Map<String, dynamic>> latest;

  /// Every call in order, e.g. `GET lookups/config/`, `POST lookups/authorize/`.
  final List<String> log = <String>[];
  final List<Map<String, dynamic>> posts = <Map<String, dynamic>>[];

  /// Return a Map/value, or an [NmHttpException] to make the call fail.
  Object? Function(String path, Map<String, dynamic> body)? onPost;

  Object? getError;

  @override
  Future<dynamic> getJson(String path, {Map<String, String>? query}) async {
    log.add('GET $path');
    final err = getError;
    if (err is NmHttpException) throw err;
    if (path == 'lookups/config/') return config;
    if (path == 'lookups/latest/') return <String, dynamic>{'profiles': latest};
    throw StateError('unexpected GET $path');
  }

  @override
  Future<dynamic> postJson(String path, Object? body) async {
    log.add('POST $path');
    final map = (body as Map).cast<String, dynamic>();
    posts.add(<String, dynamic>{'path': path, 'body': map});
    final handler = onPost;
    final result = handler != null ? handler(path, map) : null;
    if (result is NmHttpException) throw result;
    if (result != null) return result;
    if (path == 'lookups/authorize/') {
      return <String, dynamic>{
        'allowed': true,
        'ticket': 't-${map['platform']}',
        'method': map['platform'] == 'telegram' ? 'server' : 'webview',
      };
    }
    return <String, dynamic>{'ok': true};
  }

  List<Map<String, dynamic>> postsTo(String path) =>
      posts.where((p) => p['path'] == path).map((p) => p['body'] as Map<String, dynamic>).toList();
}

class FakeRunner implements AdapterRunner {
  final Map<String, AdapterResult> results = <String, AdapterResult>{};
  final Set<String> throwFor = <String>{};
  final List<String> calls = <String>[];

  @override
  Future<AdapterResult> lookup(PlatformSpec spec, String digits, {Duration timeout = const Duration(seconds: 1)}) async {
    calls.add('${spec.key}:$digits');
    if (throwFor.contains(spec.key)) throw StateError('webview crashed');
    return results[spec.key] ??
        AdapterResult(
          status: 'found',
          onPlatform: true,
          displayName: 'Name ${spec.key}',
          fieldSources: <String, String>{'display_name': spec.label},
        );
  }

  @override
  Future<LoginProbe> probe(PlatformSpec spec) async => const LoginProbe(loggedIn: true, stage: 'signed_in');

  @override
  Future<void> clearSession(PlatformSpec spec) async {}
}

Map<String, dynamic> plat(String key, {bool enabled = true, String method = 'webview', bool ready = true}) =>
    <String, dynamic>{'key': key, 'label': key, 'enabled': enabled, 'method': method, 'ready': ready};

Map<String, dynamic> cfg(List<Map<String, dynamic>> platforms) =>
    <String, dynamic>{'cache_days': 30, 'platforms': platforms, 'rules': 'قوانین'};

const String kNumber = '09120000001'; // made up
const String kDigits = '989120000001'; // the same number, international digits
