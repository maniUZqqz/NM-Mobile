import 'dart:async';

import 'package:flutter/services.dart';

int _i(dynamic v, int d) => v is num ? v.toInt() : d;
bool _b(dynamic v, bool d) => v is bool ? v : d;
String _s(dynamic v) => v == null ? '' : v.toString();

/// یک سیم‌کارت فعال روی گوشی
class SimCard {
  final int subscriptionId;
  final int slot; // از 0 شروع می‌شود
  final String name;
  final String carrier;
  final String number;
  final String country;
  final bool embedded;

  const SimCard({
    required this.subscriptionId,
    required this.slot,
    required this.name,
    required this.carrier,
    required this.number,
    required this.country,
    required this.embedded,
  });

  factory SimCard.fromMap(Map<String, dynamic> m) => SimCard(
        subscriptionId: _i(m['subId'], -1),
        slot: _i(m['slot'], -1),
        name: _s(m['name']),
        carrier: _s(m['carrier']),
        number: _s(m['number']),
        country: _s(m['country']),
        embedded: _b(m['embedded'], false),
      );

  String get slotLabel => 'SIM ${slot + 1}';

  String get title {
    final n = carrier.trim().isNotEmpty ? carrier.trim() : name.trim();
    return n.isEmpty ? slotLabel : '$slotLabel · $n';
  }
}

class SimQuery {
  final bool permissionGranted;
  final List<SimCard> sims;
  final int defaultSmsSubId;

  const SimQuery({
    required this.permissionGranted,
    required this.sims,
    required this.defaultSmsSubId,
  });

  static const SimQuery empty =
      SimQuery(permissionGranted: false, sims: [], defaultSmsSubId: -1);
}

/// نتیجه ارسال پیامک. code == 0 یعنی موفق؛ مقادیر مثبت کدهای SmsManager.RESULT_*
/// و مقادیر منفی کدهای داخلی این افزونه هستند:
/// -100 timeout · -101 سیم‌کارت فعال نیست · -102 استثنا · -103 مجوز ندارد
/// -104 قابلیت تلفن ندارد · -105 ورودی خالی · -106 افزونه بومی پیدا نشد
class SmsSendResult {
  final bool ok;
  final int code;
  final int parts;
  final int partsOk;
  final int subId;
  final int usedSubId;
  final int modemCode;
  final String error;

  const SmsSendResult({
    required this.ok,
    required this.code,
    required this.parts,
    required this.partsOk,
    required this.subId,
    required this.usedSubId,
    required this.modemCode,
    required this.error,
  });

  factory SmsSendResult.fromMap(Map<String, dynamic> m) => SmsSendResult(
        ok: _b(m['ok'], false),
        code: _i(m['code'], -102),
        parts: _i(m['parts'], 0),
        partsOk: _i(m['partsOk'], 0),
        subId: _i(m['subId'], -1),
        usedSubId: _i(m['usedSubId'], -1),
        modemCode: _i(m['modemCode'], -1),
        error: _s(m['error']),
      );

  factory SmsSendResult.failure(int code, String error, {int subId = -1}) =>
      SmsSendResult(
        ok: false,
        code: code,
        parts: 0,
        partsOk: 0,
        subId: subId,
        usedSubId: subId,
        modemCode: -1,
        error: error,
      );
}

/// وضعیت مجوزها و محیط دستگاه (از سمت بومی خوانده می‌شود، بدون نیاز به Activity)
class BridgeStatus {
  final bool available; // افزونه بومی در این engine ثبت شده؟
  final bool sendSms;
  final bool phoneState;
  final bool phoneNumbers;
  final bool notifications;
  final bool battery; // true = از بهینه‌سازی باتری مستثنا است
  final bool airplane;
  final bool telephony;
  final int sdk;
  final String manufacturer;
  final String model;
  final bool receiveSms;
  final bool callLog;
  final bool contacts;

  const BridgeStatus({
    required this.available,
    required this.sendSms,
    required this.phoneState,
    required this.phoneNumbers,
    required this.notifications,
    required this.battery,
    required this.airplane,
    required this.telephony,
    required this.sdk,
    required this.manufacturer,
    required this.model,
    this.receiveSms = false,
    this.callLog = false,
    this.contacts = false,
  });

