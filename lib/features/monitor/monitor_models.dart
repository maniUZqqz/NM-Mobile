import 'package:nm_mobile/core/nm/json_util.dart';

class HealthCheck {
  const HealthCheck({
    required this.name,
    required this.label,
    required this.ok,
    required this.detail,
  });

  factory HealthCheck.fromJson(Map<String, dynamic> j) => HealthCheck(
    name: asStr(j['name']),
    label: asStr(j['label'], asStr(j['name'])),
    ok: asBool(j['ok']),
    detail: asStr(j['detail']),
  );

  final String name;
  final String label;
  final bool ok;
  final String detail;
}

class HealthInfo {
  const HealthInfo({required this.status, required this.checks});

  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
    status: asStr(j['status'], 'unknown'),
    checks: asList(
      j['checks'],
    ).whereType<Map>().map((e) => HealthCheck.fromJson(asMap(e))).toList(),
  );

  /// ok | degraded | down | unknown
  final String status;
  final List<HealthCheck> checks;
}

class NodeInfo {
  const NodeInfo({
    required this.id,
    required this.name,
    required this.online,
    required this.enabled,
    this.lastSeen,
    this.gpu,
    this.services = const <String, bool>{},
    this.jobsDone,
  });

  factory NodeInfo.fromJson(Map<String, dynamic> j) {
    final svc = asMap(j['services']);
    return NodeInfo(
      id: asStr(j['id']),
      name: asStr(j['name']),
      online: asBool(j['online']),
      enabled: asBool(j['enabled'], true),
      lastSeen: asDate(j['last_seen']),
      gpu: asStrN(j['gpu']),
      services: {for (final e in svc.entries) e.key: e.value == true},
      jobsDone: asIntN(j['jobs_done']),
    );
  }

  final String id;
  final String name;
  final bool online;
  final bool enabled;
  final DateTime? lastSeen;
  final String? gpu;
  final Map<String, bool> services;
  final int? jobsDone;
}

class QueueInfo {
  const QueueInfo({
    this.computeQueued,
    this.computeRunning,
    this.jobsQueued,
    this.jobsProcessing,
    this.jobsWaiting,
    this.celery,
  });

  factory QueueInfo.fromJson(Map<String, dynamic> j) {
    final compute = asMap(j['compute']);
    final jobs = asMap(j['jobs']);
    final celeryRaw = j['celery'];
    Map<String, int>? celery;
    if (celeryRaw is Map) {
      celery = {};
      for (final e in celeryRaw.entries) {
        final v = asIntN(e.value);
        if (v != null) celery[e.key.toString()] = v;
      }
    }
    return QueueInfo(
      computeQueued: asIntN(compute['queued']),
      computeRunning: asIntN(compute['running']),
      jobsQueued: asIntN(jobs['queued']),
      jobsProcessing: asIntN(jobs['processing']),
      jobsWaiting: asIntN(jobs['waiting_approval']),
      celery: celery,
    );
  }

  final int? computeQueued;
  final int? computeRunning;
  final int? jobsQueued;
  final int? jobsProcessing;
  final int? jobsWaiting;

  /// null = سرور نتوانسته بخواند (نه صفر).
  final Map<String, int>? celery;
}

class FailureInfo {
  const FailureInfo({
    required this.kind,
    required this.id,
    required this.type,
    required this.error,
    this.at,
  });

  factory FailureInfo.fromJson(Map<String, dynamic> j) => FailureInfo(
    kind: asStr(j['kind']),
    id: asStr(j['id']),
    type: asStr(j['type']),
    error: asStr(j['error']),
    at: asDate(j['at']),
  );

  /// job | compute_job
  final String kind;
  final String id;
  final String type;
  final String error;
  final DateTime? at;
}

class ErrorBrief {
  const ErrorBrief({required this.kind, required this.message, this.at});

  static ErrorBrief? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = asMap(v);
    return ErrorBrief(
      kind: asStr(m['kind']),
      message: asStr(m['message']),
      at: asDate(m['at']),
    );
  }

  final String kind;
  final String message;
  final DateTime? at;
}

class AiInfo {
  const AiInfo({
    this.priority,
    this.priorityLabel,
    this.localOnline,
    this.localNode,
    this.localError,
    this.metisConfigured,
    this.metisError,
    this.metisCircuitOpen,
  });

  factory AiInfo.fromJson(Map<String, dynamic> j) {
    final local = asMap(j['local']);
    final metis = asMap(j['metis']);
    return AiInfo(
      priority: asStrN(j['priority']),
      priorityLabel: asStrN(j['priority_label']),
      localOnline: asBoolN(local['online']),
      localNode: asStrN(local['node']),
      localError: ErrorBrief.fromJson(local['last_error']),
      metisConfigured: asBoolN(metis['configured']),
      metisError: ErrorBrief.fromJson(metis['last_error']),
      metisCircuitOpen: asBoolN(metis['circuit_open']),
    );
  }

