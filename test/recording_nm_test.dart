import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/core/storage/app_storage.dart';
import 'package:nm_mobile/features/calls/data/call_settings.dart';
import 'package:nm_mobile/features/calls/data/call_state.dart';
import 'package:nm_mobile/features/calls/data/recording_repository.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/domain/nm_call_models.dart';
import 'package:nm_mobile/features/calls/presentation/recordings_section.dart';
import 'package:nm_mobile/features/calls/services/nm_recording_gateway.dart';
import 'package:nm_mobile/features/calls/services/recording_pipeline.dart';
import 'package:nm_mobile/features/calls/services/recording_scanner.dart';
import 'package:nm_mobile/features/calls/services/recording_sync.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:sms_bridge/sms_bridge.dart';

/// NM edition of the recording pipeline: found file -> consent gate -> upload to NM ->
/// poll the NM server for transcript/notes. No real network, SMS or call anywhere.
class FakeGateway implements NmRecordingGateway {
  String? uid = 'call-1';
  bool consentGranted = true;
  Object? uploadError;
  Object? detailError;
  String detailStatus = 'ANALYSED';
  String detailError2 = '';
  final List<String> events = [];

  @override
  Future<String?> resolveCallUid(CallRecording recording) async {
    events.add('resolve');
    return uid;
  }

  @override
  Future<ConsentInfo> consent(String number) async {
    events.add('consent');
    return ConsentInfo(number: number, normalized: '', granted: consentGranted);
  }

  @override
  Future<void> grantConsent(String number, String obtainedHow) async {
    events.add('grant:$obtainedHow');
    consentGranted = true;
  }

  @override
  Future<void> upload(String callUid, File audio, {int? durationSeconds}) async {
    events.add('upload:$callUid');
    final e = uploadError;
    if (e != null) throw e;
  }

  @override
  Future<NmCall> detail(String callUid) async {
    events.add('detail');
    final e = detailError;
    if (e != null) throw e;
    return NmCall(uid: callUid, number: '', normalized: '', direction: 'in', status: detailStatus, error: detailError2);
  }
}

class FakePlatform implements CallPlatform {
  final List<RawAudioFile> files = [];
  final List<RawCallLogEntry> calls = [];

  @override
  Future<List<RawAudioFile>> audioSince(DateTime since, {int limit = 500}) async => List.of(files);

  @override
  Future<List<RawCallLogEntry>> callsSince(DateTime since, {int limit = 500}) async => List.of(calls);