  static const BridgeStatus unknown = BridgeStatus(
    available: false,
    sendSms: false,
    phoneState: false,
    phoneNumbers: false,
    notifications: false,
    battery: false,
    airplane: false,
    telephony: true,
    sdk: 0,
    manufacturer: '',
    model: '',
  );

  factory BridgeStatus.fromMap(Map<String, dynamic> m) => BridgeStatus(
        available: true,
        sendSms: _b(m['sendSms'], false),
        phoneState: _b(m['phoneState'], false),
        phoneNumbers: _b(m['phoneNumbers'], false),
        notifications: _b(m['notifications'], false),
        battery: _b(m['battery'], false),
        airplane: _b(m['airplane'], false),
        telephony: _b(m['telephony'], true),
        sdk: _i(m['sdk'], 0),
        manufacturer: _s(m['manufacturer']),
        model: _s(m['model']),
        receiveSms: _b(m['receiveSms'], false),
        callLog: _b(m['callLog'], false),
        contacts: _b(m['contacts'], false),
      );
}

/// پیامکِ دریافتی که گیرندهٔ بومی در صف گذاشته است.
class IncomingSms {
  const IncomingSms({
    required this.from,
    required this.body,
    required this.at,
    this.subId = -1,
    this.slot = -1,
  });

  factory IncomingSms.fromMap(Map<String, dynamic> m) => IncomingSms(
        from: _s(m['from']),
        body: _s(m['body']),
        at: DateTime.fromMillisecondsSinceEpoch(_i(m['at'], 0)),
        subId: _i(m['subId'], -1),
        slot: _i(m['slot'], -1),
      );

  final String from;
  final String body;
  final DateTime at;
  final int subId;
  final int slot;
}

/// گزارش تحویلِ یک بخش از یک پیامک (ref = uid در NM).
class DeliveryEvent {
  const DeliveryEvent({
    required this.ref,
    required this.part,
    required this.total,
    required this.ok,
    required this.status,
  });

  factory DeliveryEvent.fromMap(Map<String, dynamic> m) => DeliveryEvent(
        ref: _s(m['ref']),
        part: _i(m['part'], 0),
        total: _i(m['total'], 1),
        ok: _b(m['ok'], false),
        status: _i(m['status'], -1),
      );

  final String ref;
  final int part;
  final int total;

  /// گزارش از اپراتور رسید
  final bool ok;

  /// کد وضعیت SMS-STATUS-REPORT؛ ۰ تا ۳۱ یعنی تحویل شد، ۶۴ به بالا شکست دائمی
  final int status;

  bool get delivered => ok && (status < 0 || status < 32);
  bool get failed => !ok || status >= 64;
}

/// باتری و شبکه، برای heartbeat
class DeviceState {
  const DeviceState({
    this.battery = -1,
    this.charging = false,
    this.network = 'none',
  });

  factory DeviceState.fromMap(Map<String, dynamic> m) => DeviceState(
        battery: _i(m['battery'], -1),
        charging: _b(m['charging'], false),
        network: _s(m['network']).isEmpty ? 'none' : _s(m['network']),
      );

  final int battery;
  final bool charging;
  final String network;
}

/// رویداد وضعیت تماس از گیرندهٔ بومی: ring | dial | answered | ended
class CallEvent {
  const CallEvent({
    required this.type,
    required this.number,
    required this.direction,
    required this.session,
    required this.at,
  });

  factory CallEvent.fromMap(Map<String, dynamic> m) => CallEvent(
        type: _s(m['type']),
        number: _s(m['number']),
        direction: _s(m['direction']),
        session: _i(m['session'], 0),
        at: DateTime.fromMillisecondsSinceEpoch(_i(m['at'], 0)),
      );

  final String type;
  final String number;

  /// in | out
  final String direction;

  /// شمارهٔ نوبتِ تماس (هر تماسِ تازه یک شماره)
  final int session;
  final DateTime at;
}

