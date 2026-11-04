import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/storage/app_storage.dart';

/// یک UUID نسخهٔ ۴ (شناسهٔ نصب برنامه).
String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final hex = List<String>.generate(16, h).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// آنچه بعد از جفت‌سازی روی گوشی می‌ماند. رمز عبور هرگز ذخیره نمی‌شود.
class NmSessionData {
  const NmSessionData({
    required this.serverUrl,
    required this.deviceToken,
    required this.deviceUid,
    required this.deviceName,
    required this.userId,
    required this.username,
    required this.displayName,
    this.pairedAt,
  });

  factory NmSessionData.fromJson(Map<String, dynamic> j) => NmSessionData(
    serverUrl: (j['serverUrl'] ?? '').toString(),
    deviceToken: (j['deviceToken'] ?? '').toString(),
    deviceUid: (j['deviceUid'] ?? '').toString(),
    deviceName: (j['deviceName'] ?? '').toString(),
    userId: (j['userId'] as num?)?.toInt() ?? 0,
    username: (j['username'] ?? '').toString(),
    displayName: (j['displayName'] ?? '').toString(),
    pairedAt: DateTime.tryParse((j['pairedAt'] ?? '').toString()),
  );

  final String serverUrl;
  final String deviceToken;
  final String deviceUid;
  final String deviceName;
  final int userId;
  final String username;
  final String displayName;
  final DateTime? pairedAt;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'deviceToken': deviceToken,
    'deviceUid': deviceUid,
    'deviceName': deviceName,
    'userId': userId,
    'username': username,
    'displayName': displayName,
    'pairedAt': pairedAt?.toIso8601String(),
  };
}

/// ذخیرهٔ فایلی در پوشهٔ خصوصی برنامه (فقط خودِ برنامه به آن دسترسی دارد).
/// سرویس پس‌زمینه (isolate جدا) هم از همین فایل می‌خواند.
class SessionStore {
  SessionStore({this.dirOverride});

  final String? dirOverride;

  Future<String> _dir() async => dirOverride ?? await AppDir.path();

  Future<File> _file(String name) async => File('${await _dir()}/$name');

  Future<NmSessionData?> load() async {
    try {
      final f = await _file('nm_session.json');
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      if (text.trim().isEmpty) return null;
      final data = NmSessionData.fromJson(
        Map<String, dynamic>.from(jsonDecode(text) as Map),
      );
      if (data.serverUrl.isEmpty || data.deviceToken.isEmpty) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(NmSessionData data) async {
    final f = await _file('nm_session.json');
    await writeAtomicFile(f, jsonEncode(data.toJson()));
  }

  Future<void> clear() async {
    try {
      final f = await _file('nm_session.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// شناسهٔ نصب: یک بار ساخته می‌شود و با قطع اتصال هم می‌ماند.
  Future<String> installId() async {
    try {
      final f = await _file('nm_install_id.txt');
      if (await f.exists()) {
        final s = (await f.readAsString()).trim();
        if (s.length >= 16) return s;
      }
      final id = newUuid();
      await writeAtomicFile(f, id);
      return id;
    } catch (_) {
      return newUuid();
    }
  }
}

/// وضعیت اتصال برنامه به NM. فقط یک ChangeNotifier ساده است.
class NmSession extends ChangeNotifier {
  NmSession({SessionStore? store, http.Client? httpClient})
    : _store = store ?? SessionStore(),
      _httpClient = httpClient;

  static final NmSession instance = NmSession();

  final SessionStore _store;
  final http.Client? _httpClient;

  NmSessionData? _data;
  NmClient? _client;
  bool _loaded = false;

  bool get loaded => _loaded;
  bool get paired => _data != null;
  NmSessionData? get data => _data;

  /// کلاینت آمادهٔ استفاده؛ اگر جفت نشده باشیم null.
  NmClient? get client {
    final d = _data;
    if (d == null) return null;
    return _client ??= NmClient(
      baseUrl: d.serverUrl,
      token: d.deviceToken,
      httpClient: _httpClient,
      onDeviceRevoked: () {
        unawaited(wipe());
      },
    );
  }

  Future<void> load() async {
    _data = await _store.load();
    _client = null;
    _loaded = true;
    notifyListeners();
  }

  /// جفت‌سازی. [password] فقط همین‌جا و برای یک درخواست استفاده می‌شود.
  Future<NmSessionData> pair({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceName,
    String model = '',
    String androidVersion = '',
  }) async {
    final base = NmClient.normalizeBaseUrl(serverUrl);
    if (base.isEmpty || Uri.tryParse(base)?.host.isEmpty != false) {
      throw NmApiException(0, 'bad_url', 'آدرس سرور درست نیست.');
    }
    final installId = await _store.installId();
    final probe = NmClient(baseUrl: base, httpClient: _httpClient);
    final PairResult result;
    try {
      result = await probe.pairDevice(
        username: username.trim(),
        password: password,
        deviceName: deviceName.trim(),
        installId: installId,
        model: model,
        androidVersion: androidVersion,
      );
    } finally {
      if (_httpClient == null) probe.close();
    }
    final saved = NmSessionData(
      serverUrl: base,
      deviceToken: result.deviceToken,
      deviceUid: result.deviceUid,
      deviceName: result.deviceName.isEmpty
          ? deviceName.trim()
          : result.deviceName,
      userId: result.userId,
      username: result.username.isEmpty ? username.trim() : result.username,
      displayName: result.displayName,
      pairedAt: DateTime.now(),
    );
    await _store.save(saved);
    _data = saved;
    _client = null;
    notifyListeners();
    return saved;
  }

  /// قطع اتصال: اول به سرور خبر می‌دهیم (اگر شد)، بعد توکن را از گوشی پاک می‌کنیم.
  Future<void> unpair({bool tellServer = true}) async {
    final c = client;
    if (tellServer && c != null) {
      try {
        await c.postJson('unpair/', <String, dynamic>{});
      } catch (_) {
        // سرور در دسترس نبود؛ توکن را از پنل هم می‌شود لغو کرد.
      }
    }
    await wipe();
  }

  /// پاک‌کردن توکن از گوشی (بدون تماس با سرور).
  Future<void> wipe() async {
    await _store.clear();
    _data = null;
    _client = null;
    notifyListeners();
  }
}
