import 'package:nm_mobile/core/nm/json_util.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:nm_mobile/features/monitor/monitor_models.dart';

/// نتیجهٔ اجرای یک اقدام.
class ActionOutcome {
  const ActionOutcome({
    required this.executed,
    required this.ok,
    required this.message,
  });

  /// کاربر تأیید نکرد؛ هیچ درخواستی به سرور نرفت.
  const ActionOutcome.cancelled()
    : executed = false,
      ok = false,
      message = 'لغو شد';

  final bool executed;
  final bool ok;
  final String message;
}

/// اجرای اقدام‌های پایش. قانون: **بدون تأییدِ صریح کاربر هیچ درخواستی ارسال نمی‌شود.**
class ActionRunner {
  ActionRunner(this.http);

  final NmHttp http;

  static const String defaultConfirm = 'این اقدام انجام شود؟';

  /// متنی که در دیالوگ تأیید نشان داده می‌شود: متن سرور، یا پیش‌فرض.
  static String confirmTextFor(ActionDef def, {String? targetLabel}) {
    final base = (def.confirmText == null || def.confirmText!.trim().isEmpty)
        ? defaultConfirm
        : def.confirmText!.trim();
    if (targetLabel == null || targetLabel.isEmpty) return base;
    return '$base\n\nمورد: $targetLabel';
  }

  /// [confirm] باید true برگرداند تا درخواست ارسال شود. خطای سرور به شکل
  /// [NmHttpException] به بالا می‌رسد (پیام فارسی سرور همراه آن است).
  Future<ActionOutcome> run(
    ActionDef def, {
    String? target,
    String? targetLabel,
    Map<String, dynamic> params = const <String, dynamic>{},
    required Future<bool> Function(String confirmText) confirm,
  }) async {
    final approved = await confirm(
      confirmTextFor(def, targetLabel: targetLabel),
    );
    if (!approved) return const ActionOutcome.cancelled();
    final body = <String, dynamic>{
      'action': def.action,
      if (target != null) 'target': target,
      'params': params,
    };
    final data = await http.postJson('monitor/actions/', body);
    final m = asMap(data);
    return ActionOutcome(
      executed: true,
      ok: asBool(m['ok'], true),
      message: asStr(m['message'], 'انجام شد'),
    );
  }

  Future<List<AuditEntry>> auditLog({int limit = 50}) async {
    final data = await http.getJson(
      'monitor/actions/',
      query: {'limit': '$limit'},
    );
    return asList(
      asMap(data)['results'],
    ).whereType<Map>().map((e) => AuditEntry.fromJson(asMap(e))).toList();
  }

  Future<MonitorSummary> summary() async {
    final data = await http.getJson('monitor/summary/');
    return MonitorSummary.fromJson(asMap(data));
  }
}
