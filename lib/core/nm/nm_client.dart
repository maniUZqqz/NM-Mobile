import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nm_mobile/core/constants/app_constants.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

/// خطای API ِ NM (یا مشکل شبکه). [message] جملهٔ فارسی قابل‌نمایش به کاربر است.
class NmApiException extends NmHttpException {
  NmApiException(super.status, super.code, super.message);

  /// status == 0 یعنی پاسخی از سرور نیامده (قطع شبکه، timeout، ...)
  bool get isNetwork => status == 0;

  bool get isRevoked => code == 'device_revoked';
}

/// نتیجهٔ جفت‌سازی موفق.
class PairResult {
  const PairResult({
    required this.deviceToken,
    required this.deviceUid,
    required this.deviceName,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.settings,
  });

  factory PairResult.fromJson(Map<String, dynamic> json) {
    final device = json['device'] is Map
        ? Map<String, dynamic>.from(json['device'] as Map)
        : <String, dynamic>{};
    final user = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : <String, dynamic>{};
    final settings = json['settings'] is Map
        ? Map<String, dynamic>.from(json['settings'] as Map)
        : <String, dynamic>{};
    return PairResult(
      deviceToken: (json['device_token'] ?? '').toString(),
      deviceUid: (device['uid'] ?? '').toString(),
      deviceName: (device['name'] ?? '').toString(),
      userId: (user['id'] as num?)?.toInt() ?? 0,
      username: (user['username'] ?? '').toString(),
      displayName: (user['display_name'] ?? '').toString(),
      settings: settings,
    );
  }

  final String deviceToken;
  final String deviceUid;
  final String deviceName;
  final int userId;
  final String username;
  final String displayName;
  final Map<String, dynamic> settings;
}

/// کلاینت HTTP ِ API موبایل NM. همهٔ مسیرها نسبت به `/api/v1/mobile/` هستند.
class NmClient implements NmHttp {
  NmClient({
    required String baseUrl,
    this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
    this.onDeviceRevoked,
  }) : baseUrl = normalizeBaseUrl(baseUrl),
       _http = httpClient ?? http.Client();

  final String baseUrl;

  /// توکن دستگاه (بدون پیشوند «Device»).
  String? token;

  final Duration timeout;

  /// وقتی سرور توکن را رد کند (۴۰۱) یک بار صدا زده می‌شود تا برنامه توکن را پاک کند.
  final void Function()? onDeviceRevoked;

  final http.Client _http;

  static const List<String> _pastedSuffixes = [
    '/api/v1/mobile',
    '/api/v1',
    '/api',
    '/panel',
  ];

