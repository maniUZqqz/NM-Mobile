// Public surface of the messenger-profile lookup feature.
//
// OWNERSHIP: the "lookup" work stream owns everything under lib/features/lookup/.
// The core app only depends on the names declared in THIS file, so both streams can
// work in parallel. Keep these signatures stable; extend, do not break.
//
// See docs/api-contract.md ("Messenger profile lookup") for the server rules. In short:
// lookups happen only for numbers of real calls (or one manual lookup), always go
// through `lookups/authorize/` first, and the owner logs into the messengers himself.
import 'package:flutter/material.dart';

/// Minimal HTTP view of the NM mobile API. Paths are relative to `/api/v1/mobile/`,
/// e.g. `lookups/latest/`. The core app's NmClient implements this.
/// Implementations throw [NmHttpException] for non-2xx answers.
abstract class NmHttp {
  Future<dynamic> getJson(String path, {Map<String, String>? query});
  Future<dynamic> postJson(String path, Object? body);
}

class NmHttpException implements Exception {
  NmHttpException(this.status, this.code, this.message);

  final int status;
  final String code;

  /// Persian sentence from the server, safe to show to the user.
  final String message;

  @override
  String toString() => 'NmHttpException($status, $code): $message';
}

/// One stored profile (the "Profile object" of the API contract).
class ProfileView {
  const ProfileView({
    required this.platform,
    required this.label,
    required this.status,
    this.onPlatform,
    this.displayName,
    this.username,
    this.bio,
    this.avatarPath,
    this.fieldSources = const <String, String>{},
    this.lookedUpAt,
    this.ageDays,
    this.stale = false,
    this.method = '',
  });

  factory ProfileView.fromJson(Map<String, dynamic> json) {
    final sources = json['field_sources'];
    return ProfileView(
      platform: (json['platform'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      onPlatform: json['on_platform'] as bool?,
      displayName: json['display_name'] as String?,
      username: json['username'] as String?,
      bio: json['bio'] as String?,
      avatarPath: json['avatar_url'] as String?,
      fieldSources: sources is Map
          ? sources.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const <String, String>{},
      lookedUpAt: DateTime.tryParse((json['looked_up_at'] ?? '').toString()),
      ageDays: (json['age_days'] as num?)?.toInt(),
      stale: json['stale'] == true,
      method: (json['method'] ?? '').toString(),
    );
  }

  final String platform; // telegram | whatsapp | eitaa | bale | soroush | rubika
  final String label; // Persian label
  final String status; // found | not_found | hidden | login_required | error
  final bool? onPlatform;
  final String? displayName;
  final String? username;
  final String? bio;

  /// Path on the NM server (needs the device token), e.g. /api/v1/mobile/lookups/<uid>/avatar/
  final String? avatarPath;

  /// field name -> human source ("WhatsApp: push name")
  final Map<String, String> fieldSources;
  final DateTime? lookedUpAt;
  final int? ageDays;
  final bool stale;
  final String method;
}

/// Progress of one platform during [LookupFacade.runAll].
class LookupProgress {
  const LookupProgress(this.platform, this.state, [this.message = '']);

  final String platform;

  /// queued | authorizing | running | login_required | done | skipped | failed
  final String state;
  final String message;
}

class LookupFacade {
  LookupFacade(this.http);

  final NmHttp http;

  /// Newest stored profile per platform for this number (never triggers a lookup).
  Future<List<ProfileView>> latest(String number) async {
    final data = await http.getJson('lookups/latest/', query: {'number': number});
    final list = (data is Map ? data['profiles'] : null) as List? ?? const [];
    return list
        .whereType<Map>()
        .map((e) => ProfileView.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Runs every enabled+ready platform for ONE number, one after another, politely
  /// spaced. `callUid` ties the lookup to a real call; `manual` is the single manual
  /// lookup of a staff user. STUB: the lookup engine replaces this body.
  Future<void> runAll({
    required String number,
    String? callUid,
    bool manual = false,
    bool refresh = false,
    void Function(LookupProgress progress)? onProgress,
  }) async {}
}

/// Card for the in-call screen and the call detail: latest profiles with the source of
/// each field, "look up now" and "refresh" buttons. STUB until the lookup engine lands.
class ProfilesCard extends StatelessWidget {
  const ProfilesCard({
    super.key,
    required this.facade,
    required this.number,
    this.callUid,
    this.manual = false,
  });

  final LookupFacade facade;
  final String number;
  final String? callUid;
  final bool manual;

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('پروفایل پیام‌رسان‌ها: به‌زودی'),
      ),
    );
  }
}

/// Screen where the owner logs into the messengers (WebViews) and sees which are
/// ready, with the Persian ban-risk warning. STUB until the lookup engine lands.
class MessengersScreen extends StatelessWidget {
  const MessengersScreen({super.key, required this.facade});

  final LookupFacade facade;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پیام‌رسان‌ها')),
      body: const Center(child: Text('به‌زودی')),
    );
  }
}
