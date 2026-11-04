import 'dart:async';
import 'dart:math';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:nm_mobile/core/constants/app_constants.dart';
import 'package:nm_mobile/core/errors/error_classifier.dart';
import 'package:nm_mobile/core/nm/json_util.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/storage/app_storage.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/services/nm_call_cycle.dart';
import 'package:nm_mobile/features/calls/services/nm_recording_gateway.dart';
import 'package:nm_mobile/features/calls/services/recording_sync.dart';
import 'package:nm_mobile/features/gateway/data/claim_store.dart';
import 'package:nm_mobile/features/gateway/domain/sms_models.dart';
import 'package:nm_mobile/features/gateway/services/incoming_uploader.dart';
import 'package:nm_mobile/features/gateway/services/sms_pipeline.dart';
import 'package:nm_mobile/features/logs/data/log_storage.dart';
import 'package:nm_mobile/features/logs/domain/log_entry.dart';
import 'package:nm_mobile/features/optout/nm_optout_sync.dart';
import 'package:nm_mobile/features/optout/optout.dart';
import 'package:nm_mobile/services/lock_coordinator.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:nm_mobile/features/settings/domain/server_config.dart';
import 'package:sms_bridge/sms_bridge.dart';

class _Flow {
  _Flow(this.entry);
  final LogEntry entry;

  FlowStep get receive => entry.steps[0];
  FlowStep get sms => entry.steps[1];
  FlowStep get report => entry.steps[2];
}

String _kindFa(String kind) {
  switch (kind) {
    case 'otp':
      return 'کد تأیید';
    case 'marketing':
      return 'تبلیغاتی';
    default:
      return 'اطلاع‌رسانی';
  }
}

/// سرویس پس‌زمینهٔ گیت‌وی: پیامک‌های صف NM را می‌گیرد، با سیم‌کارت می‌فرستد و گزارش
/// می‌کند. منطق اصلی در [SmsPipeline] است (قابل تست)؛ این کلاس فقط زمان‌بندی،
/// heartbeat، صف‌های بومی و لاگ را اداره می‌کند.
class GatewayEngine {
  GatewayEngine(this.service);

  final ServiceInstance service;

  final List<LogEntry> _logs = <LogEntry>[];
  final Map<String, _Flow> _flows = <String, _Flow>{};
  final SessionStore _sessions = SessionStore();
  final ClaimStore _claims = FileClaimStore();
  final PendingIncomingStore _pending = FilePendingStore();

  NmSessionData? _session;
  NmClient? _client;
  SmsPipeline? _pipeline;
  IncomingUploader? _uploader;
  NmOptOutSync? _optOutSync;
  DateTime? _lastOptOutSync;
  DateTime? _lastKeepAlive;
  NmCallCycle? _calls;
  RecordingSync? _rec;
  bool _scanSoon = false;
  final CallStateStore _callState = FileCallStateStore();
  DateTime? _lastScan;
  NmSettings _settings = const NmSettings();
  ServerConfig _config = ServerConfig.defaults();
  List<SimCard> _sims = <SimCard>[];

  bool _stopped = false;
  bool _reloadSession = false;
  String _conn = 'init';
  int _consecutive = 0;
  int _polls = 0;
  int _sent = 0;
  int _failed = 0;
  int? _latency;
  DateTime? _lastOk;
  DateTime? _lastHeartbeat;
  String _lastNotif = '';