/// یک ردیف از لاگ تماس گوشی.
class CallLogRow {
  const CallLogRow({
    required this.id,
    required this.number,
    required this.type,
    required this.date,
    required this.duration,
    required this.name,
  });

  factory CallLogRow.fromMap(Map<String, dynamic> m) => CallLogRow(
        id: _i(m['id'], 0),
        number: _s(m['number']),
        type: _i(m['type'], 0),
        date: DateTime.fromMillisecondsSinceEpoch(_i(m['date'], 0)),
        duration: _i(m['duration'], 0),
        name: _s(m['name']),
      );

  final int id;
  final String number;

  /// ۱ ورودی، ۲ خروجی، ۳ بی‌پاسخ، ۵ ردشده
  final int type;
  final DateTime date;

  /// ثانیه
  final int duration;
  final String name;
}

/// فایل صوتی داخل پوشهٔ انتخاب‌شده (Storage Access Framework).
class RecordingFile {
  const RecordingFile({
    required this.uri,
    required this.name,
    required this.modified,
    required this.size,
    required this.mime,
  });

  factory RecordingFile.fromMap(Map<String, dynamic> m) => RecordingFile(
        uri: _s(m['uri']),
        name: _s(m['name']),
        modified: DateTime.fromMillisecondsSinceEpoch(_i(m['modified'], 0)),
        size: _i(m['size'], 0),
        mime: _s(m['mime']),
      );

  final String uri;
  final String name;
  final DateTime modified;
  final int size;
  final String mime;
}

class PickedFolder {
  const PickedFolder({required this.tree, required this.name});

  final String tree;
  final String name;
}

class PickedContactFile {
  const PickedContactFile({required this.path, required this.name});

  final String path;
  final String name;
}

class SmsBridge {
  SmsBridge._();

  static const MethodChannel _ch = MethodChannel('sms_bridge');

  /// مسیر پایدار filesDir برنامه (برخلاف cache پاک نمی‌شود)
  static Future<String> filesDir() async {
    try {
      return (await _ch.invokeMethod<String>('filesDir')) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<PickedContactFile?> pickContactFile() async {
    final result = await _ch.invokeMapMethod<String, dynamic>(
      'pickContactFile',
    );
    if (result == null) return null;
    final path = _s(result['path']);
    if (path.isEmpty) return null;
    return PickedContactFile(path: path, name: _s(result['name']));
  }

  static Future<BridgeStatus> status() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status');
      if (m == null) return BridgeStatus.unknown;
      return BridgeStatus.fromMap(m);
    } catch (_) {
      return BridgeStatus.unknown;
    }
  }

