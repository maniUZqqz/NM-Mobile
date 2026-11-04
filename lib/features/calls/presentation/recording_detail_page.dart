import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/calls/data/recording_repository.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/presentation/call_format.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// جزئیات یک ضبط روی گوشی: اطلاعات تماس، پخش صدا، و حذف. متن و تحلیل در NM است
/// (دکمهٔ «متن و تحلیل در NM» در فهرست).
class RecordingDetailPage extends StatefulWidget {
  const RecordingDetailPage({super.key, required this.recordingId, this.repository});

  final String recordingId;
  final RecordingRepository? repository;

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  late final RecordingRepository _repo = widget.repository ?? RecordingRepository();
  CallRecording? _r;
  PlayerState _player = PlayerState.idle;
  Timer? _timer;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(SmsBridge.playerStop());
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _repo.get(widget.recordingId);
    if (!mounted) return;
    setState(() {
      _r = r;
      _missing = r == null;
    });
  }

  Future<void> _tick() async {
    final r = _r;
    if (r == null || !r.hasAudio) return;
    final s = await SmsBridge.playerState();
    if (mounted) setState(() => _player = s);
  }

  Future<void> _togglePlay() async {
    final r = _r;
    if (r == null || !r.hasAudio) return;
    if (_player.playing && _player.path == r.audioPath) {
      await SmsBridge.playerPause();
    } else if (_player.path == r.audioPath && _player.durationMs > 0) {
      await SmsBridge.playerResume();
    } else {
      await SmsBridge.playerPlay(r.audioPath);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف این ضبط؟'),
        content: const Text('فایل صوتیِ روی گوشی پاک می‌شود. اگر قبلاً به NM فرستاده شده، نسخهٔ NM می‌ماند.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SmsBridge.playerStop();
    await _repo.delete(widget.recordingId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ضبط تماس'),
        actions: [if (r != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded))],
      ),
      body: _missing
          ? const Center(child: Text('این ضبط دیگر وجود ندارد.'))
          : r == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        if (r.number.isNotEmpty && r.contactName.isNotEmpty)
                          Directionality(textDirection: TextDirection.ltr, child: Text(r.number)),
                        const SizedBox(height: 6),
                        Text(
                          '${callDirectionLabel(r.direction)} · ${formatCallWhen(r.when)}'
                          '${r.callDuration == null ? '' : ' · ${formatCallDuration(r.callDuration!)}'}',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        StatusPill(label: transcriptStatusLabel(r.transcriptStatus), color: transcriptStatusColor(r.transcriptStatus)),
                        if (r.transcriptError.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(r.transcriptError, style: const TextStyle(color: AppColors.error, height: 1.5)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (r.hasAudio)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          IconButton.filled(
                            onPressed: _togglePlay,
                            icon: Icon(_player.playing && _player.path == r.audioPath ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _player.path == r.audioPath && _player.durationMs > 0
                                  ? '${formatCallDuration(Duration(milliseconds: _player.positionMs))} / '
                                        '${formatCallDuration(Duration(milliseconds: _player.durationMs))}'
                                  : 'پخش فایل ضبط‌شده',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const Text('فایل صوتی از روی گوشی پاک شده است.', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
    );
  }
}