  Future<void> start() async {
    service.on('stopService').listen((_) => _shutdown());
    service.on('updateConfig').listen(_onConfigUpdate);
    service.on('requestStatus').listen((_) => _emitStatus());
    service.on('clearLogs').listen((_) {
      _logs.clear();
      _flows.clear();
    });
    service.on('sessionChanged').listen((_) => _reloadSession = true);
    service.on('scanRecordings').listen((_) => _scanSoon = true);
    // آلارم «بعد از پایان تماس» (WakeReceiver) ⇒ بلافاصله ضبط‌های تازه را بررسی کن
    WakeHub.add((reason) {
      if (reason == 'call_ended' || reason == 'calls') _scanSoon = true;
    });

    // جلوگیری از خوابیدن CPU/Wi-Fi وقتی برنامه بسته است (از راه هماهنگ‌کننده تا با قفل‌های
    // کمپین‌ها یکدیگر را رها نکنند)
    unawaited(LockCoordinator.acquire('gateway', needsWifi: true));

    _config = await ConfigStorage.load();
    await _loadSession();

    final history = await LogStorage.load();
    final changed = LogStorage.closeStale(history);
    _logs.addAll(history);
    for (final e in changed) {
      service.invoke('update', {'entry': e.toJson()});
    }

    _add(
      LogEntry(
        kind: LogKind.system,
        level: LogLevel.success,
        title: 'سرویس شروع شد',
        meta: {
          'سرور NM': _session?.serverUrl ?? 'جفت نشده',
          'دستگاه': _session?.deviceName ?? '-',
          'سیم‌کارت': _config.simTitle,
        },
      ),
    );
    _emitStatus();
    unawaited(_logEnvironment());
    unawaited(_loop());
  }

  Future<void> _loadSession() async {
    final d = await _sessions.load();
    _session = d;
    _lastHeartbeat = null;
    if (d == null) {
      _client = null;
      _pipeline = null;
      _uploader = null;
      _optOutSync = null;
      _calls = null;
      _rec = null;
      return;
    }
    final c = NmClient(baseUrl: d.serverUrl, token: d.deviceToken);
    _client = c;
    _pipeline = SmsPipeline(
      http: c,
      sender: _send,
      store: _claims,
      pickSub: _pickSub,
      onEvent: _onPipelineEvent,
    );
    _uploader = IncomingUploader(http: c, store: _pending, onStop: _rememberStop);
    _optOutSync = NmOptOutSync(http: c, cursor: FileOptOutCursor());
    final callsApi = CallsApi(
      c,
      upload: (path, {required fields, required filePath}) =>
          c.postMultipart(path, fields: fields, fileField: 'audio', filePath: filePath),
    );
    _calls = NmCallCycle(
      api: callsApi,
      store: _callState,
      drain: SmsBridge.drainCallEvents,
      readLog: ({required since, required limit}) =>
          SmsBridge.queryCallLog(sinceMillis: since.millisecondsSinceEpoch, limit: limit),
    );
    _rec = RecordingSync(gateway: CallsApiGateway(callsApi, _callState));
  }

  Future<SmsSendResult> _send({
    required String to,
    required String message,
    required int subId,
    required String? ref,
    required bool delivery,
  }) {
    return SmsBridge.sendSms(
      to: to,
      message: message,
      subId: subId,
      ref: ref,
      delivery: delivery,
    );
  }