  static Future<SimQuery> getSimCards() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getSimCards');
      if (m == null) return SimQuery.empty;
      final raw = m['sims'];
      final sims = <SimCard>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            sims.add(SimCard.fromMap(Map<String, dynamic>.from(e)));
          }
        }
      }
      sims.sort((a, b) => a.slot.compareTo(b.slot));
      return SimQuery(
        permissionGranted: _b(m['permission'], false),
        sims: sims,
        defaultSmsSubId: _i(m['defaultSmsSubId'], -1),
      );
    } catch (_) {
      return SimQuery.empty;
    }
  }

  /// subId < 0 یعنی سیم‌کارت پیش‌فرض پیامک گوشی.
  /// این متد هرگز استثنا پرتاب نمی‌کند؛ همیشه یک [SmsSendResult] برمی‌گرداند.
  static Future<SmsSendResult> sendSms({
    required String to,
    required String message,
    int subId = -1,
    String? ref,
    bool delivery = false,
  }) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('sendSms', {
        'to': to,
        'message': message,
        'subId': subId,
        'ref': ref ?? '',
        'delivery': delivery,
      }).timeout(const Duration(seconds: 75));
      if (m == null) {
        return SmsSendResult.failure(-102, 'پاسخ خالی از لایه بومی',
            subId: subId);
      }
      return SmsSendResult.fromMap(m);
    } on TimeoutException {
      return SmsSendResult.failure(-100, 'گزارش ارسال از سیستم نرسید',
          subId: subId);
    } on MissingPluginException catch (e) {
      return SmsSendResult.failure(-106, e.toString(), subId: subId);
    } on PlatformException catch (e) {
      return SmsSendResult.failure(-102, '${e.code}: ${e.message}',
          subId: subId);
    } catch (e) {
      return SmsSendResult.failure(-102, e.toString(), subId: subId);
    }
  }

  static List<Map<String, dynamic>> _maps(dynamic raw) {
    final out = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  /// پیامک‌های دریافتی از آخرین بار (صف بومی را خالی می‌کند).
  static Future<List<IncomingSms>> drainIncoming() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('drainIncoming');
      return _maps(raw).map(IncomingSms.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  /// گزارش‌های تحویل رسیده از آخرین بار (صف بومی را خالی می‌کند).
  static Future<List<DeliveryEvent>> drainDelivery() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('drainDelivery');
      return _maps(raw).map(DeliveryEvent.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<DeviceState> deviceState() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('deviceState');
      if (m == null) return const DeviceState();
      return DeviceState.fromMap(m);
    } catch (_) {
      return const DeviceState();
    }
  }

  /// رویدادهای تماس از آخرین بار (صف بومی را خالی می‌کند).
  static Future<List<CallEvent>> drainCallEvents() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('drainCallEvents');
      return _maps(raw).map(CallEvent.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<CallLogRow>> readCallLog({
    required DateTime since,
    int limit = 100,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('readCallLog', {
        'since': since.millisecondsSinceEpoch,
        'limit': limit,
      });
      return _maps(raw).map(CallLogRow.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> showCallNotification(String title, String text) async {
    try {
      await _ch.invokeMethod<bool>('showCallNotification', {
        'title': title,
        'text': text,
      });
    } catch (_) {}
  }

  static Future<void> cancelCallNotification() async {
    try {
      await _ch.invokeMethod<bool>('cancelCallNotification');
    } catch (_) {}
  }

  /// انتخاب پوشهٔ ضبط‌های تماس با Storage Access Framework (مجوزِ دائمی).
  static Future<PickedFolder?> pickRecordingsFolder() async {
    final m = await _ch.invokeMapMethod<String, dynamic>('pickRecordingsFolder');
    if (m == null) return null;
    final tree = _s(m['tree']);
    if (tree.isEmpty) return null;
    return PickedFolder(tree: tree, name: _s(m['name']));
  }

  static Future<List<RecordingFile>> listRecordings({
    required String tree,
    required DateTime since,
    int max = 300,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listRecordings', {
        'tree': tree,
        'since': since.millisecondsSinceEpoch,
        'max': max,
      });
      return _maps(raw).map(RecordingFile.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  /// فایل را برای آپلود در cache کپی می‌کند؛ خطا ⇒ null.
  static Future<String?> copyToCache(String uri, String name) async {
    try {
      return await _ch.invokeMethod<String>('copyToCache', {
        'uri': uri,
        'name': name,
      });
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteCacheFile(String path) async {
    try {
      await _ch.invokeMethod<bool>('deleteCacheFile', {'path': path});
    } catch (_) {}
  }

  static Future<bool> isInstalled(String package) async {
    try {
      return (await _ch.invokeMethod<bool>('isInstalled', {
            'package': package,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// لینک را باز می‌کند؛ اگر [package] نصب باشد همان برنامه آن را می‌گیرد.
  static Future<bool> openUrl(String url, {String? package}) async {
    try {
      return (await _ch.invokeMethod<bool>('openUrl', {
            'url': url,
            'package': package ?? '',
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// صفحهٔ «ذخیرهٔ مخاطب» اندروید را با نام و شماره باز می‌کند.
  static Future<bool> insertContact({
    String name = '',
    required String number,
  }) async {
    try {
      return (await _ch.invokeMethod<bool>('insertContact', {
            'name': name,
            'number': number,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// قفل CPU و Wi-Fi تا سرویس پس‌زمینه در حالت خواب (Doze) متوقف نشود
  static Future<void> acquireLocks() async {
    try {
      await _ch.invokeMethod<bool>('acquireLocks');
    } catch (_) {}
  }

  static Future<void> releaseLocks() async {
    try {
      await _ch.invokeMethod<bool>('releaseLocks');
    } catch (_) {}
  }
}
