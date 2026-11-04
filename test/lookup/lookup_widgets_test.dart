import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

import 'fakes.dart';

Widget host(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

Map<String, dynamic> stored({bool stale = false}) => <String, dynamic>{
      'platform': 'whatsapp',
      'label': 'واتساپ',
      'status': 'found',
      'on_platform': true,
      'display_name': 'علی رضایی',
      'username': 'ali_r',
      'bio': 'مدیر فروش',
      'field_sources': <String, dynamic>{'display_name': 'واتساپ: نام', 'bio': 'واتساپ: درباره'},
      'age_days': stale ? 45 : 3,
      'stale': stale,
      'method': 'webview',
    };

void main() {
  testWidgets('ProfilesCard shows name, username, bio, the source of each field, age and the stale badge', (tester) async {
    final http = FakeHttp(config: cfg([plat('whatsapp')]), latest: <Map<String, dynamic>>[stored(stale: true)]);
    final facade = LookupFacade(http, runner: FakeRunner(), delay: (d) async {});
    await tester.pumpWidget(host(ProfilesCard(facade: facade, number: kNumber, callUid: 'c1')));
    await tester.pumpAndSettle();

    expect(find.text('علی رضایی'), findsOneWidget);
    expect(find.text('@ali_r'), findsOneWidget);
    expect(find.text('مدیر فروش'), findsOneWidget);
    expect(find.textContaining('منبع:'), findsOneWidget);
    expect(find.textContaining('واتساپ: درباره'), findsOneWidget);
    expect(find.text('45 روز پیش'), findsOneWidget);
    expect(find.byKey(const Key('stale-badge')), findsOneWidget);
    // lookups only happen when the user presses a button
    expect(http.log, <String>['GET lookups/latest/']);
  });

  testWidgets('pressing «جستجو» runs ONE number for the call, with refresh=false', (tester) async {
    final http = FakeHttp(config: cfg([plat('whatsapp')]), latest: <Map<String, dynamic>>[stored()]);
    final facade = LookupFacade(http, runner: FakeRunner(), delay: (d) async {});
    await tester.pumpWidget(host(ProfilesCard(facade: facade, number: kNumber, callUid: 'c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('lookup-run')));
    await tester.pumpAndSettle();

    final auth = http.postsTo('lookups/authorize/').single;
    expect(auth['number'], kNumber);
    expect(auth['call_uid'], 'c1');
    expect(auth['trigger'], 'call');
    expect(auth['refresh'], false);
    expect(http.postsTo('lookups/'), hasLength(1));
  });

  testWidgets('pressing «تازه‌سازی» forwards refresh=true', (tester) async {
    final http = FakeHttp(config: cfg([plat('whatsapp')]), latest: <Map<String, dynamic>>[stored()]);
    final facade = LookupFacade(http, runner: FakeRunner(), delay: (d) async {});
    await tester.pumpWidget(host(ProfilesCard(facade: facade, number: kNumber, callUid: 'c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lookup-refresh')));
    await tester.pumpAndSettle();
    expect(http.postsTo('lookups/authorize/').single['refresh'], true);
  });

  testWidgets('a server refusal is shown to the user in Persian', (tester) async {
    final http = FakeHttp(config: cfg([plat('whatsapp')]), latest: <Map<String, dynamic>>[]);
    http.onPost = (path, body) => path == 'lookups/authorize/' ? NmHttpException(429, 'rate_limited', 'سقف امروز پر شده است') : null;
    final facade = LookupFacade(http, runner: FakeRunner(), delay: (d) async {});
    await tester.pumpWidget(host(ProfilesCard(facade: facade, number: kNumber, callUid: 'c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lookup-run')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lookup-notice')), findsOneWidget);
    expect(find.text('سقف امروز پر شده است'), findsOneWidget);
  });

  testWidgets('a manual card sends trigger=manual and no call uid', (tester) async {
    final http = FakeHttp(config: cfg([plat('whatsapp')]));
    final facade = LookupFacade(http, runner: FakeRunner(), delay: (d) async {});
    await tester.pumpWidget(host(ProfilesCard(facade: facade, number: kNumber, manual: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lookup-run')));
    await tester.pumpAndSettle();
    final auth = http.postsTo('lookups/authorize/').single;
    expect(auth['trigger'], 'manual');
    expect(auth.containsKey('call_uid'), isFalse);
  });

  testWidgets('MessengersScreen: rules, a card per platform, ban warning on the unofficial ones, Rubika unavailable, Telegram from the server', (tester) async {
    final http = FakeHttp(config: <String, dynamic>{
      'cache_days': 30,
      'rules': 'قوانین سرور: فقط شمارهٔ تماس‌های واقعی',
      'platforms': <Map<String, dynamic>>[
        plat('telegram', method: 'server', ready: false),
        plat('whatsapp'),
      ],
    });
    final facade = LookupFacade(http, runner: FakeRunner(), delay: (d) async {});
    tester.view.physicalSize = const Size(800, 9000); // the list is lazy: make every card visible
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fa'),
      home: Directionality(textDirection: TextDirection.rtl, child: MessengersScreen(facade: facade)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('قوانین سرور: فقط شمارهٔ تماس‌های واقعی'), findsOneWidget);
    for (final key in <String>['whatsapp', 'eitaa', 'bale', 'soroush', 'rubika', 'telegram']) {
      expect(find.byKey(Key('card-$key')), findsOneWidget, reason: key);
    }
    for (final key in <String>['whatsapp', 'eitaa', 'bale', 'soroush']) {
      expect(find.byKey(Key('warning-$key')), findsOneWidget, reason: key);
    }
    expect(find.byKey(const Key('warning-rubika')), findsNothing);
    expect(find.textContaining('راه امن و رسمی'), findsOneWidget);
    expect(find.textContaining('هنوز وصل نشده'), findsOneWidget); // telegram not ready
    // a messenger the server did not list is shown as "unknown", never as enabled
    expect(find.text('روشن در پنل'), findsWidgets);
  });
}
