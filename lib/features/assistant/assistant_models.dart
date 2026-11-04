import 'package:nm_mobile/core/nm/json_util.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';

/// متنی که به‌جای هر عددِ نامعلوم نشان می‌دهیم. هرگز «۰».
const String kNotRegistered = 'ثبت نشده';

const List<String> _faDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

String faDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x30 && r <= 0x39) {
      b.write(_faDigits[r - 0x30]);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// عدد با جداکنندهٔ هزارگان و رقم فارسی؛ null ⇒ «ثبت نشده».
String fmtNumber(num? v) {
  if (v == null) return kNotRegistered;
  final neg = v < 0;
  final rounded = v.abs() == v.abs().roundToDouble() ? v.abs().round() : null;
  var s = rounded != null ? rounded.toString() : v.abs().toStringAsFixed(1);
  var frac = '';
  final dot = s.indexOf('.');
  if (dot >= 0) {
    frac = s.substring(dot);
    s = s.substring(0, dot);
  }
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('٬');
    b.write(s[i]);
  }
  final out = '${neg ? '-' : ''}$b${frac.replaceAll('.', '٫')}';
  return faDigits(out);
}

String currencyLabel(String code) {
  switch (code.toUpperCase()) {
    case 'IRT':
      return 'تومان';
    case 'IRR':
      return 'ریال';
    default:
      return code;
  }
}

/// مبلغ با واحد؛ null ⇒ «ثبت نشده» (بدون واحد).
String fmtMoney(num? v, String currency) {
  if (v == null) return kNotRegistered;
  return '${fmtNumber(v)} ${currencyLabel(currency)}';
}

String fmtPercent(num? v) => v == null ? kNotRegistered : '${fmtNumber(v)}٪';

class ProductStock {
  const ProductStock({this.available, this.onHand, this.reserved, this.status = '', this.statusLabel = ''});

  factory ProductStock.fromJson(Map<String, dynamic> j) => ProductStock(
    available: asIntN(j['available']),
    onHand: asIntN(j['on_hand']),
    reserved: asIntN(j['reserved']),
    status: asStr(j['status']),
    statusLabel: asStr(j['status_label']),
  );

  final int? available;
  final int? onHand;
  final int? reserved;
  final String status;
  final String statusLabel;
}

class ProductVariantInfo {
  const ProductVariantInfo({required this.name, this.price, this.available});

  factory ProductVariantInfo.fromJson(Map<String, dynamic> j) =>
      ProductVariantInfo(name: asStr(j['name']), price: asDoubleN(j['price']), available: asIntN(j['available']));

  final String name;
  final double? price;
  final int? available;
}

/// یک محصول در جست‌وجوی سریع. هر عددی که سرور null بدهد همان‌طور null می‌ماند.
class ProductInfo {
  const ProductInfo({
    required this.id,
    required this.name,
    this.sku = '',
    this.brand = '',
    this.storeName = '',
    this.currency = 'IRT',
    this.price,
    this.compareAtPrice,
    this.stock = const ProductStock(),
    this.cost,
    this.unitProfit,
    this.marginPercent,
    this.floorPrice,
    this.floorBasis = 'unknown',
    this.maxDiscountPercent,
    this.maxDiscountAmount,
    this.shortDescription = '',
    this.attributes = const <MapEntry<String, String>>[],
    this.variants = const <ProductVariantInfo>[],
  });

  factory ProductInfo.fromJson(Map<String, dynamic> j) {
    final store = asMap(j['store']);
    return ProductInfo(
      id: asIntN(j['id']) ?? 0,
      name: asStr(j['name']),
      sku: asStr(j['sku']),
      brand: asStr(j['brand']),
      storeName: asStr(store['name']),
      currency: asStr(j['currency'], 'IRT'),
      price: asDoubleN(j['price']),
      compareAtPrice: asDoubleN(j['compare_at_price']),
      stock: ProductStock.fromJson(asMap(j['stock'])),
      cost: asDoubleN(j['cost']),
      unitProfit: asDoubleN(j['unit_profit']),
      marginPercent: asDoubleN(j['margin_percent']),
      floorPrice: asDoubleN(j['floor_price']),
      floorBasis: asStr(j['floor_basis'], 'unknown'),
      maxDiscountPercent: asDoubleN(j['max_discount_percent']),
      maxDiscountAmount: asDoubleN(j['max_discount_amount']),
      shortDescription: asStr(j['short_description']),
      attributes: asList(j['attributes'])
          .whereType<Map>()
          .map((e) => MapEntry(asStr(asMap(e)['key']), asStr(asMap(e)['value'])))
          .toList(),
      variants: asList(j['variants']).whereType<Map>().map((e) => ProductVariantInfo.fromJson(asMap(e))).toList(),
    );
  }

  final int id;
  final String name;
  final String sku;
  final String brand;
  final String storeName;
  final String currency;
  final double? price;
  final double? compareAtPrice;
  final ProductStock stock;
  final double? cost;
  final double? unitProfit;
  final double? marginPercent;
  final double? floorPrice;
  final String floorBasis;
  final double? maxDiscountPercent;
  final double? maxDiscountAmount;
  final String shortDescription;
  final List<MapEntry<String, String>> attributes;
  final List<ProductVariantInfo> variants;