  final String? priority;
  final String? priorityLabel;
  final bool? localOnline;
  final String? localNode;
  final ErrorBrief? localError;
  final bool? metisConfigured;
  final ErrorBrief? metisError;
  final bool? metisCircuitOpen;
}

class DiskInfo {
  const DiskInfo({
    this.path,
    this.totalGb,
    this.usedGb,
    this.freeGb,
    this.percentUsed,
    this.low,
  });

  factory DiskInfo.fromJson(Map<String, dynamic> j) => DiskInfo(
    path: asStrN(j['path']),
    totalGb: asDoubleN(j['total_gb']),
    usedGb: asDoubleN(j['used_gb']),
    freeGb: asDoubleN(j['free_gb']),
    percentUsed: asDoubleN(j['percent_used']),
    low: asBoolN(j['low']),
  );

  final String? path;
  final double? totalGb;
  final double? usedGb;
  final double? freeGb;
  final double? percentUsed;
  final bool? low;
}

class MobileCounters {
  const MobileCounters({
    this.devicesOnline,
    this.smsQueued,
    this.smsSentToday,
    this.callsToday,
  });

  factory MobileCounters.fromJson(Map<String, dynamic> j) => MobileCounters(
    devicesOnline: asIntN(j['devices_online']),
    smsQueued: asIntN(j['sms_queued']),
    smsSentToday: asIntN(j['sms_sent_today']),
    callsToday: asIntN(j['calls_today']),
  );

  final int? devicesOnline;
  final int? smsQueued;
  final int? smsSentToday;
  final int? callsToday;
}

/// یک اقدامِ مجازِ سرور. `confirmText` همان متنِ تأییدی است که باید به کاربر نشان داد.
class ActionDef {
  const ActionDef({
    required this.action,
    required this.label,
    this.targetKind,
    this.confirmText,
    this.danger = false,
  });

  factory ActionDef.fromJson(Map<String, dynamic> j) => ActionDef(
    action: asStr(j['action']),
    label: asStr(j['label'], asStr(j['action'])),
    targetKind: asStrN(j['target_kind']),
    confirmText: asStrN(j['confirm_text']),
    danger: asBool(j['danger']),
  );

  final String action;
  final String label;
  final String? targetKind;
  final String? confirmText;
  final bool danger;
}

class MonitorSummary {
  const MonitorSummary({
    required this.generatedAt,
    required this.health,
    required this.nodes,
    required this.queue,
    required this.failures,
    required this.ai,
    required this.disk,
    required this.mobile,
    required this.actions,
  });

  factory MonitorSummary.fromJson(Map<String, dynamic> j) => MonitorSummary(
    generatedAt: asDate(j['generated_at']),
    health: HealthInfo.fromJson(asMap(j['health'])),
    nodes: asList(
      j['nodes'],
    ).whereType<Map>().map((e) => NodeInfo.fromJson(asMap(e))).toList(),
    queue: QueueInfo.fromJson(asMap(j['queue'])),
    failures: asList(
      j['failures'],
    ).whereType<Map>().map((e) => FailureInfo.fromJson(asMap(e))).toList(),
    ai: AiInfo.fromJson(asMap(j['ai'])),
    disk: DiskInfo.fromJson(asMap(j['disk'])),
    mobile: MobileCounters.fromJson(asMap(j['mobile'])),
    actions: asList(
      j['actions'],
    ).whereType<Map>().map((e) => ActionDef.fromJson(asMap(e))).toList(),
  );

  final DateTime? generatedAt;
  final HealthInfo health;
  final List<NodeInfo> nodes;
  final QueueInfo queue;
  final List<FailureInfo> failures;
  final AiInfo ai;
  final DiskInfo disk;
  final MobileCounters mobile;
  final List<ActionDef> actions;

  /// اقدام‌هایی که برای یک نوع هدف (مثل compute_node) تعریف شده‌اند.
  List<ActionDef> actionsFor(String targetKind) =>
      actions.where((a) => a.targetKind == targetKind).toList();

  /// اقدام‌های بدون هدف (مثل sms.pause).
  List<ActionDef> get globalActions =>
      actions.where((a) => a.targetKind == null).toList();

  ActionDef? action(String name) {
    for (final a in actions) {
      if (a.action == name) return a;
    }
    return null;
  }
}

class AuditEntry {
  const AuditEntry({
    this.at,
    required this.user,
    required this.device,
    required this.action,
    required this.target,
    required this.ok,
    required this.message,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    at: asDate(j['at']),
    user: asStr(j['user']),
    device: asStr(j['device']),
    action: asStr(j['action']),
    target: asStr(j['target']),
    ok: asBool(j['ok']),
    message: asStr(j['message']),
  );

  final DateTime? at;
  final String user;
  final String device;
  final String action;
  final String target;
  final bool ok;
  final String message;
}
