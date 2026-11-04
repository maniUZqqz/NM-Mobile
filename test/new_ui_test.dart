import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:nm_mobile/core/storage/app_storage.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/calls/data/call_settings.dart';
import 'package:nm_mobile/features/calls/presentation/call_setup_page.dart';
import 'package:nm_mobile/features/optout/optout.dart';
import 'package:nm_mobile/features/optout/optout_page.dart';
import 'package:nm_mobile/features/settings/domain/send_settings.dart';
import 'package:nm_mobile/features/settings/presentation/scheduler_health_card.dart';
import 'package:nm_mobile/features/settings/presentation/send_settings_sheet.dart';

const _channel = MethodChannel('sms_bridge');

Map<String, Object?> _status({String manufacturer = 'samsung', String brand = 'samsung', bool exactAlarm = true}) => {
  'sendSms': true,
  'phoneState': true,
  'phoneNumbers': true,
  'notifications': true,
  'battery': true,
  'airplane': false,
  'telephony': true,
  'sdk': 34,
  'manufacturer': manufacturer,
  'model': 'SM-S918B',
  'brand': brand,
  'exactAlarm': exactAlarm,
  'callLog': false,
  'audioMedia': false,
  'recordAudio': false,
  'accessibility': false,
};

void _mockBridge({Map<String, Object?>? status}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    switch (call.method) {
      case 'status':
        return status ?? _status();
      case 'callRecorderStatus':
        return {'enabled': false, 'autoSpeaker': false, 'accessibilityEnabled': false, 'recording': false, 'lastError': '', 'lastRecordingAt': 0, 'recordingsDir': ''};
      case 'wakeStatus':
        return {'canExact': true, 'nextWakeAt': 0, 'lastFiredAt': 0, 'lastStartedService': false, 'mode': 'none'};
      case 'playerState':
        return {'playing': false, 'positionMs': 0, 'durationMs': 0, 'path': ''};
      case 'secureRead':
        return '';
      default:
        return true;
    }
  });
}

Widget _shell(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Directionality(textDirection: TextDirection.rtl, child: child),
);

void _compactPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// IO واقعی داخل تست ویجت باید در runAsync انجام شود و هر مرحله‌ی زنجیره‌ی await یک دور
/// «زمان واقعی + pump» لازم دارد. به‌جای شمارش ثابت، تا برقرار شدن شرط (حداکثر چند ثانیه) صبر می‌کنیم.
Future<void> _settle(
  WidgetTester tester, {
  bool Function()? ready,
  Future<bool> Function()? readyAsync,
}) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 30));
    if (i < 6) continue;
    if (ready != null && ready()) return;
    if (readyAsync != null && (await tester.runAsync(readyAsync)) == true) return;
    if (ready == null && readyAsync == null && i >= 14) return;
  }
}

bool Function() _shows(Finder finder) => () => finder.evaluate().isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.toString();
      debugPrint('FLUTTER-ERROR: ${text.length > 2500 ? text.substring(0, 2500) : text}');
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    dir = await Directory.systemTemp.createTemp('ui-');
    AppDir.setPathForTests(dir.path);
    _mockBridge();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    AppDir.setPathForTests(null);
    await dir.delete(recursive: true);
  });

  testWidgets('send settings sheet shows the limits and returns edited values', (tester) async {
    _compactPhone(tester);
    SendSettings? result;
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showModalBottomSheet<SendSettings>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const SendSettingsSheet(initial: SendSettings()),
                  );
                },
                child: const Text('باز کن'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('باز کن'));
    await tester.pumpAndSettle();

    expect(find.text('احتیاط در ارسال'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).first, '45');
    await tester.scrollUntilVisible(find.text('ذخیره'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(result!.minDelaySeconds, 45);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opt-out page lists numbers and accepts several at once', (tester) async {
    _compactPhone(tester);
    await tester.runAsync(() => OptOutStorage.add(OptOutEntry.create(phone: '09120000001', name: 'علی')));
    await tester.pumpWidget(_shell(const OptOutPage()));
    await _settle(tester, ready: _shows(find.text('علی')));

    expect(find.text('علی'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '09120000002\n+989120000003\nabc');
    await tester.tap(find.text('افزودن به فهرست لغو'));
    await _settle(tester, readyAsync: () async => (await OptOutStorage.loadKeys()).length == 3);

    final keys = (await tester.runAsync(OptOutStorage.loadKeys))!;
    expect(keys, {'9120000001', '9120000002', '9120000003'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('call setup: consent first, then the brand-specific instructions', (tester) async {
    tester.view.physicalSize = const Size(360, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_shell(const CallSetupPage()));
    await _settle(tester, ready: _shows(find.text('اطلاعیه‌ی مسئولیت ضبط تماس')));

    expect(find.text('اطلاعیه‌ی مسئولیت ضبط تماس'), findsOneWidget);
    expect(find.text('ضبط‌کنندهٔ خودِ گوشی'), findsNothing,
        reason: 'nothing else is offered before the consent is accepted');

    await tester.tap(find.text('می‌خوانم و مسئولیت را می‌پذیرم'));
    await _settle(tester, ready: _shows(find.text('ضبط‌کنندهٔ خودِ گوشی')));

    expect(find.text('ضبط‌کنندهٔ خودِ گوشی'), findsOneWidget);
    expect(find.textContaining('سامسونگ (One UI)'), findsOneWidget);
    expect(find.textContaining('Record calls'), findsWidgets);
    // NM edition: upload goes to NM only (with the consent gate); no on-phone STT and no accessibility recorder
    expect(find.text('ارسال به NM'), findsOneWidget);
    expect(find.text('ارسال خودکار به NM'), findsOneWidget);
    expect(find.text('تبدیل صدا به متن'), findsNothing);
    expect(find.textContaining('ضبط داخلی'), findsNothing);
    expect(find.textContaining('دسترس‌پذیری'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('call setup picks Xiaomi instructions on a Xiaomi phone', (tester) async {
    tester.view.physicalSize = const Size(360, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _mockBridge(status: _status(manufacturer: 'Xiaomi', brand: 'redmi'));
    await tester.runAsync(
      () => CallSettingsStorage.save(CallSettings(consentAcceptedAt: DateTime(2026, 11, 4), setupCompleted: true)),
    );
    await tester.pumpWidget(_shell(const CallSetupPage()));
    await _settle(tester, ready: _shows(find.textContaining('شیائومی / ردمی / پوکو')));

    expect(find.textContaining('شیائومی / ردمی / پوکو'), findsOneWidget);
    expect(find.textContaining('MIUI'), findsWidgets);
    expect(find.textContaining('سامسونگ (One UI)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scheduler health card explains a closed exact-alarm permission', (tester) async {
    _compactPhone(tester);
    await tester.pumpWidget(
      _shell(
        Scaffold(
          body: SchedulerHealthCard(
            status: BridgeStatus.fromMap(_status(exactAlarm: false)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('آلارم دقیق بسته است'), findsOneWidget);
    expect(find.text('اجازه‌ی «آلارم‌ها و یادآورها»'), findsOneWidget);
    expect(find.text('آزمایش زمان‌بندی (۶۰ ثانیه)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
