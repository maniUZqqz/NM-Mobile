/// نرمال‌سازی متن فارسی/عربی/انگلیسی برای مقایسه: ارقام فارسی و عربی به لاتین،
/// «ي/ك» به «ی/ک»، نیم‌فاصله و نویسه‌های نامرئی حذف، حروف کوچک، فاصله‌ها یکی.
String normalizeText(String input) {
  final b = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + (r - 0x06F0)); // ۰-۹
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + (r - 0x0660)); // ٠-٩
    } else if (r == 0x064A) {
      b.write('ی'); // ي
    } else if (r == 0x0643) {
      b.write('ک'); // ك
    } else if (r == 0x200C) {
      b.write(' '); // نیم‌فاصله
    } else if (r == 0x200B ||
        r == 0x200D ||
        r == 0x200E ||
        r == 0x200F ||
        r == 0xFEFF ||
        r == 0x0640) {
      // نویسه‌های نامرئی و کشیده
    } else {
      b.writeCharCode(r);
    }
  }
  return b
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// کلمه‌هایی که یعنی «دیگر برایم پیام نفرستید». همه نرمال‌شده‌اند.
const List<String> kStopWords = <String>[
  'لغو',
  'لغو عضویت',
  'لغو11',
  'لغو 11',
  'توقف',
  'توقف ارسال',
  'stop',
  'stop all',
  'unsubscribe',
];

/// آیا این پیامکِ دریافتی یک درخواستِ «لغو/stop» است؟
/// قاعده: کل متن (بدون نشانه‌گذاری) برابر یکی از کلمه‌هاست، یا با آن شروع می‌شود و
/// کوتاه است (مثل «لغو لطفا»). متن‌های بلند هرگز «لغو» حساب نمی‌شوند.
bool isStopWord(String text) {
  var t = normalizeText(text);
  t = t
      .replaceAll(RegExp(r'[.!?؟،,؛;:"“”«»()\[\]\-_*~]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty || t.length > 25) return false;
  for (final w in kStopWords) {
    if (t == w) return true;
    if (t.startsWith('$w ')) return true;
  }
  return false;
}
