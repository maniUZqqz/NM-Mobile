import 'dart:convert';

import 'lookup_facade.dart';

/// One platform as the server describes it in `lookups/config/`.
class LookupPlatformConfig {
  const LookupPlatformConfig({
    required this.key,
    required this.label,
    required this.enabled,
    required this.method,
    required this.ready,
    this.warning = '',
    this.leftToday,
  });

  factory LookupPlatformConfig.fromJson(Map<String, dynamic> json) {
    return LookupPlatformConfig(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      enabled: json['enabled'] == true,
      method: (json['method'] ?? 'webview').toString(),
      ready: json['ready'] != false,
      warning: (json['warning'] ?? '').toString(),
      leftToday: (json['left_today'] as num?)?.toInt(),
    );
  }

  final String key;
  final String label;
  final bool enabled;

  /// `webview` (this phone does it) or `server` (the NM server does it; Telegram).
  final String method;
  final bool ready;
  final String warning;
  final int? leftToday;

  bool get isServer => method == 'server';
}

class LookupConfig {
  const LookupConfig({this.cacheDays = 30, this.platforms = const <LookupPlatformConfig>[], this.rules = ''});

  factory LookupConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['platforms'];
    return LookupConfig(
      cacheDays: (json['cache_days'] as num?)?.toInt() ?? 30,
      platforms: raw is List
          ? raw.whereType<Map>().map((e) => LookupPlatformConfig.fromJson(e.cast<String, dynamic>())).toList()
          : const <LookupPlatformConfig>[],
      rules: (json['rules'] ?? '').toString(),
    );
  }

  final int cacheDays;
  final List<LookupPlatformConfig> platforms;
  final String rules;
}

/// What an adapter (a file named after the platform in assets/lookup/) returned, parsed. Absent fields are null.
class AdapterResult {
  const AdapterResult({
    required this.status,
    this.onPlatform,
    this.displayName,
    this.username,
    this.bio,
    this.deepLinkId,
    this.avatarB64,
    this.fieldSources = const <String, String>{},
    this.extra = const <String, dynamic>{},
    this.error = '',
  });

  factory AdapterResult.error(String code) => AdapterResult(status: 'error', error: code);

  factory AdapterResult.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final v = json[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final sources = json['field_sources'];
    final extra = json['extra'];
    return AdapterResult(
      status: (json['status'] ?? 'error').toString(),
      onPlatform: json['on_platform'] as bool?,
      displayName: text('display_name'),
      username: text('username'),
      bio: text('bio'),
      deepLinkId: text('deep_link_id'),
      avatarB64: text('avatar_b64'),
      fieldSources: sources is Map
          ? sources.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const <String, String>{},
      extra: extra is Map ? extra.cast<String, dynamic>() : const <String, dynamic>{},
      error: (json['error'] ?? '').toString(),
    );
  }

  /// Parses the JSON text returned by the page; never throws.
  factory AdapterResult.fromJsonString(String text) {
    try {
      final data = jsonDecode(text);
      if (data is Map) return AdapterResult.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      // fall through
    }
    return AdapterResult.error('bad_adapter_output');
  }

  final String status; // found | not_found | hidden | login_required | error
  final bool? onPlatform;
  final String? displayName;
  final String? username;
  final String? bio;
  final String? deepLinkId;
  final String? avatarB64;
  final Map<String, String> fieldSources;
  final Map<String, dynamic> extra;
  final String error;

  bool get isLoginRequired => status == 'login_required';
  bool get isError => status == 'error';

  /// Body of POST lookups/. Only what the platform really returned is sent.
  Map<String, dynamic> toSubmitBody(String ticket) {
    final body = <String, dynamic>{'ticket': ticket, 'status': status};
    if (onPlatform != null) body['on_platform'] = onPlatform;
    if (displayName != null) body['display_name'] = displayName;
    if (username != null) body['username'] = username;
    if (bio != null) body['bio'] = bio;
    if (deepLinkId != null) body['deep_link_id'] = deepLinkId;
    if (avatarB64 != null) body['avatar_b64'] = avatarB64;
    if (fieldSources.isNotEmpty) body['field_sources'] = fieldSources;
    if (extra.isNotEmpty) body['extra'] = extra;
    if (error.isNotEmpty) body['error'] = error;
    return body;
  }
}

/// Result of a login-state probe of one messenger web client.
class LoginProbe {
  const LoginProbe({required this.loggedIn, this.stage = 'unknown'});

  factory LoginProbe.fromJsonString(String text) {
    try {
      final data = jsonDecode(text);
      if (data is Map) {
        return LoginProbe(loggedIn: data['logged_in'] == true, stage: (data['stage'] ?? 'unknown').toString());
      }
    } catch (_) {
      // fall through
    }
    return const LoginProbe(loggedIn: false, stage: 'unknown');
  }

  final bool loggedIn;

  /// signed_in | qr | phone | code | auth | loading | unknown ...
  final String stage;
}

/// Summary of one `runAll`: last progress per platform and whether it was cut short.
class LookupRunResult {
  final Map<String, LookupProgress> byPlatform = <String, LookupProgress>{};
  final List<LookupProgress> events = <LookupProgress>[];
  String? stopCode;
  String? stopMessage;

  bool get stopped => stopCode != null;

  void record(LookupProgress p) {
    events.add(p);
    byPlatform[p.platform] = p;
  }

  void stop(String code, String message) {
    stopCode = code;
    stopMessage = message;
  }

  /// Platforms whose last state is `done`.
  List<String> get done =>
      byPlatform.values.where((p) => p.state == 'done').map((p) => p.platform).toList();
}
