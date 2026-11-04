import 'package:nm_mobile/features/gateway/services/stop_words.dart';

/// ارقام یک رشته (ارقام فارسی/عربی هم به لاتین تبدیل می‌شود).
String digitsOnly(String s) => normalizeText(s).replaceAll(RegExp(r'[^0-9]'), '');

/// آخرین [n] رقم شماره؛ با +98 و 0 ابتدایی هم کار می‌کند.
String numberTail(String number, {int n = 8}) {
  final d = digitsOnly(number);
  return d.length <= n ? d : d.substring(d.length - n);
}
