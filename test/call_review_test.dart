import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/features/calls/data/call_settings.dart';
import 'package:nm_mobile/features/calls/data/recording_repository.dart';
import 'package:nm_mobile/features/calls/services/recording_scanner.dart';
import 'package:sms_bridge/sms_bridge.dart';

// From SMS-and-call (deb261a). Its transcription pipeline tests were dropped: transcription is
// done by the NM server only; the NM pipeline is covered in recording_nm_test.dart.

class _FailingCopyPlatform implements CallPlatform {
  _FailingCopyPlatform(this.file);

  final RawAudioFile file;

  @override
  Future<List<RawAudioFile>> audioSince(DateTime since, {int limit = 500}) async => [file];

  @override
  Future<List<RawCallLogEntry>> callsSince(DateTime since, {int limit = 500}) async => const [];

  @override
  Future<String?> copyUri(String uri, String destination) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 4, 12, 0);

  test('a file that cannot be copied holds the scan watermark back so it is retried', () async {
    final dir = await Directory.systemTemp.createTemp('scan-');
    addTearDown(() => dir.delete(recursive: true));
    final modified = DateTime(2026, 11, 4, 11, 0);
    final file = RawAudioFile(
      id: 5,
      uri: 'content://media/5',
      displayName: 'Call recording 09123456789_261104_110000.m4a',
      relativePath: 'Recordings/Call/',
      mime: 'audio/mp4',
      durationMs: 60000,
      sizeBytes: 20000,
      dateAddedMillis: modified.millisecondsSinceEpoch,
      dateModifiedMillis: modified.millisecondsSinceEpoch,
    );
    final scanner = RecordingScanner(
      platform: _FailingCopyPlatform(file),
      repository: RecordingRepository(rootPath: '${dir.path}/store'),
      settings: () => const CallSettings(),
      clock: () => now,
    );

    final report = await scanner.scan();

    expect(report.imported, 0);
    expect(report.deferred, 1);
    expect(report.safeUntil, modified);
  });
}
