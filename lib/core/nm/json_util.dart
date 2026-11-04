/// کمک‌های کوچک برای خواندنِ امنِ JSON سرور (هیچ‌چیز را از خودمان نمی‌سازیم؛
/// مقدار نبود = null).
Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> asList(dynamic v) => v is List ? v : const <dynamic>[];

String asStr(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

String? asStrN(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int? asIntN(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? asDoubleN(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool asBool(dynamic v, [bool fallback = false]) => v is bool ? v : fallback;

bool? asBoolN(dynamic v) => v is bool ? v : null;

DateTime? asDate(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toLocal();
}
