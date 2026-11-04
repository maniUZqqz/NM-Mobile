import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/assistant/assistant_models.dart';
import 'package:nm_mobile/features/assistant/messenger_links.dart';
import 'package:nm_mobile/features/assistant/product_card.dart';

import 'support/helpers.dart';

Map<String, dynamic> _product({bool withCost = false}) => {
  'id': 5,
  'name': 'کفش ورزشی',
  'sku': 'SH-1',
  'brand': 'نایکی',
  'store': {'id': 1, 'name': 'فروشگاه'},
  'currency': 'IRT',
  'price': 1200000,
  'compare_at_price': null,
  'stock': {'available': 7, 'on_hand': 9, 'reserved': 2, 'status': 'IN_STOCK', 'status_label': 'موجود'},
  'cost': withCost ? 800000 : null,
  'unit_profit': withCost ? 400000 : null,
  'margin_percent': withCost ? 33.3 : null,
  'floor_price': withCost ? 880000 : null,
  'floor_basis': withCost ? 'cost_plus' : 'unknown',
  'max_discount_percent': withCost ? 26.7 : null,
  'max_discount_amount': withCost ? 320000 : null,
  'short_description': 'سبک و راحت',
  'attributes': [
    {'key': 'رنگ', 'value': 'سیاه'},
  ],
  'image_url': null,
  'variants': [
    {'name': 'L', 'price': null, 'available': 3},
  ],
};

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SingleChildScrollView(child: child))),
);