  @override
  Future<String?> copyUri(String uri, String destination) async {
    final f = File(destination);
    await f.create(recursive: true);
    await f.writeAsBytes(List<int>.generate(4096, (i) => i % 200));
    return destination;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = DateTime(2026, 11, 4, 15, 0, 0);
  late DateTime now;
  late Directory dir;
  late RecordingRepository repo;
  late FakeGateway gw;

  setUp(() async {
    now = base;
    dir = await Directory.systemTemp.createTemp('rec-nm-');
    repo = RecordingRepository(rootPath: '${dir.path}/store');
    gw = FakeGateway();
    AppDir.setPathForTests(dir.path);
  });
  tearDown(() async {
    AppDir.setPathForTests(null);
    await dir.delete(recursive: true);
  });

  RecordingPipeline pipeline() => RecordingPipeline(repository: repo, gateway: gw, clock: () => now);

  Future<CallRecording> queued(
    String id, {
    String number = '09123456789',
    TranscriptStatus status = TranscriptStatus.queued,
    bool audio = true,
  }) async {
    final f = File('${dir.path}/$id.m4a')..writeAsBytesSync(List.filled(2048, 7));
    final r = CallRecording(
      id: id,
      audioPath: audio ? f.path : '',
      sourceKey: 'k$id',
      source: RecordingSource.phoneRecorder,
      recordedAt: base.subtract(const Duration(minutes: 10)),
      importedAt: base.subtract(const Duration(minutes: 9)),
      number: number,
      callStartedAt: base.subtract(const Duration(minutes: 15)),
      callDuration: const Duration(minutes: 5),
      linked: true,
      transcriptStatus: status,
    );
    await repo.upsert(r);
    return r;
  }

  group('pipeline: consent gate -> upload to NM -> poll', () {
    test('with consent: resolve call, check consent, upload, then wait for the NM server', () async {
      await queued('a');
      expect(await pipeline().processDue(), 1);

      expect(gw.events, ['resolve', 'consent', 'upload:call-1']);
      final r = (await repo.get('a'))!;
      expect(r.transcriptStatus, TranscriptStatus.running);
      expect(r.nmCallUid, 'call-1');
      expect(r.uploadedAt, now);
      expect(r.needsConsent, isFalse);
      expect(r.nextAttemptAt, now.add(const Duration(seconds: 20)));
    });

    test('NO consent: nothing is uploaded, the recording waits for the user', () async {
      gw.consentGranted = false;
      await queued('a');
      await pipeline().processDue();

      expect(gw.events.any((e) => e.startsWith('upload')), isFalse);
      final r = (await repo.get('a'))!;
      expect(r.needsConsent, isTrue);
      expect(r.transcriptStatus, TranscriptStatus.none);
      expect(r.uploadedAt, isNull);
      // and it is not retried in a loop
      expect(await pipeline().processDue(), 0);
    });

    test('the user confirms consent: it is recorded FIRST, then the file goes out', () async {
      gw.consentGranted = false;
      await queued('a');
      final p = pipeline();
      await p.processDue();
      expect(gw.events.where((e) => e.startsWith('upload')), isEmpty);

      await p.confirmConsentAndSend('a', 'گفتم ضبط می‌شود و موافقت کرد');
      await p.processDue();

      final order = gw.events.where((e) => e.startsWith('grant') || e.startsWith('upload')).toList();
      expect(order, ['grant:گفتم ضبط می‌شود و موافقت کرد', 'upload:call-1']);
      expect((await repo.get('a'))!.needsConsent, isFalse);
    });

    test('an empty «how consent was obtained» is refused and nothing is granted', () async {
      gw.consentGranted = false;
      await queued('a');
      expect(pipeline().confirmConsentAndSend('a', '  '), throwsArgumentError);
      expect(gw.events.where((e) => e.startsWith('grant')), isEmpty);
    });

    test('the server refusing with no_consent at upload time also stops at the gate', () async {
      gw.uploadError = NmHttpException(403, 'no_consent', 'رضایت ثبت نشده');
      await queued('a');
      await pipeline().processDue();
      final r = (await repo.get('a'))!;
      expect(r.needsConsent, isTrue);
      expect(r.uploadedAt, isNull);
      expect(r.permanentFailure, isFalse);
    });

    test('the call is not in NM yet (call log not uploaded): retried later, not lost', () async {
      gw.uid = null;
      await queued('a');
      await pipeline().processDue();
      var r = (await repo.get('a'))!;
      expect(r.transcriptStatus, TranscriptStatus.failed);
      expect(r.permanentFailure, isFalse);
      expect(r.nextAttemptAt, isNotNull);
      expect(gw.events.contains('consent'), isFalse, reason: 'no consent lookup without a call');

      // before the retry time nothing happens
      expect(await pipeline().processDue(), 0);
      // after it, the call has reached NM
      gw.uid = 'call-9';
      now = now.add(const Duration(minutes: 3));
      expect(await pipeline().processDue(), 1);
      r = (await repo.get('a'))!;
      expect(r.nmCallUid, 'call-9');
      expect(r.uploadedAt, isNotNull);
    });

    test('network errors back off and finally stop; the user can retry', () async {
      gw.uploadError = NmHttpException(0, 'network', 'قطع');
      await queued('a');
      final p = pipeline();
      for (var i = 0; i < 8; i++) {
        await p.processDue();
        now = now.add(const Duration(hours: 7));
      }
      final r = (await repo.get('a'))!;
      expect(r.permanentFailure, isTrue);
      expect(r.transcriptError, contains('متوقف شد'));

      gw.uploadError = null;
      await p.requestSend('a');
      expect(await p.processDue(), 1);
      expect((await repo.get('a'))!.uploadedAt, isNotNull);
    });

    test('a recording without a number is never uploaded', () async {
      await queued('a', number: '');
      await pipeline().processDue();
      expect(gw.events, isEmpty);
      expect((await repo.get('a'))!.permanentFailure, isTrue);
    });

    test('a revoked token pauses the queue without burning attempts', () async {
      gw.uploadError = NmHttpException(401, 'device_revoked', 'x');
      await queued('a');
      await pipeline().processDue();
      final r = (await repo.get('a'))!;
      expect(r.transcriptStatus, TranscriptStatus.queued);
      expect(r.permanentFailure, isFalse);
    });

    test('a recording left «running» by a dead service is picked up again after the lease', () async {
      final r = await queued('a', status: TranscriptStatus.running);
      await repo.update(r.id, (x) => x.copyWith(nextAttemptAt: now.subtract(const Duration(minutes: 1))));
      expect(await pipeline().processDue(), 1);
      expect(gw.events, ['resolve', 'consent', 'upload:call-1']);
    });

    test('polling: ANALYSED means the transcript and AI notes are ready in NM', () async {
      await queued('a');
      final p = pipeline();
      await p.processDue();
      now = now.add(const Duration(seconds: 30));
      await p.processDue();
      final r = (await repo.get('a'))!;
      expect(r.transcriptStatus, TranscriptStatus.done);
      expect(r.transcriptProvider, 'nm');
    });

    test('polling: keeps asking while NM works, and reports a server-side failure', () async {
      await queued('a');
      final p = pipeline();
      await p.processDue();

      gw.detailStatus = 'TRANSCRIBING';
      now = now.add(const Duration(seconds: 30));
      await p.processDue();
      var r = (await repo.get('a'))!;
      expect(r.transcriptStatus, TranscriptStatus.running);
      expect(r.nextAttemptAt, isNotNull);

      gw.detailStatus = 'FAILED';
      gw.detailError2 = 'صدایی شنیده نشد';
      now = now.add(const Duration(seconds: 30));
      await p.processDue();
      r = (await repo.get('a'))!;
      expect(r.transcriptStatus, TranscriptStatus.failed);
      expect(r.transcriptError, 'صدایی شنیده نشد');
    });

    test('polling: a transcript without notes is accepted after a few minutes', () async {
      await queued('a');
      final p = pipeline();
      await p.processDue();
      gw.detailStatus = 'TRANSCRIBED';
      now = now.add(const Duration(minutes: 1));
      await p.processDue();
      expect((await repo.get('a'))!.transcriptStatus, TranscriptStatus.running);
      now = now.add(const Duration(minutes: 5));
      await p.processDue();
      expect((await repo.get('a'))!.transcriptStatus, TranscriptStatus.done);
    });

    test('nextDueAt tells when the service must wake up again', () async {
      await queued('a');
      final p = pipeline();
      await p.processDue();
      expect(await p.nextDueAt(), now.add(const Duration(seconds: 20)));
    });
  });

  group('matching a phone recording to a call known to NM', () {
    final start = DateTime(2026, 11, 4, 14, 20);
    final calls = [
      KnownCall(uid: 'c1', number: '09123456789', startedAt: start, durationS: 300),
      KnownCall(uid: 'c2', number: '09350000000', startedAt: start, durationS: 300),
    ];

    CallRecording rec({String number = '09123456789', DateTime? callStarted, DateTime? recorded}) => CallRecording(
      id: 'r',
      audioPath: 'x',
      sourceKey: 'k',
      source: RecordingSource.phoneRecorder,
      recordedAt: recorded ?? start.add(const Duration(minutes: 5)),
      importedAt: start,
      number: number,
      callStartedAt: callStarted,
    );

    test('same number and same start time', () {
      expect(matchKnownCall(rec(callStarted: start), calls)!.uid, 'c1');
      expect(matchKnownCall(rec(number: '+989350000000', callStarted: start), calls)!.uid, 'c2');
    });

    test('a different number or a far-away time never matches', () {
      expect(matchKnownCall(rec(number: '09999999999', callStarted: start), calls), isNull);
      expect(matchKnownCall(rec(callStarted: start.add(const Duration(hours: 2))), calls), isNull);
    });

    test('without a linked call-log row only the recording time is used', () {
      expect(matchKnownCall(rec(recorded: start.add(const Duration(minutes: 6))), calls)!.uid, 'c1');
      expect(matchKnownCall(rec(recorded: start.add(const Duration(hours: 3))), calls), isNull);
    });
  });

  group('RecordingSync: scan -> link -> (consent gate) -> upload', () {
    RawAudioFile file() {
      final t = DateTime(2026, 11, 4, 14, 25, 30);
      return RawAudioFile(
        id: 7,
        uri: 'content://media/7',
        displayName: 'Call recording 09123456789_261104_142530.m4a',
        relativePath: 'Recordings/Call/',
        mime: 'audio/mp4',
        durationMs: 60000,
        sizeBytes: 20000,
        dateAddedMillis: t.millisecondsSinceEpoch,
        dateModifiedMillis: t.millisecondsSinceEpoch,
      );
    }

    RawCallLogEntry call() => RawCallLogEntry(
      id: 1,
      number: '09123456789',
      name: '',
      startedAtMillis: DateTime(2026, 11, 4, 14, 20).millisecondsSinceEpoch,
      durationSeconds: 300,
      type: 1,
    );

    Future<RecordingSync> sync(CallSettings settings) async {
      await CallSettingsStorage.save(settings);
      final platform = FakePlatform()
        ..files.add(file())
        ..calls.add(call());
      return RecordingSync(gateway: gw, platform: platform, repository: repo, clock: () => base);
    }

    test('does nothing until the owner accepted the recording notice', () async {
      final s = await sync(const CallSettings(autoUploadToNm: true));
      final report = await s.run();
      expect(report.skipped, isTrue);
      expect(await repo.all(), isEmpty);
      expect(gw.events, isEmpty);
    });

    test('without automatic upload the file is imported and linked but NOT sent', () async {
      final s = await sync(CallSettings(consentAcceptedAt: base));
      final report = await s.run();
      expect(report.scan!.imported, 1);
      final r = (await repo.all()).single;
      expect(r.linked, isTrue);
      expect(r.transcriptStatus, TranscriptStatus.none);
      expect(gw.events, isEmpty);
    });

    test('with automatic upload and consent already in NM the file goes out', () async {
      final s = await sync(CallSettings(consentAcceptedAt: base, autoUploadToNm: true));
      await s.run();
      expect(gw.events, ['resolve', 'consent', 'upload:call-1']);
      expect((await repo.all()).single.uploadedAt, isNotNull);
    });

    test('with automatic upload but NO consent in NM it stops at the gate', () async {
      gw.consentGranted = false;
      final s = await sync(CallSettings(consentAcceptedAt: base, autoUploadToNm: true));
      await s.run();
      expect(gw.events.any((e) => e.startsWith('upload')), isFalse);
      expect((await repo.all()).single.needsConsent, isTrue);
    });
  });

  group('recordingStatus labels', () {
    CallRecording r(TranscriptStatus s, {bool consent = false, DateTime? up}) => CallRecording(
      id: 'x',
      audioPath: 'p',
      sourceKey: 'k',
      source: RecordingSource.phoneRecorder,
      recordedAt: base,
      importedAt: base,
      transcriptStatus: s,
      needsConsent: consent,
      uploadedAt: up,
    );

    test('a recording waiting for consent says so, whatever its other state', () {
      expect(recordingStatus(r(TranscriptStatus.none, consent: true)).label, contains('رضایت'));
    });

    test('each state has its own text', () {
      final labels = {
        recordingStatus(r(TranscriptStatus.none)).label,
        recordingStatus(r(TranscriptStatus.queued)).label,
        recordingStatus(r(TranscriptStatus.running)).label,
        recordingStatus(r(TranscriptStatus.running, up: base)).label,
        recordingStatus(r(TranscriptStatus.done)).label,
        recordingStatus(r(TranscriptStatus.failed)).label,
      };
      expect(labels.length, 6);
    });
  });

  test('CallRecording keeps the NM fields through JSON', () {
    final a = CallRecording(
      id: 'x',
      audioPath: 'p',
      sourceKey: 'k',
      source: RecordingSource.phoneRecorder,
      recordedAt: base,
      importedAt: base,
      nmCallUid: 'u-1',
      needsConsent: true,
    );
    final b = CallRecording.fromJson(a.toJson());
    expect(b.nmCallUid, 'u-1');
    expect(b.needsConsent, isTrue);
  });

  test('CallSettings: no transcription or custom upload target exists any more', () {
    final s = CallSettings.fromJson({
      'consentAcceptedAt': 1,
      'autoUploadToNm': true,
      // old SMS-and-call keys must be ignored, never honoured
      'provider': 'openAiCompatible',
      'uploadEnabled': true,
      'uploadUrl': 'https://evil.example.com',
      'inAppRecorderEnabled': true,
    });
    expect(s.autoUploadToNm, isTrue);
    expect(s.toJson().keys.toSet(), {
      'consentAcceptedAt',
      'setupCompleted',
      'watchPhoneRecorder',
      'autoUploadToNm',
      'lastScanAtMillis',
      'importDays',
    });
  });
}
