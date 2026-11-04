import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/core/utils/persian_date.dart';
import 'package:nm_mobile/features/assistant/assistant_models.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/domain/nm_call_models.dart';
import 'package:nm_mobile/features/calls/presentation/call_detail_page.dart';
import 'package:nm_mobile/features/calls/presentation/recordings_section.dart';
import 'package:nm_mobile/features/logs/domain/log_entry.dart';

String callTimeText(DateTime? t) {
  if (t == null) return '';
  return '${formatPersianDate(t)} ${toPersianDigits(fmtTime(t).substring(0, 5))}';
}

IconData callIcon(String d) {
  switch (d) {
    case 'in':
      return Icons.call_received_rounded;
    case 'out':
      return Icons.call_made_rounded;
    case 'missed':
      return Icons.call_missed_rounded;
    default:
      return Icons.call_end_rounded;
  }
}

/// تب «تماس‌ها»: تماس‌های ثبت‌شده در NM، و ضبط‌های روی گوشی (ارسال به NM با دروازهٔ رضایت).
class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  int _view = 0;
  List<NmCall>? _calls;
  String? _error;
  bool _busy = false;

  CallsApi? get _api {
    final c = NmSession.instance.client;
    return c == null ? null : CallsApi(c);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null || _busy) return;
    setState(() => _busy = true);
    try {
      final calls = await api.list(limit: 40);
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _error = null;
      });
    } on NmApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('تماس‌های NM'), icon: Icon(Icons.call_rounded)),
              ButtonSegment(value: 1, label: Text('ضبط‌های گوشی'), icon: Icon(Icons.mic_rounded)),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          const SizedBox(height: 14),
          if (_view == 1) const RecordingsSection() else ..._nmCalls(),
        ],
      ),
    );
  }

  List<Widget> _nmCalls() {
    return [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(_error!, style: const TextStyle(color: AppColors.error)),
        ),
      if (_calls == null && _error == null)
        const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      if (_calls != null && _calls!.isEmpty)
        const Text(
          'هنوز تماسی در NM ثبت نشده است. بعد از اولین تماس، اینجا می‌آید.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.6),
        ),
      if (_calls != null)
        for (final c in _calls!)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: Icon(callIcon(c.direction), color: AppColors.primary),
                title: Text(c.displayName ?? c.number, textDirection: c.displayName == null ? TextDirection.ltr : null),
                subtitle: Text(
                  '${nmDirectionLabel(c.direction)} · ${callTimeText(c.startedAt)}'
                  '${c.durationS == null ? '' : ' · ${faDigits('${c.durationS}')} ثانیه'}',
                ),
                trailing: Chip(
                  label: Text(callStatusLabel(c.status), style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => CallDetailPage(uid: c.uid, initial: c)),
                ),
              ),
            ),
          ),
    ];
  }
}
