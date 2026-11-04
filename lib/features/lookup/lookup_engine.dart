import 'dart:math';

import 'lookup_facade.dart';
import 'lookup_messages.dart';

typedef LookupDelay = Future<void> Function(Duration duration);

/// Runs the guarded lookup of ONE number across the platforms the NM server enabled.
///
/// Rules (the server enforces them too; the phone never relies only on itself):
///  * one number per run, there is no list API anywhere;
///  * platforms are handled one after another (never in parallel) with a jittered pause
///    between real lookups;
///  * every platform first asks `lookups/authorize/` and only runs with the ticket it gets;
///  * a cached answer, a disabled platform or an unavailable adapter costs nothing;
///  * the run stops at once on rate_limited / bulk_blocked / no_matching_call / not_staff;
///  * nothing is retried in a loop.
class LookupEngine {
  LookupEngine({
    required this.http,
    required this.runner,
    LookupDelay? delay,
    Random? random,
    this.minGap = const Duration(seconds: 4),
    this.maxGap = const Duration(seconds: 9),
    this.perLookupTimeout = const Duration(seconds: 75),
  })  : _delay = delay ?? ((d) => Future<void>.delayed(d)),
        _random = random ?? Random();

  final NmHttp http;
  final AdapterRunner runner;
  final Duration minGap;
  final Duration maxGap;
  final Duration perLookupTimeout;
  final LookupDelay _delay;
  final Random _random;

  Duration _gap() {
    final spread = maxGap.inMilliseconds - minGap.inMilliseconds;
    final extra = spread <= 0 ? 0 : _random.nextInt(spread + 1);
    return Duration(milliseconds: minGap.inMilliseconds + extra);
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// International digits for the adapters (the server answer field named normalized wins; this is the fallback):
  /// 0912... / +98912... / 0098912... -> 98912...
  static String normalizeNumber(String raw) {
    var d = _digits(raw);
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0') && d.length == 11) return '98${d.substring(1)}';
    if (d.length == 10 && d.startsWith('9')) return '98$d';
    return d;
  }

  Future<LookupConfig> fetchConfig() async {
    final data = await http.getJson('lookups/config/');
    if (data is! Map) return const LookupConfig();
    return LookupConfig.fromJson(data.cast<String, dynamic>());
  }

  Future<LookupRunResult> run({
    required String number,
    String? callUid,
    bool manual = false,
    bool refresh = false,
    void Function(LookupProgress progress)? onProgress,
  }) async {
    final result = LookupRunResult();
    void emit(String platform, String state, [String message = '']) {
      final p = LookupProgress(platform, state, message);
      result.record(p);
      onProgress?.call(p);
    }

    final digits = _digits(number);
    if (digits.length < 8 || digits.length > 15) {
      result.stop('bad_number', lookupMessage('bad_number'));
      return result;
    }
    if (!manual && (callUid == null || callUid.isEmpty)) {
      result.stop('no_call', lookupMessage('no_call'));
      return result;
    }

    LookupConfig config;
    try {
      config = await fetchConfig();
    } on NmHttpException catch (e) {
      result.stop(e.code, lookupMessage(e.code, e.message));
      return result;
    }

    final queue = <LookupPlatformConfig>[];
    for (final p in config.platforms) {
      if (!p.enabled) {
        emit(p.key, 'skipped', 'در پنل NM خاموش است');
        continue;
      }
      if (!p.ready) {
        emit(p.key, 'skipped', lookupMessage('platform_not_ready'));
        continue;
      }
      if (!p.isServer) {
        final spec = platformSpecFor(p.key);
        if (spec == null) {
          emit(p.key, 'skipped', 'این پلتفرم در این نسخه پشتیبانی نمی‌شود');
          continue;
        }
        if (spec.unavailable) {
          emit(p.key, 'skipped', spec.unavailableReason);
          continue;
        }
      }
      queue.add(p);
    }

    var didRealLookup = false;
    for (var i = 0; i < queue.length; i++) {
      final platform = queue[i];
      final key = platform.key;
      emit(key, 'authorizing');

      Map<String, dynamic> auth;
      try {
        final body = <String, dynamic>{
          'number': number.trim(),
          'platform': key,
          'trigger': manual ? 'manual' : 'call',
          'refresh': refresh,
          if (!manual) 'call_uid': callUid,
        };
        final raw = await http.postJson('lookups/authorize/', body);
        auth = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
      } on NmHttpException catch (e) {
        final msg = lookupMessage(e.code, e.message);
        if (kStopRunCodes.contains(e.code)) {
          emit(key, 'failed', msg);
          result.stop(e.code, msg);
          for (var j = i + 1; j < queue.length; j++) {
            emit(queue[j].key, 'skipped', msg);
          }
          return result;
        }
        if (e.code == 'platform_disabled' || e.code == 'recently_refreshed') {
          emit(key, 'skipped', msg);
          continue;
        }
        // Unknown refusal or network failure: do not hammer the server, stop here.
        emit(key, 'failed', msg);
        result.stop(e.code, msg);
        for (var j = i + 1; j < queue.length; j++) {
          emit(queue[j].key, 'skipped', msg);
        }
        return result;
      }

      if (auth['allowed'] != true) {
        emit(key, 'done', auth['reason'] == 'cached' ? 'از حافظه (کمتر از ${config.cacheDays} روز)' : 'انجام نشد');
        continue;
      }
      final ticket = (auth['ticket'] ?? '').toString();
      if (ticket.isEmpty) {
        emit(key, 'failed', 'بلیت جستجو از سرور نیامد');
        continue;
      }
      final method = (auth['method'] ?? platform.method).toString();

      if (didRealLookup) {
        await _delay(_gap());
      }
      didRealLookup = true;
      emit(key, 'running');

      try {
        if (method == 'server') {
          await http.postJson('lookups/server/', <String, dynamic>{'ticket': ticket});
          emit(key, 'done');
          continue;
        }
        final spec = platformSpecFor(key)!;
        final fromServer = _digits((auth['normalized'] ?? '').toString());
        final target = fromServer.length >= 8 ? fromServer : normalizeNumber(number);
        final adapter = await runner
            .lookup(spec, target, timeout: perLookupTimeout)
            .timeout(perLookupTimeout + const Duration(seconds: 15), onTimeout: () => AdapterResult.error('timeout'));
        await http.postJson('lookups/', adapter.toSubmitBody(ticket));
        if (adapter.isLoginRequired) {
          emit(key, 'login_required', lookupMessage('login_required'));
        } else if (adapter.isError) {
          emit(key, 'failed', lookupMessage(adapter.error));
        } else if (adapter.status == 'found') {
          emit(key, 'done', 'پیدا شد');
        } else {
          emit(key, 'done', adapter.status == 'not_found' ? 'در این پیام‌رسان نیست' : 'انجام شد');
        }
      } on NmHttpException catch (e) {
        emit(key, 'failed', lookupMessage(e.code, e.message));
      } catch (e) {
        emit(key, 'failed', 'خطا: $e');
      }
    }
    return result;
  }
}