  /// آدرسی که کاربر وارد کرده را مرتب می‌کند: بدون فاصله و اسلش انتهایی،
  /// با http:// اگر پروتکل ننوشته، و بدون «/api/v1/mobile» یا «/panel» اگر چسبانده باشد.
  static String normalizeBaseUrl(String raw) {
    var s = raw.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return s;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) {
      s = 'http://$s';
    }
    final hash = s.indexOf('#');
    if (hash >= 0) s = s.substring(0, hash);
    final q = s.indexOf('?');
    if (q >= 0) s = s.substring(0, q);
    var changed = true;
    while (changed) {
      changed = false;
      while (s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
        changed = true;
      }
      final low = s.toLowerCase();
      for (final suffix in _pastedSuffixes) {
        if (low.endsWith(suffix)) {
          s = s.substring(0, s.length - suffix.length);
          changed = true;
          break;
        }
      }
    }
    return s;
  }

  /// آدرس کامل یک مسیر API (مثلاً `lookups/latest/`).
  Uri uri(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    final u = Uri.parse('$baseUrl/$kApiPrefix/$p');
    if (query == null || query.isEmpty) return u;
    return u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  /// آدرس کامل برای مسیرهایی که سرور مطلق می‌دهد (مثل avatar_url).
  Uri resolve(String serverPath) {
    final p = serverPath.startsWith('/') ? serverPath : '/$serverPath';
    return Uri.parse('$baseUrl$p');
  }

  /// سرآیندهای احراز هویت، برای ویجت‌هایی مثل Image.network.
  Map<String, String> get authHeaders {
    final t = token;
    return {
      'User-Agent': 'NM-Mobile/$kAppVersion',
      if (t != null && t.isNotEmpty) 'Authorization': 'Device $t',
    };
  }

  Map<String, String> _headers({bool json = false}) => {
    ...authHeaders,
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json; charset=utf-8',
  };

  @override
  Future<dynamic> getJson(String path, {Map<String, String>? query}) {
    return _run(() => _http.get(uri(path, query), headers: _headers()));
  }

  @override
  Future<dynamic> postJson(String path, Object? body) {
    return _run(
      () => _http.post(
        uri(path),
        headers: _headers(json: true),
        body: jsonEncode(body ?? <String, dynamic>{}),
      ),
    );
  }

  Future<dynamic> deleteJson(String path) {
    return _run(() => _http.delete(uri(path), headers: _headers()));
  }

  /// آپلود فایل (multipart). برای فایل‌های صوتی بزرگ مهلت طولانی‌تر است.
  Future<dynamic> postMultipart(
    String path, {
    Map<String, String> fields = const {},
    required String fileField,
    required String filePath,
    String? fileName,
  }) {
    return _run(() async {
      final req = http.MultipartRequest('POST', uri(path));
      req.headers.addAll(_headers());
      req.fields.addAll(fields);
      req.files.add(
        await http.MultipartFile.fromPath(
          fileField,
          filePath,
          filename: fileName,
        ),
      );
      final streamed = await _http.send(req);
      return http.Response.fromStream(streamed);
    }, timeout: const Duration(minutes: 6));
  }

  /// دانلود بایت‌ها (عکس پروفایل، فایل صوتی) از یک مسیر مطلق سرور.
  Future<Uint8List> getBytes(String serverPath) async {
    try {
      final res = await _http
          .get(resolve(serverPath), headers: _headers())
          .timeout(const Duration(minutes: 2));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
      _decode(res);
      throw NmApiException(res.statusCode, 'http', 'دریافت فایل ناموفق بود.');
    } on NmApiException {
      rethrow;
    } catch (e) {
      throw _transportError(e);
    }
  }

  /// جفت‌سازی با نام کاربری و رمز کارمند NM. رمز هرگز ذخیره نمی‌شود.
  Future<PairResult> pairDevice({
    required String username,
    required String password,
    required String deviceName,
    required String installId,
    String model = '',
    String androidVersion = '',
    String appVersion = kAppVersion,
  }) async {
    final data = await postJson('pair/', {
      'username': username,
      'password': password,
      'device_name': deviceName,
      'install_id': installId,
      'model': model,
      'android_version': androidVersion,
      'app_version': appVersion,
    });
    if (data is! Map) {
      throw NmApiException(200, 'bad_response', 'پاسخ جفت‌سازی قابل خواندن نیست.');
    }
    final result = PairResult.fromJson(Map<String, dynamic>.from(data));
    if (result.deviceToken.isEmpty) {
      throw NmApiException(200, 'bad_response', 'سرور توکن دستگاه را برنگرداند.');
    }
    return result;
  }

  void close() => _http.close();

  // ── internals ──────────────────────────────────────────────────────────────

  Future<dynamic> _run(
    Future<http.Response> Function() call, {
    Duration? timeout,
  }) async {
    final http.Response res;
    try {
      res = await call().timeout(timeout ?? this.timeout);
    } catch (e) {
      throw _transportError(e);
    }
    return _decode(res);
  }

  NmApiException _transportError(Object e) {
    if (e is NmApiException) return e;
    if (e is TimeoutException) {
      return NmApiException(
        0,
        'timeout',
        'سرور NM پاسخ نداد. اینترنت گوشی و آدرس سرور را بررسی کنید.',
      );
    }
    if (e is HandshakeException || e is TlsException) {
      return NmApiException(
        0,
        'tls',
        'اتصال امن (https) برقرار نشد. گواهی سرور یا آدرس را بررسی کنید.',
      );
    }
    if (e is SocketException || e is http.ClientException) {
      return NmApiException(
        0,
        'network',
        'به سرور NM وصل نشد. اینترنت گوشی و آدرس سرور را بررسی کنید.',
      );
    }
    return NmApiException(0, 'error', 'خطای غیرمنتظره در ارتباط با سرور: $e');
  }

  dynamic _decode(http.Response res) {
    final status = res.statusCode;
    final ok = status >= 200 && status < 300;
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    dynamic data;
    if (text.trim().isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        if (ok) {
          throw NmApiException(
            status,
            'bad_response',
            'پاسخ سرور قابل خواندن نیست (JSON نیست). آدرس سرور درست است؟',
          );
        }
      }
    }
    if (ok) return data;

    var code = 'http_$status';
    var message = _defaultMessage(status);
    if (data is Map) {
      final err = data['error'];
      if (err is Map) {
        code = (err['code'] ?? code).toString();
        message = (err['message'] ?? message).toString();
      } else if (err is String && err.isNotEmpty) {
        message = err;
      } else if (data['detail'] is String) {
        message = data['detail'] as String;
      }
    }
    final t = token;
    if (status == 401 && t != null && t.isNotEmpty) {
      code = 'device_revoked';
      message = 'این دستگاه دیگر مجاز نیست؛ دوباره جفت‌سازی کنید.';
      final cb = onDeviceRevoked;
      if (cb != null) cb();
    }
    throw NmApiException(status, code, message);
  }

  String _defaultMessage(int status) {
    switch (status) {
      case 400:
        return 'درخواست نادرست بود.';
      case 401:
        return 'نام کاربری یا رمز درست نیست.';
      case 403:
        return 'دسترسی ندارید.';
      case 404:
        return 'آدرس پیدا نشد؛ آدرس سرور را بررسی کنید.';
      case 429:
        return 'درخواست‌ها زیاد بود؛ کمی بعد دوباره تلاش کنید.';
      default:
        if (status >= 500) return 'خطای سرور NM ($status).';
        return 'خطای ناشناخته ($status).';
    }
  }
}