void main() {
  group('number formatting', () {
    test('null is always shown as «ثبت نشده», never as zero', () {
      expect(fmtNumber(null), 'ثبت نشده');
      expect(fmtMoney(null, 'IRT'), 'ثبت نشده');
      expect(fmtPercent(null), 'ثبت نشده');
    });

    test('real numbers get Persian digits and thousands separators', () {
      expect(fmtNumber(0), '۰');
      expect(fmtNumber(1200000), '۱٬۲۰۰٬۰۰۰');
      expect(fmtMoney(1200000, 'IRT'), '۱٬۲۰۰٬۰۰۰ تومان');
      expect(fmtPercent(26.7), '۲۶٫۷٪');
      expect(fmtNumber(-500), '-۵۰۰');
    });
  });

  group('ProductInfo', () {
    test('unknown cost/profit/floor stay null and read «ثبت نشده»', () {
      final p = ProductInfo.fromJson(_product());
      expect(p.cost, isNull);
      expect(p.floorPrice, isNull);
      expect(p.maxDiscountPercent, isNull);
      expect(p.costText, 'ثبت نشده');
      expect(p.profitText, 'ثبت نشده');
      expect(p.floorText, 'ثبت نشده');
      expect(p.maxDiscountText, 'ثبت نشده');
      expect(p.priceText, '۱٬۲۰۰٬۰۰۰ تومان');
      expect(p.stockText, contains('۷'));
    });

    test('known numbers are formatted', () {
      final p = ProductInfo.fromJson(_product(withCost: true));
      expect(p.costText, '۸۰۰٬۰۰۰ تومان');
      expect(p.floorText, '۸۸۰٬۰۰۰ تومان');
      expect(p.maxDiscountText, contains('۲۶٫۷٪'));
      expect(p.maxDiscountText, contains('۳۲۰٬۰۰۰ تومان'));
    });
  });

  group('ProductCard widget', () {
    testWidgets('shows «ثبت نشده» for every missing figure and no fake zero', (tester) async {
      await tester.pumpWidget(_wrap(ProductCard(product: ProductInfo.fromJson(_product()))));
      // cost, profit, floor, max discount
      expect(find.text('ثبت نشده'), findsNWidgets(4));
      expect(find.textContaining('ثبت نشده'), findsNWidgets(4));
      expect(find.text('۰'), findsNothing);
      expect(find.textContaining('۱٬۲۰۰٬۰۰۰ تومان'), findsOneWidget);
    });

    testWidgets('shows the floor price and max discount when the owner registered a cost', (tester) async {
      await tester.pumpWidget(_wrap(ProductCard(product: ProductInfo.fromJson(_product(withCost: true)))));
      expect(find.textContaining('ثبت نشده'), findsNothing);
      expect(find.text('۸۸۰٬۰۰۰ تومان'), findsOneWidget);
    });
  });

  group('messenger deep links', () {
    final defs = parseMessengers(File('assets/messengers.json').readAsStringSync());
    MessengerDef by(String k) => defs.firstWhere((m) => m.key == k);

    test('the six messengers are present', () {
      expect(defs.map((m) => m.key).toSet(), {'telegram', 'whatsapp', 'eitaa', 'bale', 'soroush', 'rubika'});
    });

    test('only messengers with a verified phone link get a button', () {
      expect(by('whatsapp').hasPhoneLink, isTrue);
      expect(by('telegram').hasPhoneLink, isTrue);
      for (final k in ['eitaa', 'bale', 'soroush', 'rubika']) {
        expect(by(k).hasPhoneLink, isFalse, reason: k);
        expect(buildPhoneLink(by(k), '09121234567'), isNull, reason: k);
      }
    });

    test('links use the international digits without + or the leading zero', () {
      expect(buildPhoneLink(by('whatsapp'), '09121234567'), 'https://wa.me/989121234567');
      expect(buildPhoneLink(by('telegram'), '+98 912 123 4567'), 'https://t.me/+989121234567');
      expect(buildPhoneLink(by('whatsapp'), '۰۹۱۲۱۲۳۴۵۶۷'), 'https://wa.me/989121234567');
      expect(buildPhoneLink(by('whatsapp'), '12'), isNull);
    });

    test('internationalDigits handles the common Iranian forms', () {
      expect(internationalDigits('09121234567'), '989121234567');
      expect(internationalDigits('+989121234567'), '989121234567');
      expect(internationalDigits('00989121234567'), '989121234567');
      expect(internationalDigits('9121234567'), '989121234567');
      expect(internationalDigits('+44 20 7946 0958'), '442079460958');
    });

    test('packages are listed so the app can tell which messenger is installed', () {
      expect(by('whatsapp').packages, contains('com.whatsapp'));
      expect(by('telegram').packages, contains('org.telegram.messenger'));
    });
  });

  test('AssistantApi parses search, caller id and AI replies', () async {
    final nm = FakeNmHttp((m, p, b) async {
      if (p == 'products/search/') {
        return {'count': 1, 'results': [_product()]};
      }
      if (p == 'callerid/') {
        return {
          'number': '0912',
          'normalized': '98912',
          'display': 'علی',
          'known': true,
          'matches': [
            {'source': 'customer', 'name': 'علی', 'detail': '۲ سفارش', 'store': 'ف'},
          ],
          'history': {'calls': 3, 'sms_out': 1, 'sms_in': 0, 'last_call_at': '2026-11-04T10:00:00+03:30'},
          'consent': {'granted': true},
        };
      }
      return {
        'replies': [
          {'text': 'تا ۲۰٪ می‌توانم تخفیف بدهم.'},
        ],
        'notes': 'قیمت تمام‌شده را نگویید',
        'engine': 'local',
      };
    });
    final api = AssistantApi(nm);
    final products = await api.searchProducts('کفش');
    expect(products.single.name, 'کفش ورزشی');
    expect(nm.calls.first, 'GET products/search/');
    final c = await api.callerId('0912');
    expect(c.display, 'علی');
    expect(c.matches.single.sourceLabel, 'مشتری');
    expect(c.calls, 3);
    expect(c.consentGranted, isTrue);
    final r = await api.ask('تخفیف؟', number: '0912', productIds: [5]);
    expect(r.replies.single, contains('تخفیف'));
    expect(r.engine, 'local');
    final body = nm.payloads.last as Map;
    expect(body['product_ids'], [5]);
  });
}
