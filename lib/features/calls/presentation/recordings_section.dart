import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/calls/data/call_settings.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/data/recording_repository.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/presentation/call_detail_page.dart';
import 'package:nm_mobile/features/calls/presentation/call_format.dart';
import 'package:nm_mobile/features/calls/presentation/call_setup_page.dart';
import 'package:nm_mobile/features/calls/presentation/consent_dialog.dart';
import 'package:nm_mobile/features/calls/presentation/recording_detail_page.dart';
import 'package:nm_mobile/features/calls/services/nm_recording_gateway.dart';
import 'package:nm_mobile/features/calls/services/recording_pipeline.dart';
import 'package:nm_mobile/features/calls/services/recording_sync.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

/// متن و رنگِ وضعیتِ یک ضبط در مسیر «ارسال به NM». (تابع خالص؛ تست دارد)
({String label, Color color}) recordingStatus(CallRecording r) {
  if (r.needsConsent) {
    return (label: 'منتظر رضایتِ ضبط (ارسال نشده)', color: AppColors.warning);
  }
  switch (r.transcriptStatus) {
    case TranscriptStatus.none:
      return (label: 'ارسال نشده', color: AppColors.textSecondary);
    case TranscriptStatus.queued:
      return (label: 'در صف ارسال به NM', color: AppColors.warning);
    case TranscriptStatus.running:
      return (
        label: r.uploadedAt == null ? 'در حال ارسال…' : 'ارسال شد؛ NM در حال تبدیل به متن…',
        color: AppColors.warning,
      );
    case TranscriptStatus.done:
      return (label: 'متن و تحلیل در NM آماده است', color: AppColors.success);
    case TranscriptStatus.failed:
      return (label: 'ناموفق', color: AppColors.error);
  }
}

/// بخش «ضبط‌های گوشی»: فایل‌هایی که ضبط‌کنندهٔ گوشی ساخته و برنامه پیدا کرده؛ ارسال به NM با
/// دروازهٔ رضایت.
class RecordingsSection extends StatefulWidget {
  const RecordingsSection({super.key, this.repository, this.gateway});

  final RecordingRepository? repository;
  final NmRecordingGateway? gateway;

  @override
  State<RecordingsSection> createState() => _RecordingsSectionState();
}

class _RecordingsSectionState extends State<RecordingsSection> {
  late final RecordingRepository _repo = widget.repository ?? RecordingRepository();
  List<CallRecording> _items = const [];
  CallSettings _settings = const CallSettings();
  bool _loading = true;
  bool _syncing = false;
  String? _message;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  NmRecordingGateway? _gateway() {
    if (widget.gateway != null) return widget.gateway;
    final c = NmSession.instance.client;
    if (c == null) return null;
    final api = CallsApi(
      c,
      upload: (path, {required fields, required filePath}) =>
          c.postMultipart(path, fields: fields, fileField: 'audio', filePath: filePath),
    );
    return CallsApiGateway(api, FileCallStateStore());
  }

  Future<void> _reload() async {
    final items = await _repo.all();
    final settings = await CallSettingsStorage.load();
    items.sort((a, b) => b.when.compareTo(a.when));
    if (!mounted) return;
    setState(() {
      _items = items;
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    final gw = _gateway();
    if (gw == null || _syncing) return;
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      final report = await RecordingSync(gateway: gw, repository: _repo).run();
      if (report.skipped && !_settings.consentAccepted) {
        _message = 'اول «تنظیم ضبط تماس» را بزنید و اطلاعیهٔ مسئولیت را بپذیرید.';
      } else {
        final imported = report.scan?.imported ?? 0;
        _message = imported > 0 ? '$imported ضبط تازه پیدا شد.' : 'ضبط تازه‌ای پیدا نشد.';
      }
    } on NmHttpException catch (e) {
      _message = e.message;
    } catch (e) {
      _message = 'خطا: $e';
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    await _reload();
  }

  Future<void> _send(CallRecording r) async {
    final gw = _gateway();
    if (gw == null) return;
    final pipeline = RecordingPipeline(repository: _repo, gateway: gw);
    try {
      if (r.needsConsent) {
        final how = await askRecordingConsent(context, r.number);
        if (how == null) {
          _snack('رضایت ثبت نشد؛ فایل ارسال نشد.');
          return;
        }
        await pipeline.confirmConsentAndSend(r.id, how);
      } else {
        await pipeline.requestSend(r.id);
      }
      await RecordingSync(gateway: gw, repository: _repo).run(scan: false);
    } on NmHttpException catch (e) {
      _snack(e.message);
    }
    await _reload();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search_rounded, size: 18),
                label: const Text('بررسی ضبط‌های جدید'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CallSetupPage()));
                await _reload();
              },
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('تنظیم'),
            ),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, style: const TextStyle(color: AppColors.primary, fontSize: 12)),
          ),
        if (!_settings.consentAccepted)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'ضبط تماس هنوز راه‌اندازی نشده. «تنظیم» را بزنید، اطلاعیهٔ مسئولیت را بپذیرید و پوشهٔ ضبط‌کنندهٔ گوشی را روشن کنید. '
              'برنامه خودش صدا ضبط نمی‌کند؛ فقط فایل‌های ضبط‌کنندهٔ گوشی را می‌خواند.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.7, fontSize: 13),
            ),
          ),
        const SizedBox(height: 10),
        if (_items.isEmpty && _settings.consentAccepted)
          const Text(
            'هنوز ضبطی پیدا نشده. بعد از یک تماسِ ضبط‌شده، «بررسی ضبط‌های جدید» را بزنید.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.7),
          ),
        for (final r in _items) _card(r),
      ],
    );
  }

  Widget _card(CallRecording r) {
    final st = recordingStatus(r);
    final canSend = r.hasAudio && r.uploadedAt == null && r.transcriptStatus != TranscriptStatus.running;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => RecordingDetailPage(recordingId: r.id, repository: _repo)),
            );
            await _reload();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(callDirectionIcon(r.direction), color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    StatusPill(label: st.label, color: st.color),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatCallWhen(r.when)}'
                  '${r.callDuration == null ? '' : ' · ${formatCallDuration(r.callDuration!)}'}'
                  '${r.linked ? '' : ' · به تماسی وصل نشده'}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                if (r.transcriptStatus == TranscriptStatus.failed && r.transcriptError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(r.transcriptError, style: const TextStyle(color: AppColors.error, fontSize: 12, height: 1.5)),
                  ),
                if (r.needsConsent)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'رضایتِ ضبطِ این شماره در NM ثبت نیست؛ تا تأیید نکنید هیچ فایلی ارسال نمی‌شود.',
                      style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.5),
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    if (canSend && r.number.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => _send(r),
                        icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                        label: Text(r.needsConsent ? 'تأیید رضایت و ارسال' : 'ارسال به NM'),
                      ),
                    if (r.nmCallUid.isNotEmpty && r.uploadedAt != null)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => CallDetailPage(uid: r.nmCallUid)),
                        ),
                        icon: const Icon(Icons.subtitles_rounded, size: 18),
                        label: const Text('متن و تحلیل در NM'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
