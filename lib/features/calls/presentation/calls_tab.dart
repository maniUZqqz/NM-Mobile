import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/core/utils/persian_date.dart';
import 'package:nm_mobile/features/assistant/assistant_models.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/presentation/call_detail_page.dart';
import 'package:nm_mobile/features/calls/presentation/consent_dialog.dart';
import 'package:nm_mobile/features/calls/presentation/recording_setup_page.dart';
import 'package:nm_mobile/features/calls/services/recording_cycle.dart';
import 'package:nm_mobile/features/calls/services/recording_source.dart';
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

/// تب «تماس‌ها»: فهرست تماس‌های ثبت‌شده در NM + ضبط‌های پیداشده که منتظر ارسال‌اند.
class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  final CallStateStore _state = FileCallStateStore();
  final CallSettingsStore _settings = CallSettingsStore();

  List<NmCall>? _calls;
  List<PendingRecording> _pending = const [];
  String? _error;
  bool _busy = false;
  String? _uploading;

  CallsApi? get _api {
    final c = NmSession.instance.client;
    if (c == null) return null;
    return CallsApi(
      c,
      upload: (path, {required fields, required filePath}) =>
          c.postMultipart(path, fields: fields, fileField: 'audio', filePath: filePath),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  RecordingCycle? _cycle() {
    final api = _api;
    if (api == null) return null;
    return RecordingCycle(source: SafFolderSource(_settings), api: api, store: _state);
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _cycle()?.scan();
      final st = await _state.load();
      final calls = await api.list(limit: 40);
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _pending = st.pending;
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

  Future<void> _upload(PendingRecording p) async {
    final cycle = _cycle();
    if (cycle == null) return;
    setState(() => _uploading = p.uri);
    try {
      final r = await cycle.upload(p, askConsent: (number) => askRecordingConsent(context, number));
      if (!mounted) return;
      final msg = switch (r.result) {
        UploadResult.uploaded => 'ارسال شد؛ NM در حال تبدیل به متن و تحلیل است.',
        UploadResult.noConsent => r.message.isEmpty ? 'بدون رضایت ضبط ارسال نمی‌شود.' : r.message,
        UploadResult.unreadable => r.message,
        UploadResult.failed => 'ارسال نشد: ${r.message}',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _uploading = null);
      unawaited(_refresh());
    }
  }

  Future<void> _dismiss(PendingRecording p) async {
    await _cycle()?.dismiss(p);
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RecordingSetupPage()));
              unawaited(_refresh());
            },
            icon: const Icon(Icons.folder_special_rounded),
            label: const Text('تنظیم ضبط تماس (پوشهٔ ضبط‌های گوشی)'),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: const TextStyle(color: AppColors.error)),
            ),
          if (_pending.isNotEmpty) ...[
            const Text('ضبط‌های پیداشده — منتظر ارسال', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'بدون ثبت رضایتِ طرف مقابل هیچ فایلی به NM نمی‌رود.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final p in _pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(p.number, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        Text(
                          '${callTimeText(p.modified)} · ${p.note}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: _uploading != null ? null : () => _upload(p),
                              icon: _uploading == p.uri
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.cloud_upload_rounded, size: 18),
                              label: const Text('ارسال به NM'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(onPressed: () => _dismiss(p), child: const Text('نادیده بگیر')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
          const Text('تماس‌ها', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
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
                      '${callDirectionLabel(c.direction)} · ${callTimeText(c.startedAt)}'
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
        ],
      ),
    );
  }
}