  Future<void> _logEnvironment() async {
    try {
      final st = await SmsBridge.status();
      if (!st.available) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.error,
            title: 'افزونه بومی پیامک در سرویس در دسترس نیست',
            hint: 'برنامه را دوباره نصب کنید.',
            dedupeKey: 'env-plugin',
          ),
        );
        return;
      }
      if (!st.telephony) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.error,
            title: 'این دستگاه قابلیت پیامک ندارد',
            hint: 'برنامه را روی گوشی دارای سیم‌کارت اجرا کنید.',
            dedupeKey: 'env-telephony',
          ),
        );
      }
      if (!st.sendSms) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.error,
            title: 'مجوز ارسال پیامک داده نشده',
            hint: 'برنامه را باز کنید و از «مجوزهای گوشی» آن را فعال کنید.',
            dedupeKey: 'env-sms',
          ),
        );
      }
      if (st.airplane) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: 'حالت پرواز روشن است',
            hint: 'تا حالت پرواز روشن است پیامکی ارسال نمی‌شود.',
            dedupeKey: 'env-airplane',
          ),
        );
      }

      final q = await SmsBridge.getSimCards();
      if (!q.permissionGranted) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: 'دسترسی به لیست سیم‌کارت‌ها داده نشده',
            hint:
                'بدون مجوز «تلفن» انتخاب سیم‌کارت ممکن نیست و از پیش‌فرض گوشی استفاده می‌شود.',
            dedupeKey: 'env-phone',
          ),
        );
        return;
      }
      _sims = q.sims;
      final meta = <String, String>{'تعداد فعال': '${q.sims.length}'};
      for (final s in q.sims) {
        meta[s.slotLabel] =
            '${s.carrier.isNotEmpty ? s.carrier : s.name}${s.number.isNotEmpty ? ' · ${s.number}' : ''}'
            '${s.subscriptionId == q.defaultSmsSubId ? ' (پیش‌فرض پیامک)' : ''}';
      }
      meta['سیم انتخابی'] = _config.simTitle;
      _add(
        LogEntry(
          kind: LogKind.system,
          level: q.sims.isEmpty ? LogLevel.warning : LogLevel.info,
          title: q.sims.isEmpty
              ? 'سیم‌کارت فعالی پیدا نشد'
              : 'وضعیت سیم‌کارت‌ها',
          meta: meta,
        ),
      );
    } catch (_) {}
  }

  LogEntry _add(LogEntry e) {
    if (e.dedupeKey != null &&
        _logs.isNotEmpty &&
        _logs.first.dedupeKey == e.dedupeKey) {
      final top = _logs.first;
      top.count++;
      top.time = DateTime.now();
      top.detail = e.detail;
      top.hint = e.hint;
      top.tech = e.tech;
      top.meta = e.meta;
      _emit(top);
      return top;
    }

    _logs.insert(0, e);

    if (_logs.length > kMaxLogs) {
      _logs.removeRange(kMaxLogs, _logs.length);
    }

    _emit(e);
    return e;
  }

  void _touch(LogEntry e) {
    e.time = DateTime.now();
    _emit(e);
  }

  void _emit(LogEntry e) {
    service.invoke('update', {'entry': e.toJson()});
    LogStorage.save(_logs);
    _notify(e);
  }

  void _notify(LogEntry e) {
    final text = e.notificationText;
    final s = service;

    if (s is AndroidServiceInstance && text != _lastNotif) {
      _lastNotif = text;
      s.setForegroundNotificationInfo(title: 'گیت‌وی NM', content: text);
    }
  }

  void _emitStatus() {
    service.invoke('status', {
      'conn': _conn,
      'latency': _latency,
      'polls': _polls,
      'sent': _sent,
      'failed': _failed,
      'failures': _consecutive,
      'lastOk': _lastOk?.millisecondsSinceEpoch,
    });
  }

  String _host(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  }

  void _onConfigUpdate(Map<String, dynamic>? event) {
    if (event == null) return;
    try {
      final old = _config;
      _config = ServerConfig.fromJson(Map<String, dynamic>.from(event));
      if (old.simSubscriptionId != _config.simSubscriptionId ||
          old.simSlot != _config.simSlot) {
        _add(
          LogEntry(
            kind: LogKind.system,
            title: 'تنظیمات پیامک به‌روز شد',
            meta: {'سیم‌کارت': _config.simTitle},
          ),
        );
      }
    } catch (e) {
      _add(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.error,
          title: 'اعمال تنظیمات جدید ناموفق بود',
          tech: ErrorClassifier.describe(e),
        ),
      );
    }
  }

  Future<void> _shutdown() async {
    _stopped = true;

    _add(
      LogEntry(
        kind: LogKind.system,
        level: LogLevel.warning,
        title: 'سرویس متوقف شد',
        meta: {
          'تعداد بررسی': '$_polls',
          'پیامک ارسال‌شده': '$_sent',
          'خطاها': '$_failed',
        },
      ),
    );

    await LogStorage.flush(_logs);
    await LockCoordinator.release('gateway');
    unawaited(SmsBridge.cancelWake(slot: 'gateway'));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    service.stopSelf();
  }

  // ── حلقهٔ اصلی ──────────────────────────────────────────────────────────────

  Future<void> _loop() async {
    while (!_stopped) {
      var delay = const Duration(seconds: 5);
      try {
        delay = await _cycle();
      } catch (e) {
        delay = const Duration(seconds: 10);
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.error,
            title: 'خطای غیرمنتظره در سرویس',
            hint: 'اگر تکرار شد، گزارش را کپی و بررسی کنید.',
            tech: ErrorClassifier.describe(e),
            dedupeKey: 'unexpected:${e.runtimeType}',
          ),
        );
      }

      if (_stopped) break;
      _emitStatus();
      await Future<void>.delayed(delay);
    }
  }

  Duration get _backoff => Duration(seconds: min(2 + _consecutive * 2, 30));

  Future<Duration> _cycle() async {
    if (_reloadSession) {
      _reloadSession = false;
      await _loadSession();
      if (_session != null) {
        _conn = 'init';
        _consecutive = 0;
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.success,
            title: 'اتصال به NM برقرار شد',
            meta: {
              'سرور': _host(_session!.serverUrl),
              'دستگاه': _session!.deviceName,
            },
          ),
        );
      }
    }

    final p = _pipeline;
    final c = _client;
    if (p == null || c == null) {
      if (_conn != 'unpaired') {
        _conn = 'unpaired';
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: 'این گوشی هنوز به NM جفت نشده است',
            hint: 'برنامه را باز کنید و از صفحهٔ «اتصال به NM» جفت‌سازی کنید.',
            dedupeKey: 'unpaired',
          ),
        );
      }
      return const Duration(seconds: 5);
    }

    _polls++;
    final sw = Stopwatch()..start();
    try {
      await _heartbeatIfDue(c);
      await _nativeQueues(p);
      await _optOutStep();
      await _callsStep();
      await _keepAlive();
      final res = await p.tick(
        max: _settings.claimBatch,
        simSlot: _config.simSlot >= 0 ? _config.simSlot : null,
      );
      sw.stop();
      _latency = sw.elapsedMilliseconds;
      _onConnected();

      if (res.paused) {
        _conn = 'paused';
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: 'صف پیامک در NM متوقف است',
            hint: 'از پنل NM یا صفحهٔ «وضعیت NM» می‌توانید دوباره روشنش کنید.',
            dedupeKey: 'paused',
          ),
        );
        return const Duration(seconds: 15);
      }
      if (res.limited != null) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: res.limited == 'day'
                ? 'سقف ارسال روزانهٔ این گوشی پر شد'
                : 'سقف ارسال ساعتی این گوشی پر شد',
            hint: 'ارسال بعدی خودکار ادامه پیدا می‌کند.',
            dedupeKey: 'limited:${res.limited}',
          ),
        );
        return Duration(seconds: max(res.retryAfterS, 30));
      }
      if (res.messages.isNotEmpty) return const Duration(seconds: 1);
      return Duration(seconds: _settings.pollIntervalS);
    } on NmHttpException catch (e) {
      sw.stop();
      await _onApiError(e);
      return _conn == 'revoked' ? const Duration(seconds: 5) : _backoff;
    }
  }

  Future<void> _heartbeatIfDue(NmClient c) async {
    final now = DateTime.now();
    final last = _lastHeartbeat;
    if (last != null && now.difference(last) < const Duration(seconds: 60)) {
      return;
    }
    final st = await SmsBridge.deviceState();
    final bs = await SmsBridge.status();
    final q = await SmsBridge.getSimCards();
    if (q.permissionGranted) _sims = q.sims;
    final res = asMap(
      await c.postJson('heartbeat/', {
        'battery_percent': st.battery,
        'charging': st.charging,
        'network': st.network,
        'sims': [
          for (final s in q.sims)
            {
              'slot': s.slot,
              'subscription_id': s.subscriptionId,
              'carrier': s.carrier,
              'label': s.title,
            },
        ],
        'sms_ready': bs.sendSms && bs.telephony && !bs.airplane,
        'app_version': kAppVersion,
      }),
    );
    _lastHeartbeat = now;
    final s = res['settings'];
    if (s is Map) _settings = NmSettings.fromJson(asMap(s));
  }

  /// تماس‌ها: ثبتِ زنده، ارسال لاگ تماس و پیدا کردن فایل‌های ضبط. خطای این بخش
  /// نباید ارسال پیامک را مختل کند (فقط ۴۰۱ به بالا می‌رسد).
  Future<void> _callsStep() async {
    final cc = _calls;
    if (cc == null || !_settings.callsUploadEnabled) return;
    try {
      final st = await cc.process();
      final a = st.active;
      final ongoing = a != null && !a.ended;
      final now = DateTime.now();
      final rec = _rec;
      if (rec != null &&
          !ongoing &&
          (_scanSoon || _lastScan == null || now.difference(_lastScan!) > const Duration(seconds: 60))) {
        _lastScan = now;
        _scanSoon = false;
        final report = await rec.run();
        final imported = report.scan?.imported ?? 0;
        if (imported > 0) {
          _add(
            LogEntry(
              kind: LogKind.system,
              level: LogLevel.info,
              title: 'ضبط تماس تازه‌ای پیدا شد',
              detail: '$imported فایل در تب «تماس‌ها ⇐ ضبط‌های گوشی» است؛ بدون رضایتِ ثبت‌شده به NM نمی‌رود.',
            ),
          );
        }
        if (report.processed > 0) {
          service.invoke('recordingsChanged', {'processed': report.processed});
        }
      }
    } on NmHttpException {
      rethrow;
    } catch (e) {
      _add(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.warning,
          title: 'بخش تماس‌ها با خطا روبه‌رو شد',
          tech: ErrorClassifier.describe(e),
          dedupeKey: 'calls-step',
        ),
      );
    }
  }

  /// پیامک‌های دریافتی و گزارش‌های تحویل که گیرنده‌های بومی در صف گذاشته‌اند.
  Future<void> _nativeQueues(SmsPipeline p) async {
    final up = _uploader;
    if (up != null) {
      final incoming = await SmsBridge.drainIncoming();
      final r = await up.process(
        incoming,
        forward: _settings.forwardIncomingSms,
      );
      if (r.optOutsAdded > 0) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.info,
            title: 'درخواست «لغو» از مشتری ثبت شد',
            detail: '${r.optOutsAdded} شماره به فهرست «دیگر پیام نده» رفت.',
          ),
        );
      }
    }
    final deliveries = await SmsBridge.drainDelivery();
    if (deliveries.isNotEmpty) await p.handleDelivery(deliveries);
  }

  /// کسی «لغو/stop» جواب داد: به فهرست لغوِ محلیِ گوشی هم می‌رود تا کمپین‌های محلیِ
  /// مخاطب‌ها دیگر به او پیام ندهند (NM هم همین را برای صف خودش انجام می‌دهد).
  Future<void> _rememberStop(IncomingSms sms) async {
    if (sms.from.trim().isEmpty) return;
    final added = await OptOutStorage.add(
      OptOutEntry.create(phone: sms.from, source: OptOutSource.reply, at: sms.at),
    );
    if (added) {
      _add(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.info,
          title: 'درخواست «لغو» از ${sms.from}',
          detail: 'به فهرست «دیگر پیام نده»ی این گوشی اضافه شد.',
        ),
      );
    }
  }

  /// فهرست «دیگر پیام نده»ی NM را هر ۱۰ دقیقه به فهرست محلی می‌آورد.
  Future<void> _optOutStep() async {
    final sync = _optOutSync;
    if (sync == null || sync.unsupported) return;
    final now = DateTime.now();
    final last = _lastOptOutSync;
    if (last != null && now.difference(last) < const Duration(minutes: 10)) return;
    _lastOptOutSync = now;
    try {
      final added = await sync.sync();
      if (added > 0) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.info,
            title: 'فهرست «دیگر پیام نده» NM به‌روز شد',
            detail: '$added شمارهٔ تازه به فهرست لغوِ این گوشی آمد.',
          ),
        );
      }
    } on NmHttpException {
      rethrow;
    } catch (_) {}
  }

  /// آلارم «زنده‌ماندن»: تا وقتی سرویس زنده است هر چند دقیقه عقب‌تر می‌افتد و هرگز
  /// نمی‌رسد؛ اگر اندروید سرویس را بکشد، همین آلارم (WakeReceiver) آن را دوباره بالا می‌آورد.
  Future<void> _keepAlive() async {
    final now = DateTime.now();
    final last = _lastKeepAlive;
    if (last != null && now.difference(last) < const Duration(minutes: 5)) return;
    _lastKeepAlive = now;
    await SmsBridge.scheduleWake(
      now.add(const Duration(minutes: 20)),
      reason: 'gateway_keepalive',
      slot: 'gateway',
    );
  }

  // ── وضعیت اتصال ─────────────────────────────────────────────────────────────

  void _onConnected() {
    final was = _conn;
    _lastOk = DateTime.now();
    if (was == 'ok') {
      _consecutive = 0;
      return;
    }
    final tries = _consecutive;
    _consecutive = 0;
    _conn = 'ok';
    _add(
      LogEntry(
        kind: LogKind.response,
        level: LogLevel.success,
        title: was == 'init'
            ? 'اتصال به NM برقرار شد'
            : 'ارتباط با NM دوباره برقرار شد',
        detail: tries > 0 ? 'پس از $tries تلاش ناموفق' : null,
        meta: {'سرور': _host(_session?.serverUrl ?? '')},
      ),
    );
  }

  Future<void> _onApiError(NmHttpException e) async {
    if (e.status == 401) {
      _conn = 'revoked';
      _add(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.error,
          title: 'این گوشی از NM لغو شد',
          hint: 'توکن دستگاه از پنل NM لغو شده است. دوباره جفت‌سازی کنید.',
          dedupeKey: 'revoked',
        ),
      );
      await _sessions.clear();
      _session = null;
      _client = null;
      _pipeline = null;
      _uploader = null;
      _optOutSync = null;
      _calls = null;
      _rec = null;
      service.invoke('sessionRevoked');
      return;
    }
    _consecutive++;
    if (e.status == 0) {
      if (_conn != 'down') _failed++;
      _conn = 'down';
    } else {
      if (_conn != 'error') _failed++;
      _conn = 'error';
    }
    final info = e.status == 0
        ? ErrorInfo('NM در دسترس نیست', e.message, e.toString())
        : ErrorClassifier.httpStatus(e.status);
    _add(
      LogEntry(
        kind: e.status == 0 ? LogKind.request : LogKind.response,
        level: LogLevel.error,
        title: info.title,
        detail: e.message,
        hint: info.hint,
        tech: e.toString(),
        dedupeKey: 'api:${e.status}:${e.code}',
        meta: {
          'سرور': _host(_session?.serverUrl ?? ''),
          'تلاش متوالی': '$_consecutive',
          'تلاش بعدی': '${_backoff.inSeconds} ثانیه دیگر',
        },
      ),
    );
  }

  // ── رویدادهای خط لوله ⇒ لاگ ─────────────────────────────────────────────────

  String _short(String uid) => uid.length > 8 ? uid.substring(0, 8) : uid;

  void _onPipelineEvent(PipelineEvent e) {
    final m = e.sms;
    switch (e.type) {
      case 'claimed':
        if (m == null || _flows.containsKey(m.uid)) return;
        final flow = _Flow(
          LogEntry(
            kind: LogKind.flow,
            title: 'پیامک برای ${m.to}',
            meta: {
              'شناسه': _short(m.uid),
              'شماره': m.to,
              'نوع': _kindFa(m.kind),
              'سیم‌کارت': m.simSlot == null
                  ? _config.simTitle
                  : 'SIM ${m.simSlot! + 1}',
              'سرور': _host(_session?.serverUrl ?? ''),
            },
            steps: [
              FlowStep(
                'دریافت از NM',
                state: StepState.ok,
                detail: 'گرفته شد${m.attempt > 1 ? ' (تلاش ${m.attempt})' : ''}',
              ),
              FlowStep('ارسال پیامک'),
              FlowStep('گزارش به NM'),
            ],
          ),
        );
        _flows[m.uid] = flow;
        _add(flow.entry);
        break;
      case 'sending':
        final f = m == null ? null : _flows[m.uid];
        if (f == null) return;
        f.sms.update(StepState.pending, detail: 'در حال ارسال…');
        _touch(f.entry);
        break;
      case 'sent':
        final f = m == null ? null : _flows[m.uid];
        if (f == null || m == null) return;
        _sent++;
        final r = e.result;
        final simName = r == null ? '' : simNameOf(_sims, r.usedSubId);
        f.sms.update(
          StepState.ok,
          detail:
              'از $simName ارسال شد${r != null && r.parts > 1 ? ' (${r.parts} بخش)' : ''}',
          tech: r == null
              ? null
              : 'subId=${r.usedSubId} · parts=${r.partsOk}/${r.parts}',
        );
        if (simName.isNotEmpty) f.entry.meta['سیم‌کارت'] = simName;
        _touch(f.entry);
        break;
      case 'failed':
        final f = m == null ? null : _flows[m.uid];
        if (f == null) return;
        _failed++;
        final r = e.result;
        final info = r == null ? null : ErrorClassifier.smsResult(r);
        f.sms.update(
          StepState.fail,
          detail: info?.title ?? e.detail,
          hint: info?.hint,
          tech: info?.technical,
        );
        _touch(f.entry);
        break;
      case 'duplicate':
        final f = m == null ? null : _flows[m.uid];
        if (f == null) return;
        f.sms.update(StepState.warn, detail: e.detail);
        _touch(f.entry);
        break;
      case 'reported':
        final f = _flows[e.uid];
        if (f == null) return;
        final rejected = e.detail.startsWith('سرور نپذیرفت');
        f.report.update(
          rejected ? StepState.warn : StepState.ok,
          detail: rejected ? e.detail : 'به NM گزارش شد (${e.detail})',
        );
        _flows.remove(e.uid);
        _touch(f.entry);
        break;
      case 'report_failed':
        final f = _flows[e.uid];
        if (f == null) return;
        f.report.update(
          StepState.fail,
          detail: 'گزارش به NM نرسید',
          hint: 'پیامک ارسال شده؛ گزارش در بررسی بعدی خودکار تکرار می‌شود.',
          tech: e.detail,
        );
        _touch(f.entry);
        break;
      default:
        break;
    }
  }

  /// subId نهایی را تعیین می‌کند (سیم انتخابی کاربر، سیم اسلات خواسته‌شدهٔ NM، یا پیش‌فرض گوشی).
  Future<int> _pickSub(int? simSlot) async {
    final q = await SmsBridge.getSimCards();
    if (q.permissionGranted) _sims = q.sims;

    if (simSlot != null && q.permissionGranted) {
      for (final s in q.sims) {
        if (s.slot == simSlot) return s.subscriptionId;
      }
    }

    final picked = pickSubId(_config, q);

    if (q.permissionGranted) {
      final want = _config.simSubscriptionId;

      if (want >= 0 && picked != want && picked >= 0) {
        final s = q.sims.firstWhere(
          (x) => x.subscriptionId == picked,
          orElse: () => q.sims.first,
        );
        _config = _config.copyWith(
          simSubscriptionId: picked,
          simSlot: s.slot,
          simLabel: s.title,
        );
        unawaited(ConfigStorage.save(_config));
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: 'شناسه‌ی سیم‌کارت تغییر کرده بود؛ به‌روز شد',
            detail: 'سیم‌کارت اسلات ${s.slot + 1} با شناسه‌ی جدید انتخاب شد.',
            dedupeKey: 'sim-remap',
          ),
        );
      } else if (want < 0 && q.defaultSmsSubId < 0 && picked >= 0) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.info,
            title:
                'سیم‌کارت پیش‌فرض پیامک در گوشی تعیین نشده؛ از ${simNameOf(q.sims, picked)} استفاده شد',
            hint:
                'برای ثبات بیشتر یک سیم‌کارت را در «تنظیمات پیامک» برنامه انتخاب کنید.',
            dedupeKey: 'sim-auto',
          ),
        );
      }
    }

    return picked;
  }
}
