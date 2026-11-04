import 'package:nm_mobile/features/gateway/services/stop_words.dart';

/// فایلی که منبع ضبط پیدا کرده (مستقل از اینکه از کجا آمده).
class RecordingCandidate {
  const RecordingCandidate({
    required this.id,
    required this.name,
    required this.modified,
    required this.size,
  });

  /// برای منبع SAF همان uri است.
  final String id;
  final String name;
  final DateTime modified;
  final int size;
}

/// تماسی که می‌شود یک فایل را به آن وصل کرد.
class MatchTarget {
  const MatchTarget({
    required this.uid,
    required this.number,
    required this.startedAt,
    required this.durationS,
  });

  final String uid;
  final String number;
  final DateTime startedAt;
  final int durationS;

  DateTime get endedAt => startedAt.add(Duration(seconds: durationS));
}

/// ارقام یک رشته (فارسی/عربی هم به لاتین تبدیل می‌شود).
String digitsOnly(String s) => normalizeText(s).replaceAll(RegExp(r'[^0-9]'), '');

/// آخرین ۸ رقمِ شماره؛ با +98 و 0 ابتدایی هم کار می‌کند.
String numberTail(String number, {int n = 8}) {
  final d = digitsOnly(number);
  return d.length <= n ? d : d.substring(d.length - n);
}

/// زمانی که در نام فایل نوشته شده (اگر باشد). الگوهای رایج:
/// `20231104_101530`، `20231104101530`، `231104_101530`، `231104-101530`.
/// زمانِ نامِ فایل محلیِ گوشی فرض می‌شود.
DateTime? timestampFromFileName(String name) {
  final full = RegExp(r'(20\d{2})[-_ ]?(\d{2})[-_ ]?(\d{2})[-_ T]?(\d{2})[-_:]?(\d{2})[-_:]?(\d{2})').firstMatch(name);
  if (full != null) {
    return _dt(full.group(1)!, full.group(2)!, full.group(3)!, full.group(4)!, full.group(5)!, full.group(6)!);
  }
  final short = RegExp(r'(?<!\d)(\d{2})(\d{2})(\d{2})[-_](\d{2})(\d{2})(\d{2})(?!\d)').firstMatch(name);
  if (short != null) {
    return _dt('20${short.group(1)}', short.group(2)!, short.group(3)!, short.group(4)!, short.group(5)!, short.group(6)!);
  }
  return null;
}

DateTime? _dt(String y, String mo, String d, String h, String mi, String s) {
  final year = int.parse(y);
  final month = int.parse(mo);
  final day = int.parse(d);
  final hour = int.parse(h);
  final minute = int.parse(mi);
  final second = int.parse(s);
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) return null;
  return DateTime(year, month, day, hour, minute, second);
}

class MatchResult {
  const MatchResult(this.target, this.score, this.numberMatched);

  final MatchTarget target;
  final int score;
  final bool numberMatched;
}

/// بهترین تماس برای یک فایل، یا null. قاعده: حتماً باید **زمان** جور باشد؛
/// شماره‌ی داخل نام فایل فقط امتیاز می‌دهد و بین چند گزینه تعیین‌کننده است.
MatchResult? bestMatch(RecordingCandidate file, List<MatchTarget> targets) {
  final nameTime = timestampFromFileName(file.name);
  final nameDigits = digitsOnly(file.name);
  MatchResult? best;
  var bestDiff = 1 << 30;
  for (final t in targets) {
    final start = t.startedAt;
    final end = t.endedAt;
    // ۱) آخرین تغییر فایل ≈ پایان تماس (از ۱ دقیقه قبل از شروع تا ۳ دقیقه بعد از پایان)
    final byModified =
        !file.modified.isBefore(start.subtract(const Duration(minutes: 1))) &&
        !file.modified.isAfter(end.add(const Duration(minutes: 3)));
    // ۲) زمانِ داخل نام ≈ شروع تماس (±۲ دقیقه)
    final nt = nameTime;
    final nameDiff = nt == null ? null : nt.difference(start).inSeconds.abs();
    final byName = nameDiff != null && nameDiff <= 120;
    if (!byModified && !byName) continue;
    final tail = numberTail(t.number);
    final numberMatched = tail.length >= 6 && nameDigits.contains(tail);
    var score = 2;
    if (byModified && byName) score += 1;
    if (numberMatched) score += 3;
    final diff = (nameDiff != null && byName)
        ? nameDiff
        : file.modified.difference(end).inSeconds.abs();
    if (best == null || score > best.score || (score == best.score && diff < bestDiff)) {
      best = MatchResult(t, score, numberMatched);
      bestDiff = diff;
    }
  }
  return best;
}
