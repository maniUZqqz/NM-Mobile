import 'dart:io';

import 'package:nm_mobile/core/nm/json_util.dart';
import 'package:nm_mobile/core/storage/app_storage.dart';
import 'package:nm_mobile/features/lookup/lookup_facade.dart';
import 'package:nm_mobile/features/optout/optout.dart';

/// نشانگرِ «تا کجا از فهرست لغوِ NM خوانده‌ایم».
abstract class OptOutCursorStore {
  Future<String?> load();
  Future<void> save(String value);
}

class MemoryOptOutCursor implements OptOutCursorStore {
  String? value;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String v) async => value = v;
}

class FileOptOutCursor implements OptOutCursorStore {
  FileOptOutCursor({this.dirOverride});

  final String? dirOverride;

  Future<File> _file() async => File('${dirOverride ?? await AppDir.path()}/nm_optout_cursor.txt');

  @override
  Future<String?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final s = (await f.readAsString()).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String value) async {
    await writeAtomicFile(await _file(), value);
  }
}

/// فهرستِ «دیگر پیام نده»ی سراسریِ NM را به فهرست لغوِ محلیِ این گوشی می‌آورد، تا
/// کمپین‌های محلیِ مخاطب‌ها هم هرگز به شماره‌ای که از NM لغو کرده پیام ندهند.
///
/// قرارداد (اختیاری در سرور): `GET sms/optouts/?since=<iso>&limit=500` ⇒
/// `{"numbers": ["989121234567", …], "next_since": "<iso>", "has_more": false}`.
/// اگر سرور هنوز این مسیر را ندارد (۴۰۴/۴۰۵) این همگام‌سازی بی‌صدا کنار می‌رود.
class NmOptOutSync {
  NmOptOutSync({
    required this.http,
    required this.cursor,
    Future<int> Function(Iterable<OptOutEntry> entries)? add,
    this.pageSize = 500,
    this.maxPages = 20,
  }) : _add = add ?? OptOutStorage.addAll;

  final NmHttp http;
  final OptOutCursorStore cursor;
  final Future<int> Function(Iterable<OptOutEntry> entries) _add;
  final int pageSize;
  final int maxPages;

  /// true بعد از اینکه سرور گفت این مسیر را ندارد.
  bool unsupported = false;

  /// تعداد شماره‌های تازه‌ای که به فهرست محلی اضافه شد.
  Future<int> sync() async {
    if (unsupported) return 0;
    var added = 0;
    var since = await cursor.load();
    for (var page = 0; page < maxPages; page++) {
      final dynamic data;
      try {
        data = await http.getJson(
          'sms/optouts/',
          query: {'limit': '$pageSize', if (since != null) 'since': since},
        );
      } on NmHttpException catch (e) {
        if (e.status == 404 || e.status == 405) {
          unsupported = true;
          return added;
        }
        rethrow;
      }
      final m = asMap(data);
      final numbers = asList(m['numbers']).map((e) => e.toString()).where((e) => e.trim().isNotEmpty);
      added += await _add(
        numbers.map(
          (n) => OptOutEntry.create(phone: n.startsWith('+') ? n : '+$n', source: OptOutSource.nm),
        ),
      );
      final next = asStrN(m['next_since']);
      if (next != null) {
        await cursor.save(next);
        since = next;
      }
      if (!asBool(m['has_more'])) break;
    }
    return added;
  }
}
