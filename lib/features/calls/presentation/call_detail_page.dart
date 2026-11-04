import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nm_mobile/core/nm/nm_client.dart';
import 'package:nm_mobile/core/nm/nm_session.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/assistant/assistant_models.dart';
import 'package:nm_mobile/features/assistant/assistant_page.dart';
import 'package:nm_mobile/features/calls/data/calls_api.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/presentation/calls_tab.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

String sentimentLabel(String s) {
  switch (s.toUpperCase()) {
    case 'POSITIVE':
      return 'مثبت';
    case 'NEUTRAL':
      return 'خنثی';
    case 'NEGATIVE':
      return 'منفی';
    default:
      return '';
  }
}

/// جزئیات یک تماس: متن مکالمه (پیاده‌شده در NM) و یادداشت‌های هوش مصنوعی.
class CallDetailPage extends StatefulWidget {
  const CallDetailPage({super.key, required this.uid, this.initial, this.api, this.pollEvery = const Duration(seconds: 5)});

  final String uid;
  final NmCall? initial;
  final CallsApi? api;
  final Duration pollEvery;

  @override
  State<CallDetailPage> createState() => _CallDetailPageState();
}

class _CallDetailPageState extends State<CallDetailPage> {
  NmCall? _call;
  String? _error;
  Timer? _timer;
  bool _busy = false;

  CallsApi? get _api {
    if (widget.api != null) return widget.api;
    final c = NmSession.instance.client;
    return c == null ? null : CallsApi(c);
  }

  @override
  void initState() {
    super.initState();
    _call = widget.initial;
    unawaited(_load());
    _timer = Timer.periodic(widget.pollEvery, (_) {
      final c = _call;
      if (c == null || callStatusInProgress(c.status)) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    try {
      final c = await api.detail(widget.uid);
      if (mounted) {
        setState(() {
          _call = c;
          _error = null;
        });
      }
    } on NmHttpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _reprocess() async {
    final api = _api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.reprocess(widget.uid);
      await _load();
    } on NmHttpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _call;
    final client = NmSession.instance.client;
    return Scaffold(
      appBar: AppBar(title: const Text('جزئیات تماس')),
      body: c == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: AppColors.primary)
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _header(c),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                    ),
                  const SizedBox(height: 12),
                  _notes(c),
                  const SizedBox(height: 12),
                  _transcript(c),
                  const SizedBox(height: 12),
                  if (client != null && c.number.isNotEmpty)
                    ProfilesCard(facade: LookupFacade(client), number: c.number, callUid: c.uid),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (c.number.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AssistantPage(number: c.number, callUid: c.uid, direction: c.direction),
                            ),
                          ),
                          icon: const Icon(Icons.support_agent_rounded),
                          label: const Text('دستیار این شماره'),
                        ),
                      if (c.hasAudio)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _reprocess,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('پردازش دوباره'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header(NmCall c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(callIcon(c.direction), color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.displayName ?? c.number,
                    textDirection: c.displayName == null ? TextDirection.ltr : null,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                Chip(label: Text(callStatusLabel(c.status), style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
              ],
            ),
            if (c.displayName != null)
              Directionality(textDirection: TextDirection.ltr, child: Text(c.number, style: const TextStyle(color: AppColors.textSecondary))),
            const SizedBox(height: 4),
            Text(
              '${callDirectionLabel(c.direction)} · ${callTimeText(c.startedAt)}'
              '${c.durationS == null ? '' : ' · ${faDigits('${c.durationS}')} ثانیه'}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            if (callStatusInProgress(c.status))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 4, color: AppColors.primary),
              ),
            if (c.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(c.error, style: const TextStyle(color: AppColors.error, height: 1.5)),
              ),
            if (c.status == 'NO_CONSENT')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'رضایت ضبط این شماره ثبت نشده؛ فایل صوتی ذخیره نشده است.',
                  style: TextStyle(color: AppColors.warning, height: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notes(NmCall c) {
    final hasNotes = c.summary.isNotEmpty || c.objections.isNotEmpty || c.commitments.isNotEmpty || c.nextSteps.isNotEmpty;
    if (!hasNotes) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'یادداشت هوش مصنوعی هنوز آماده نیست (بعد از ارسال ضبط و تبدیل به متن پدیدار می‌شود).',
            style: TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ),
      );
    }
    Widget section(String title, List<String> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            for (final i in items) Padding(padding: const EdgeInsets.only(top: 3), child: Text('• $i', style: const TextStyle(height: 1.5))),
          ],
        ),
      );
    }

    final sentiment = sentimentLabel(c.sentiment);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 18),
                const SizedBox(width: 6),
                const Expanded(child: Text('خلاصه و قدم بعدی (هوش مصنوعی)', style: TextStyle(fontWeight: FontWeight.w800))),
                if (sentiment.isNotEmpty)
                  Chip(label: Text(sentiment, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
              ],
            ),
            if (c.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.summary, style: const TextStyle(height: 1.6))),
            section('اعتراض‌ها و نگرانی‌ها', c.objections),
            section('قول‌هایی که داده شد', c.commitments),
            section('قدم بعدی پیشنهادی', c.nextSteps),
            const SizedBox(height: 8),
            const Text(
              'این‌ها پیشنهادند، نه تصمیم؛ درستی‌شان را با متن مکالمه بسنجید.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transcript(NmCall c) {
    if (c.transcript.isEmpty && c.segments.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.subtitles_rounded, color: AppColors.secondary, size: 18),
                const SizedBox(width: 6),
                const Expanded(child: Text('متن مکالمه', style: TextStyle(fontWeight: FontWeight.w800))),
                if (c.asrEngine.isNotEmpty)
                  Text('موتور: ${c.asrEngine}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            if (c.segments.isNotEmpty)
              for (final s in c.segments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('[${faDigits(s.start.toStringAsFixed(0))}s] ${s.text}', style: const TextStyle(height: 1.6)),
                )
            else
              SelectableText(c.transcript, style: const TextStyle(height: 1.7)),
          ],
        ),
      ),
    );
  }
}
