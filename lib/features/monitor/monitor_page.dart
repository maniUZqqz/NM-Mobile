import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/core/utils/persian_date.dart';
import 'package:nm_mobile/features/logs/domain/log_entry.dart';
import 'package:nm_mobile/features/monitor/audit_log_page.dart';
import 'package:nm_mobile/features/monitor/monitor_actions.dart';
import 'package:nm_mobile/features/monitor/monitor_models.dart';

String _faInt(int? v) => v == null ? 'نامشخص' : toPersianDigits(v);

String _faTime(DateTime? t) {
  if (t == null) return 'نامشخص';
  return '${formatPersianDate(t)} ${toPersianDigits(fmtTime(t).substring(0, 5))}';
}

/// داشبورد پایش NM: سلامت، سرورهای پردازش، صف، خطاها، مسیر هوش مصنوعی، دیسک و آمار موبایل.
class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key, this.session});

  final NmSession? session;

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  MonitorSummary? _data;
  String? _error;
  bool _loading = false;
  Timer? _timer;

  NmSession get _session => widget.session ?? NmSession.instance;
  NmClient? get _client => _session.client;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final c = _client;
    if (c == null || _loading) return;
    _loading = true;
    try {
      final s = await ActionRunner(c).summary();
      if (!mounted) return;
      setState(() {
        _data = s;
        _error = null;
      });
    } on NmApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا در خواندن وضعیت: $e');
    } finally {
      _loading = false;
    }
  }

  Future<bool> _confirm(String text, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
          color: danger ? AppColors.error : AppColors.warning,
        ),
        title: const Text('تأیید اقدام'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  )
                : null,
            child: const Text('بله، انجام بده'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _runAction(
    ActionDef def, {
    String? target,
    String? targetLabel,
  }) async {
    final c = _client;
    if (c == null) return;
    try {
      final r = await ActionRunner(c).run(
        def,
        target: target,
        targetLabel: targetLabel,
        confirm: (t) => _confirm(t, danger: def.danger),
      );
      if (!mounted) return;
      if (r.executed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.message)),
        );
        unawaited(_load());
      }
    } on NmApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) _errorCard(_error!),
          if (d == null && _error == null)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          if (d != null) ..._sections(d),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AuditLogPage(session: widget.session),
              ),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('گزارش اقدام‌های انجام‌شده'),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_off_rounded, color: AppColors.error),
          title: const Text('خواندن وضعیت ناموفق بود'),
          subtitle: Text(msg),
          trailing: IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(MonitorSummary d) {
    return [
      _healthCard(d),
      const SizedBox(height: 12),
      _nodesCard(d),
      const SizedBox(height: 12),
      _queueCard(d),
      const SizedBox(height: 12),
      _failuresCard(d),
      const SizedBox(height: 12),
      _aiCard(d),
      const SizedBox(height: 12),
      _diskCard(d),
      const SizedBox(height: 12),
      _mobileCard(d),
      if (d.generatedAt != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'به‌روزرسانی: ${_faTime(d.generatedAt)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
    ];
  }

  Widget _title(String text, {IconData? icon, Widget? trailing}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _healthCard(MonitorSummary d) {
    final st = d.health.status;
    final (label, color, icon) = switch (st) {
      'ok' => ('همه‌چیز سالم است', AppColors.success, Icons.check_circle_rounded),
      'degraded' => ('بخشی از سیستم مشکل دارد', AppColors.warning, Icons.warning_rounded),
      'down' => ('سیستم از کار افتاده', AppColors.error, Icons.error_rounded),
      _ => ('وضعیت نامشخص', AppColors.textSecondary, Icons.help_rounded),
    };
    return _card([
      _title('سلامت سرویس‌ها', icon: Icons.monitor_heart_rounded),
      const SizedBox(height: 10),
      Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
      for (final c in d.health.checks)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(
                c.ok ? Icons.check_rounded : Icons.close_rounded,
                size: 18,
                color: c.ok ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.detail.isEmpty ? c.label : '${c.label} — ${c.detail}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _nodesCard(MonitorSummary d) {
    final disable = d.action('compute_node.disable');
    final enable = d.action('compute_node.enable');
    return _card([
      _title('سرورهای پردازش', icon: Icons.memory_rounded),
      const SizedBox(height: 8),
      if (d.nodes.isEmpty)
        const Text('سرور پردازشی ثبت نشده است.',
            style: TextStyle(color: AppColors.textSecondary)),
      for (final n in d.nodes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: !n.enabled
                        ? AppColors.textSecondary
                        : (n.online ? AppColors.success : AppColors.error),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    !n.enabled
                        ? 'غیرفعال'
                        : (n.online ? 'آنلاین' : 'آفلاین'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 18),
                child: Text(
                  [
                    if (n.gpu != null) n.gpu!,
                    'کارهای انجام‌شده: ${_faInt(n.jobsDone)}',
                    if (n.lastSeen != null) 'آخرین تماس: ${_faTime(n.lastSeen)}',
                  ].join(' · '),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              if (n.services.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 18),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final e in n.services.entries)
                        Chip(
                          label: Text(e.key, style: const TextStyle(fontSize: 11)),
                          avatar: Icon(
                            e.value ? Icons.check : Icons.close,
                            size: 14,
                            color: e.value ? AppColors.success : AppColors.error,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 14),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (n.enabled && disable != null)
                      TextButton(
                        onPressed: () => _runAction(
                          disable,
                          target: n.id,
                          targetLabel: n.name,
                        ),
                        child: Text(disable.label),
                      ),
                    if (!n.enabled && enable != null)
                      TextButton(
                        onPressed: () => _runAction(
                          enable,
                          target: n.id,
                          targetLabel: n.name,
                        ),
                        child: Text(enable.label),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _queueCard(MonitorSummary d) {
    final q = d.queue;
    final pause = d.action('sms.pause');
    final resume = d.action('sms.resume');
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return _card([
      _title('صف کارها', icon: Icons.queue_rounded),
      const SizedBox(height: 8),
      row('سرور پردازش — در صف', _faInt(q.computeQueued)),
      row('سرور پردازش — در حال اجرا', _faInt(q.computeRunning)),
      row('کارهای سایت — در صف', _faInt(q.jobsQueued)),
      row('کارهای سایت — در حال پردازش', _faInt(q.jobsProcessing)),
      row('منتظر تأیید', _faInt(q.jobsWaiting)),
      if (q.celery == null)
        row('صف Celery', 'نامشخص')
      else
        for (final e in q.celery!.entries) row('Celery «${e.key}»', _faInt(e.value)),
      if (pause != null || resume != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            children: [
              if (pause != null)
                OutlinedButton.icon(
                  onPressed: () => _runAction(pause),
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                  label: Text(pause.label),
                ),
              if (resume != null)
                OutlinedButton.icon(
                  onPressed: () => _runAction(resume),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: Text(resume.label),
                ),
            ],
          ),
        ),
    ]);
  }

  Widget _failuresCard(MonitorSummary d) {
    return _card([
      _title('خطاهای اخیر', icon: Icons.report_problem_rounded),
      const SizedBox(height: 8),
      if (d.failures.isEmpty)
        const Text('خطای تازه‌ای نیست.',
            style: TextStyle(color: AppColors.textSecondary)),
      for (final f in d.failures)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${f.type.isEmpty ? f.kind : f.type} · شناسه ${f.id}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (f.error.isNotEmpty)
                Text(
                  f.error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              Text(
                _faTime(f.at),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in d.actionsFor(f.kind))
                    TextButton(
                      onPressed: () => _runAction(
                        a,
                        target: f.id,
                        targetLabel: '${f.type} ${f.id}',
                      ),
                      child: Text(a.label),
                    ),
                ],
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _aiCard(MonitorSummary d) {
    final a = d.ai;
    final reset = d.action('ai.reset_circuit');
    String yn(bool? v, String yes, String no) =>
        v == null ? 'نامشخص' : (v ? yes : no);
    return _card([
      _title('مسیر هوش مصنوعی', icon: Icons.psychology_rounded),
      const SizedBox(height: 8),
      Text(a.priorityLabel ?? a.priority ?? 'اولویت نامشخص'),
      const SizedBox(height: 6),
      Text(
        'لوکال: ${yn(a.localOnline, 'آنلاین', 'آفلاین')}'
        '${a.localNode == null ? '' : ' (${a.localNode})'}',
      ),
      if (a.localError != null)
        Text(
          'آخرین خطای لوکال: ${a.localError!.message}',
          style: const TextStyle(color: AppColors.warning, fontSize: 12),
        ),
      const SizedBox(height: 4),
      Text('متیس: ${yn(a.metisConfigured, 'تنظیم‌شده', 'تنظیم نشده')}'
          '${a.metisCircuitOpen == true ? ' · موقتاً کنار گذاشته شده' : ''}'),
      if (a.metisError != null)
        Text(
          'آخرین خطای متیس: ${a.metisError!.message}',
          style: const TextStyle(color: AppColors.warning, fontSize: 12),
        ),
      if (reset != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: OutlinedButton.icon(
            onPressed: () => _runAction(reset),
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(reset.label),
          ),
        ),
    ]);
  }

  Widget _diskCard(MonitorSummary d) {
    final k = d.disk;
    final pct = k.percentUsed;
    final low = k.low == true;
    return _card([
      _title('فضای دیسک سرور', icon: Icons.storage_rounded),
      const SizedBox(height: 10),
      if (pct == null)
        const Text('نامشخص', style: TextStyle(color: AppColors.textSecondary))
      else ...[
        LinearProgressIndicator(
          value: (pct / 100).clamp(0, 1).toDouble(),
          minHeight: 8,
          borderRadius: BorderRadius.circular(6),
          color: low ? AppColors.error : AppColors.primary,
          backgroundColor: AppColors.surfaceHighest,
        ),
        const SizedBox(height: 6),
        Text(
          '${toPersianDigits(pct.round())}٪ پر · آزاد: '
          '${k.freeGb == null ? 'نامشخص' : '${toPersianDigits(k.freeGb!.toStringAsFixed(1))} گیگابایت'}',
          style: TextStyle(color: low ? AppColors.error : null),
        ),
        if (low)
          const Text(
            'فضای دیسک کم است.',
            style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700),
          ),
      ],
    ]);
  }

  Widget _mobileCard(MonitorSummary d) {
    final m = d.mobile;
    Widget cell(String k, int? v) => Expanded(
      child: Column(
        children: [
          Text(_faInt(v),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 2),
          Text(k,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
    return _card([
      _title('موبایل‌ها', icon: Icons.smartphone_rounded),
      const SizedBox(height: 10),
      Row(
        children: [
          cell('گوشی آنلاین', m.devicesOnline),
          cell('پیامک در صف', m.smsQueued),
          cell('پیامک امروز', m.smsSentToday),
          cell('تماس امروز', m.callsToday),
        ],
      ),
    ]);
  }
}
