import 'package:flutter/material.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/core/utils/persian_date.dart';
import 'package:nm_mobile/features/logs/domain/log_entry.dart';
import 'package:nm_mobile/features/monitor/monitor_actions.dart';
import 'package:nm_mobile/features/monitor/monitor_models.dart';

/// گزارش اقدام‌هایی که از موبایل/پنل روی NM انجام شده (چه کسی، با کدام گوشی، چه چیزی).
class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key, this.session});

  final NmSession? session;

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  List<AuditEntry>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = (widget.session ?? NmSession.instance).client;
    if (c == null) return;
    try {
      final rows = await ActionRunner(c).auditLog(limit: 60);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } on NmApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش اقدام‌ها')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
            if (rows == null && _error == null)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            if (rows != null && rows.isEmpty)
              const Text(
                'هنوز اقدامی ثبت نشده است.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            if (rows != null)
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: Icon(
                        r.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                        color: r.ok ? AppColors.success : AppColors.error,
                      ),
                      title: Text(
                        r.target.isEmpty ? r.action : '${r.action} → ${r.target}',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                      ),
                      subtitle: Text(
                        '${r.user}${r.device.isEmpty ? '' : ' · ${r.device}'}'
                        '${r.at == null ? '' : '\n${formatPersianDate(r.at!)} ${toPersianDigits(fmtTime(r.at!).substring(0, 5))}'}'
                        '${r.message.isEmpty ? '' : '\n${r.message}'}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
