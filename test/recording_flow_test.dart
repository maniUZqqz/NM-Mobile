import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:nm_mobile/features/calls/data/call_settings.dart';
import 'package:nm_mobile/features/calls/data/recording_repository.dart';
import 'package:nm_mobile/features/calls/domain/call_models.dart';
import 'package:nm_mobile/features/calls/services/recording_scanner.dart';

/// بستر جعلیِ اندروید: فایل‌ها و تماس‌ها از لیست می‌آیند؛ «کپی» یک فایل واقعی می‌نویسد.
class FakePlatform implements CallPlatform {
  final List<RawAudioFile> files = [];
  final List<RawCallLogEntry> calls = [];

  @override
  Future<List<RawAudioFile>> audioSince(DateTime since, {int limit = 500}) async =>
      List.of(files);

  @override
  Future<List<RawCallLogEntry>> callsSince(DateTime since, {int limit = 500}) async =>
      List.of(calls);

  @override
  Future<String?> copyUri(String uri, String destination) async {
    final file = File(destination);
    await file.create(recursive: true);
    await file.writeAsBytes(List<int>.generate(4096, (i) => i % 200));
    return destination;
  }
}

RawAudioFile _file(
  int id,
  String name,
  String path,
  DateTime modified, {
  int size = 20000,
}) => RawAudioFile(
  id: id,
  uri: 'content://media/external/audio/media/$id',
  displayName: name,
  relativePath: path,
  mime: 'audio/mp4',
  durationMs: 60000,
  sizeBytes: size,
  dateAddedMillis: modified.millisecondsSinceEpoch,
  dateModifiedMillis: modified.millisecondsSinceEpoch,
);

RawCallLogEntry _call(int id, String number, DateTime start, int seconds, {int type = 1, String name = ''}) =>
    RawCallLogEntry(
      id: id,
      number: number,
      name: name,
      startedAtMillis: start.millisecondsSinceEpoch,
      durationSeconds: seconds,
      type: type,
    );