  String get priceText => fmtMoney(price, currency);
  String get costText => fmtMoney(cost, currency);
  String get profitText => fmtMoney(unitProfit, currency);
  String get marginText => fmtPercent(marginPercent);
  String get floorText => fmtMoney(floorPrice, currency);
  String get maxDiscountText {
    if (maxDiscountPercent == null && maxDiscountAmount == null) return kNotRegistered;
    final parts = <String>[];
    if (maxDiscountPercent != null) parts.add(fmtPercent(maxDiscountPercent));
    if (maxDiscountAmount != null) parts.add(fmtMoney(maxDiscountAmount, currency));
    return parts.join(' · ');
  }

  String get stockText {
    final a = stock.available;
    if (a == null) return stock.statusLabel.isEmpty ? kNotRegistered : stock.statusLabel;
    final label = stock.statusLabel.isEmpty ? '' : ' (${stock.statusLabel})';
    return '${fmtNumber(a)} عدد قابل فروش$label';
  }
}

class CallerMatch {
  const CallerMatch({required this.source, required this.name, this.detail = '', this.store = ''});

  factory CallerMatch.fromJson(Map<String, dynamic> j) => CallerMatch(
    source: asStr(j['source']),
    name: asStr(j['name']),
    detail: asStr(j['detail']),
    store: asStr(j['store']),
  );

  final String source;
  final String name;
  final String detail;
  final String store;

  String get sourceLabel {
    switch (source) {
      case 'customer':
        return 'مشتری';
      case 'prospect':
        return 'سرنخ فروش';
      case 'lead':
        return 'لید وب‌سایت';
      case 'growth_lead':
        return 'لید رشد';
      case 'synced_contact':
        return 'مخاطب گوشی';
      case 'previous_call':
        return 'تماس قبلی';
      case 'previous_sms':
        return 'پیامک قبلی';
      default:
        return source;
    }
  }
}

class CallerId {
  const CallerId({
    required this.number,
    required this.normalized,
    this.display,
    this.known = false,
    this.matches = const <CallerMatch>[],
    this.calls = 0,
    this.smsOut = 0,
    this.smsIn = 0,
    this.lastCallAt,
    this.consentGranted = false,
  });

  factory CallerId.fromJson(Map<String, dynamic> j) {
    final h = asMap(j['history']);
    return CallerId(
      number: asStr(j['number']),
      normalized: asStr(j['normalized']),
      display: asStrN(j['display']),
      known: asBool(j['known']),
      matches: asList(j['matches']).whereType<Map>().map((e) => CallerMatch.fromJson(asMap(e))).toList(),
      calls: asIntN(h['calls']) ?? 0,
      smsOut: asIntN(h['sms_out']) ?? 0,
      smsIn: asIntN(h['sms_in']) ?? 0,
      lastCallAt: asDate(h['last_call_at']),
      consentGranted: asBool(asMap(j['consent'])['granted']),
    );
  }

  final String number;
  final String normalized;
  final String? display;
  final bool known;
  final List<CallerMatch> matches;
  final int calls;
  final int smsOut;
  final int smsIn;
  final DateTime? lastCallAt;
  final bool consentGranted;
}

class AiReply {
  const AiReply({required this.replies, this.notes = '', this.engine = ''});

  factory AiReply.fromJson(Map<String, dynamic> j) => AiReply(
    replies: asList(j['replies'])
        .map((e) => e is Map ? asStr(asMap(e)['text']) : e.toString())
        .where((t) => t.trim().isNotEmpty)
        .toList(),
    notes: asStr(j['notes']),
    engine: asStr(j['engine']),
  );

  final List<String> replies;
  final String notes;
  final String engine;
}

/// API ِ ابزارهای حینِ تماس: جست‌وجوی محصول، شناساییِ تماس‌گیرنده، پیشنهادِ پاسخ.
class AssistantApi {
  AssistantApi(this.http);

  final NmHttp http;

  Future<List<ProductInfo>> searchProducts(String q, {int limit = 10}) async {
    final data = await http.getJson('products/search/', query: {'q': q, 'limit': '$limit'});
    return asList(asMap(data)['results']).whereType<Map>().map((e) => ProductInfo.fromJson(asMap(e))).toList();
  }

  Future<CallerId> callerId(String number) async {
    final data = await http.getJson('callerid/', query: {'number': number});
    return CallerId.fromJson(asMap(data));
  }

  Future<AiReply> ask(String question, {String? number, List<int> productIds = const [], String? callUid}) async {
    final data = await http.postJson('assistant/ask/', {
      'question': question,
      if (number != null && number.isNotEmpty) 'number': number,
      if (productIds.isNotEmpty) 'product_ids': productIds,
      if (callUid != null && callUid.isNotEmpty) 'call_uid': callUid,
    });
    return AiReply.fromJson(asMap(data));
  }
}