void main() {
  final now = DateTime(2026, 11, 4, 15, 0, 0);
  late Directory dir;
  late RecordingRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rec-flow-');
    repo = RecordingRepository(rootPath: '${dir.path}/store');
  });
  tearDown(() => dir.delete(recursive: true));

  CallRecording sample(String id, {String number = '09123456789', String name = 'علی', TranscriptStatus status = TranscriptStatus.none, String audio = ''}) {
    return CallRecording(
      id: id,
      audioPath: audio,
      sourceKey: 'k$id',
      source: RecordingSource.phoneRecorder,
      recordedAt: now,
      importedAt: now,
      number: number,
      contactName: name,
      transcriptStatus: status,
    );
  }

  group('repository', () {
    test('stores recordings and finds them by name, number and transcript text', () async {
      await repo.upsert(sample('a', name: 'علی رضایی', status: TranscriptStatus.done));
      await repo.upsert(sample('b', number: '09121112233', name: 'مریم'));
      await repo.writeTranscript('a', 'قرار شد فردا ساعت ۱۰ جلسه داشته باشیم');

      expect((await repo.search('رضایی')).map((r) => r.id), ['a']);
      expect((await repo.search('0912111')).map((r) => r.id), ['b']);
      expect((await repo.search('جلسه')).map((r) => r.id), ['a']);
      // ارقام فارسی و عربی و ی/ک عربی یکسان می‌شوند
      expect((await repo.search('ساعت 10')).map((r) => r.id), ['a']);
      expect((await repo.search('علي')).map((r) => r.id), ['a']);
      expect(await repo.search('نامرتبط'), isEmpty);
    });

    test('filters by status', () async {
      await repo.upsert(sample('a', status: TranscriptStatus.done));
      await repo.upsert(sample('b', status: TranscriptStatus.failed));
      await repo.upsert(sample('c', status: TranscriptStatus.queued));

      expect((await repo.search('', filter: RecordingFilter.withText)).map((r) => r.id), ['a']);
      expect((await repo.search('', filter: RecordingFilter.failed)).map((r) => r.id), ['b']);
      expect((await repo.search('', filter: RecordingFilter.pending)).map((r) => r.id), ['c']);
    });

    test('deleting the audio keeps the transcript; deleting both removes the row', () async {
      final audio = File('${dir.path}/a.m4a')..writeAsBytesSync([1, 2, 3]);
      await repo.upsert(sample('a', status: TranscriptStatus.done, audio: audio.path));
      await repo.writeTranscript('a', 'متن');

      await repo.delete('a', deleteTranscript: false);
      expect(audio.existsSync(), isFalse);
      expect((await repo.get('a'))!.hasAudio, isFalse);
      expect(await repo.readTranscript('a'), 'متن');

      await repo.delete('a');
      expect(await repo.get('a'), isNull);
      expect(await repo.readTranscript('a'), '');
    });

    test('a source can only be imported once', () async {
      expect(await repo.addIfNew(sample('a')), isTrue);
      final again = CallRecording(
        id: 'other',
        audioPath: '',
        sourceKey: 'ka',
        source: RecordingSource.phoneRecorder,
        recordedAt: now,
        importedAt: now,
      );
      expect(await repo.addIfNew(again), isFalse);
      expect((await repo.all()), hasLength(1));
    });

    test('a recording can be claimed by only one worker at a time', () async {
      await repo.upsert(sample('a', status: TranscriptStatus.queued, audio: 'x'));
      final first = await repo.claim('a', now: now, lease: const Duration(minutes: 15));
      final second = await repo.claim('a', now: now, lease: const Duration(minutes: 15));
      expect(first, isNotNull);
      expect(second, isNull);
      // مهلت که تمام شود، دوباره قابل ادعا است (کارگر قبلی مرده)
      final later = await repo.claim('a', now: now.add(const Duration(minutes: 20)), lease: const Duration(minutes: 15));
      expect(later, isNotNull);
    });
  });

  group('scanner: phone recorder folder -> app, linked to the call log', () {
    CallSettings settings0() => const CallSettings(autoUploadToNm: true);

    RecordingScanner scanner(FakePlatform platform, {CallSettings? settings}) => RecordingScanner(
      platform: platform,
      repository: repo,
      settings: () => settings ?? settings0(),
      clock: () => now,
    );

    test('imports a Samsung recording, copies it and links it to the call', () async {
      final platform = FakePlatform();
      final callStart = DateTime(2026, 11, 4, 14, 20);
      platform.files.add(_file(7, 'Call recording Ali_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));
      platform.files.add(_file(8, 'song.mp3', 'Music/', DateTime(2026, 11, 4, 14, 26)));
      platform.calls.add(_call(1, '09123456789', callStart, 300, name: 'Ali Rezaei'));

      final report = await scanner(platform).scan();

      expect(report.imported, 1);
      expect(report.linked, 1);
      final recordings = await repo.all();
      expect(recordings, hasLength(1));
      final r = recordings.single;
      expect(r.number, '09123456789');
      expect(r.contactName, 'Ali Rezaei');
      expect(r.direction, CallDirection.incoming);
      expect(r.callStartedAt, callStart);
      expect(r.callDuration, const Duration(minutes: 5));
      expect(r.linked, isTrue);
      expect(r.brand, 'samsung');
      expect(File(r.audioPath).existsSync(), isTrue);
      expect(r.transcriptStatus, TranscriptStatus.queued);
    });

    test('scanning twice does not duplicate', () async {
      final platform = FakePlatform();
      platform.files.add(_file(7, 'Call recording 09123456789_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));
      await scanner(platform).scan();
      final second = await scanner(platform).scan();

      expect(second.imported, 0);
      expect(await repo.all(), hasLength(1));
    });

    test('a file still being written is deferred, and the scan window does not move past it', () async {
      final platform = FakePlatform();
      final writing = now.subtract(const Duration(seconds: 5));
      platform.files.add(_file(9, 'Call recording 09123456789_261104_145955.m4a', 'Recordings/Call/', writing));

      final report = await scanner(platform).scan();

      expect(report.imported, 0);
      expect(report.deferred, 1);
      expect(report.safeUntil, writing);
    });

    test('a recording whose call log row arrives later is linked on a later scan', () async {
      final platform = FakePlatform();
      platform.files.add(_file(7, 'Call recording 09123456789_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));

      final first = await scanner(platform).scan();
      expect(first.imported, 1);
      expect((await repo.all()).single.linked, isFalse);
      expect((await repo.all()).single.number, '09123456789'); // از نام فایل

      platform.calls.add(_call(1, '09123456789', DateTime(2026, 11, 4, 14, 20), 300));
      final second = await scanner(platform).scan();

      expect(second.relinked, 1);
      expect((await repo.all()).single.linked, isTrue);
    });

    test('tiny files and non-recorder folders are ignored', () async {
      final platform = FakePlatform();
      platform.files.add(_file(1, 'a.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 0), size: 300));
      platform.files.add(_file(2, 'Voice 001.m4a', 'Recordings/Voice Recorder/', DateTime(2026, 11, 4, 14, 0)));

      final report = await scanner(platform).scan();

      expect(report.imported, 0);
    });

    test('folder watching can be switched off', () async {
      final platform = FakePlatform();
      platform.files.add(_file(7, 'Call recording 09123456789_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));

      final report = await scanner(platform, settings: const CallSettings(watchPhoneRecorder: false)).scan();

      expect(report.imported, 0);
    });

    test('without automatic upload, new recordings are stored but not queued for NM', () async {
      final platform = FakePlatform();
      platform.files.add(_file(7, 'Call recording 09123456789_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));

      await scanner(platform, settings: const CallSettings()).scan();

      expect((await repo.all()).single.transcriptStatus, TranscriptStatus.none);
    });

  });
}
